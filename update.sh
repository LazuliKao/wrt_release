#!/usr/bin/env bash

set -e
set -o errexit
set -o errtrace

# 定义错误处理函数
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置trap捕获ERR信号
trap 'error_handler' ERR

source /etc/profile
BASE_PATH=$(cd $(dirname $0) && pwd)

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4
CONFIG_FILE=$5
DISABLED_FUNCTIONS=$6
ENABLED_FUNCTIONS=$7
KERNEL_VERMAGIC=$8
KERNEL_MODULES=$9

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="24.x"
THEME_SET="argon"
LAN_ADDR="192.168.6.1"

_set_config() {
    key=$1
    value=$2
    original=$(grep "^$key" "$CONFIG_FILE" | cut -d'=' -f2)
    echo "Setting $key=$value (original: $original)"
    sed -i "s/^\($key\s*=\s*\).*\$/\1$value/" .config
}
_set_config_quote() {
    key=$1
    value=$2
    original=$(grep "^$key" "$CONFIG_FILE" | cut -d'=' -f2)
    echo "Setting $key=\"$value\" (original: $original)"
    sed -i "s/^\($key\s*=\s*\).*\$/\1\"$value\"/" .config
}
_get_config() {
    key=$1
    grep "^$key=" "$CONFIG_FILE" | cut -d'=' -f2
}
_get_arch_from_config() {
    value_CONFIG_TARGET_x86_64=$(_get_config "CONFIG_TARGET_x86_64")
    if [[ $value_CONFIG_TARGET_x86_64 == "y" ]]; then
        echo "x86_64"
    else
        echo "aarch64"
    fi
}

clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo $REPO_URL $REPO_BRANCH
        git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
    fi
}

clean_up() {
    cd $BUILD_DIR
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    mkdir -p $BUILD_DIR/tmp
    echo "1" >$BUILD_DIR/tmp/.build
}

reset_feeds_conf() {
    if [ "$(git symbolic-ref -q HEAD)" == "" ]; then
        echo "[git] Detached HEAD state Mode"
        git reset --hard HEAD
    else
        git reset --hard origin/$REPO_BRANCH
    fi
    git clean -f -d
    git pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
}

update_feeds() {
    # 删除注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"
    add_feeds() {
        local feed=$1
        local url=$2
        if ! grep -q "$feed" "$BUILD_DIR/$FEEDS_CONF"; then
            # 确保文件以换行符结尾
            [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
            echo "src-git $feed $url" >>"$BUILD_DIR/$FEEDS_CONF"
        fi
    }
    # 检查并添加 small-package 源
    add_feeds "small8" "https://github.com/kenzok8/small-package"
    # 检查并添加 kwrt 源
    add_feeds "kiddin9" "https://github.com/kiddin9/kwrt-packages.git"
    # 检查并添加 opentopd 源
    add_feeds "opentopd" "https://github.com/sirpdboy/sirpdboy-package"
    # 检查并添加 node 源
    add_feeds "node" "https://github.com/nxhack/openwrt-node-packages.git"
    # 检查并添加 libremesh 源
    # add_feeds "libremesh" "https://github.com/libremesh/lime-packages"
    # 添加bpf.mk解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi
    # 切换nss-packages源
    #if grep -q "nss_packages" "$BUILD_DIR/$FEEDS_CONF"; then
    #    sed -i '/nss_packages/d' "$BUILD_DIR/$FEEDS_CONF"
    #    [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
    #    echo "src-git nss_packages https://github.com/ZqinKing/nss-packages.git" >>"$BUILD_DIR/$FEEDS_CONF"
    #fi
    # 更新 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

remove_unwanted_packages() {
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
        "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter" "luci-app-msd_lite"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter"
        "msd_lite"
    )
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-theme-argon" "luci-app-argon-config"
    )

    for pkg in "${luci_packages[@]}"; do
        \rm -rf ./feeds/luci/applications/$pkg
        \rm -rf ./feeds/luci/themes/$pkg
    done

    for pkg in "${packages_net[@]}"; do
        \rm -rf ./feeds/packages/net/$pkg
    done

    for pkg in "${small8_packages[@]}"; do
        \rm -rf ./feeds/small8/$pkg
    done

    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi

    git clone https://github.com/LazuliKao/luci-theme-argon -b openwrt-24.10 ./feeds/luci/themes/luci-theme-argon-new
    mv ./feeds/luci/themes/luci-theme-argon-new/luci-theme-argon ./feeds/luci/themes/luci-theme-argon
    mv ./feeds/luci/themes/luci-theme-argon-new/luci-app-argon-config ./feeds/luci/applications/luci-app-argon-config
    \rm -rf ./feeds/luci/themes/luci-theme-argon-new

    # ipq60xx不支持NSS offload mnet_rx
    if grep -q "nss_packages" "$BUILD_DIR/$FEEDS_CONF"; then
        rm -rf "$BUILD_DIR/feeds/nss_packages/wwan"
    fi

    # 临时放一下，清理脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        git clone --depth 1 $GOLANG_REPO -b $GOLANG_BRANCH ./feeds/packages/lang/golang
    fi
}

install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall luci-app-passwall2 alist luci-app-alist smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns \
        adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash luci-app-homeproxy \
        luci-app-amlogic nikki luci-app-nikki tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf \
        luci-app-wan-mac easytier luci-app-easytier luci-app-control-timewol luci-app-guest-wifi luci-app-wolplus wrtbwmon luci-app-wrtbwmon \
        luci-app-supervisord \
        easytier luci-app-easytier msd_lite luci-app-msd_lite
}

install_opentopd() {
    # \rm -rf ./feeds/opentopd/luci-app-advancedplus
    # git clone https://github.com/sirpdboy/luci-app-advancedplus.git ./feeds/opentopd/luci-app-advancedplus
    ./scripts/feeds install -p opentopd -f cpulimit luci-app-cpulimit luci-app-advanced
}

install_kiddin9() {
    ./scripts/feeds install -p kiddin9 -f luci-app-advancedplus luci-app-change-mac cdnspeedtest luci-app-cloudflarespeedtest qosmate luci-app-qosmate luci-app-unishare unishare
}

install_node() {
    ./scripts/feeds update node
    \rm -rf ./package/feeds/packages/node
    \rm -rf ./package/feeds/packages/node-*
    ./scripts/feeds install -a -p node
}

install_feeds() {
    ./scripts/feeds update -i
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            dir_name=$(basename "$dir")
            if [[ "$dir_name" == "small8" ]]; then
                install_small8
                install_fullconenat
            elif [[ "$dir_name" == "opentopd" ]]; then
                install_opentopd
            elif [[ "$dir_name" == "kiddin9" ]]; then
                install_kiddin9
            elif [[ "$dir_name" == "node" ]]; then
                install_node
            else
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}

fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    if [ -d "$BUILD_DIR/feeds/small8/luci-theme-argon" ]; then
        find "$BUILD_DIR/feeds/small8/luci-theme-argon" -type f -name "cascade*" -exec sed -i 's/--bar-bg/--primary/g' {} \;
    fi

    install -Dm755 "$BASE_PATH/patches/990_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/990_set_argon_primary"
    install -Dm755 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

fix_miniupnpd() {
    local miniupnpd_dir="$BUILD_DIR/feeds/packages/net/miniupnpd"
    local patch_file="999-chanage-default-leaseduration.patch"

    if [ -d "$miniupnpd_dir" ] && [ -f "$BASE_PATH/patches/$patch_file" ]; then
        install -Dm644 "$BASE_PATH/patches/$patch_file" "$miniupnpd_dir/patches/$patch_file"
    fi
}

change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

install_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        ./scripts/feeds install -p small8 -f fullconenat-nft
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        ./scripts/feeds install -p small8 -f fullconenat
    fi
}

fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-basic-mbedtls/wpad-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

add_wifi_default_set() {
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}

remove_something_nss_kmod() {
    local ipq_target_path="$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk"
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    if [ -f $ipq_target_path ]; then
        sed -i 's/kmod-qca-nss-drv-eogremgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-gre//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-map-t//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-match//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-mirror//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-pvxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tun6rd//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tunipip6//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-vxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-macsec//g' $ipq_target_path
    fi

    if [ -f $ipq_mk_path ]; then
        sed -i 's/kmod-qca-nss-crypto //g' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-eogremgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-gre/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-map-t/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-match/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-mirror/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tun6rd/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tunipip6/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-macsec/d' $ipq_mk_path

        sed -i 's/automount //g' $ipq_mk_path
        sed -i 's/cpufreq //g' $ipq_mk_path
    fi
}

update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}

fix_build_for_openssl() {
    local openssl_dir="$BUILD_DIR/package/libs/openssl"
    local makefile="$openssl_dir/Makefile"
    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        if grep -q "3.0.16" "$makefile"; then
            # 替换本地openssl版本
            rm -rf "$openssl_dir"
            cp -rf "$BASE_PATH/patches/openssl" "$openssl_dir"
        fi
    fi
}

update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"

    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        [ -f "$new_mk" ] && \rm -f "$new_mk"
        curl -L -o "$new_mk" https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile
        \mv -f "$new_mk" "$makefile"
    fi
}

fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}

add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"

    # 删除旧的目录（如果存在）
    rm -rf "$athena_led_dir" 2>/dev/null

    # 克隆最新的仓库
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git "$athena_led_dir"
    # 设置执行权限
    chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
    chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
}

chanage_cpuusage() {
    local luci_dir="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local imm_script1="$BUILD_DIR/package/base-files/files/sbin/cpuusage"

    if [ -f $luci_dir ]; then
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" $luci_dir
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' $luci_dir
    fi

    if [ -f "$imm_script1" ]; then
        rm -f "$imm_script1"
    fi

    install -Dm755 "$BASE_PATH/patches/cpuusage" "$BUILD_DIR/target/linux/qualcommax/base-files/sbin/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin/cpuusage"
}

update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ] && [ -f "$tcping_path" ]; then
        \rm -f "$tcping_path"
        curl -L -o "$tcping_path" https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile
    fi
}

set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存请求定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_watchdog 任务
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_watchdog 任务，每10分钟执行一次
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

update_pw() {
    local pw_share_dir="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall"
    local smartdns_lua_path="$pw_share_dir/helper_smartdns_add.lua"
    local rules_dir="$pw_share_dir/rules"

    # 清空chnlist
    [ -f "$rules_dir/chnlist" ] && echo "" >"$rules_dir/chnlist"
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}

update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by LazuliKao')/g" "$file"
    fi
}

fix_compile_vlmcsd() {
    local dir="$BUILD_DIR/feeds/packages/net/vlmcsd"
    local patch_src="$BASE_PATH/patches/001-fix_compile_with_ccache.patch"
    local patch_dest="$dir/patches"

    if [ -d "$dir" ]; then
        mkdir -p "$patch_dest"
        cp -f "$patch_src" "$patch_dest"
    fi
}

update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        \rm -f "$file"
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
        git clone --depth 1 "$repo_url" "$target_dir"
    fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i '/dns_redirect/d' "$file"
    fi
}

# 更新版本
update_package() {
    local dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name $1)
    if [ -z $dir ]; then
        return 0
    fi
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        # 提取repo
        local PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z $PKG_REPO ]; then
            return 0
        fi
        local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r '.[0].tag_name')
        PKG_VER=$(echo $PKG_VER | grep -oE "[\.0-9]{1,}")

        local PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE=$(awk -F"=" '/PKG_SOURCE:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE_URL=$(awk -F"=" '/PKG_SOURCE_URL:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")

        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_VERSION\)/$PKG_VER}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_VERSION\)/$PKG_VER}

        local PKG_HASH=$(curl -sL "$PKG_SOURCE_URL""$PKG_SOURCE" | sha256sum | cut -b -64)

        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' $mk_path
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' $mk_path

        echo "Update Package $1 to $PKG_VER $PKG_HASH"
    fi
}

# 添加系统升级时的备份信息
function add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

# 更新启动顺序
function update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

function optimize_smartDNS() {
    local smartdns_custom="$BUILD_DIR/feeds/small8/smartdns/conf/custom.conf"
    local smartdns_patch="$BUILD_DIR/feeds/small8/smartdns/patches/010_change_start_order.patch"
    install -Dm644 "$BASE_PATH/patches/010_change_start_order.patch" "$smartdns_patch"

    # 检查配置文件所在的目录和文件是否存在
    if [ -d "${smartdns_custom%/*}" ] && [ -f "$smartdns_custom" ]; then
        # 优化配置选项：
        # serve-expired-ttl: 缓存有效期(单位：小时)，默认值影响DNS解析速度
        # serve-expired-reply-ttl: 过期回复TTL
        # max-reply-ip-num: 最大IP数
        # dualstack-ip-selection-threshold: IPv6优先的阈值
        # server: 配置上游DNS
        echo "优化SmartDNS配置"
        cat >"$smartdns_custom" <<'EOF'
serve-expired-ttl 7200
serve-expired-reply-ttl 5
max-reply-ip-num 3
dualstack-ip-selection-threshold 15
server 223.5.5.5 -bootstrap-dns
EOF
    fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g' "$mosdns_conf"
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

fix_quickstart() {
    local qs_index_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/htdocs/luci-static/quickstart/index.js"
    local fix_path="$BASE_PATH/patches/quickstart_index.js"
    if [ -f "$qs_index_path" ] && [ -f "$fix_path" ]; then
        cat "$fix_path" >"$qs_index_path"
    else
        echo "Quickstart index.js 或补丁文件不存在，请检查路径是否正确。"
    fi
}

update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"

    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            -e "s/auto_load_engine '1'/auto_load_engine '0'/g" \
            "$conf_path"
    fi

    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"

        # 禁用脚本
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

support_fw4_adg() {
    local src_path="$BASE_PATH/patches/AdGuardHome"
    local dst_path="$BUILD_DIR/package/feeds/small8/luci-app-adguardhome/root/etc/init.d/AdGuardHome"
    # 验证源路径是否文件存在且是文件，目标路径目录存在且脚本路径合法
    if [ -f "$src_path" ] && [ -d "${dst_path%/*}" ] && [ -f "$dst_path" ]; then
        # 使用 install 命令替代 cp 以确保权限和备份处理
        install -Dm 755 "$src_path" "$dst_path"
        echo "已更新AdGuardHome启动脚本"
    fi
}

add_timecontrol() {
    local timecontrol_dir="$BUILD_DIR/package/luci-app-timecontrol"
    # 删除旧的目录（如果存在）
    rm -rf "$timecontrol_dir" 2>/dev/null
    git clone --depth 1 https://github.com/sirpdboy/luci-app-timecontrol.git "$timecontrol_dir"
}

add_gecoosac() {
    local gecoosac_dir="$BUILD_DIR/package/openwrt-gecoosac"
    # 删除旧的目录（如果存在）
    rm -rf "$gecoosac_dir" 2>/dev/null
    git clone --depth 1 https://github.com/lwb1978/openwrt-gecoosac.git "$gecoosac_dir"
}

update_proxy_app_menu_location() {
    # passwall
    local passwall_path="$BUILD_DIR/package/feeds/small8/luci-app-passwall/luasrc/controller/passwall.lua"
    if [ -d "${passwall_path%/*}" ] && [ -f "$passwall_path" ]; then
        local pos=$(grep -n "entry" "$passwall_path" | head -n 1 | awk -F ":" '{print $1}')
        if [ -n $pos ]; then
            sed -i ''${pos}'i\	entry({"admin", "proxy"}, firstchild(), "Proxy", 30).dependent = false' "$passwall_path"
            sed -i 's/"services"/"proxy"/g' "$passwall_path"
        fi
    fi
    # passwall2
    local passwall2_path="$BUILD_DIR/package/feeds/small8/luci-app-passwall2/luasrc/controller/passwall2.lua"
    if [ -d "${passwall2_path%/*}" ] && [ -f "$passwall2_path" ]; then
        local pos=$(grep -n "entry" "$passwall2_path" | head -n 1 | awk -F ":" '{print $1}')
        if [ -n $pos ]; then
            sed -i ''${pos}'i\	entry({"admin", "proxy"}, firstchild(), "Proxy", 30).dependent = false' "$passwall2_path"
            sed -i 's/"services"/"proxy"/g' "$passwall2_path"
        fi
    fi

    # homeproxy
    local homeproxy_path="$BUILD_DIR/package/feeds/small8/luci-app-homeproxy/root/usr/share/luci/menu.d/luci-app-homeproxy.json"
    if [ -d "${homeproxy_path%/*}" ] && [ -f "$homeproxy_path" ]; then
        sed -i 's/\/services\//\/proxy\//g' "$homeproxy_path"
    fi

    # nikki
    local nikki_path="$BUILD_DIR/package/feeds/small8/luci-app-nikki/root/usr/share/luci/menu.d/luci-app-nikki.json"
    if [ -d "${nikki_path%/*}" ] && [ -f "$nikki_path" ]; then
        sed -i 's/\/services\//\/proxy\//g' "$nikki_path"
    fi
}

update_dns_app_menu_location() {
    # smartdns
    local smartdns_path="$BUILD_DIR/package/feeds/small8/luci-app-smartdns/luasrc/controller/smartdns.lua"
    if [ -d "${smartdns_path%/*}" ] && [ -f "$smartdns_path" ]; then
        local pos=$(grep -n "entry" "$smartdns_path" | head -n 1 | awk -F ":" '{print $1}')
        if [ -n $pos ]; then
            sed -i ''${pos}'i\	entry({"admin", "dns"}, firstchild(), "DNS", 29).dependent = false' "$smartdns_path"
            sed -i 's/"services"/"dns"/g' "$smartdns_path"
        fi
    fi

    # mosdns
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/usr/share/luci/menu.d/luci-app-mosdns.json"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/\/services\//\/dns\//g' "$mosdns_path"
    fi

    # AdGuardHome
    local adg_path="$BUILD_DIR/package/feeds/small8/luci-app-adguardhome/luasrc/controller/AdGuardHome.lua"
    if [ -d "${adg_path%/*}" ] && [ -f "$adg_path" ]; then
        sed -i 's/"services"/"dns"/g' "$adg_path"
    fi
}

fix_easytier() {
    local easytier_path="$BUILD_DIR/package/feeds/small8/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -d "${easytier_path%/*}" ] && [ -f "$easytier_path" ]; then
        sed -i 's/util/xml/g' "$easytier_path"
    fi
}

update_geoip() {
    local geodata_path="$BUILD_DIR/package/feeds/small8/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' $geodata_path | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            # 下载旧的geoip.dat和新的geoip-only-cn-private.dat文件的校验和
            local old_SHA256=$(wget -qO- "$base_url/geoip.dat.sha256sum" | awk '{print $1}')
            local new_SHA256=$(wget -qO- "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}')
            # 更新Makefile中的文件名和校验和
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g" "$geodata_path"
                    sed -i "s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}

update_lucky() {
    local version=$(find "$BASE_PATH/patches" -name "lucky*" -printf "%f\n" | head -n 1 | awk -F'_' '{print $2}')
    local mk_dir="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ -d "${mk_dir%/*}" ] && [ -f "$mk_dir" ]; then
        sed -i '/Build\/Prepare/ a\	[ -f $(TOPDIR)/../patches/lucky_'${version}'_Linux_$(LUCKY_ARCH)_wanji.tar.gz ] && install -Dm644 $(TOPDIR)/../patches/lucky_'${version}'_Linux_$(LUCKY_ARCH)_wanji.tar.gz $(PKG_BUILD_DIR)/$(PKG_NAME)_$(PKG_VERSION)_Linux_$(LUCKY_ARCH).tar.gz' "$mk_dir"
        sed -i '/wget/d' "$mk_dir"
    fi
}

update_base_files() {
    local base_files_path="$BUILD_DIR/package/base-files/files"
    local uci_defaults_path="$base_files_path/etc/uci-defaults"
    if [ -d "$uci_defaults_path" ]; then
        cp -f "$BASE_PATH/uci-defaults/"* "$uci_defaults_path"
    fi
}

add_ohmyzsh() {
    local base_files_path="$BUILD_DIR/package/base-files/files"
    echo "Adding oh-my-zsh"
    mkdir -p "$base_files_path/root"
    if [ -d "$base_files_path/root/.oh-my-zsh" ]; then
        rm -rf "$base_files_path/root/.oh-my-zsh"
    fi
    git clone https://mirror.nju.edu.cn/git/ohmyzsh.git "$base_files_path/root/.oh-my-zsh"
    if [ -f "$base_files_path/root/.zshrc" ]; then
        rm "$base_files_path/root/.zshrc"
    fi
    cp "$base_files_path/root/.oh-my-zsh/templates/zshrc.zsh-template" "$base_files_path/root/.zshrc"
    # echo "source /etc/profile" >> "$base_files_path/root/.zshrc"
    sed -i "1i source /etc/profile" "$base_files_path/root/.zshrc"
    # sed -i "s:/bin/ash:/usr/bin/zsh:g" "base_files_path/etc/passwd"
}

add_nbtverify() {
    local base_files_path="$BUILD_DIR/package/base-files/files"
    echo "Adding nbtverify"
    mkdir -p "$base_files_path/root"
    local ipk_path="$base_files_path/root/luci-app-nbtverify.ipk"
    if [ -f "$ipk_path" ]; then
        echo "luci-app-nbtverify already exists"
        return
    fi
    local arch=$(_get_arch_from_config)
    if [[ $arch == "x86_64" ]]; then
        wget https://github.com/LazuliKao/luci-app-nbtverify/releases/download/v0.1.9/luci-app-nbtverify_amd64_x86_64.ipk -O "$ipk_path"
    elif [[ $arch == "aarch64" ]]; then
        wget https://github.com/LazuliKao/luci-app-nbtverify/releases/download/v0.1.9/luci-app-nbtverify_arm64_aarch64_cortex-a53.ipk -O "$ipk_path"
    else
        echo "[nbtverify] Unsupported architecture: $arch"
        return
    fi
}

add_turboacc() {
    cd "$BUILD_DIR"
    curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
    bash add_turboacc.sh --no-sfe
    cd -
}

fix_cudy_tr3000_114m() {

    #mt7981b-cudy-tr3000-v1-ubootmod.dts
    #  target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts
    #  target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts
    local size="0x7200000" #114MB
    # local size="0x7000000" #112MB
    local dts_file="$BUILD_DIR/target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1-ubootmod.dts"
    if [ -f "$dts_file" ]; then
        sed -i "s/reg = <0x5c0000 0x[0-9a-fA-F]*>/reg = <0x5c0000 $size>/g" "$dts_file"
        echo "Updated $dts_file"
    fi
    local dts_file2="$BUILD_DIR/target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts"
    if [ -f "$dts_file2" ]; then
        sed -i "s/reg = <0x5c0000 0x[0-9a-fA-F]*>/reg = <0x5c0000 $size>/g" "$dts_file2"
        echo "Updated $dts_file2"
    fi
    local dts_uboot_file="$BUILD_DIR/package/boot/uboot-mediatek/patches/445-add-cudy_tr3000-v1.patch"
    if [ -f "$dts_uboot_file" ]; then
        sed -i "s/0x5c0000 0x[0-9a-fA-F]*/0x5c0000 $size/g" "$dts_uboot_file"
        echo "Updated $dts_uboot_file"
    fi
    local dts_for_padavanonly="$BUILD_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-cudy-tr3000-v1.dts"
    if [ -f "$dts_for_padavanonly" ]; then
        sed -i "s/reg = <0x5c0000 0x[0-9a-fA-F]*>/reg = <0x5c0000 $size>/g" "$dts_for_padavanonly"
        echo "Updated $dts_for_padavanonly"
    fi
}

fix_kernel_magic() {
    # Check if KERNEL_VERMAGIC is empty or not specified
    if [ -z "$KERNEL_VERMAGIC" ]; then
        echo "KERNEL_VERMAGIC is empty, skipping kernel magic fix"
        return 0
    fi

    local kernel_defaults="$BUILD_DIR/include/kernel-defaults.mk"
    sed -i "/\\\$(LINUX_DIR)\/.vermagic$/c\\\techo ${KERNEL_VERMAGIC} > \\\$(LINUX_DIR)/.vermagic" "$kernel_defaults"
    echo "Kernel vermagic set to: $KERNEL_VERMAGIC"

    local kernel_makefile="$BUILD_DIR/package/kernel/linux/Makefile"
    sed -i "/STAMP_BUILT:=/c\\  STAMP_BUILT:=\\\$(STAMP_BUILT)_$KERNEL_VERMAGIC" "$kernel_makefile"

    # If KERNEL_MODULES is specified, add the distfeeds.conf
    if [ -n "$KERNEL_MODULES" ]; then
        local base_files_path="$BUILD_DIR/package/base-files/files"
        local uci_defaults_path="$base_files_path/etc/uci-defaults"
        if [ -d "$uci_defaults_path" ]; then
            cat <<EOF >"$uci_defaults_path/99-kmod-distfeeds.sh"
echo "src/gz kmod $KERNEL_MODULES" >> /etc/opkg/distfeeds.conf
EOF
        fi
    fi
}

update_mt76() {
    echo "Update Mt76 version."
    patch -p1 <"$BASE_PATH/patches/update_mt76.patch"
    echo "Add extra patch file for mt76."
    local mt76_patch_dir="$BUILD_DIR/package/kernel/mt76/patches"
    if [ -d "$mt76_patch_dir" ]; then
        cp -f "$BASE_PATH/patches/mt76/002_mt76_mt7921_fix_returned_txpower.patch" "$mt76_patch_dir"
        cp -f "$BASE_PATH/patches/mt76/003_mt76_mt7925_fix_returned_txpower.patch" "$mt76_patch_dir"
    else
        echo "Mt76 patch directory does not exist: $mt76_patch_dir"
    fi
}

_trim_space() {
    local str=$1
    echo "$str" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
_call_function() {
    local func_name=$1
    shift
    if type "$func_name" &>/dev/null; then
        "$func_name" "$@"
    else
        echo "    Function '$func_name' not found."
    fi
}
_run_function() {
    local func_name=$1
    shift
    if [[ $func_name =~ ^# ]]; then
        local original_name=${func_name:1}
        local original_name=$(_trim_space "$original_name")
        if [[ $ENABLED_FUNCTIONS =~ $original_name ]]; then
            echo "+ '$original_name'"
            echo "    Call Force-Enabled Function '$original_name'"
            _call_function "$original_name" "$@"
        else
            echo "- '$original_name'"
            echo "    Skip Comment Function '$original_name'"
        fi
    elif [[ $DISABLED_FUNCTIONS =~ $func_name ]]; then
        echo "- '$func_name'"
        echo "    Skip Disabled Function '$func_name'"
    else
        echo "+ '$func_name'"
        _call_function "$func_name" "$@"
    fi
}
_foreach_function() {
    while read -r func_name; do
        if [ -n "$func_name" ]; then
            _run_function "$func_name"
        fi
    done < <(cat)
}

main() {
    cat <<EOF | _foreach_function

    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    remove_unwanted_packages
    update_homeproxy
    fix_default_set
    fix_miniupnpd
    update_golang
    change_dnsmasq2full
    fix_mk_def_depends
    add_wifi_default_set
    update_default_lan_addr
    remove_something_nss_kmod
    update_affinity_script
    # fix_build_for_openssl
    update_ath11k_fw
    # fix_mkpkg_format_invalid
    chanage_cpuusage
    update_tcping
    add_ax6600_led
    set_custom_task
    update_pw
    install_opkg_distfeeds
    update_nss_pbuf_performance
    set_build_signature
    fix_compile_vlmcsd
    update_nss_diag
    update_menu_location
    fix_compile_coremark
    update_dnsmasq_conf
    add_backup_info_to_sysupgrade
    optimize_smartDNS
    update_mosdns_deconfig
    fix_quickstart
    update_oaf_deconfig
    add_timecontrol
    add_gecoosac
    # update_lucky
    install_feeds
    support_fw4_adg
    update_script_priority
    update_base_files
    add_ohmyzsh
    add_nbtverify
    # add_turboacc
    # fix_cudy_tr3000_114m
    fix_easytier
    update_geoip
    update_package "xray-core"
    # update_proxy_app_menu_location
    update_dns_app_menu_location
    # fix_kernel_magic
    # update_mt76

EOF
}

main "$@"
