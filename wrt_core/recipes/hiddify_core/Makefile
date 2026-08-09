include $(TOPDIR)/rules.mk

PKG_NAME:=hiddify-core
PKG_VERSION:=4.1.0
PKG_RELEASE:=1

PKG_LICENSE:=https://github.com/hiddify/hiddify-app/edit/main/LICENSE.md
PKG_LICENSE_FILES:=LICENSE

PKG_MAINTAINER:=Hiddify <wrt@hiddify.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/hiddify/hiddify-core
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/main

GO_PKG_LDFLAGS_X:= \
	github.com/hiddify/hiddify-core/v2/hcommon/constants.Version=$(PKG_VERSION) \
	github.com/sagernet/sing-box/constant.Version=$(PKG_VERSION)


include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk
GO_PKG_BUILD_VARS := $(filter-out GOTOOLCHAIN=%,$(GO_PKG_BUILD_VARS)) GOTOOLCHAIN=go1.25.6

define Package/hiddify-core
  TITLE:=Hiddify universal proxy platform
  SECTION:=net
  CATEGORY:=Network
  URL:=https://hiddify.com/
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-inet-diag +kmod-tun +firewall4 +kmod-nft-queue
  USERID:=hiddify=15566:hiddify=15566
endef

define Package/hiddify-core/description
  Hiddify is a universal proxy platform which supports hysteria, SOCKS, Shadowsocks,
  ShadowTLS, Tor, trojan, VLess, VMess, WireGuard and so on.
endef

GO_PKG_TAGS:=with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,tfogo_checklinkname0

define Package/hiddify-core/conffiles
/etc/config/hiddify
/etc/hiddify/
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/* $(PKG_BUILD_DIR)/
endef

define Package/hiddify-core/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/main $(1)/usr/bin/hiddify-core

	$(INSTALL_DIR) $(1)/etc/hiddify/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/release/config/config.json $(1)/etc/hiddify/config.json

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/release/config/openwrt.conf $(1)/etc/config/hiddify

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/release/config/openwrt.init $(1)/etc/init.d/hiddify

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/release/config/openwrt.keep $(1)/lib/upgrade/keep.d/hiddify

	$(INSTALL_DIR) $(1)/usr/share/licenses/hiddify-core/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE.md $(1)/usr/share/licenses/hiddify-core/LICENSE.md
endef

$(eval $(call BuildPackage,hiddify-core))
