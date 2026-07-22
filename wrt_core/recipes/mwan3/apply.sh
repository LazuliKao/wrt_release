#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/luci-app-mwan3/Makefile"
expected='include $(TOPDIR)/feeds/luci/luci.mk'

if [ ! -f "$makefile" ]; then
    echo "mwan3: package Makefile not found: $makefile" >&2
    exit 1
fi

# The package is imported into custom_feed, where ../../luci.mk resolves to the
# nonexistent feeds/luci.mk. Use the LuCI feed's canonical helper instead.
sed -i 's|^include ../../luci\.mk$|include $(TOPDIR)/feeds/luci/luci.mk|' "$makefile"

if ! grep -Fxq "$expected" "$makefile"; then
    echo "mwan3: failed to set the LuCI helper include path" >&2
    exit 1
fi

# Importing registers the unpatched source first. Rebuild its metadata and link
# after the correction so make defconfig can retain luci-app-mwan3.
if [ ! -x "$BUILD_DIR/scripts/feeds" ]; then
    echo "mwan3: scripts/feeds not found: $BUILD_DIR/scripts/feeds" >&2
    exit 1
fi

(
    cd "$BUILD_DIR"
    ./scripts/feeds update custom_feed
    ./scripts/feeds install -p custom_feed -f luci-app-mwan3
)
