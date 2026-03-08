#!/usr/bin/env bash
#
# build_container.sh - 基于 Docker 容器的一键本地构建脚本
#
# 用法:
#   ./build_container.sh              # 交互式选择配置
#   ./build_container.sh <设备名>     # 直接指定配置，如 x64_immwrt
#
# 此脚本同时作为宿主机入口和容器内执行入口：
#   - 宿主机：选择配置 → 准备容器镜像 → 启动容器构建
#   - 容器内（CONTAINER_BUILD=1）：执行 build.sh 进行编译
#
# INI 可选配置项:
#   BUILD_TARGET_SDK  - 指定基础 Docker 镜像（默认: ubuntu:22.04）
#

set -e

# ============================================================
#  容器内模式：当 CONTAINER_BUILD=1 时，直接执行构建
# ============================================================
if [ "${CONTAINER_BUILD}" = "1" ]; then
    Dev=$1
    if [ -z "$Dev" ]; then
        echo "错误：需要指定设备名"
        echo "用法: $0 <设备名>"
        exit 1
    fi

    LOGFILE="build-${Dev}-$(date +%Y%m%d-%H%M%S).log"
    echo "构建日志: $LOGFILE"

    # 标准输出和标准错误同时写入日志和终端
    exec > >(tee -a "$LOGFILE") 2>&1

    set -x
    ./build.sh "$Dev"
    exit 0
fi

# ============================================================
#  宿主机模式：准备容器并启动构建
# ============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 检查 Docker 是否可用
check_docker() {
    if ! command -v docker &>/dev/null; then
        error "未找到 docker 命令，请先安装 Docker"
    fi
    if ! docker info &>/dev/null; then
        error "Docker 守护进程未运行，请先启动 Docker"
    fi
}

# 定位 wrt_core 目录
find_wrt_core() {
    if [ -d "wrt_core" ]; then
        WRT_CORE_PATH="wrt_core"
    elif [ -d "../wrt_core" ]; then
        WRT_CORE_PATH="../wrt_core"
    else
        error "wrt_core 目录未找到！"
    fi
    BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)
}

# 从 INI 文件读取指定 key 的值
read_ini_by_key() {
    local ini_file=$1
    local key=$2
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$ini_file"
}

# 交互式选择配置
select_config() {
    local configs=("$BASE_PATH"/compilecfg/*.ini)

    if [ ${#configs[@]} -eq 0 ] || [ ! -f "${configs[0]}" ]; then
        error "未找到配置文件 ($BASE_PATH/compilecfg/*.ini)"
    fi

    echo ""
    echo -e "${CYAN}请选择一个配置：${NC}"
    echo ""
    for i in "${!configs[@]}"; do
        local name
        name=$(basename "${configs[$i]}" .ini)
        echo "  $((i + 1)). $name"
    done

    echo ""
    echo -n "请输入选择的编号 (1-${#configs[@]}): "
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#configs[@]} ]; then
        error "无效的选择"
    fi

    local selected="${configs[$((choice - 1))]}"
    Dev=$(basename "$selected" .ini)
}

# 准备容器镜像（生成 Dockerfile 并构建）
prepare_container() {
    local base_image=$1
    local image_name=$2

    info "拉取基础镜像: $base_image"
    docker pull "$base_image"

    # 检测基础镜像的默认用户
    local default_user
    default_user=$(docker run --rm "$base_image" whoami 2>/dev/null || echo "root")

    info "基础镜像默认用户: $default_user"
    info "构建容器镜像: $image_name"

    # 创建临时 Dockerfile
    local tmp_dockerfile
    tmp_dockerfile=$(mktemp /tmp/Dockerfile.XXXXXX)

    cat > "$tmp_dockerfile" <<EOF
FROM ${base_image}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \\
    sudo git jq curl wget \\
    build-essential cmake g++ clang gcc-multilib g++-multilib \\
    bison flex gawk gettext \\
    libelf-dev libncurses5-dev libssl-dev zlib1g-dev \\
    python3 python3-distutils python3-setuptools python3-dev \\
    pkg-config rsync swig unzip file \\
    && rm -rf /var/lib/apt/lists/*
USER ${default_user}
RUN git config --global pull.rebase false && \\
    git config --global advice.detachedHead false
EOF

    docker build -t "$image_name" -f "$tmp_dockerfile" .
    rm -f "$tmp_dockerfile"

    info "容器镜像构建完成: $image_name"
}

# ============================================================
#  主流程
# ============================================================

check_docker
find_wrt_core

# 接受设备名参数，否则交互式选择
Dev=${1:-}
if [ -z "$Dev" ]; then
    select_config
else
    # 验证指定的配置是否存在
    if [ ! -f "$BASE_PATH/compilecfg/${Dev}.ini" ]; then
        error "配置文件不存在: $BASE_PATH/compilecfg/${Dev}.ini"
    fi
fi

INI_FILE="$BASE_PATH/compilecfg/${Dev}.ini"
info "已选择配置: $Dev"
info "INI 文件: $INI_FILE"

# 读取 SDK 基础镜像（INI 中可选配置，默认 ubuntu:22.04）
BUILD_TARGET_SDK=$(read_ini_by_key "$INI_FILE" "BUILD_TARGET_SDK")
BUILD_TARGET_SDK=${BUILD_TARGET_SDK:-"ubuntu:22.04"}

# 生成容器镜像名（设备名转小写，特殊字符替换）
CONTAINER_IMAGE="$(echo "$Dev" | tr '[:upper:]' '[:lower:]' | tr '/:' '-_')-wrt-builder"

info "基础镜像: $BUILD_TARGET_SDK"
info "容器镜像: $CONTAINER_IMAGE"
echo ""

# 检查镜像是否已构建，避免重复构建
if docker image inspect "$CONTAINER_IMAGE" &>/dev/null; then
    echo -e "${YELLOW}容器镜像 $CONTAINER_IMAGE 已存在${NC}"
    echo -n "是否重新构建？(y/N): "
    read -r rebuild
    if [[ "$rebuild" =~ ^[Yy]$ ]]; then
        prepare_container "$BUILD_TARGET_SDK" "$CONTAINER_IMAGE"
    else
        info "使用已有镜像"
    fi
else
    prepare_container "$BUILD_TARGET_SDK" "$CONTAINER_IMAGE"
fi

echo ""
info "启动容器构建: $Dev"
info "项目目录将挂载到容器的 /build"
echo ""

# 启动容器，挂载当前项目目录，运行 build_container.sh 的容器内模式
docker run --rm -it \
    -e CONTAINER_BUILD=1 \
    -v "$(pwd)":/build \
    -w /build \
    --shm-size=8g \
    --ipc=shareable \
    --ulimit nofile=65535:65535 \
    "$CONTAINER_IMAGE" \
    bash build_container.sh "$Dev"
