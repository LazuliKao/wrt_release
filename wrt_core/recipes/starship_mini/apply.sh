#!/usr/bin/env bash
set -euo pipefail

base_files_path="$BUILD_DIR/package/base-files/files"
dest_bin="$base_files_path/usr/bin/starship"

# 1. Detect target architecture from the .config file
starship_arch="aarch64-openwrt-musl" # Default to ARM64 as most modern targets are arm64
if [ -f "$BUILD_DIR/.config" ]; then
    if grep -q "CONFIG_TARGET_x86_64=y" "$BUILD_DIR/.config"; then
        starship_arch="x86_64-openwrt-musl"
    elif grep -q "CONFIG_ARCH=\"arm\"" "$BUILD_DIR/.config" || grep -q "CONFIG_arm=y" "$BUILD_DIR/.config"; then
        if grep -q "CONFIG_arm_v7=y" "$BUILD_DIR/.config" || grep -q "CONFIG_CPU_V7=y" "$BUILD_DIR/.config"; then
            if grep -q "CONFIG_HAS_FPU=y" "$BUILD_DIR/.config"; then
                starship_arch="armv7hf-openwrt-musl"
            else
                starship_arch="armv7-openwrt-musl"
            fi
        else
            starship_arch="armv5-openwrt-musl"
        fi
    elif grep -q "CONFIG_riscv64=y" "$BUILD_DIR/.config" || grep -q "CONFIG_ARCH=\"riscv\"" "$BUILD_DIR/.config"; then
        starship_arch="riscv64-openwrt-musl"
    fi
fi

# 2. Download and install Starship pre-built binary
starship_ver="1.26.0-mini"
download_url="https://github.com/LazuliKao/starship/releases/download/v${starship_ver}/starship-${starship_arch}.tar.gz"

mkdir -p "$base_files_path/usr/bin"

if [ -x "$dest_bin" ]; then
    echo "starship: already installed at $dest_bin"
else
    echo "starship: downloading from $download_url..."
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    if curl -fL "$download_url" -o "$tmp_dir/starship.tar.gz"; then
        tar -xzf "$tmp_dir/starship.tar.gz" -C "$tmp_dir"
        
        src_bin=$(find "$tmp_dir" -type f -name starship | head -n 1)
        if [ -n "$src_bin" ] && [ -f "$src_bin" ]; then
            install -m0755 "$src_bin" "$dest_bin"
            echo "starship: installed successfully to $dest_bin"

            # 2.5 Compress the installed binary using UPX
            upx_bin="$BUILD_DIR/upx/upx"
            if [ -x "$upx_bin" ]; then
                echo "starship: compressing binary with UPX..."
                "$upx_bin" --lzma "$dest_bin" || echo "starship: Warning: UPX compression failed" >&2
            else
                echo "starship: Warning: UPX binary not found at $upx_bin" >&2
            fi
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

