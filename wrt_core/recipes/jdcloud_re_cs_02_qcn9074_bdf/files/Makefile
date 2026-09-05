include $(TOPDIR)/rules.mk

PKG_NAME:=jdcloud-re-cs-02-qcn9074-bdf
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/jdcloud-re-cs-02-qcn9074-bdf
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=JDCloud RE-CS-02 QCN9074 board data
  DEPENDS:=+ath11k-firmware-qcn9074-ddwrt
endef

define Build/Compile
endef

define Package/jdcloud-re-cs-02-qcn9074-bdf/install
	$(INSTALL_DIR) $(1)/lib/firmware/ath11k/QCN9074/hw1.0
	$(INSTALL_DATA) ./files/board.bin $(1)/lib/firmware/ath11k/QCN9074/hw1.0/board.bin
endef

$(eval $(call BuildPackage,jdcloud-re-cs-02-qcn9074-bdf))
