#!/usr/bin/env bash
set -euo pipefail

config_file="$BUILD_DIR/custom_feed/miniupnpd/files/upnpd.config"

# Copy default lease duration patch to custom miniupnpd package patches directory
original_patch="$BASE_PATH/patches/999-chanage-default-leaseduration.patch"
patches_dir="$BUILD_DIR/custom_feed/miniupnpd/patches"
if [ -f "$original_patch" ]; then
    echo "miniupnpd: Installing lease duration patch to custom miniupnpd package..."
    mkdir -p "$patches_dir"
    cp -f "$original_patch" "$patches_dir/999-chanage-default-leaseduration.patch"
fi

if [ -f "$config_file" ]; then
    if grep -q "allow_cgnat" "$config_file"; then
        echo "miniupnpd: upnpd.config already patched, skipping."
    else
        echo "miniupnpd: Patching upnpd.config..."
        awk '
        BEGIN { in_settings = 0; done = 0 }
        /^config upnpd '\''settings'\''/ { in_settings = 1; print; next }
        /^[[:space:]]*option enabled/ {
            if (in_settings && !done) {
                print "\toption enabled                    '\''1'\''"
                print "\toption allow_cgnat                '\''allow-filtered'\''"
                print "\toption stun_host                  '\''stun.miwifi.com'\''"
                done = 1
                in_settings = 0
                next
            }
        }
        { print }
        ' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        echo "miniupnpd: upnpd.config patched successfully."
    fi
else
    echo "miniupnpd: Error: upnpd.config not found at $config_file" >&2
    exit 1
fi
