#!/usr/bin/env bash
set -euo pipefail

echo "kernel_size_expand: starting kernel partition size modification"

target_dir="${BUILD_DIR:-}/target/linux/qualcommax/image"
image_file="$target_dir/ipq60xx.mk"

if [ -z "${BUILD_DIR:-}" ] || [ ! -d "$target_dir" ] || [ ! -f "$image_file" ]; then
    echo "kernel_size_expand: target file ($image_file) not found; skipping"
    exit 0
fi

# 1. 修改 京东云无线宝 亚瑟/百里/雅典娜 (RE-SS-01, RE-CS-02, RE-CS-07) 以及红米 AX5 京东云版 的内核大小为 12M (12288k)
if grep -q "define Device/redmi_ax5-jdcloud" "$image_file"; then
    sed -i "/^define Device\/redmi_ax5-jdcloud/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/redmi_ax5-jdcloud"
fi

if grep -q "define Device/jdcloud_re-ss-01" "$image_file"; then
    sed -i "/^define Device\/jdcloud_re-ss-01/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/jdcloud_re-ss-01"
fi

if grep -q "define Device/jdcloud_re-cs-02" "$image_file"; then
    sed -i "/^define Device\/jdcloud_re-cs-02/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/jdcloud_re-cs-02"
fi

if grep -q "define Device/jdcloud_re-cs-07" "$image_file"; then
    sed -i "/^define Device\/jdcloud_re-cs-07/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/jdcloud_re-cs-07"
fi

# 2. 修改 Link NN6000 v1 / v2 的内核大小为 12M (12288k)
if grep -q "define Device/link_nn6000-v1" "$image_file"; then
    sed -i "/^define Device\/link_nn6000-v1/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/link_nn6000-v1"
fi

if grep -q "define Device/link_nn6000-v2" "$image_file"; then
    sed -i "/^define Device\/link_nn6000-v2/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/link_nn6000-v2"
fi

# 3. 修改 Linksys MR 系列的内核大小为 12M (从 8192k 扩容)
if grep -q "define Device/linksys_mr" "$image_file"; then
    sed -i "/^define Device\/linksys_mr/,/^endef/ { /KERNEL_SIZE := 8192k/s//KERNEL_SIZE := 12288k/ }" "$image_file"
    echo "kernel_size_expand: updated Device/linksys_mr"
fi

# 4. 修改 Linksys MR7350 以追加其 IMAGE_SIZE 配置
if grep -q "define Device/linksys_mr7350" "$image_file"; then
    sed -i "/^define Device\/linksys_mr7350/,/^endef/ s/^endef/\tIMAGE_SIZE := 12288k\nendef/" "$image_file"
    echo "kernel_size_expand: updated Device/linksys_mr7350"
fi

echo "kernel_size_expand: kernel partition size modification completed"
