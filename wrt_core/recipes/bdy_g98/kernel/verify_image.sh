#!/usr/bin/env bash
# Verify the published image, after all upstream bootfs/rootfs transformations.
set -euo pipefail
image=$(realpath "$1")
bundle=$(realpath "$2")
release=$(cat "$bundle/kernel-release")
work=$(mktemp -d)
loop=""
cleanup() {
    mountpoint -q "$work/boot" && umount "$work/boot"
    mountpoint -q "$work/root" && umount "$work/root"
    [[ -z "$loop" ]] || losetup -d "$loop"
    rm -rf "$work"
}
trap cleanup EXIT
case "$image" in *.gz) gzip -dc "$image" > "$work/image.img" ;; *.xz) xz -dc "$image" > "$work/image.img" ;; *) exit 2 ;; esac
mkdir -p "$work/boot" "$work/root" "$work/expected-boot" "$work/expected-dtb" "$work/expected-modules"
loop=$(losetup --find --show --partscan "$work/image.img")
mount -o ro "${loop}p1" "$work/boot"
mount -o ro "${loop}p2" "$work/root"
tar -xzf "$bundle/boot-$release.tar.gz" -C "$work/expected-boot"
tar -xzf "$bundle/dtb-rockchip-$release.tar.gz" -C "$work/expected-dtb"
tar -xzf "$bundle/modules-$release.tar.gz" -C "$work/expected-modules"
cmp "$work/boot/Image" "$work/expected-boot/vmlinuz-$release"
cmp "$work/boot/uInitrd" "$work/expected-boot/uInitrd-$release"
cmp "$work/boot/dtb/rockchip/rk3588-bdy-g98.dtb" "$work/expected-dtb/rk3588-bdy-g98.dtb"
grep -q 'rk3588-bdy-g98.dtb' "$work/boot/armbianEnv.txt"
[[ -x "$work/root/sbin/init" ]]
for updater in openwrt-kernel openwrt-update-rockchip openwrt-update-amlogic; do
    cmp "$(dirname "$0")/update_guard" "$work/root/usr/sbin/$updater"
done
for module in "$work/expected-modules/$release/kernel/openwrt/"*.ko; do
    cmp "$module" "$work/root/lib/modules/$release/kernel/openwrt/$(basename "$module")"
done
echo "Verified final image kernel, initrd, G98 DTB and modules: $(basename "$image")"
