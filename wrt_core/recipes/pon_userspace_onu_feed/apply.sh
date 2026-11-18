#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-${BUILD_DIR:-}}"
if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "错误: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

ONU_FEED_URL="https://github.com/naoki66/OpenWrt_ONU_CONFIG.git"
ONU_FEED_LINE="src-git pon_userspace ${ONU_FEED_URL};main"

FEEDS_PATH="$BUILD_DIR/feeds.conf.default"
if [[ -f "$BUILD_DIR/feeds.conf" ]]; then
    FEEDS_PATH="$BUILD_DIR/feeds.conf"
fi

if [[ ! -f "$FEEDS_PATH" ]]; then
    echo "错误: 未找到 feeds 配置文件: $FEEDS_PATH" >&2
    exit 1
fi

tmp_file="${FEEDS_PATH}.tmp"
replaced=0
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ "$(printf '%s\n' "$line" | awk '{print $2}')" == "pon_userspace" ]]; then
        if [[ "$replaced" -eq 0 ]]; then
            printf '%s\n' "$ONU_FEED_LINE" >> "$tmp_file"
            replaced=1
        fi
    else
        printf '%s\n' "$line" >> "$tmp_file"
    fi
done < "$FEEDS_PATH"

if [[ "$replaced" -eq 0 ]]; then
    printf '%s\n' "$ONU_FEED_LINE" >> "$tmp_file"
fi
mv "$tmp_file" "$FEEDS_PATH"
echo "pon_userspace_onu_feed: 已将 pon_userspace 指向 $ONU_FEED_URL"

# 复用构建目录时，若原 feeds/pon_userspace 仍指向旧仓库，先清理以重新拉取。
FEED_DIR="$BUILD_DIR/feeds/pon_userspace"
if [[ -d "$FEED_DIR/.git" ]]; then
    current_url="$(git -C "$FEED_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$current_url" != "$ONU_FEED_URL" ]]; then
        echo "pon_userspace_onu_feed: 检测到旧 feed 源 ($current_url)，清理 feeds/pon_userspace 以重新克隆"
        rm -rf "$FEED_DIR" "$BUILD_DIR/feeds/pon_userspace.tmp" "$BUILD_DIR/package/feeds/pon_userspace"
    fi
fi
