#!/usr/bin/env bash
set -euo pipefail

makefile="$BUILD_DIR/custom_feed/hiddify-core/Makefile"
source_url="https://codeload.github.com/1andrevich/hiddify-core/tar.gz/main?"

if [ ! -f "$makefile" ]; then
    echo "hiddify-core: package Makefile not found: $makefile" >&2
    exit 1
fi

pkg_name=$(awk -F ':=' '$1 == "PKG_NAME" { print $2; exit }' "$makefile")
pkg_version=$(awk -F ':=' '$1 == "PKG_VERSION" { print $2; exit }' "$makefile")
if [ "$pkg_name" != "hiddify-core" ] || [ -z "$pkg_version" ]; then
    echo "hiddify-core: invalid package metadata in $makefile" >&2
    exit 1
fi

pkg_source="${pkg_name}-${pkg_version}.tar.gz"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL --retry 3 "$source_url$pkg_source" -o "$tmp_dir/$pkg_source"
pkg_hash=$(sha256sum "$tmp_dir/$pkg_source" | awk '{print $1}')

sed -i "s|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=$source_url|" "$makefile"
sed -i "s|^PKG_HASH:=.*|PKG_HASH:=$pkg_hash|" "$makefile"

echo "hiddify-core: using 1andrevich/hiddify-core main (hash $pkg_hash)"
