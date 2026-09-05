#!/usr/bin/env bash
set -euo pipefail

package_dir="$BUILD_DIR/package/firmware/jdcloud-re-cs-02-qcn9074-bdf"
bdf_url="https://raw.githubusercontent.com/openwrt/firmware_qca-wireless/e20f4c6ff197823762319e4b7e31af01816503cf/board-jdcloud_re-cs-02.qcn9074"
bdf_sha256="c5d006900011acbd5444d160e72485b3be037e1359dadf8c536e038db7100455"
board_sha256="717a0b2f45812261fd43ffa71285cb3cae40cdd1973b6f2df4d2687e623f5373"

if [ ! -d "$BUILD_DIR/package/firmware" ]; then
    echo "jdcloud_re_cs_02_qcn9074_bdf: package/firmware not found" >&2
    exit 1
fi

install -d "$package_dir/files"
temp_bdf="$(mktemp "$package_dir/.board-2.bin.XXXXXX")"
trap 'rm -f "$temp_bdf"' EXIT

echo "jdcloud_re_cs_02_qcn9074_bdf: downloading board data"
curl --fail --location --show-error --silent --retry 3 --retry-delay 5 --retry-connrefused \
    -o "$temp_bdf" "$bdf_url"
if ! printf '%s  %s\n' "$bdf_sha256" "$temp_bdf" | sha256sum --check --status; then
    echo "jdcloud_re_cs_02_qcn9074_bdf: source BDF checksum mismatch" >&2
    exit 1
fi

if ! dd if="$temp_bdf" of="$package_dir/files/board.bin" bs=1 skip=104 count=131072 status=none; then
    rm -f "$package_dir/files/board.bin"
    echo "jdcloud_re_cs_02_qcn9074_bdf: board.bin extraction failed" >&2
    exit 1
fi
if ! printf '%s  %s\n' "$board_sha256" "$package_dir/files/board.bin" | sha256sum --check --status; then
    rm -f "$package_dir/files/board.bin"
    echo "jdcloud_re_cs_02_qcn9074_bdf: board.bin checksum mismatch" >&2
    exit 1
fi

echo "jdcloud_re_cs_02_qcn9074_bdf: verified board.bin"
