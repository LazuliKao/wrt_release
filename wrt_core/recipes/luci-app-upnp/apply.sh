#!/usr/bin/env bash
set -euo pipefail

config_file="$BUILD_DIR/custom_feed/miniupnpd/files/upnpd.config"

if [ -f "$config_file" ]; then
    if grep -q "allow_cgnat" "$config_file"; then
        echo "miniupnpd_stun: upnpd.config already patched, skipping."
    else
        echo "miniupnpd_stun: Patching upnpd.config..."
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
        echo "miniupnpd_stun: upnpd.config patched successfully."
    fi
else
    echo "miniupnpd_stun: Error: upnpd.config not found at $config_file" >&2
    exit 1
fi
