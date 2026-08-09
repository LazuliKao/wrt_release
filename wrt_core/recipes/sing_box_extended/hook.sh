#!/usr/bin/env bash
set -euo pipefail

makefile="$PACKAGE_DIR/Makefile"
extended_commit="00d3ed46bf84b0602e7e542bf9e949fef5080d7f"
source_url="https://codeload.github.com/shtorm-7/sing-box-extended/tar.gz/${extended_commit}?"
full_tags="with_acme,with_clash_api,with_dhcp,with_gvisor,with_quic,with_tailscale,with_utls,with_wireguard,with_masque,with_mtproxy,with_ccm,with_ocm,with_openvpn,with_trusttunnel,with_sudoku,with_snell,with_musl,badlinkname,tfogo_checklinkname0"
ldflags="-X internal/godebug.defaultGODEBUG=multipathtcp=0 -checklinkname=0"

if [ ! -f "$makefile" ]; then
    echo "sing_box_extended: Makefile not found: $makefile" >&2
    exit 1
fi

replace_assignment() {
    local variable="$1"
    local value="$2"

    if ! grep -q "^${variable}:=" "$makefile"; then
        echo "sing_box_extended: missing ${variable} in $makefile" >&2
        exit 1
    fi

    sed -i "s|^${variable}:=.*|${variable}:=${value}|" "$makefile"
}

replace_assignment "PKG_SOURCE_URL" "$source_url"
replace_assignment "PKG_HASH" ""

if grep -q '^PKG_BUILD_DIR:=' "$makefile"; then
    replace_assignment "PKG_BUILD_DIR" "\$(BUILD_DIR)/sing-box-extended-${extended_commit}"
else
    sed -i "/^PKG_HASH:=/a\\PKG_BUILD_DIR:=\$(BUILD_DIR)/sing-box-extended-${extended_commit}" "$makefile"
fi

if grep -q '^GO_PKG_LDFLAGS:=' "$makefile"; then
    replace_assignment "GO_PKG_LDFLAGS" "$ldflags"
else
    if ! grep -q '^GO_PKG_LDFLAGS_X:=' "$makefile"; then
        echo "sing_box_extended: missing GO_PKG_LDFLAGS_X in $makefile" >&2
        exit 1
    fi
    sed -i "/^GO_PKG_LDFLAGS_X:=/a\\GO_PKG_LDFLAGS:=${ldflags}" "$makefile"
fi

if ! sed -n '/^ifeq ($(BUILD_VARIANT),full)$/,/^else$/ { /^[[:space:]]*GO_PKG_TAGS:=/p; }' "$makefile" | grep -q .; then
    echo "sing_box_extended: full build GO_PKG_TAGS not found in $makefile" >&2
    exit 1
fi

sed -i \
    '/^ifeq ($(BUILD_VARIANT),full)$/,/^else$/ s|^[[:space:]]*GO_PKG_TAGS:=.*$|  GO_PKG_TAGS:='"$full_tags"'|' \
    "$makefile"

echo "sing_box_extended: configured sing-box-extended ${extended_commit}"
