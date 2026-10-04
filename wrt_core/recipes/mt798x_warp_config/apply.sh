#!/usr/bin/env bash
set -euo pipefail

config="$BUILD_DIR/.config"

if ! grep -qx 'CONFIG_PACKAGE_kmod-mt_wifi=y' "$config"; then
    exit 0
fi

if grep -qx 'CONFIG_MTK_WHNAT_SUPPORT=m' "$config" && grep -qx 'CONFIG_MTK_WARP_V2=y' "$config"; then
    exit 0
fi

echo 'mt798x_warp_config: restoring WARP proxy options after defconfig'
printf 'CONFIG_MTK_WHNAT_SUPPORT=m\nCONFIG_MTK_WARP_V2=y\n' >> "$config"
make -C "$BUILD_DIR" defconfig

if ! grep -qx 'CONFIG_MTK_WHNAT_SUPPORT=m' "$config" || ! grep -qx 'CONFIG_MTK_WARP_V2=y' "$config"; then
    echo 'mt798x_warp_config: unable to enable WARP proxy; check mt_wifi Kconfig dependencies' >&2
    exit 1
fi
