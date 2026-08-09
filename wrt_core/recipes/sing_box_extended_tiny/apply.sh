#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/sing-box/Makefile"
tiny_tags="with_dhcp,with_gvisor,with_quic,with_utls,with_wireguard,with_masque,with_musl,badlinkname,tfogo_checklinkname0"
install_line='$(call GoPackage/Package/Install/Bin,$(1))'
upx_line='$(TOPDIR)/upx/upx --lzma $(1)/usr/bin/sing-box'

if [ ! -f "$makefile" ]; then
    echo "sing_box_extended_tiny: Makefile not found: $makefile" >&2
    exit 1
fi

if ! sed -n '/^ifeq ($(BUILD_VARIANT),full)$/,/^else$/ { /^[[:space:]]*GO_PKG_TAGS:=/p; }' "$makefile" | grep -q .; then
    echo "sing_box_extended_tiny: full build GO_PKG_TAGS not found in $makefile" >&2
    exit 1
fi

sed -i \
    '/^ifeq ($(BUILD_VARIANT),full)$/,/^else$/ s|^[[:space:]]*GO_PKG_TAGS:=.*$|  GO_PKG_TAGS:='"$tiny_tags"'|' \
    "$makefile"

if ! grep -qF "$upx_line" "$makefile"; then
    install_count=$(grep -cF "$install_line" "$makefile" || true)
    if [ "$install_count" -ne 1 ]; then
        echo "sing_box_extended_tiny: expected one sing-box install command, found $install_count" >&2
        exit 1
    fi

    sed -i '/^[[:space:]]*$(call GoPackage\/Package\/Install\/Bin,$(1))[[:space:]]*$/a\
	$(TOPDIR)/upx/upx --lzma $(1)/usr/bin/sing-box
' "$makefile"
fi

echo "sing_box_extended_tiny: configured reduced build tags and UPX compression"
