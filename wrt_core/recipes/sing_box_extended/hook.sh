#!/usr/bin/env bash
set -euo pipefail

cronet_dir="$PACKAGE_DIR/.cronet-go"
cronet_commit="98d539ce67568fb911654e66a14cf4247ed833ec"

cp "$RECIPE_DIR/Makefile" "$PACKAGE_DIR/Makefile"
mkdir -p "$PACKAGE_DIR/files"
cp "$RECIPE_DIR/files/sing-box.conf" "$PACKAGE_DIR/files/sing-box.conf"
cp "$RECIPE_DIR/files/sing-box.init" "$PACKAGE_DIR/files/sing-box.init"

rm -rf "$cronet_dir"
git init "$cronet_dir"
git -C "$cronet_dir" remote add origin https://github.com/sagernet/cronet-go.git
git -C "$cronet_dir" fetch --depth=1 origin "$cronet_commit"
git -C "$cronet_dir" checkout --detach --quiet FETCH_HEAD
git -c url.https://github.com/.insteadOf=git@github.com: -C "$cronet_dir" submodule update --init --recursive --depth=1
