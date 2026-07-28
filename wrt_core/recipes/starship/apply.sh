#!/usr/bin/env bash
set -euo pipefail

base_files_path="$BUILD_DIR/package/base-files/files"
dest_bin="$base_files_path/usr/bin/starship"

# 1. Detect target architecture from the .config file
starship_arch="aarch64-unknown-linux-musl" # Default to ARM64 as most modern targets are arm64
if [ -f "$BUILD_DIR/.config" ]; then
    if grep -q "CONFIG_TARGET_x86_64=y" "$BUILD_DIR/.config"; then
        starship_arch="x86_64-unknown-linux-musl"
    elif grep -q "CONFIG_ARCH=\"arm\"" "$BUILD_DIR/.config" || grep -q "CONFIG_arm=y" "$BUILD_DIR/.config"; then
        starship_arch="arm-unknown-linux-musleabihf"
    fi
fi

# 2. Download and install Starship pre-built binary
starship_ver="1.26.0"
download_url="https://github.com/starship/starship/releases/download/v${starship_ver}/starship-${starship_arch}.tar.gz"

mkdir -p "$base_files_path/usr/bin"

if [ -x "$dest_bin" ]; then
    echo "starship: already installed at $dest_bin"
else
    echo "starship: downloading from $download_url..."
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    if curl -fL "$download_url" -o "$tmp_dir/starship.tar.gz"; then
        tar -xzf "$tmp_dir/starship.tar.gz" -C "$tmp_dir"
        if [ -f "$tmp_dir/starship" ]; then
            install -m0755 "$tmp_dir/starship" "$dest_bin"
            echo "starship: installed successfully to $dest_bin"
        else
            echo "starship: Error: binary not found in archive" >&2
            exit 1
        fi
    else
        echo "starship: Error: failed to download from $download_url" >&2
        exit 1
    fi
fi
# 3. passwd shell modification removed (using .profile forwarding instead)

