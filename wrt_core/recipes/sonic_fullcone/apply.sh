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

# ponwrt/ImmortalWrt 的旧 FullCone 补丁与 SONiC 修改同一份 fw3/fw4 源码。
# 只替换已知旧补丁，且须先确认上游已安装替代补丁，避免两套实现叠加。
for legacy_patch in \
    package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch \
    package/network/config/firewall/patches/fullconenat.patch; do
    if [[ -f "$legacy_patch" ]]; then
        sonic_patch="$(dirname "$legacy_patch")/001-sonic-fullcone.patch"
        if [[ ! -s "$sonic_patch" ]]; then
            echo "sonic_fullcone: 缺少替代补丁 $sonic_patch，保留旧补丁并终止构建" >&2
            exit 1
        fi
        rm -f "$legacy_patch"
        echo "sonic_fullcone: 已替换旧补丁: $legacy_patch"
    fi
done

# SONiC 的 fullcone expression 位于 nft_masq 中，不再使用旧 nft_fullcone 模块。
# .config 中的显式选包由 recipe configs 关闭；这里解除源码的强制依赖，
# 否则 defconfig 会再次选中旧模块，导致两种同名 expression 同时装入。
fw4_makefile=package/network/config/firewall4/Makefile
if [[ -s package/network/config/firewall4/patches/001-sonic-fullcone.patch && -f "$fw4_makefile" ]]; then
    sed -i -E 's/\+kmod-nft-fullcone([[:space:]]|$)/\1/g' "$fw4_makefile"
fi
echo "sonic_fullcone: 上游安装完成；运行时开关由 LuCI/UCI 配置"
