#!/usr/bin/env bash
# ==============================================================================
# luci_app_airoha recipe apply.sh
# 拉取 Airoha 专有 LuCI 状态插件：
# 1. luci-app-airoha-npu (Airoha SoC/NPU/PPE 状态页，带中文)
# 2. luci-app-pon-status (PON 光模块收发光/偏置电流卡片)
# 3. luci-app-natmode (全锥形 NAT1/受限型 NAT3 切换)
# ==============================================================================
set -euo pipefail

BUILD_DIR="${1:-$BUILD_DIR}"

if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "错误: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

cd "$BUILD_DIR"
echo "=== [luci_app_airoha] 正在拉取 Airoha LuCI 状态插件 ==="

PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"

clone_repo() {
    local url="$1" dir="$2" br="${3:-main}"
    rm -rf "$dir"
    git clone --depth 1 -b "$br" "$url" "$dir" 2>&1 | tail -3
}

# 1. 拉取 qwe3017/luci-app (含 luci-app-pon-status, luci-app-natmode)
TMP_DIR="$(mktemp -d)/luci-app"
echo ">>> 正在拉取 qwe3017/luci-app..."
if clone_repo "https://github.com/qwe3017/luci-app.git" "$TMP_DIR" "main"; then
    for p in luci-app-natmode luci-app-pon-status; do
        if [ -d "$TMP_DIR/$p" ]; then
            rm -rf "$PKG_DIR/$p"
            cp -r "$TMP_DIR/$p" "$PKG_DIR/"
            echo "已成功导入: $p"
        fi
    done
    rm -rf "$TMP_DIR"
fi

# 2. 拉取 luanmuc/luci-app-airoha-npu (自带 po/zh_Hans)
echo ">>> 正在拉取 luanmuc/luci-app-airoha-npu..."
if clone_repo "https://github.com/luanmuc/luci-app-airoha-npu.git" "$PKG_DIR/luci-app-airoha-npu" "main"; then
    echo "已成功导入: luci-app-airoha-npu"
    PODIR="$PKG_DIR/luci-app-airoha-npu/po"
    if [ -f "$PODIR/zh_Hans/luci-app-airoha-npu.po" ]; then
        grep -q '^"Language:' "$PODIR/zh_Hans/luci-app-airoha-npu.po" || \
            sed -i 's/^msgstr ""$/msgstr ""\n"Language: zh_Hans\\n"/' "$PODIR/zh_Hans/luci-app-airoha-npu.po"
        mv "$PODIR/zh_Hans/luci-app-airoha-npu.po" "$PODIR/zh_Hans/airoha-npu.po"
        echo "已修正 airoha-npu.po 语言包命名"
    fi
fi

# 3. 重建 package 索引
echo ">>> 正在重建 package 索引 (prepare-tmpinfo)..."
rm -f tmp/.packageinfo tmp/.targetinfo
rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
make -s prepare-tmpinfo OPENWRT_BUILD= 2>&1 | tail -5 || true

echo "=== [luci_app_airoha] 插件拉取与索引完成 ==="
