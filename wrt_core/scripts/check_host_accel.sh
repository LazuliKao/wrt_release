#!/usr/bin/env bash
# Integration checks in isolated source trees; never modifies a real OpenWrt tree.
set -euo pipefail
CORE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODULE="$CORE/modules/host_accel.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/tree"
mkdir -p "$ROOT/feeds/packages/lang/"{golang,python/python3,rust} "$ROOT/tmp" "$TMP/bin" "$TMP/go/"{src,bin} "$TMP/rust/bin"
export WRT_TEST_GO_ROOT="$TMP/go" WRT_TEST_RUST_ROOT="$TMP/rust"
export PATH="$TMP/bin:$PATH"
unset WRT_HOST_ACCEL WRT_HOST_ACCEL_GO WRT_HOST_ACCEL_LLVM WRT_HOST_ACCEL_RUST WRT_HOST_ACCEL_PYTHON

fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$MODULE" "$1" "$ROOT"; }
hash() { sha256sum "$1" | cut -d' ' -f1; }

cat > "$TMP/go/bin/go" <<'SH'
#!/usr/bin/env bash
case "$1" in env) echo "$WRT_TEST_GO_ROOT" ;; version) echo 'go version go1.26.1 linux/amd64' ;; *) exit 1 ;; esac
SH
chmod +x "$TMP/go/bin/go"
ln -s "$TMP/go/bin/go" "$TMP/bin/go"
printf 'config GOLANG_EXTERNAL_BOOTSTRAP_ROOT\n\tstring\n' > "$ROOT/feeds/packages/lang/golang/Config.in"
printf 'BOOTSTRAP_SOURCE:=go1.24.6.linux-amd64.tar.gz\n' > "$ROOT/feeds/packages/lang/golang/Makefile"
printf 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=""\nCONFIG_PACKAGE_probe=m\n' > "$ROOT/.config"
run go
grep -qF "CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=\"$TMP/go\"" "$ROOT/.config" || fail 'Go not selected'
mkdir -p "$ROOT/staging_dir/hostpkg/stamp"
touch "$ROOT/staging_dir/hostpkg/stamp/.golang_installed"
before=$(hash "$ROOT/.config")
run go
[[ "$before" == "$(hash "$ROOT/.config")" && -f "$ROOT/staging_dir/hostpkg/stamp/.golang_installed" ]] || fail 'Go reapplication not idempotent'
WRT_HOST_ACCEL_GO=off run go
grep -qx 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=""' "$ROOT/.config" || fail 'Go original config not restored'
[[ ! -f "$ROOT/staging_dir/hostpkg/stamp/.golang_installed" ]] || fail 'Go transition stamp not invalidated'
printf 'BOOTSTRAP_SOURCE:=go1.99.0.linux-amd64.tar.gz\n' > "$ROOT/feeds/packages/lang/golang/Makefile"
run go
grep -qx 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=""' "$ROOT/.config" || fail 'Incompatible Go accepted'
printf 'BOOTSTRAP_SOURCE:=go1.24.6.linux-amd64.tar.gz\n' > "$ROOT/feeds/packages/lang/golang/Makefile"
run go
sed -i 's|^CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=.*|CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="/user/edit"|' "$ROOT/.config"
WRT_HOST_ACCEL=off run go
grep -qx 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="/user/edit"' "$ROOT/.config" || fail 'User config edit overwritten'
echo 'PASS: Go version floor, idempotence, disable, user edits and stamps'

cat > "$ROOT/feeds/packages/lang/python/python3/Makefile" <<'MAKE'
HOST_CONFIGURE_ARGS += \
	--enable-shared \
	--enable-optimizations
CONFIGURE_ARGS += --enable-optimizations
$(eval $(call HostBuild))
MAKE
original=$(hash "$ROOT/feeds/packages/lang/python/python3/Makefile")
run python
grep -q '^HOST_CONFIGURE_ARGS := .*--disable-optimizations' "$ROOT/feeds/packages/lang/python/python3/Makefile" || fail 'Python PGO override missing'
grep -qx 'CONFIGURE_ARGS += --enable-optimizations' "$ROOT/feeds/packages/lang/python/python3/Makefile" || fail 'Target Python changed'
before=$(hash "$ROOT/feeds/packages/lang/python/python3/Makefile")
run python
[[ "$before" == "$(hash "$ROOT/feeds/packages/lang/python/python3/Makefile")" ]] || fail 'Python reapplication changed file'
WRT_HOST_ACCEL_PYTHON=off run python
[[ "$original" == "$(hash "$ROOT/feeds/packages/lang/python/python3/Makefile")" ]] || fail 'Python original not restored'
echo 'PASS: host-only Python PGO, idempotence and restore'

cat > "$ROOT/rules.mk" <<'MAKE'
STAGING_DIR:=$(TOPDIR)/staging_dir
INSTALL_DIR:=mkdir -p
MAKE
cat > "$ROOT/feeds/packages/lang/rust/rust-values.mk" <<'MAKE'
RUSTC_TARGET_ARCH:=aarch64-unknown-linux-musl
TARGET_CC_NOCACHE:=cc
CARGO_RUSTFLAGS:=-Ctarget-feature=-crt-static
MAKE
cat > "$ROOT/feeds/packages/lang/rust/Makefile" <<'MAKE'
include $(TOPDIR)/rules.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk
PKG_VERSION:=1.96.0
define Host/Prepare
	@echo source-prepare >> "$(TOPDIR)/source-used"
endef
define Host/Configure
	@echo source-configure >> "$(TOPDIR)/source-used"
endef
define Host/Compile
	@echo source-compile >> "$(TOPDIR)/source-used"
endef
define Host/Install
	@echo source-install >> "$(TOPDIR)/source-used"
endef
define Host/Uninstall
	@echo source-uninstall >> "$(TOPDIR)/source-used"
endef
define HostBuild
.PHONY: all clean
all:
	$(call Host/Prepare)
	$(call Host/Configure)
	$(call Host/Compile)
	$(call Host/Install)
clean:
	$(call Host/Uninstall)
endef
$(eval $(call HostBuild))
MAKE
cat > "$ROOT/tmp/.packageinfo" <<'INFO'
Source-Makefile: feeds/packages/lang/rust-app/Makefile
Build-Depends: rust/host
Package: probe
INFO
cat > "$TMP/bin/rustup" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WRT_TEST_RUST_ROOT/rustup-calls"
case "$1" in
    toolchain|target) [[ ${WRT_TEST_DOWNLOAD_FAIL:-0} == 0 ]] ;;
    run) printf '%s\n' "$WRT_TEST_RUST_ROOT" ;;
    *) exit 1 ;;
esac
SH
cat > "$TMP/rust/bin/rustc" <<'SH'
#!/usr/bin/env bash
[[ "$1" != --version ]] || { echo 'rustc 1.96.0 (test)'; exit; }
case " $* " in *' --emit=obj '*) ;; *) [[ ${WRT_TEST_LINK_FAIL:-0} == 0 ]] || exit 1 ;; esac
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then touch "$2"; fi
    shift
done
cat >/dev/null
SH
for tool in cargo rustdoc; do printf '#!/usr/bin/env bash\necho "%s 1.96.0 (test)"\n' "$tool" > "$TMP/rust/bin/$tool"; done
chmod +x "$TMP/bin/rustup" "$TMP/rust/bin/"*
rust_make() { make --no-print-directory -s -f "$ROOT/feeds/packages/lang/rust/Makefile" "TOPDIR=$ROOT" "$@"; }
original=$(hash "$ROOT/feeds/packages/lang/rust/Makefile")
WRT_HOST_ACCEL_RUST=off run rust
[[ ! -f "$TMP/rust/rustup-calls" ]] || fail 'Disabled Rust downloaded a toolchain'
cp "$ROOT/tmp/.packageinfo" "$TMP/packageinfo"
printf 'Source-Makefile: other\nBuild-Depends: rust/host\nPackage: not-selected\n' > "$ROOT/tmp/.packageinfo"
run rust
[[ ! -f "$TMP/rust/rustup-calls" ]] || fail 'Unselected Rust dependency downloaded a toolchain'
cp "$TMP/packageinfo" "$ROOT/tmp/.packageinfo"
cp "$ROOT/feeds/packages/lang/rust/rust-values.mk" "$TMP/rust-values"
printf 'RUSTC_TARGET_ARCH:=powerpc-unknown-linux-musl\nRUSTC_TARGET_RUSTFLAGS:=-Ctarget-feature=-hard-float\n' >> "$ROOT/feeds/packages/lang/rust/rust-values.mk"
run rust
[[ ! -f "$TMP/rust/rustup-calls" ]] || fail 'Unsupported std ABI downloaded a toolchain'
cp "$TMP/rust-values" "$ROOT/feeds/packages/lang/rust/rust-values.mk"
WRT_TEST_DOWNLOAD_FAIL=1 run rust
[[ "$original" == "$(hash "$ROOT/feeds/packages/lang/rust/Makefile")" ]] || fail 'Failed download changed Rust rules'
run rust
grep -q '^WRT_RUST_ROOT :=' "$ROOT/feeds/packages/lang/rust/Makefile" || fail 'Rust override missing'
before=$(hash "$ROOT/feeds/packages/lang/rust/Makefile")
rust_make all
[[ -L "$ROOT/staging_dir/host/bin/rustc" && ! -f "$ROOT/source-used" ]] || fail 'Prebuilt host install failed'
touch "$ROOT/staging_dir/hostpkg/stamp/.rust_installed"
run rust
[[ "$before" == "$(hash "$ROOT/feeds/packages/lang/rust/Makefile")" && -L "$ROOT/staging_dir/host/bin/rustc" ]] || fail 'Rust repeat removed installed tools'
[[ -f "$ROOT/staging_dir/hostpkg/stamp/.rust_installed" ]] || fail 'Rust repeat invalidated identical toolchain'
WRT_TEST_LINK_FAIL=1 rust_make all
grep -qx source-compile "$ROOT/source-used" || fail 'Link failure did not restore source compile'
[[ ! -L "$ROOT/staging_dir/host/bin/rustc" && ! -f "$ROOT/staging_dir/hostpkg/stamp/.rust_installed" ]] || fail 'Link failure retained prebuilt links/stamps'
rm "$ROOT/source-used"
run rust
rust_make all
rust_make clean
[[ ! -L "$ROOT/staging_dir/host/bin/rustc" ]] || fail 'Uninstall did not remove owned links'
rust_make DUMP=1 all
grep -qx source-compile "$ROOT/source-used" || fail 'Metadata mode changed original rules'
WRT_HOST_ACCEL_RUST=off run rust
[[ "$original" == "$(hash "$ROOT/feeds/packages/lang/rust/Makefile")" ]] || fail 'Rust disable did not restore Makefile'
echo 'PASS: Rust dependency, download failure, override, runtime fallback, repeat and uninstall'

# Exercise LLVM against an actual source pipeline, not mocked --version output.
if [[ -n "${1:-}" ]]; then
    mkdir -p "$ROOT/include" "$ROOT/toolchain"
    cp "$1/include/bpf.mk" "$ROOT/include/bpf.mk"
    cp "$1/toolchain/Config.in" "$ROOT/toolchain/Config.in"
    for endian in little big; do
        printf 'CONFIG_BPF_TOOLCHAIN_PREBUILT=y\n' > "$ROOT/.config"
        [[ "$endian" != big ]] || printf 'CONFIG_BIG_ENDIAN=y\n' >> "$ROOT/.config"
        run llvm
        if [[ ${WRT_TEST_LLVM_REQUIRED:-0} == 1 ]]; then
            grep -qx CONFIG_BPF_TOOLCHAIN_HOST=y "$ROOT/.config" || fail "LLVM $endian endian not enabled"
        fi
        WRT_HOST_ACCEL_LLVM=off run llvm
        grep -qx CONFIG_BPF_TOOLCHAIN_PREBUILT=y "$ROOT/.config" || fail 'LLVM selection not restored'
        ! grep -qx CONFIG_BPF_TOOLCHAIN_HOST=y "$ROOT/.config" || fail 'LLVM host selection retained after disable'
    done
    echo 'PASS: actual BPF pipeline and original selection restoration (both endians)'
fi
echo 'All host acceleration checks passed.'
