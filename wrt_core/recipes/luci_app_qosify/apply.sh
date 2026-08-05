#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/luci-app-qosify/Makefile"
expected='include $(TOPDIR)/feeds/luci/luci.mk'

if [ ! -f "$makefile" ]; then
    echo "luci_app_qosify: package Makefile not found: $makefile" >&2
    exit 1
fi

# The package is imported into custom_feed, where ../../luci.mk resolves to the
# nonexistent feeds/luci.mk. Use the LuCI feed's canonical helper instead.
sed -i 's|^include ../../luci\.mk$|include $(TOPDIR)/feeds/luci/luci.mk|' "$makefile"

if ! grep -Fxq "$expected" "$makefile"; then
    echo "luci_app_qosify: failed to set the LuCI helper include path" >&2
    exit 1
fi

# Importing registers the unpatched source first. Rebuild its metadata and link
# after the correction so make defconfig can retain luci-app-qosify.
if [ ! -x "$BUILD_DIR/scripts/feeds" ]; then
    echo "luci_app_qosify: scripts/feeds not found: $BUILD_DIR/scripts/feeds" >&2
    exit 1
fi

(
    cd "$BUILD_DIR"
    ./scripts/feeds update custom_feed
    ./scripts/feeds install -p custom_feed -f luci-app-qosify
)
