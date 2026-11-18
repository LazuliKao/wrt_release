#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-${BUILD_DIR:-}}"
if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "错误: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

PATCH_SRC="$BUILD_DIR/feeds/pon_userspace/patches/firewall4/010-fw4-zone-device-flowtable.patch"
PATCH_DST_DIR="$BUILD_DIR/package/network/config/firewall4/patches"
PATCH_DST="$PATCH_DST_DIR/010-fw4-zone-device-flowtable.patch"

if [[ -f "$PATCH_SRC" ]]; then
    mkdir -p "$PATCH_DST_DIR"
    cp -f "$PATCH_SRC" "$PATCH_DST"
    echo "pon_userspace_onu: 已应用 firewall4 补丁 010-fw4-zone-device-flowtable.patch"
else
    echo "警告: 未在 feed 中找到 $PATCH_SRC，跳过 firewall4 补丁" >&2
fi
