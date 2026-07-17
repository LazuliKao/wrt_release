#!/usr/bin/env bash
set -euo pipefail

echo "kernel_compress_lzma: starting kernel compression enhancement"

target_dir="${BUILD_DIR:-}/target/linux"

if [ -z "${BUILD_DIR:-}" ] || [ ! -d "$target_dir" ]; then
    echo "kernel_compress_lzma: build directory target ($target_dir) not found; skipping"
    exit 0
fi

# Find and update Makefiles defining Device/FitImage
find "$target_dir" -type f \( -name "Makefile" -o -name "*.mk" \) | while read -r makefile; do
    if grep -q "define Device/FitImage" "$makefile"; then
        sed -i '/define Device\/FitImage/,/endef/ {
            s/libdeflate-gzip/lzma/g
            s/kernel-bin | gzip/kernel-bin | lzma/g
            s/fit gzip/fit lzma/g
        }' "$makefile"
        echo "kernel_compress_lzma: updated Device/FitImage in $makefile"
    fi
done

echo "kernel_compress_lzma: kernel compression enhancement completed"
