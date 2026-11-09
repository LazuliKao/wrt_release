#!/usr/bin/env bash

set -euo pipefail

: "${PACKAGE_DIR:?PACKAGE_DIR is required}"
: "${BUILD_DIR:?BUILD_DIR is required}"

die() {
    echo "luci_app_honk: $*" >&2
    exit 1
}

for command in awk curl file git mktemp sha256sum tar; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

MAKEFILE="$PACKAGE_DIR/Makefile"
TOOLCHAIN_HELPER="$PACKAGE_DIR/honk_toolchain.sh"
BUILD_SCRIPT="$PACKAGE_DIR/build_honk_core.sh"
[ -f "$MAKEFILE" ] || die "Honk package Makefile not found: $MAKEFILE"
[ -f "$TOOLCHAIN_HELPER" ] || die "Honk toolchain helper is missing"
[ -f "$BUILD_SCRIPT" ] || die "Honk build script is missing"

TOOLCHAIN_ROOT="$BUILD_DIR/staging_dir/host/honk-toolchain"
TOOL_BIN="$TOOLCHAIN_ROOT/bin"
mkdir -p "$TOOL_BIN"

# Resolve versions from the exact Honk source revision pinned in its package Makefile.
eval "$(bash "$TOOLCHAIN_HELPER" "$MAKEFILE")"
printf 'luci_app_honk: Honk %s requires Zig %s and bpf-linker %s\n' \
    "$HONK_SRC_VERSION" "$ZIG_VERSION" "$BPF_LINKER_VERSION"

if [ ! -x "$TOOL_BIN/zig" ] || [ "$("$TOOL_BIN/zig" version 2>/dev/null || true)" != "$ZIG_VERSION" ]; then
    ZIG_ARCHIVE="$TOOLCHAIN_ROOT/zig-${ZIG_VERSION}-x86_64-linux.tar.xz"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
    curl -fsSL --retry 3 "$ZIG_URL" -o "$ZIG_ARCHIVE" || die "failed to download Zig $ZIG_VERSION"
    ZIG_DIR="$TOOLCHAIN_ROOT/zig-${ZIG_VERSION}"
    rm -rf "$ZIG_DIR"
    mkdir -p "$ZIG_DIR"
    tar -xJf "$ZIG_ARCHIVE" -C "$ZIG_DIR" --strip-components=1
    ln -sfn "$ZIG_DIR/zig" "$TOOL_BIN/zig"
fi

# Rustup is provisioned by the build container; make its cargo bin available to
# the upstream script and build process without relying on a parent-shell PATH.
if [ -f "${HOME:-}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
fi
export PATH="$TOOL_BIN:${CARGO_HOME:-${HOME:-}/.cargo}/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# Honk's CI build requires bindgen, clang/LLVM and zstd development tools.
# The base OpenWrt container already carries most of these, so install only
# missing host packages when apt and sudo are available.
missing=()
for command in clang llvm-config cmake pkg-config zstd file; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
if ! ldconfig -p 2>/dev/null | grep -q 'libclang-'; then
    missing+=(libclang-dev)
fi
if ! pkg-config --exists libbpf; then
    missing+=(libbpf-dev)
fi
if [ "${#missing[@]}" -gt 0 ]; then
    command -v apt-get >/dev/null 2>&1 || die "missing build dependencies (${missing[*]}) and apt-get is unavailable"
    if [ "$(id -u)" -eq 0 ]; then
        APT=(apt-get)
    elif command -v sudo >/dev/null 2>&1; then
        APT=(sudo apt-get)
    else
        die "missing build dependencies (${missing[*]}); install them on the build host"
    fi
    "${APT[@]}" update
    "${APT[@]}" install -y clang llvm cmake pkg-config zstd file libclang-dev libbpf-dev
fi

# boring-sys requires CMake 3.22+, while the Debian build container can ship
# an older system CMake. Keep a verified, self-contained CMake beside Zig so
# the imported package Makefile can use it through the injected toolchain PATH.
CMAKE_VERSION=3.31.8
CMAKE_SHA256=630615d8e98ac33eba7fbe472626dff5c899c85af3c024585ae109166a6909d0
CMAKE_DIR="$TOOLCHAIN_ROOT/cmake-$CMAKE_VERSION-linux-x86_64"
if [ ! -x "$TOOL_BIN/cmake" ] || [ "$("$TOOL_BIN/cmake" --version 2>/dev/null | awk 'NR == 1 { print $3 }')" != "$CMAKE_VERSION" ]; then
    CMAKE_ARCHIVE="$TOOLCHAIN_ROOT/cmake-$CMAKE_VERSION-linux-x86_64.tar.gz"
    curl -fsSL --retry 3 \
        "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
        -o "$CMAKE_ARCHIVE" || die "failed to download CMake $CMAKE_VERSION"
    echo "$CMAKE_SHA256  $CMAKE_ARCHIVE" | sha256sum -c - || die "CMake checksum verification failed"
    rm -rf "$CMAKE_DIR"
    mkdir -p "$CMAKE_DIR"
    tar -xzf "$CMAKE_ARCHIVE" -C "$CMAKE_DIR" --strip-components=1
    ln -sfn "$CMAKE_DIR/bin/cmake" "$TOOL_BIN/cmake"
fi
"$TOOL_BIN/cmake" --version | awk -v expected="$CMAKE_VERSION" 'NR == 1 && $3 == expected { found = 1 } END { exit !found }' \
    || die "CMake $CMAKE_VERSION is not available from $TOOL_BIN"

if [ ! -f "$TOOL_BIN/.bpf-linker-${BPF_LINKER_VERSION}.installed" ]; then
    BPF_ARCHIVE="$TOOLCHAIN_ROOT/bpf-linker-${BPF_LINKER_VERSION}.tar.zst"
    curl -fsSL --retry 3 \
        "https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst" \
        -o "$BPF_ARCHIVE" || die "failed to download bpf-linker $BPF_LINKER_VERSION"
    echo "$BPF_LINKER_SHA256  $BPF_ARCHIVE" | sha256sum -c - || die "bpf-linker checksum verification failed"
    rm -f "$TOOL_BIN/bpf-linker"
    zstd -dc "$BPF_ARCHIVE" | tar -xf - -C "$TOOL_BIN"
    [ -x "$TOOL_BIN/bpf-linker" ] || die "bpf-linker archive did not contain executable"
    touch "$TOOL_BIN/.bpf-linker-${BPF_LINKER_VERSION}.installed"
fi

for command in cargo rustup; do
    command -v "$command" >/dev/null 2>&1 || die "required Rust command not found: $command"
done

# pre_defconfig runs before OpenWrt's make defconfig, so ARCH is not yet
# available here. Inject the toolchain PATH into the package's Build/Compile
# command; there, OpenWrt supplies the resolved architecture to the upstream
# build script.
if ! grep -Fq 'CMAKE="$(STAGING_DIR_HOST)/honk-toolchain/bin/cmake"' "$MAKEFILE"; then
    if grep -Fq 'PATH="$(STAGING_DIR_HOST)/honk-toolchain/bin:$(PATH)"' "$MAKEFILE"; then
        sed -i 's|PATH="$(STAGING_DIR_HOST)/honk-toolchain/bin:$(PATH)"|CMAKE="$(STAGING_DIR_HOST)/honk-toolchain/bin/cmake" PATH="$(STAGING_DIR_HOST)/honk-toolchain/bin:$(PATH)"|' "$MAKEFILE"
    else
        grep -Fq '"$(CURDIR)/build_honk_core.sh"' "$MAKEFILE" || die "unexpected Honk Build/Compile command in $MAKEFILE"
        sed -i 's|"$(CURDIR)/build_honk_core.sh"|CMAKE="$(STAGING_DIR_HOST)/honk-toolchain/bin/cmake" PATH="$(STAGING_DIR_HOST)/honk-toolchain/bin:$(PATH)" "$(CURDIR)/build_honk_core.sh"|' "$MAKEFILE"
    fi
fi

echo "luci_app_honk: prepared pinned Honk toolchain; core will build with OpenWrt ARCH"
