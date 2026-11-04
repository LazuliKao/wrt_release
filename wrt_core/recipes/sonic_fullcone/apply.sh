#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-${BUILD_DIR:-}}"
INSTALL_URL="https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh"

cd "$BUILD_DIR"
installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT
curl --fail --show-error --silent --location "$INSTALL_URL" --output "$installer"
bash "$installer"

# 上游使用新文件名，安装成功后移除仍会参与构建的旧补丁。
rm -f \
    package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch \
    package/network/config/firewall/patches/fullconenat.patch

# 避免 defconfig 通过旧依赖重新选中独立 Full Cone 模块。
for package in firewall4 firewall; do
    makefile="package/network/config/$package/Makefile"
    if [[ -f "$makefile" ]]; then
        if [[ "$package" == firewall4 ]]; then
            dependency=kmod-nft-fullcone
        else
            dependency=iptables-mod-fullconenat
        fi
        sed -i -E "s/\\+$dependency([[:space:]]|$)/\\1/g" "$makefile"
    fi
done

# 保留包源码，只关闭旧模块、旧管理插件及其翻译包。
sed -i -E \
    -e '/^(CONFIG_PACKAGE_|# CONFIG_PACKAGE_)(kmod-ipt-fullconenat|iptables-mod-fullconenat|ip6tables-mod-fullconenat|kmod-nft-fullcone|luci-app-turboacc-mtk|luci-app-natmode)(=| is not set)/d' \
    -e 's/^CONFIG_PACKAGE_(luci-i18n-(turboacc-mtk|natmode)-[^=]+)=[ym]$/# CONFIG_PACKAGE_\1 is not set/' \
    .config
for package in kmod-ipt-fullconenat iptables-mod-fullconenat \
    ip6tables-mod-fullconenat kmod-nft-fullcone \
    luci-app-turboacc-mtk luci-app-natmode; do
    printf '# CONFIG_PACKAGE_%s is not set\n' "$package" >> .config
done
