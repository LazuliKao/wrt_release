#!/usr/bin/env bash
set -euo pipefail

recipe_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir="${1:-.}"

echo "Applying BDY-G98 board network and kernel patch support..."

# 1. 复制 02_network 到 target 与 rootfs
if [ -d "$build_dir/target/linux/rockchip/armv8/base-files/etc/board.d" ]; then
    cp -f "$recipe_dir/files/target/linux/rockchip/armv8/base-files/etc/board.d/02_network" \
          "$build_dir/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
fi

if [ -d "$build_dir/package/base-files/files/etc/board.d" ]; then
    cp -f "$recipe_dir/files/target/linux/rockchip/armv8/base-files/etc/board.d/02_network" \
          "$build_dir/package/base-files/files/etc/board.d/02_network"
fi

# 2. 复制 49-yt921x 自动加载文件
mkdir -p "$build_dir/package/base-files/files/etc/modules.d"
cp -f "$recipe_dir/files/target/linux/rockchip/armv8/base-files/etc/modules.d/49-yt921x" \
      "$build_dir/package/base-files/files/etc/modules.d/49-yt921x"

# 3. 获取 YT921x DSA 驱动补丁（动态下载 + 本地持久化缓存，带 SHA256 校验）
PATCH_NAME="799-net-dsa-add-motorcomm-yt921x.patch"
PATCH_URL="https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/generic/backport-6.12/${PATCH_NAME}"
EXPECTED_SHA256="ceda8360e790819a7137c6c1ccfea2a0e909d13d3f1fd2ba053c0e2805c87e06"

# 优先在编译树 dl/ 目录或本地 recipe 缓存目录中查找/存放
DL_DIR="$build_dir/dl"
mkdir -p "$DL_DIR"
CACHED_PATCH="$DL_DIR/$PATCH_NAME"

verify_patch() {
    local file="$1"
    if [ -f "$file" ]; then
        local sum
        sum=$(sha256sum "$file" 2>/dev/null | awk '{print $1}' || true)
        if [ "$sum" = "$EXPECTED_SHA256" ]; then
            return 0
        fi
    fi
    return 1
}

if ! verify_patch "$CACHED_PATCH"; then
    echo "Downloading $PATCH_NAME from upstream..."
    rm -f "$CACHED_PATCH"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 10 -o "$CACHED_PATCH" "$PATCH_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -t 3 -T 10 -O "$CACHED_PATCH" "$PATCH_URL"
    else
        echo "Error: neither curl nor wget found to download $PATCH_NAME" >&2
        exit 1
    fi

    if ! verify_patch "$CACHED_PATCH"; then
        echo "Error: Checksum mismatch for downloaded $PATCH_NAME" >&2
        rm -f "$CACHED_PATCH"
        exit 1
    fi
    echo "Downloaded $PATCH_NAME and verified checksum successfully."
else
    echo "Using cached $PATCH_NAME from $CACHED_PATCH."
fi

# 4. 将补丁安装到目标内核补丁目录
if [ -d "$build_dir/target/linux/rockchip/patches-6.12" ]; then
    cp -f "$CACHED_PATCH" "$build_dir/target/linux/rockchip/patches-6.12/$PATCH_NAME"
fi

if [ -d "$build_dir/target/linux/generic/backport-6.12" ]; then
    cp -f "$CACHED_PATCH" "$build_dir/target/linux/generic/backport-6.12/$PATCH_NAME"
fi

echo "BDY-G98 support applied successfully."
