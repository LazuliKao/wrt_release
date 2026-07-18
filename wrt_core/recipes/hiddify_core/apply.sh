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

# Ensure PKG_SOURCE_URL in the Makefile targets 1andrevich's fork instead of hiddify official repo
# (so update_package extracts 1andrevich/hiddify-core as the repo)
sed -i "s|https://codeload.github.com/hiddify/hiddify-core|https://codeload.github.com/1andrevich/hiddify-core|g" "$makefile"

# This package is imported under custom_feed, not feeds/packages/net; resolve the
# Go package helper from the packages feed rather than relative to this package.
sed -i 's|^include ../../lang/golang/golang-package\.mk$|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|' "$makefile"

if ! grep -qx 'include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk' "$makefile"; then
    echo "hiddify-core: failed to set the Go package helper include path" >&2
    exit 1
fi

# Source target update modules
source "$BASE_PATH/modules/network.sh"
source "$BASE_PATH/modules/package_source_updates.sh"

# Run the standard update_package logic
update_package "hiddify-core" "releases" ""
