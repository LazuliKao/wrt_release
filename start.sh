#!/usr/bin/env bash

set -e

echo "请选择一个配置："
echo ""

# 获取配置文件列表
configs=(compilecfg/*.ini)
if [ ${#configs[@]} -eq 0 ] || [ ! -f "${configs[0]}" ]; then
    echo "错误：未找到配置文件 (compilecfg/*.ini)"
    exit 1
fi

# 显示配置选项
for i in "${!configs[@]}"; do
    config_name=$(basename "${configs[$i]}" .ini)
    echo "$((i + 1)). $config_name"
done

echo ""
echo -n "请输入选择的编号 (1-${#configs[@]}): "
read -r choice

# 验证输入
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#configs[@]} ]; then
    echo "错误：无效的选择"
    exit 1
fi

# 获取选择的配置名称（去掉 .ini 扩展名）
selected_config="${configs[$((choice - 1))]}"
Dev=$(basename "$selected_config" .ini)

echo "已选择配置: $Dev"
echo ""

# 询问构建方式
echo "请选择构建方式："
echo "1. 容器构建 (build_container.sh)"
echo "2. 普通构建 (build.sh)"
echo ""
echo -n "请输入选择的编号 (1-2): "
read -r build_choice

BASE_PATH=$(pwd)
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"
read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}
BUILD_TARGET_SDK=$(read_ini_by_key "BUILD_TARGET_SDK")

case $build_choice in
1)
    echo "启动容器构建..."
    docker run --rm -it \
        -v "$(pwd)":/build \
        -w /build \
        --shm-size=8g \
        --ipc=shareable \
        --ulimit nofile=65535:65535 \
        $BUILD_TARGET_SDK \
        bash build_container.sh $Dev
    ;;
2)
    echo "启动普通构建..."
    ./build.sh "$Dev"
    ;;
*)
    echo "错误：无效的选择"
    exit 1
    ;;
esac
