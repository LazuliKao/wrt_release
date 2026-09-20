#!/usr/bin/env bash
set -euo pipefail

source "$BASE_PATH/modules/network.sh"
source "$BASE_PATH/modules/package_source_updates.sh"

update_package "tailscale" "releases"
echo "tailscale_awg: refreshed Tailscale source version and hash"
