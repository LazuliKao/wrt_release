#!/usr/bin/env bash
set -euo pipefail

echo "cudy_tr3000_114m: starting partition size modification"

local_size="0x7200000" #114MB

dts_file2="${BUILD_DIR:-}/target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts"
if [ -f "$dts_file2" ]; then
    sed -i "s/reg = <0x5c0000 0x[0-9a-fA-F]*>/reg = <0x5c0000 $local_size>/g" "$dts_file2"
    echo "Updated $dts_file2"
fi

dts_uboot_file="${BUILD_DIR:-}/package/boot/uboot-mediatek/patches/445-add-cudy_tr3000-v1.patch"
if [ -f "$dts_uboot_file" ]; then
    sed -i "s/0x5c0000 0x[0-9a-fA-F]*/0x5c0000 $local_size/g" "$dts_uboot_file"
    echo "Updated $dts_uboot_file"
fi

echo "cudy_tr3000_114m: partition size modification completed"
