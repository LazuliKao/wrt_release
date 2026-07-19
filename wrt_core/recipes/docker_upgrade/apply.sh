#!/usr/bin/env bash
set -euo pipefail

# 打印执行日志
echo "docker_upgrade: [开始] 正在执行容器底层套件与 CLI 客户端越级覆盖方案 (v29.x)..."

# 1. 升级函数：通用下载组件 Makefile
# 参数: $1=组件名称(dockerd/containerd/runc/docker), $2=下载相对路径, $3=目标路径
_download_upstream_file() {
    local pkg_name="$1"
    local file_rel="$2"
    local dest_dir="$3"
    local base_url="https://raw.githubusercontent.com/openwrt/packages/master/utils"
    
    mkdir -p "$(dirname "$dest_dir/$file_rel")"
    if curl -fsSL "$base_url/$pkg_name/$file_rel" -o "$dest_dir/$file_rel"; then
        echo "docker_upgrade: 已成功同步 $pkg_name -> $file_rel"
    else
        echo "docker_upgrade: 警告! 同步 $pkg_name -> $file_rel 失败" >&2
        return 1
    fi
}

# 2. 依次遍历升级四大容器核心组件 (含命令行客户端 docker)
for pkg in dockerd containerd runc docker; do
    echo "docker_upgrade: 正在检索本地 $pkg 路径..."
    
    # 查找本地 feed 缓存中的该包路径
    pkg_dirs=$(find "$BUILD_DIR/package" "$BUILD_DIR/feeds" \( -type d -o -type l \) -name "$pkg" 2>/dev/null)
    
    if [ -z "$pkg_dirs" ]; then
        echo "docker_upgrade: 未在本地源码树中找到 $pkg 路径，跳过..."
        continue
    fi
    
    for dir in $pkg_dirs; do
        # 确保该目录下包含 Makefile，防止误触非软件包目录 (如 oh-my-zsh 插件等)
        if [ ! -f "$dir/Makefile" ]; then
            continue
        fi
        
        # 转换并解析物理真实路径
        real_dir=$(readlink -f "$dir" || echo "$dir")
        echo "docker_upgrade: 目标覆盖路径 -> $real_dir"
        
        case "$pkg" in
            "dockerd")
                # dockerd 除了 Makefile 还有启动脚本和附加依赖配置
                _download_upstream_file "dockerd" "Makefile" "$real_dir"
                _download_upstream_file "dockerd" "Config.in" "$real_dir"
                _download_upstream_file "dockerd" "git-short-commit.sh" "$real_dir"
                _download_upstream_file "dockerd" "files/dockerd.init" "$real_dir"
                _download_upstream_file "dockerd" "files/etc/config/dockerd" "$real_dir"
                _download_upstream_file "dockerd" "files/etc/sysctl.d/sysctl-br-netfilter-ip.conf" "$real_dir"
                ;;
            "containerd")
                _download_upstream_file "containerd" "Makefile" "$real_dir"
                ;;
            "runc")
                _download_upstream_file "runc" "Makefile" "$real_dir"
                ;;
            "docker")
                # 升级命令行客户端以通过 dockerd 的同版本校验
                _download_upstream_file "docker" "Makefile" "$real_dir"
                ;;
        esac
    done
done

# 3. 重建 feed 链接，使修改在编译区生效
echo "docker_upgrade: 重新在 OpenWrt 源码树中建立链接缓存..."
(
    cd "$BUILD_DIR"
    ./scripts/feeds install -f dockerd containerd runc docker
)

echo "docker_upgrade: [成功] 所有容器核心套件与 CLI 客户端已越级覆写为最新版本！"
