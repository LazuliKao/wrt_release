#!/usr/bin/env bash
# Shared post-build entry point for local builds and GitHub Actions.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ophub_ref=bad969aa9f6ca124ecc3bc1dffe951311760ff8b
rootfs_dir="$repo_root/firmware"
rootfs_file=""
output_dir="$repo_root/firmware"
board=""

usage() {
    echo "Usage: $0 --board <ophub board|platform|board1_board2> [--rootfs <rootfs.tar.gz> | --rootfs-dir <directory>] [--output <directory>]"
}

while (($#)); do
    case "$1" in
        --board|--rootfs|--rootfs-dir|--output)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in
                --board) board=$2 ;;
                --rootfs) rootfs_file=$2 ;;
                --rootfs-dir) rootfs_dir=$2 ;;
                --output) output_dir=$2 ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -n "$board" && "$board" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Specify a valid ophub board or platform with --board.' >&2; exit 2; }
[[ $(uname -s) == Linux ]] || { echo 'Image packaging requires a Linux host.' >&2; exit 1; }
for cmd in git sudo losetup parted mkfs.btrfs mkfs.ext4 mkfs.vfat curl; do
    command -v "$cmd" >/dev/null || { echo "Missing host dependency: $cmd" >&2; exit 1; }
done

if [[ -z "$rootfs_file" ]]; then
    shopt -s nullglob
    files=("$rootfs_dir"/*rootfs.tar.gz)
    # ARMv8 builds can emit both generic-rootfs and generic-targz-rootfs;
    # the former is the conventional rootfs artifact for remake.
    if ((${#files[@]} > 1)); then
        files=("$rootfs_dir"/*-generic-rootfs.tar.gz)
    fi
    shopt -u nullglob
    ((${#files[@]} == 1)) || { echo "Expected exactly one rootfs tarball in $rootfs_dir; use --rootfs to select one." >&2; exit 1; }
    rootfs_file=${files[0]}
fi
[[ -s "$rootfs_file" && "$rootfs_file" == *rootfs.tar.gz ]] || { echo "Invalid rootfs tarball: $rootfs_file" >&2; exit 1; }
rootfs_file=$(realpath "$rootfs_file")
mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

# Keep ophub's build tree separate from OpenWrt's build tree and published outputs.
workdir=$(mktemp -d "$output_dir/.ophub-remake.XXXXXXXX")
success=0
cleanup() {
    if ((success)); then
        sudo rm -rf -- "$workdir"
    else
        echo "Packaging failed; working directory retained for inspection: $workdir" >&2
    fi
}
trap cleanup EXIT

git clone --quiet https://github.com/ophub/amlogic-s9xxx-openwrt.git "$workdir/remake"
git -C "$workdir/remake" checkout --quiet --detach "$ophub_ref"
mkdir -p "$workdir/remake/openwrt-armsr"
cp "$rootfs_file" "$workdir/remake/openwrt-armsr/"

echo "Building ophub images for $board from $(basename "$rootfs_file") (revision $ophub_ref)"
(cd "$workdir/remake" && sudo ./remake -b "$board")

shopt -s nullglob
images=("$workdir/remake/openwrt/out/"*.img.gz "${workdir}/remake/openwrt/out/"*.img.xz)
shopt -u nullglob
((${#images[@]} > 0)) || { echo 'ophub/remake produced no compressed images.' >&2; exit 1; }
for image in "${images[@]}"; do
    sudo install -m 0644 "$image" "$output_dir/$(basename "$image")"
done
success=1
echo "Packaged ${#images[@]} image(s) into $output_dir"
