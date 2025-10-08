#!/usr/bin/env bash

set -e

Dev=$1
if [ -z "$Dev" ]; then
    echo "Usage: $0 <dev_name>"
    echo "或者运行 ./start.sh 进行交互式选择"
    exit 1
fi

LOGFILE="build-$Dev-$(date +%Y%m%d-%H%M%S).log"

# 把标准输出和标准错误都重定向到 tee
exec > >(tee -a "$LOGFILE") 2>&1

# 打开命令回显
set -x

BASE_PATH=$(cd $(dirname $0) && pwd)

./build.sh $Dev "container"