# BDY G98 local kernel chain

This target compiles Linux 6.12, the G98 DTB and Motorcomm YT921x support in
one OpenWrt build. Kernel options are merged into the armsr/armv8 kernel
configuration, rather than adding kernel symbols to OpenWrt's `.config`.

The G98 DTS and RK806 regulator include are pinned to LEDE commit
`c2d18bda9688e571fe2d5124a86c04ab57f33977`. `prepare_dts.py` removes downstream
display nodes incompatible with 6.12 (this is a headless NAS target), removes
the downstream USB PHY child-provider nodes and explicitly enables UART2.
The YT921x backport is pinned independently to
`241650a12c1121c76ba6e82567f3cbd81e368d3d`, with its SHA-256 checked by `apply.sh`.

## File layout

* `apply.sh`, `prepare_dts.py`: install the pinned driver patch and board DTS.
* `configs/bdy_g98.config`: OpenWrt package and BusyBox selections.
* `kernel/config`: boot-critical Linux kernel options.
* `kernel/export.sh`: export the complete local kernel bundle.
* `kernel/init`: target initramfs entry point.
* `kernel/validate.py`: standard bundle and U-Boot CRC validation.
* `kernel/verify_image.sh`: read-only final image verification.
* `kernel/update_guard`: prevent independent remote kernel upgrades.

The shared packaging entry point remains `wrt_core/ophub_package.sh`.

## Build and package

After the firmware build succeeds, `kernel/export.sh` exports:

* `boot-<release>.tar.gz`: raw ARM64 Image as `vmlinuz-<release>`, config,
  System.map, target BusyBox/modules initramfs and CRC-protected U-Boot uInitrd.
* `dtb-rockchip-<release>.tar.gz`: G98 and Rock 5B DTBs compiled in that kernel
  tree (original remake requires at least two DTBs).
* `modules-<release>.tar.gz`: the rootfs modules in the directory layout
  expected by original remake.
* `kernel-release`, `provenance.txt` and `sha256sums`.

Local build example on the development machine:

```sh
./build.sh ophub_bdy_g98_immwrt container
sudo bash wrt_core/ophub_package.sh --board bdy-g98 \
  --rootfs-dir firmware/ophub-immortalwrt \
  --kernel-bundle firmware/ophub-immortalwrt/local-kernel \
  --output firmware/ophub-immortalwrt
```

The wrapper checks the bundle and its rootfs provenance before starting
remake, seeds `kernel/stable/<release>` and changes only the selected model's
kernel tag. Original remake functions and board hooks run unchanged.
The final compressed image is mounted read-only to compare Image, uInitrd,
G98 DTB and every installed module with the local bundle. G98's independent
remote-kernel updater is disabled; use complete images for upgrades.

These checks validate the image's contents and boot-file contract. Hardware
acceptance still requires serial-console boot, rootfs mounting, Ethernet/DSA,
NVMe and thermal/fan checks on a G98.
