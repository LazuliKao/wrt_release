#!/usr/bin/env bash
# Shared post-build entry point for local builds and GitHub Actions.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ophub_ref=bad969aa9f6ca124ecc3bc1dffe951311760ff8b
rootfs_dir="$repo_root/firmware"
rootfs_file=""
output_dir="$repo_root/firmware"
board=""
custom_kernel=0

usage() {
    echo "Usage: $0 --board <ophub board|platform|board1_board2> [--rootfs <rootfs.tar.gz> | --rootfs-dir <directory>] [--output <directory>] [--custom-kernel]"
}

while (($#)); do
    case "$1" in
        --board|--rootfs|--rootfs-dir|--output)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in
                --board) board=$2 ;;
                --rootfs) rootfs_file=$2 ;;
                --rootfs-dir) rootfs_dir=$2 ;;
                --output) output_dir=$2 ;;
            esac
            shift 2 ;;
        --custom-kernel)
            custom_kernel=1
            shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -n "$board" && "$board" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Specify a valid ophub board or platform with --board.' >&2; exit 2; }
[[ $(uname -s) == Linux ]] || { echo 'Image packaging requires a Linux host.' >&2; exit 1; }
for cmd in git sudo losetup parted mkfs.btrfs mkfs.ext4 mkfs.vfat curl; do
    command -v "$cmd" >/dev/null || { echo "Missing host dependency: $cmd" >&2; exit 1; }
done

if [[ -z "$rootfs_file" ]]; then
    shopt -s nullglob
    files=("$rootfs_dir"/*rootfs.tar.gz)
    # ARMv8 builds can emit both generic-rootfs and generic-targz-rootfs;
    # the former is the conventional rootfs artifact for remake.
    if ((${#files[@]} > 1)); then
        files=("$rootfs_dir"/*-generic-rootfs.tar.gz)
    fi
    shopt -u nullglob
    ((${#files[@]} == 1)) || { echo "Expected exactly one rootfs tarball in $rootfs_dir; use --rootfs to select one." >&2; exit 1; }
    rootfs_file=${files[0]}
fi
[[ -s "$rootfs_file" && "$rootfs_file" == *rootfs.tar.gz ]] || { echo "Invalid rootfs tarball: $rootfs_file" >&2; exit 1; }
rootfs_file=$(realpath "$rootfs_file")
mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

# Keep ophub's build tree separate from OpenWrt's build tree and published outputs.
workdir=$(mktemp -d "$output_dir/.ophub-remake.XXXXXXXX")
success=0
cleanup() {
    if ((success)); then
        sudo rm -rf -- "$workdir"
    else
        echo "Packaging failed; working directory retained for inspection: $workdir" >&2
    fi
}
trap cleanup EXIT

git clone --quiet https://github.com/ophub/amlogic-s9xxx-openwrt.git "$workdir/remake"
git -C "$workdir/remake" checkout --quiet --detach "$ophub_ref"
mkdir -p "$workdir/remake/openwrt-armsr"
cp "$rootfs_file" "$workdir/remake/openwrt-armsr/"

if ((custom_kernel)); then
    echo "Configuring ophub/remake with local custom kernel chain ($board)..."

    # 1. 查找 OpenWrt 自主编译产出的内核文件 (ARM64 Image)
    local_kernel=""
    for cand in \
        "$rootfs_dir"/*-kernel.bin \
        "$repo_root/firmware"/*-kernel.bin \
        "$repo_root/firmware"/*Image* \
        "$repo_root/action_build/bin/targets/armsr/armv8"/*-kernel.bin \
        "$repo_root/action_build/build_dir/target-aarch64_generic_musl/linux-armsr_armv8/linux-"*/arch/arm64/boot/Image \
        "$repo_root/ophub-immortalwrt/build_dir/target-aarch64_generic_musl/linux-armsr_armv8/linux-"*/arch/arm64/boot/Image; do
        if [[ -f "$cand" ]]; then
            local_kernel=$(realpath "$cand")
            break
        fi
    done

    [[ -n "$local_kernel" ]] || { echo "Error: Local custom kernel not found in $rootfs_dir or build trees." >&2; exit 1; }
    echo "Found local kernel: $local_kernel"

    # 2. 准备本地内核暂存目录供 remake 链接模式使用
    custom_kdir="$workdir/custom_kpkg"
    mkdir -p "$custom_kdir"
    cp -f "$local_kernel" "$custom_kdir/local_Image"

    # 3. 阻止 remake 从 rootfs 中清空 OpenWrt 编译出的 /lib/modules/
    sed -i 's|\[\[ -n "\${tag_rootfs}" && -d "\${tag_rootfs}/lib/modules" \]\] && rm -rf "\${tag_rootfs}/lib/modules"/\*|# custom_kernel: preserve rootfs /lib/modules|g' "$workdir/remake/remake"

    # 4. 彻底屏蔽 download_kernel（不下载任何远程内核）
    sed -i 's|^download_kernel$|# custom_kernel: skip download_kernel|g' "$workdir/remake/remake"

    # 5. 重写 replace_kernel 为本地复制与软链接模式 (保持和原 replace_kernel 完全一致的引导链路规范):
    #    - 安装 local_Image 到 bootfs 命名为 vmlinuz-${kernel_name}
    #    - 对 rockchip: ln -sf vmlinuz-${kernel_name} Image
    #    - 确保 /boot/dtb/rockchip 存在且软链接 dtb-${kernel_name} -> dtb
    #    - 保留 /lib/modules
    cat << 'EOF' > "$workdir/custom_replace_kernel.sh"
replace_kernel() {
    process_msg "(3/6) Installing local custom kernel files (symlink mode)."
    cd "${current_path}"

    local_kernel_bin="CUSTOM_KERNEL_PATH"
    local_kname="6.12"
    if [[ -d "${tag_rootfs}/lib/modules" ]]; then
        local first_mod_dir
        first_mod_dir="$(ls -1 "${tag_rootfs}/lib/modules" 2>/dev/null | grep -E '^[0-9]' | head -n 1 || true)"
        if [[ -n "${first_mod_dir}" ]]; then
            local_kname="${first_mod_dir}"
        fi
    fi
    kernel_name="${local_kname}"

    # 01. 仿照原生 replace_kernel 模式在 /boot 写入实体内核并创建 Image 软链接
    cp -f "${local_kernel_bin}" "${tag_bootfs}/vmlinuz-${kernel_name}"
    (cd "${tag_bootfs}" && rm -f Image && ln -sf "vmlinuz-${kernel_name}" Image)
    [[ -f "${tag_bootfs}/uInitrd-${kernel_name}" ]] && (cd "${tag_bootfs}" && ln -sf "uInitrd-${kernel_name}" uInitrd)

    # 02. 设备树链接模式支持: 保留 dtb-${kernel_name} -> dtb 软链接
    mkdir -p "${tag_bootfs}/dtb/${PLATFORM}"
    (cd "${tag_bootfs}" && rm -f "dtb-${kernel_name}" && ln -sf dtb "dtb-${kernel_name}")

    # 03. 镜像已由 make_image 按原 kernel 值创建；改用本地内核版本时，
    #     同步重命名实际文件，否则后续压缩阶段会找不到 build_image_file。
    local previous_kernel="${kernel}"
    local previous_image_file="${build_image_file}"

    # 04. 修正版本显示和镜像文件名，确保与本地内核版本对齐
    kernel="${kernel_name}"
    openwrt_filename="openwrt_${openwrt_alias}${PLATFORM}_${board}_k${kernel}_$(date +"%Y.%m.%d").img"
    build_image_file="${out_path}/${openwrt_filename}"
    if [[ "${build_image_file}" != "${previous_image_file}" ]]; then
        [[ -f "${previous_image_file}" ]] || error_msg "Image created by make_image is missing: ${previous_image_file}"
        mv -f "${previous_image_file}" "${build_image_file}"
    fi
}
EOF
    sed -i "s|CUSTOM_KERNEL_PATH|$custom_kdir/local_Image|g" "$workdir/custom_replace_kernel.sh"

    # 用自定义函数替换 remake 中的 replace_kernel 函数定义
    python3 -c "
with open('$workdir/remake/remake', 'r') as f:
    content = f.read()
with open('$workdir/custom_replace_kernel.sh', 'r') as f:
    repl = f.read()
import re
new_content = re.sub(r'replace_kernel\(\) \{[\s\S]*?\n\}\n\nrefactor_bootfs', repl + '\n\nrefactor_bootfs', content, count=1)
with open('$workdir/remake/remake', 'w') as f:
    f.write(new_content)
"
fi

echo "Building ophub images for $board from $(basename "$rootfs_file") (revision $ophub_ref)"
(cd "$workdir/remake" && sudo ./remake -b "$board")

shopt -s nullglob
images=("$workdir/remake/openwrt/out/"*.img.gz "${workdir}/remake/openwrt/out/"*.img.xz)
shopt -u nullglob
((${#images[@]} > 0)) || { echo 'ophub/remake produced no compressed images.' >&2; exit 1; }
for image in "${images[@]}"; do
    sudo install -m 0644 "$image" "$output_dir/$(basename "$image")"
done
success=1
echo "Packaged ${#images[@]} image(s) into $output_dir"
