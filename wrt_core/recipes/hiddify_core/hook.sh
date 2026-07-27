#!/usr/bin/env bash
set -euo pipefail

makefile="$PACKAGE_DIR/Makefile"

# Overwrite the downloaded package Makefile with our custom local Makefile
cp "$RECIPE_DIR/Makefile" "$makefile"

# Clean up the duplicate package Makefile in platform/wrt to prevent double registration.
# This prevents OpenWrt's feeds script from registering the package under the name "wrt".
rm -rf "$PACKAGE_DIR/platform/wrt"

# Pull submodules directly inside the package directory to avoid secondary download.
echo "hiddify-core: pulling git submodules recursively..."
git -c url.https://github.com/.insteadOf=git@github.com: -C "$PACKAGE_DIR" submodule update --init --recursive
