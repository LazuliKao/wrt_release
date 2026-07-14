#!/usr/bin/env bash

set -e

signature_file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
build_time=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

if [ -f "$signature_file" ]; then
    sed -E -i "s#(\(luciversion \|\| ''\))( \+ \(' / build by [^']*'\))?#\1 + (' / build by LazuliKao - $build_time')#g" "$signature_file"
fi
