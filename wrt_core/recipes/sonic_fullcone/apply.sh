#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-${BUILD_DIR:-}}"
INSTALL_URL="https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh"

if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "sonic_fullcone: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

for tool in curl git bash; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "sonic_fullcone: 缺少工具: $tool" >&2
        exit 1
    fi
done

cd "$BUILD_DIR"
for path in package target feeds/luci/applications/luci-app-firewall; do
    if [[ ! -d "$path" ]]; then
        echo "sonic_fullcone: 缺少源码目录 $path，请确认源码和 LuCI feeds 已准备完成" >&2
        exit 1
    fi
done

# feeds update/install 由项目已有阶段完成；这里只运行上游安装脚本。
# 先检查下载结果，避免 curl 管道失败后被空脚本的成功退出掩盖。
installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT
echo "sonic_fullcone: 下载上游安装脚本: $INSTALL_URL"
curl --fail --show-error --silent --location "$INSTALL_URL" --output "$installer"
if [[ ! -s "$installer" ]]; then
    echo "sonic_fullcone: 上游安装脚本为空" >&2
    exit 1
fi
bash "$installer"
echo "sonic_fullcone: 上游安装完成；运行时开关由 LuCI/UCI 配置"
