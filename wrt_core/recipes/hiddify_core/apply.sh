#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/hiddify-core/Makefile"

if [ ! -f "$makefile" ]; then
    echo "hiddify-core: package Makefile not found: $makefile" >&2
    exit 1
fi

pkg_name=$(awk -F ':=' '$1 == "PKG_NAME" { print $2; exit }' "$makefile")
if [ "$pkg_name" != "hiddify-core" ]; then
    echo "hiddify-core: invalid package name in $makefile" >&2
    exit 1
fi

# Fetch the tagged repository through OpenWrt's Git downloader, which includes
# the nested hiddify-sing-box and ray2sing submodules required by go.mod.
sed -i '/^PKG_SOURCE_PROTO:=/d; /^PKG_SOURCE_VERSION:=/d; /^PKG_SOURCE_URL:=/d; /^PKG_SOURCE_SUBMODULES:=/d; /^PKG_HASH:=/d; /^PKG_MIRROR_HASH:=/d' "$makefile"
sed -i '/^PKG_SOURCE:=/a\
PKG_SOURCE_PROTO:=git\
PKG_SOURCE_VERSION:=v$(PKG_VERSION)\
PKG_SOURCE_URL:=https://github.com/1andrevich/hiddify-core.git\
PKG_SOURCE_SUBMODULES:=\
PKG_MIRROR_HASH:=skip' "$makefile"

# The upstream ray2sing submodule uses an SSH URL; OpenWrt's downloader has no
# GitHub SSH host key or credentials, so make Git resolve it through HTTPS.
git config --global url."https://github.com/".insteadOf "git@github.com:"

# v4.1.0 moved the executable from cli to cmd/main; retain the packaged
# hiddify-cli filename while building the current entrypoint.
sed -i 's|^GO_PKG_BUILD_PKG:=.*$|GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/main|' "$makefile"
sed -i 's|$(GO_PKG_BUILD_BIN_DIR)/cli|$(GO_PKG_BUILD_BIN_DIR)/main|' "$makefile"

# Hiddify v4 migrated ECH support into the Go standard library; its legacy
# with_ech build tag deliberately fails compilation.
sed -i 's/with_ech,//' "$makefile"

# The v4 package no longer ships these legacy assets; keep the directory for
# user-provided state while avoiding an install-time reference to absent files.
sed -i '/hiddify\.json/d; /files\/webui/d' "$makefile"

# This package is imported under custom_feed, not feeds/packages/net; resolve the
# Go package helper from the packages feed rather than relative to this package.
sed -i 's|^include ../../lang/golang/golang-package\.mk$|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|' "$makefile"

if ! grep -qx 'include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk' "$makefile"; then
    echo "hiddify-core: failed to set the Go package helper include path" >&2
    exit 1
fi

if grep -q 'hiddify\.json\|files/webui' "$makefile"; then
    echo "hiddify-core: stale v3 asset installation remains" >&2
    exit 1
fi

if ! grep -qx 'PKG_SOURCE_PROTO:=git' "$makefile" || ! grep -qx 'PKG_SOURCE_VERSION:=v$(PKG_VERSION)' "$makefile"; then
    echo "hiddify-core: failed to enable Git source download with submodules" >&2
    exit 1
fi

if ! grep -qx 'GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/main' "$makefile" || ! grep -q '$(GO_PKG_BUILD_BIN_DIR)/main' "$makefile"; then
    echo "hiddify-core: failed to select the v4 command entrypoint" >&2
    exit 1
fi
