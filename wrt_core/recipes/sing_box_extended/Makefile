include $(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=1.13.14-extended-2.5.3
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:sagernet:sing-box

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/sing-box
GO_PKG_LDFLAGS_X:=$(GO_PKG)/constant.Version=$(PKG_VERSION)
GO_PKG_LDFLAGS:=-X internal/godebug.defaultGODEBUG=multipathtcp=0 -checklinkname=0

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# The fork requires Go 1.26.4. The local replacement Golang feed supplies Go 1.26.5.
GO_PKG_BUILD_VARS := $(filter-out GOTOOLCHAIN=%,$(GO_PKG_BUILD_VARS)) GOTOOLCHAIN=local

SING_BOX_NAIVE_TARGET:=0
ifneq ($(filter amd64 arm64 loong64 riscv64,$(GO_ARCH)),)
  SING_BOX_NAIVE_TARGET:=1
endif
ifeq ($(GO_ARCH),386)
  ifeq ($(GO_386),sse2)
    SING_BOX_NAIVE_TARGET:=1
  endif
endif
ifeq ($(GO_ARCH),arm)
  ifeq ($(GO_ARM),7)
    SING_BOX_NAIVE_TARGET:=1
  endif
endif
ifeq ($(GO_ARCH),mipsle)
  ifeq ($(GO_MIPS),softfloat)
    SING_BOX_NAIVE_TARGET:=1
  endif
endif

ifeq ($(SING_BOX_NAIVE_TARGET),1)
  GO_PKG_TAGS:=with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_masque,with_mtproxy,with_ccm,with_ocm,with_openvpn,with_trusttunnel,with_sudoku,with_snell,with_naive_outbound,with_musl,badlinkname,tfogo_checklinkname0
else
  GO_PKG_TAGS:=with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_manager,with_admin_panel,with_masque,with_mtproxy,with_ccm,with_ocm,with_openvpn,with_trusttunnel,with_sudoku,with_snell,with_musl,badlinkname,tfogo_checklinkname0
endif

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/* $(PKG_BUILD_DIR)/
endef

ifeq ($(SING_BOX_NAIVE_TARGET),1)
define Build/Compile
	cd $(CURDIR)/.cronet-go && \
		$(GO_PKG_BUILD_VARS) \
		GOOS= GOARCH= GO386= GOAMD64= GOARM= GOMIPS= GOMIPS64= GOPPC64= \
		go run ./cmd/build-naive --target=linux/$(GO_ARCH) --libc=musl download-toolchain
	cd $(CURDIR)/.cronet-go && \
		eval "$$($(GO_PKG_BUILD_VARS) GOOS= GOARCH= GO386= GOAMD64= GOARM= GOMIPS= GOMIPS64= GOPPC64= go run ./cmd/build-naive --target=linux/$(GO_ARCH) --libc=musl env --export)" && \
		$(GO_GENERAL_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_VARS) \
		GOOS="$(GO_OS)" \
		GOARCH="$(GO_ARCH)" \
		GO386="$(GO_386)" \
		GOAMD64="$(GO_AMD64)" \
		GOARM="$(GO_ARM)" \
		GOMIPS="$(GO_MIPS)" \
		GOMIPS64="$(GO_MIPS64)" \
		GOPPC64="$(GO_PPC64)" \
		CGO_ENABLED=1 \
		CC="$$CC" \
		CXX="$$CXX" \
		CGO_CFLAGS="$(filter-out $(GO_CFLAGS_TO_REMOVE),$(TARGET_CFLAGS))" \
		CGO_CPPFLAGS="$(TARGET_CPPFLAGS)" \
		CGO_CXXFLAGS="$(filter-out $(GO_CFLAGS_TO_REMOVE),$(TARGET_CXXFLAGS))" \
		CGO_LDFLAGS="$$CGO_LDFLAGS" \
		$(SHELL) $(GO_INCLUDE_DIR)/golang-build.sh build $(GO_PKG_INSTALL_ARGS)
endef
endif

define Package/sing-box
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=The universal proxy platform (extended)
  URL:=https://github.com/shtorm-7/sing-box-extended
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +kmod-netlink-diag +kmod-tun
  USERID:=sing-box=5566:sing-box=5566
endef

define Package/sing-box/description
  Sing-box is a universal proxy platform which supports hysteria, SOCKS, Shadowsocks,
  ShadowTLS, Tor, trojan, VLess, VMess, WireGuard and so on.
endef

define Package/sing-box/config
  depends on $(subst @,,$(GO_ARCH_DEPENDS))
endef

define Package/sing-box/conffiles
/etc/config/sing-box
/etc/sing-box/
endef

define Package/sing-box/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/sing-box
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/release/config/config.json $(1)/etc/sing-box/config.json

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) ./files/sing-box.conf $(1)/etc/config/sing-box
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/sing-box.init $(1)/etc/init.d/sing-box
endef

$(eval $(call BuildPackage,sing-box))
