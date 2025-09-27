#!/usr/bin/env bash

set -e

Dev=$1
if [ -z "$Dev" ]; then
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
        echo "$((i+1)). $config_name"
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
    selected_config="${configs[$((choice-1))]}"
    Dev=$(basename "$selected_config" .ini)
    
    echo "已选择配置: $Dev"
    echo ""
fi

LOGFILE="build-$Dev-$(date +%Y%m%d-%H%M%S).log"

# 把标准输出和标准错误都重定向到 tee
exec > >(tee -a "$LOGFILE") 2>&1

# 打开命令回显
set -x


git config --global pull.rebase false
sudo apt-get update
sudo apt-get install jq -y
sudo apt-get install build-essential cmake g++ clang bison flex libelf-dev libncurses5-dev python3-distutils zlib1g-dev python3 pkg-config libssl-dev -y

BASE_PATH=$(cd $(dirname $0) && pwd)

./build.sh $Dev "container"