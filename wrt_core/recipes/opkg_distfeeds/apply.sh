#!/usr/bin/env bash
set -euo pipefail

source "$RECIPE_DIR/repositories.sh"
distfeeds_init
distfeeds_resolve_kmods
distfeeds_fix_kernel_magic

# 模板解析
render_template() {
    local template_file="$1"
    sed -e "s/{VERSION}/$version/g" -e "s/{ARCH}/$arch/g" \
        -e "s|{MIRROR}|$mirror|g" -e "s|{REPO_PATH}|$repo_path|g" "$template_file"
}

# 定位 default-settings 软件包目录
emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
if [ ! -d "$emortal_def_dir" ]; then
    echo "opkg_distfeeds warning: default-settings package directory not found at $emortal_def_dir"
    mkdir -p "$emortal_def_dir/files"
fi

# 获取软件源内容
if [[ "$custom_feeds" =~ [[:space:]] || "$custom_feeds" =~ ^src/ || "$custom_feeds" =~ ^https?:// ]]; then
    echo "opkg_distfeeds: Using raw custom feeds from INI"
    rendered_content=$(printf '%s\n' "$custom_feeds" | tr ',' '\n')
else
    case "$custom_feeds" in
        ''|nju|ustc|official) ;;
        *) echo "opkg_distfeeds warning: unknown preset '$custom_feeds'; using default mirror" ;;
    esac
    rendered_content=$(render_template "$RECIPE_DIR/presets/default.conf")
fi

# 根据包管理器格式输出并进行补丁
if [ "$use_apk" -eq 1 ]; then
    echo "opkg_distfeeds: Target uses APK package manager, converting feeds to APK repository indexes"
    # APK repositories must name the package index explicitly; a bare feed URL
    # makes apk request the legacy APKINDEX.tar.gz instead of packages.adb.
    standard_apk_content=$(printf '%s\n' "$rendered_content" | awk '
        /^[[:space:]]*($|#)/ { print; next }
        {
            sub(/^src\/gz[[:space:]]+[^[:space:]]+[[:space:]]+/, "")
            sub(/\/+$/, "")
            if ($0 !~ /\/packages\.adb$/) {
                $0 = $0 "/packages.adb"
            }
            print
        }
    ')

    target_apk_content=""
    if [ -n "$target_repo" ]; then
        target_apk_content="$target_repo/packages/packages.adb"
    else
        echo "opkg_distfeeds warning: unable to determine target board and subtarget; omitting target repository"
    fi
    if [ -n "$kernel_modules" ]; then
        target_apk_content="${target_apk_content:+$target_apk_content\n}$kernel_modules/packages.adb"
    fi

    if [ -n "$target_apk_content" ]; then
        apk_content=$(printf '%b\n%s\n' "$target_apk_content" "$standard_apk_content")
    else
        apk_content="$standard_apk_content"
    fi

    distfeeds_list="$emortal_def_dir/files/99-distfeeds.list"
    mkdir -p "$(dirname "$distfeeds_list")"
    printf '%s\n' "$apk_content" > "$distfeeds_list"

    # A previous recipe version installed bare URLs into /etc/apk/repositories.
    # Remove that override so only the valid repository.d feed list is active.
    rm -f "$emortal_def_dir/files/99-repositories"

    if [ -f "$emortal_def_dir/Makefile" ]; then
        sed -i '/99-repositories/d' "$emortal_def_dir/Makefile"
        if ! grep -q "99-distfeeds.list" "$emortal_def_dir/Makefile"; then
            echo "opkg_distfeeds: patching default-settings Makefile to install 99-distfeeds.list"
            sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.list \$(1)/etc/99-distfeeds.list\n" "$emortal_def_dir/Makefile"
        fi
    fi

    if [ -f "$emortal_def_dir/files/99-default-settings" ]; then
        sed -i "\|^\[ -f '/etc/99-repositories' \] && mv '/etc/99-repositories' '/etc/apk/repositories'$|d" "$emortal_def_dir/files/99-default-settings"
        if ! grep -q "99-distfeeds.list" "$emortal_def_dir/files/99-default-settings"; then
            echo "opkg_distfeeds: patching 99-default-settings to load 99-distfeeds.list"
            sed -i "/exit 0/i\\
[ -f '/etc/99-distfeeds.list' ] && mv '/etc/99-distfeeds.list' '/etc/apk/repositories.d/distfeeds.list'\n" "$emortal_def_dir/files/99-default-settings"
        fi
    fi
else
    echo "opkg_distfeeds: Target uses OPKG package manager"
    if [ -n "$kernel_modules" ]; then
        rendered_content="$rendered_content
src/gz kmod $kernel_modules"
    fi
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
