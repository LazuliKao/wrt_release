#!/usr/bin/env bash
set -euo pipefail

package_dir="$BUILD_DIR/custom_feed/luci-app-qosmate"
makefile="$package_dir/Makefile"
settings="$package_dir/htdocs/luci-static/resources/view/settings.js"

replace_version() {
    local file="$1"
    local old="$2"
    local new="$3"
    local label="$4"

    if grep -Fq "$new" "$file"; then
        echo "qosmate: $label is already 1.8.0"
        return
    fi

    if ! grep -Fq "$old" "$file"; then
        echo "qosmate: expected $label version was not found in $file" >&2
        exit 1
    fi

    sed -i "s|$old|$new|" "$file"
    echo "qosmate: set $label to 1.8.0"
}

[ -f "$makefile" ] || { echo "qosmate: missing $makefile" >&2; exit 1; }
[ -f "$settings" ] || { echo "qosmate: missing $settings" >&2; exit 1; }

replace_version "$makefile" "PKG_VERSION:=1.0.14" "PKG_VERSION:=1.8.0" "package version"
replace_version "$settings" "const UI_VERSION = '1.2.0';" "const UI_VERSION = '1.8.0';" "frontend version"
