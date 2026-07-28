#!/usr/bin/env bash
set -euo pipefail

# 1. Detect target architecture from the .config file
flyline_arch=""
if [ -f "$BUILD_DIR/.config" ]; then
    if grep -q "CONFIG_TARGET_x86_64=y" "$BUILD_DIR/.config"; then
        flyline_arch="x86_64-unknown-linux-musl"
    elif grep -q "CONFIG_aarch64=y" "$BUILD_DIR/.config"; then
        flyline_arch="aarch64-unknown-linux-musl"
    fi
fi

if [ -z "$flyline_arch" ]; then
    echo "flyline: Warning: Target architecture not supported or could not be detected from .config." >&2
    echo "flyline: Flyline only supports x86_64 and aarch64 (ARM64) OpenWrt builds. Skipping installation." >&2
    exit 0
fi

# 2. Setup paths
base_files_path="$BUILD_DIR/package/base-files/files"
dest_lib_dir="$base_files_path/usr/lib"
dest_lib="$dest_lib_dir/libflyline.so"

mkdir -p "$dest_lib_dir"

# 3. Download and extract flyline library
flyline_ver="1.4.0"
download_url="https://github.com/HalFrgrd/flyline/releases/download/v${flyline_ver}/libflyline-v${flyline_ver}-${flyline_arch}.tar.gz"

if [ -f "$dest_lib" ]; then
    echo "flyline: already installed at $dest_lib"
else
    echo "flyline: downloading from $download_url..."
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    if curl -fL "$download_url" -o "$tmp_dir/flyline.tar.gz"; then
        tar -xzf "$tmp_dir/flyline.tar.gz" -C "$tmp_dir"
        
        # Inside the tar.gz is libflyline.so.1.4.0
        extracted_lib="$tmp_dir/libflyline.so.${flyline_ver}"
        
        if [ -f "$extracted_lib" ]; then
            install -m0755 "$extracted_lib" "$dest_lib"
            echo "flyline: installed successfully to $dest_lib"
        else
            found_lib=$(find "$tmp_dir" -name "libflyline.so*" | head -n 1)
            if [ -n "$found_lib" ] && [ -f "$found_lib" ]; then
                install -m0755 "$found_lib" "$dest_lib"
                echo "flyline: installed successfully (fallback detection) to $dest_lib"
            else
                echo "flyline: Error: shared library not found in archive" >&2
                exit 1
            fi
        fi
    else
        echo "flyline: Error: failed to download from $download_url" >&2
        exit 1
    fi
fi
