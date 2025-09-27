#!/usr/bin/env bash
#
# Copyright (C) 2025 ZqinKing
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -e

BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1
Build_Mod=$2

if [ -z "$Dev" ]; then
    echo "Usage: $0 <dev_name> [build_mod]"
    echo "或者运行 ./start.sh 进行交互式选择"
    exit 1
fi

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

# 移除 uhttpd 依赖
# 当启用luci-app-quickfile插件时，表示启动nginx，所以移除luci对uhttp(luci-light)的依赖
remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

# 应用配置文件
apply_config() {
    # 复制基础配置文件
    \cp -f "$CONFIG_FILE" "$BASE_PATH/$BUILD_DIR/.config"
    
    # 如果是 ipq60xx 或 ipq807x 平台，则追加 NSS 配置
    if grep -qE "(ipq60xx|ipq807x)" "$BASE_PATH/$BUILD_DIR/.config"; then
        cat "$BASE_PATH/deconfig/nss.config" >> "$BASE_PATH/$BUILD_DIR/.config"
    fi

    # 追加代理配置
    cat "$BASE_PATH/deconfig/proxy.config" >> "$BASE_PATH/$BUILD_DIR/.config"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
DISABLED_FUNCTIONS=$(read_ini_by_key "DISABLED_FUNCTIONS")
ENABLED_FUNCTIONS=$(read_ini_by_key "ENABLED_FUNCTIONS")
KERNEL_VERMAGIC=$(read_ini_by_key "KERNEL_VERMAGIC")
KERNEL_MODULES=$(read_ini_by_key "KERNEL_MODULES")
COMMIT_HASH=${COMMIT_HASH:-none}

if [[ -d $BASE_PATH/action_build ]]; then
    BUILD_DIR="action_build"
fi
chmod +x "$BASE_PATH/update.sh"
$BASE_PATH/update.sh "$REPO_URL" "$REPO_BRANCH" "$BASE_PATH/$BUILD_DIR" "$COMMIT_HASH" "$CONFIG_FILE" "$DISABLED_FUNCTIONS" "$ENABLED_FUNCTIONS" "$KERNEL_VERMAGIC" "$KERNEL_MODULES"

apply_config
remove_uhttpd_dependency

cd "$BASE_PATH/$BUILD_DIR"
make defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec rm -f {} +
fi

make download -j$(($(nproc) * 2)) || make download -j$(nproc) || make download -j1 || make download -j1 V=1 || make download -j1 V=s
make -j$(($(nproc) + 1)) || make -j$(nproc) || make -j$(nproc) V=1 || make -j1 V=1 || make -j1 V=s

FIRMWARE_DIR="$BASE_PATH/firmware/$BUILD_DIR"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.fip" -o -name "*.ubi" -o -name "*rootfs.tar.gz" \) -exec cp -f {} "$FIRMWARE_DIR/" \;
\rm -f "$BASE_PATH/firmware/Packages.manifest" 2>/dev/null

if [[ -d $BASE_PATH/action_build ]]; then
    make clean
fi
