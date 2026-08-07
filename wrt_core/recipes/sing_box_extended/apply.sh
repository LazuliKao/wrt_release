#!/usr/bin/env bash
set -euo pipefail

source "$BASE_PATH/modules/network.sh"
source "$BASE_PATH/modules/package_source_updates.sh"

update_package "sing-box" "releases" "1.13.16"
