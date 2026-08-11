#!/usr/bin/env bash
set -euo pipefail

read_target_ini() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$TARGET_INI"
}

kernel_vermagic=$(read_target_ini KERNEL_VERMAGIC)
kernel_modules=$(read_target_ini KERNEL_MODULES)

if [ -z "$kernel_vermagic" ]; then
    echo "fix_kernel_magic: KERNEL_VERMAGIC is empty; attempting to crawl from mirror"
    
    # 1. 确定 mirror 和 version
    mirror=""
    opkg_mirror=$(read_target_ini OPKG_DISTFEEDS_MIRROR)
    opkg_feeds=$(read_target_ini OPKG_DISTFEEDS)
    if [ -n "$opkg_mirror" ]; then
        mirror="$opkg_mirror"
    elif [ -n "$opkg_feeds" ]; then
        if [ "$opkg_feeds" = "ustc" ]; then
            mirror="https://mirrors.ustc.edu.cn/immortalwrt"
        elif [ "$opkg_feeds" = "nju" ]; then
            mirror="https://mirror.nju.edu.cn/immortalwrt"
        elif [ "$opkg_feeds" = "official" ]; then
            mirror="https://downloads.immortalwrt.org"
        fi
    fi
    [ -z "$mirror" ] && mirror="https://mirror.nju.edu.cn/immortalwrt"
    
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
                version="25.12.1"
            fi
        else
            version="25.12.1"
        fi
    fi
    
    # 2. 从 .config 获取 target_board 和 target_subtarget
    target_board=""
    target_subtarget=""
    if [ -f "$BUILD_DIR/.config" ]; then
        target_board=$(awk -F= '
            $1 ~ /^CONFIG_TARGET_[[:alnum:]]+$/ && $2 == "y" {
                sub(/^CONFIG_TARGET_/, "", $1)
                print $1
                exit
            }
        ' "$BUILD_DIR/.config")
        if [ -n "$target_board" ]; then
            target_subtarget=$(awk -F= -v board="$target_board" '
                $2 == "y" && index($1, "CONFIG_TARGET_" board "_") == 1 && $1 !~ /_DEVICE_/ {
                    sub("^CONFIG_TARGET_" board "_", "", $1)
                    print $1
                    exit
                }
            ' "$BUILD_DIR/.config")
        fi
    fi
    
    # 3. 抓取官方或镜像站的 vermagic
    if [ -n "$target_board" ] && [ -n "$target_subtarget" ]; then
        target_repo="$mirror/releases/$version/targets/$target_board/$target_subtarget"
        kmods_url="$target_repo/kmods/"
        
        fetch_url() {
            local url="$1"
            if command -v curl >/dev/null 2>&1; then
                curl --fail --location --silent --show-error "$url"
            elif command -v wget >/dev/null 2>&1; then
                wget -qO- "$url"
            else
                return 127
            fi
        }
        
        if kmods_listing=$(fetch_url "$kmods_url" 2>/dev/null); then
            kmods_directory=$(printf '%s\n' "$kmods_listing" | sed -n 's|.*href="\([0-9][0-9.]*-[0-9][0-9]*-[0-9a-f][0-9a-f]*\)/".*|\1|p' | sed -n '1p')
            if [ -n "$kmods_directory" ]; then
                kernel_vermagic="${kmods_directory##*-}"
                kernel_modules="$target_repo/kmods/$kmods_directory"
                echo "fix_kernel_magic: Crawled KERNEL_VERMAGIC '$kernel_vermagic'"
                echo "fix_kernel_magic: Crawled KERNEL_MODULES '$kernel_modules'"
            else
                echo "fix_kernel_magic warning: no published kmod ABI found at $kmods_url"
            fi
        else
            echo "fix_kernel_magic warning: unable to fetch published kmod ABIs from $kmods_url"
        fi
    else
        echo "fix_kernel_magic warning: unable to determine target board and subtarget from .config"
    fi
fi

if [ -z "$kernel_vermagic" ]; then
    echo "fix_kernel_magic: KERNEL_VERMAGIC is empty and crawl failed; skipping"
    exit 0
fi

kernel_defaults="$BUILD_DIR/include/kernel-defaults.mk"
kernel_makefile="$BUILD_DIR/package/kernel/linux/Makefile"

if [ ! -f "$kernel_defaults" ]; then
    echo "fix_kernel_magic: missing $kernel_defaults" >&2
    exit 1
fi
if [ ! -f "$kernel_makefile" ]; then
    echo "fix_kernel_magic: missing $kernel_makefile" >&2
    exit 1
fi

sed -i '/\$(LINUX_DIR)\/.vermagic$/c\	echo '"${kernel_vermagic}"' > \$(LINUX_DIR)/.vermagic' "$kernel_defaults"
sed -i '/STAMP_BUILT:=/c\  STAMP_BUILT:=\$(STAMP_BUILT)_'"${kernel_vermagic}" "$kernel_makefile"

echo "fix_kernel_magic: kernel vermagic set to ${kernel_vermagic}"

if [ -n "$kernel_modules" ]; then
    opkg_mirror=$(read_target_ini OPKG_DISTFEEDS_MIRROR)
    opkg_feeds=$(read_target_ini OPKG_DISTFEEDS)
    mirror=""
    if [ -n "$opkg_mirror" ]; then
        mirror="$opkg_mirror"
    elif [ -n "$opkg_feeds" ]; then
        if [ "$opkg_feeds" = "ustc" ]; then
            mirror="https://mirrors.ustc.edu.cn/immortalwrt"
        elif [ "$opkg_feeds" = "nju" ]; then
            mirror="https://mirror.nju.edu.cn/immortalwrt"
        elif [ "$opkg_feeds" = "official" ]; then
            mirror="https://downloads.immortalwrt.org"
        fi
    fi
    [ -z "$mirror" ] && mirror="https://mirror.nju.edu.cn/immortalwrt"

    if [[ "$kernel_modules" =~ ^https://downloads.immortalwrt.org(.*) ]]; then
        kernel_modules="${mirror}${BASH_REMATCH[1]}"
    fi

    uci_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults"
    mkdir -p "$uci_defaults_path"
    cat > "$uci_defaults_path/99-kmod-distfeeds.sh" <<EOF
#!/bin/sh
grep -qxF 'src/gz kmod ${kernel_modules}' /etc/opkg/distfeeds.conf || echo 'src/gz kmod ${kernel_modules}' >> /etc/opkg/distfeeds.conf
exit 0
EOF
    chmod 0755 "$uci_defaults_path/99-kmod-distfeeds.sh"
    echo "fix_kernel_magic: kmod distfeed set to ${kernel_modules}"
fi
