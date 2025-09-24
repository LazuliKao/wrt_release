#!/usr/bin/env bash

set -e

LOGFILE="build.log"

# 把标准输出和标准错误都重定向到 tee
exec > >(tee -a "$LOGFILE") 2>&1

# 打开命令回显
set -x


git config --global pull.rebase false
sudo apt-get update
sudo apt-get install jq -y

BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1

./build.sh $Dev "container"