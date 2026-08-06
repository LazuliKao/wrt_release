#!/usr/bin/env bash
set -euo pipefail

read_target_ini() {
    local key="$1"
    if [ -f "${TARGET_INI:-}" ]; then
        awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$TARGET_INI"
    fi
}

# 1. 默认参数
DEFAULT_MIRROR="https://mirror.nju.edu.cn/immortalwrt"
DEFAULT_VERSION="25.12.1"
DEFAULT_ARCH="aarch64_cortex-a53"

# 2. 读取配置
mirror=$(read_target_ini OPKG_DISTFEEDS_MIRROR)
[ -z "$mirror" ] && mirror="$DEFAULT_MIRROR"

version=$(read_target_ini OPKG_DISTFEEDS_VERSION)
if [ -z "$version" ]; then
    branch=$(read_target_ini REPO_BRANCH)
    if [ -n "$branch" ]; then
        if [[ "$branch" =~ ^v[0-9] ]]; then
            version="${branch#v}"
        elif [[ "$branch" =~ ^openwrt-[0-9] ]]; then
            version="${branch#openwrt-}"
        elif [[ "$branch" =~ ^[0-9] ]]; then
            version="$branch"
        else
            version="$DEFAULT_VERSION"
        fi
    else
        version="$DEFAULT_VERSION"
    fi
fi

arch=$(read_target_ini OPKG_DISTFEEDS_ARCH)
if [ -z "$arch" ]; then
    if [ -f "$BUILD_DIR/.config" ]; then
        config_arch=$(grep '^CONFIG_TARGET_ARCH_PACKAGES=' "$BUILD_DIR/.config" | cut -d'"' -f2)
        if [ -n "$config_arch" ]; then
            arch="$config_arch"
        fi
    fi
fi
[ -z "$arch" ] && arch="$DEFAULT_ARCH"

custom_feeds=$(read_target_ini OPKG_DISTFEEDS)

# 3. 模版解析函数
render_template() {
    local template_file="$1"
    sed -e "s/{VERSION}/$version/g" -e "s/{ARCH}/$arch/g" -e "s|{MIRROR}|$mirror|g" "$template_file"
}

# 4. 检测是否是 APK 包管理器
use_apk=0
if [ -f "$BUILD_DIR/.config" ]; then
    if grep -q '^CONFIG_USE_APK=y' "$BUILD_DIR/.config"; then
        use_apk=1
    fi
fi

# 5. 定位 default-settings 软件包目录
emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
if [ ! -d "$emortal_def_dir" ]; then
    echo "opkg_distfeeds warning: default-settings package directory not found at $emortal_def_dir"
    mkdir -p "$emortal_def_dir/files"
fi

# 6. 获取软件源渲染后的源内容
rendered_content=""
if [ -n "$custom_feeds" ]; then
    # 判断是否是预设名称 (nju / ustc / official)
    if [ -f "$RECIPE_DIR/presets/${custom_feeds}.conf" ]; then
        echo "opkg_distfeeds: Using preset '${custom_feeds}'"
        rendered_content=$(render_template "$RECIPE_DIR/presets/${custom_feeds}.conf")
    else
        # 如果既不是预设文件，又没有空格/src字符，说明输入可能是有误的预设名称，进行回退
        if [[ ! "$custom_feeds" =~ [[:space:]] ]] && [[ ! "$custom_feeds" =~ ^src/ ]]; then
            echo "opkg_distfeeds warning: preset '${custom_feeds}' not found, falling back to 'nju' preset"
            rendered_content=$(render_template "$RECIPE_DIR/presets/nju.conf")
        else
            echo "opkg_distfeeds: Using raw custom feeds from INI"
            rendered_content=$(echo "$custom_feeds" | tr ',' '\n')
        fi
    fi
else
    # 默认使用南京大学预设
    echo "opkg_distfeeds: Using default 'nju' preset"
    rendered_content=$(render_template "$RECIPE_DIR/presets/nju.conf")
fi

# 7. 根据包管理器格式输出并进行补丁
if [ "$use_apk" -eq 1 ]; then
    echo "opkg_distfeeds: Target uses APK package manager, converting feeds to APK repositories format"
    # 将 opkg 格式转换为 apk 格式（去掉 'src/gz <name> ' 前缀）
    apk_content=$(echo "$rendered_content" | sed -E 's/^src\/gz [^ ]+ //g')
    
    repositories_conf="$emortal_def_dir/files/99-repositories"
    mkdir -p "$(dirname "$repositories_conf")"
    echo "$apk_content" > "$repositories_conf"
    
    # 检查并打补丁到 Makefile
    if [ -f "$emortal_def_dir/Makefile" ]; then
        if ! grep -q "99-repositories" "$emortal_def_dir/Makefile"; then
            echo "opkg_distfeeds: patching default-settings Makefile to install 99-repositories"
            sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-repositories \$(1)/etc/99-repositories\n" "$emortal_def_dir/Makefile"
        fi
    fi
    
    # 检查并打补丁到 99-default-settings 启动脚本
    if [ -f "$emortal_def_dir/files/99-default-settings" ]; then
        if ! grep -q "99-repositories" "$emortal_def_dir/files/99-default-settings"; then
            echo "opkg_distfeeds: patching 99-default-settings to load 99-repositories"
            sed -i "/exit 0/i\\
[ -f \'/etc/99-repositories\' ] && mv \'/etc/99-repositories\' \'/etc/apk/repositories\'\n" "$emortal_def_dir/files/99-default-settings"
        fi
    fi
else
    echo "opkg_distfeeds: Target uses OPKG package manager"
    distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    mkdir -p "$(dirname "$distfeeds_conf")"
    echo "$rendered_content" > "$distfeeds_conf"
    
    # 检查并打补丁到 Makefile
    if [ -f "$emortal_def_dir/Makefile" ]; then
        if ! grep -q "99-distfeeds.conf" "$emortal_def_dir/Makefile"; then
            echo "opkg_distfeeds: patching default-settings Makefile to install 99-distfeeds.conf"
            sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" "$emortal_def_dir/Makefile"
        fi
    fi
    
    # 检查并打补丁到 99-default-settings 启动脚本
    if [ -f "$emortal_def_dir/files/99-default-settings" ]; then
        if ! grep -q "99-distfeeds.conf" "$emortal_def_dir/files/99-default-settings"; then
            echo "opkg_distfeeds: patching 99-default-settings to load 99-distfeeds.conf"
            sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" "$emortal_def_dir/files/99-default-settings"
        fi
    fi
fi

echo "opkg_distfeeds: successful"
