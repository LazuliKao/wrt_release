#!/usr/bin/env bash
set -e
git config pull.rebase false
sudo apt-get update
sudo apt-get install jq -y

BASE_PATH=$(cd $(dirname $0) && pwd)

Dev=$1

./build.sh $Dev "container"