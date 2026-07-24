#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/hiddify-core/Makefile"

# Overwrite the downloaded package Makefile with our custom local Makefile
cp "$RECIPE_DIR/Makefile" "$makefile"

# Clean up the duplicate package Makefile in platform/wrt to prevent double registration.
# This prevents OpenWrt's feeds script from registering the package under the name "wrt".
rm -rf "$BUILD_DIR/custom_feed/hiddify-core/platform/wrt"
rm -rf "$BUILD_DIR/feeds/custom_feed/hiddify-core/platform/wrt"
rm -f "$BUILD_DIR/package/feeds/custom_feed/wrt"

# Pull submodules directly inside the package directory to avoid secondary download.
# We pass the insteadOf configuration via the -c flag to rewrite SSH URLs to HTTPS recursively.
# Git automatically propagates this configuration override to all nested submodule child clones.
echo "hiddify-core: pulling git submodules recursively..."
git -c url.https://github.com/.insteadOf=git@github.com: -C "$BUILD_DIR/custom_feed/hiddify-core" submodule update --init --recursive
