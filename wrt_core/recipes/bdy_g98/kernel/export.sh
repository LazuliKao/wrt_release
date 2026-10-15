#!/usr/bin/env bash
# Export the standard ophub kernel contract from one completed OpenWrt build.
set -euo pipefail
base=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ $# == 3 ]] || { echo "Usage: $0 <OpenWrt tree> <rootfs.tar.gz> <output directory>" >&2; exit 2; }
tree=$(realpath "$1")
rootfs=$(realpath "$2")
mkdir -p "$3"
output=$(realpath "$3")
fail() { echo "$*" >&2; exit 1; }
for cmd in cpio gzip python3 readelf sha256sum depmod; do command -v "$cmd" >/dev/null || fail "Missing $cmd"; done
mapfile -t kernels < <(find "$tree/build_dir/target-aarch64_generic_musl/linux-armsr_armv8" -mindepth 1 -maxdepth 1 -type d -name 'linux-6.12.*')
[[ ${#kernels[@]} == 1 ]] || fail 'Expected exactly one prepared armsr 6.12 kernel tree.'
kernel=${kernels[0]}
release=$(cat "$kernel/include/config/kernel.release")
[[ $release =~ ^6\.12\.[0-9]+$ ]] || fail "Unsupported kernel release: $release"
for file in arch/arm64/boot/Image .config System.map; do [[ -s "$kernel/$file" ]] || fail "Missing $kernel/$file"; done
# Reject a nominally compiled DTB backed by an incomplete boot-critical config.
while IFS= read -r setting; do
    [[ $setting == CONFIG_*=y ]] || continue
    symbol=${setting%=*}
    grep -qx "$symbol=y" "$kernel/.config" || fail "Boot-critical kernel option not built in: $symbol"
done < "$base/config"
work=$(mktemp -d "$output/.kernel-export.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root" "$work/boot" "$work/dtb" "$work/modules/$release/kernel/openwrt" "$work/initrd" "$work/bundle"
tar -xzf "$rootfs" -C "$work/root"
[[ -d "$work/root/lib/modules/$release" ]] || fail 'Rootfs modules do not match the compiled kernel release.'
mapfile -t moddirs < <(find "$work/root/lib/modules" -mindepth 1 -maxdepth 1 -type d)
[[ ${#moddirs[@]} == 1 ]] || fail 'Rootfs contains multiple kernel releases.'
find "$work/root/lib/modules/$release" -type f -name '*.ko' -exec cp -t "$work/modules/$release/kernel/openwrt" {} +
[[ -n $(find "$work/modules" -name '*.ko' -print -quit) ]] || fail 'Rootfs has no kernel modules.'
for module in "$work/modules/$release/kernel/openwrt/"*.ko; do
    readelf -p .modinfo "$module" | grep -Eq "vermagic=$release( |$)" || fail "Module release mismatch: $module"
done
# Use the same dependency/alias contract as upstream initramfs-tools. Keep
# the full local module set available, but let modprobe select dependencies.
cp "$kernel/modules.builtin" "$kernel/modules.builtin.modinfo" "$work/modules/$release/"
(cd "$work/modules/$release" && find kernel -type f -name '*.ko' | sort > modules.order)
mkdir -p "$work/module-root/lib"
ln -s "$work/modules" "$work/module-root/lib/modules"
depmod -b "$work/module-root" "$release"
# The DTB is built using the same compiler/config/prepared sources as Image.
gcc_version=$(sed -n 's/^CONFIG_GCC_VERSION="\(.*\)"$/\1/p' "$tree/.config")
[[ -n "$gcc_version" ]] || fail 'Cannot determine configured GCC version.'
mapfile -t compilers < <(find "$tree/staging_dir/toolchain-aarch64_generic_gcc-${gcc_version}_musl" -path '*/bin/aarch64-openwrt-linux-musl-gcc' -type f)
[[ ${#compilers[@]} == 1 ]] || fail 'Expected exactly one matching target compiler.'
cross=${compilers[0]%gcc}
make -C "$kernel" ARCH=arm64 CROSS_COMPILE="$cross" rockchip/rk3588-bdy-g98.dtb
cp "$kernel/arch/arm64/boot/dts/rockchip/rk3588-bdy-g98.dtb" "$work/dtb/"
# Original remake requires at least two DTBs. Include another RK3588 board
# built from this tree, without duplicating the G98 DTB under a false name.
make -C "$kernel" ARCH=arm64 CROSS_COMPILE="$cross" rockchip/rk3588-rock-5b.dtb
cp "$kernel/arch/arm64/boot/dts/rockchip/rk3588-rock-5b.dtb" "$work/dtb/"
mkdir -p "$work/initrd"/{bin,sbin,lib,proc,sys,dev,newroot}
for option in ASH MOUNT FEATURE_MOUNT_FLAGS UMOUNT CAT GREP MODPROBE SLEEP BLKID FEATURE_BLKID_TYPE FEATURE_VOLUMEID_BTRFS SWITCH_ROOT; do
    grep -qx "CONFIG_BUSYBOX_CONFIG_$option=y" "$tree/.config" || fail "Missing initramfs BusyBox option: $option"
done
grep -qx 'CONFIG_BUSYBOX_CONFIG_DEFAULT_MODULES_DIR="/lib/modules"' "$tree/.config" || fail 'BusyBox modprobe must search /lib/modules.'
grep -qx 'CONFIG_BUSYBOX_CONFIG_DEFAULT_DEPMOD_FILE="modules.dep"' "$tree/.config" || fail 'BusyBox modprobe must read modules.dep.'
cp "$work/root/bin/busybox" "$work/initrd/bin/"
# BusyBox uses the target musl interpreter. Copy the top-level target shared
# libraries and their symlinks, never host binaries/libraries.
find "$work/root/lib" -maxdepth 1 \( -name '*.so' -o -name '*.so.*' \) -exec cp -a -t "$work/initrd/lib" {} +
readelf -h "$work/initrd/bin/busybox" | grep -q AArch64 || fail 'BusyBox is not an AArch64 executable.'
cp -a "$work/modules/." "$work/initrd/lib/modules"
for applet in sh mount umount cat grep blkid modprobe insmod sleep switch_root; do
    ln -s busybox "$work/initrd/bin/$applet"
done
cp "$base/init" "$work/initrd/init"
chmod 0755 "$work/initrd/init"
(cd "$work/initrd" && find . -print0 | cpio --null --create --format=newc --owner=0:0 | gzip -n > "$work/boot/initrd.img-$release")
mkimage=$(command -v mkimage || true)
if [[ -z $mkimage ]]; then
    [[ -x "$tree/staging_dir/host/bin/mkimage" ]] || fail 'Missing mkimage (install u-boot-tools).'
    mkimage="$tree/staging_dir/host/bin/mkimage"
fi
"$mkimage" -A arm64 -O linux -T ramdisk -C gzip -n "G98 $release" -d "$work/boot/initrd.img-$release" "$work/boot/uInitrd-$release"
cp "$kernel/arch/arm64/boot/Image" "$work/boot/vmlinuz-$release"
cp "$kernel/.config" "$work/boot/config-$release"
cp "$kernel/System.map" "$work/boot/System.map-$release"
tar -czf "$work/bundle/boot-$release.tar.gz" -C "$work/boot" .
tar -czf "$work/bundle/dtb-rockchip-$release.tar.gz" -C "$work/dtb" .
tar -czf "$work/bundle/modules-$release.tar.gz" -C "$work/modules" "$release"
printf '%s\n' "$release" > "$work/bundle/kernel-release"
sha256sum "$rootfs" | cut -d' ' -f1 > "$work/bundle/rootfs.sha256"
(cd "$work/bundle" && sha256sum ./*.tar.gz kernel-release rootfs.sha256 > sha256sums)
cp -a "$work/bundle/." "$output/"
echo "Exported local ophub kernel $release to $output"
