#!/usr/bin/env bash
# ==============================================================================
# airoha_an7581 recipe apply.sh
# 1. 注入系统文件 (tempinfo & 96-wifi-5g-cn)
# 2. 保留上游 NPU 固件选择，按编译期开关补全 WiFi 卸载所需的 NPU 保留内存区
# ==============================================================================
set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${1:-${BUILD_DIR:-}}"

if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "错误: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

# recipe runner 通过 TARGET_INI 传入设备配置；未配置时默认关闭。
# 在切换工作目录前读取，兼容相对路径的 TARGET_INI。
ENABLE_WIFI_NPU=0
if [[ -n "${TARGET_INI:-}" ]]; then
    if [[ ! -f "$TARGET_INI" ]]; then
        echo "错误: TARGET_INI 不存在: $TARGET_INI" >&2
        exit 1
    fi
    wifi_npu=$(awk -F= '$1 == "ENABLE_WIFI_NPU" {
        sub(/^[^=]*=/, ""); sub(/\r$/, ""); print; exit
    }' "$TARGET_INI")
    ENABLE_WIFI_NPU="${wifi_npu:-0}"
fi
case "$ENABLE_WIFI_NPU" in
    0|1) ;;
    *) echo "错误: ENABLE_WIFI_NPU 只接受 0 或 1: $ENABLE_WIFI_NPU" >&2; exit 1 ;;
esac

cd "$BUILD_DIR"
echo "=== [airoha_an7581] 正在执行底层平台适配 ==="

# 开启时必须有上游 WiFi NPU 内存定义，避免生成无法编译的 include。
DTS_DIR="target/linux/airoha/dts"
if [[ "$ENABLE_WIFI_NPU" = 1 && ! -f "$DTS_DIR/an7581-npu-wlan.dtsi" ]]; then
    echo "错误: 开启 WiFi NPU 需要 $DTS_DIR/an7581-npu-wlan.dtsi" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. 注入 files/ 文件
# ------------------------------------------------------------------------------
echo ">>> 正在注入 files 文件..."
mkdir -p files/sbin files/etc/uci-defaults
cp -f "$RECIPE_DIR/files/sbin/tempinfo" files/sbin/tempinfo
chmod +x files/sbin/tempinfo
cp -f "$RECIPE_DIR/files/etc/uci-defaults/96-wifi-5g-cn" files/etc/uci-defaults/96-wifi-5g-cn
chmod +x files/etc/uci-defaults/96-wifi-5g-cn

# ------------------------------------------------------------------------------
# 2. 按 ENABLE_WIFI_NPU 为机型 DTS 补全/清理 WiFi NPU 内存预留
# 固件由上游 DEFAULT_PACKAGES/DEVICE_PACKAGES 按设备选择，不在此删除。
# DTS 的内存引用不能替代 NPU 驱动实际请求的 rv32/data 固件文件。
# ------------------------------------------------------------------------------
if [ -d "$DTS_DIR" ]; then
    DTSI="$DTS_DIR/an7581-npu-clanker.dtsi"
    # 需要补齐 NPU 内存引用的 DTS/DTSI 列表
    TARGET_DTS_FILES=(
        "an7581-fiberhome-hg5585f-common.dtsi"
        "an7581-znxt-zn515xg-d.dts"
        "an7581-h3c-hm2004-du.dts"
        "an7581-gemtek-xg2010g.dts"
    )

    if [ "$ENABLE_WIFI_NPU" = 1 ]; then
        echo ">>> ENABLE_WIFI_NPU=1，正在生成 WiFi NPU 内存预留..."
        cat > "$DTSI" <<'EOF'
// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)
/* NPU WiFi 卸载保留内存区补全 */
#include "an7581-npu-wlan.dtsi"
EOF
    else
        echo ">>> ENABLE_WIFI_NPU=0，清理 recipe 注入的 WiFi NPU 内存预留..."
    fi

    for dts_file in "${TARGET_DTS_FILES[@]}"; do
        target_path="$DTS_DIR/$dts_file"
        if [ -f "$target_path" ]; then
            if [ "$ENABLE_WIFI_NPU" = 0 ]; then
                # 仅删除本 recipe 的 include；兼容旧版本及重复切换构建目录。
                sed -i '/^[[:space:]]*#include[[:space:]]*"an7581-npu-clanker\.dtsi"[[:space:]]*$/d' "$target_path"
            elif ! grep -Fq 'an7581-npu-clanker.dtsi' "$target_path"; then
                # 在 #include "an7581.dtsi" 后面注入
                if grep -q '#include "an7581.dtsi"' "$target_path"; then
                    sed -i '/#include "an7581.dtsi"/a #include "an7581-npu-clanker.dtsi"' "$target_path"
                    echo "已为 $dts_file 注入 NPU 内存节点引用"
                else
                    echo '#include "an7581-npu-clanker.dtsi"' >> "$target_path"
                    echo "已为 $dts_file 追加 NPU 内存节点引用"
                fi
            fi
        fi
    done

    if [ "$ENABLE_WIFI_NPU" = 0 ]; then
        rm -f "$DTSI"
    fi
fi

# ------------------------------------------------------------------------------
# 3. 注入 AN7581 内核软 AES / EIP-93 / AF_ALG 配置
# AN7581 无 ARMv8 CE 指令，需开启 NEON 位切片软 AES 与 EIP-93 硬件引擎及 AF_ALG 接口
# ------------------------------------------------------------------------------
echo ">>> 正在配置 AN7581 内核加密与 EIP-93 / AF_ALG 支持..."
shopt -s nullglob
kconfs=(target/linux/airoha/an7581/config-*)
shopt -u nullglob

for kconf in "${kconfs[@]}"; do
    if [ -f "$kconf" ]; then
        echo "正在注入内核配置: $kconf"
        for key in \
            CRYPTO_AES \
            CRYPTO_AES_ARM64 \
            CRYPTO_AES_ARM64_BS \
            CRYPTO_AES_ARM64_NEON_BLK \
            CRYPTO_SIMD \
            CRYPTO_CBC \
            CRYPTO_CTR \
            CRYPTO_XTS \
            CRYPTO_GHASH \
            CRYPTO_GCM \
            CRYPTO_HW \
            CRYPTO_DEV_EIP93 \
            CRYPTO_AUTHENC \
            CRYPTO_DEV_EIP93_AES_128_SW_MAX_LEN \
            CRYPTO_DEV_EIP93_GENERIC_SW_MAX_LEN \
            CRYPTO_USER_API_AEAD \
            CRYPTO_USER_API_HASH \
            CRYPTO_USER_API_SKCIPHER; do
            sed -i -e "/^CONFIG_${key}=/d" -e "/^# CONFIG_${key} is not set$/d" "$kconf"
        done

        cat >> "$kconf" <<'EOF'
CONFIG_CRYPTO_AES=y
CONFIG_CRYPTO_AES_ARM64=y
CONFIG_CRYPTO_AES_ARM64_BS=y
CONFIG_CRYPTO_AES_ARM64_NEON_BLK=y
CONFIG_CRYPTO_SIMD=y
CONFIG_CRYPTO_CBC=y
CONFIG_CRYPTO_CTR=y
CONFIG_CRYPTO_XTS=y
CONFIG_CRYPTO_GHASH=y
CONFIG_CRYPTO_GCM=y
CONFIG_CRYPTO_HW=y
CONFIG_CRYPTO_DEV_EIP93=m
CONFIG_CRYPTO_AUTHENC=y
CONFIG_CRYPTO_DEV_EIP93_AES_128_SW_MAX_LEN=512
CONFIG_CRYPTO_DEV_EIP93_GENERIC_SW_MAX_LEN=256
CONFIG_CRYPTO_USER_API_AEAD=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
EOF
        echo "✅ $kconf EIP-93 / AF_ALG 软硬件混合加密配置写入完成"
    fi
done

echo "=== [airoha_an7581] 平台适配执行完成 ==="
