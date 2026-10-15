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

### Driver alignment and local follow-ups

`kernel/patches/` contains ordered follow-ups installed after the pinned
`799-net-dsa-add-motorcomm-yt921x.patch`:

* YT921x aligns with ophub's initial import
  `ffe6d52efca61ed646a4864c36d01332a2e1dba1`, retaining the Linux 6.12 TC,
  allocation and HSR API adaptations. The tagger is identical. The LEDE
  base already includes external port 9 (`port < 10`), so ophub's separate
  `2f40513e045a1c6d8ed1ebc7113232a8a9282380` fix is not applied twice.
* Ophub `36e2e370843c943a8ea53999d455d2e65fe62dfe` applies the board's
  joint RJ45 LED profile after reset. Both LEDs stay lit on link, blink on
  RX/TX activity and stay dark when disconnected. It is gated by
  `motorcomm,bdy-g98-led-profile`, already present on both pinned DTS switches.
* Ophub `5c450c357c005e70b8375ad13dcd9219deb0bd83` fixes the LED profile's
  `BIT()`-derived log format specifiers.
* Upstream stmmac `b55dfb173ce808ecc8c598f2c378a9b04c5ce241` is adapted to
  6.12 by adding `ndo_features_check`. Packets whose ethertype cannot trigger
  the hardware checksum engine (including YT921x-tagged traffic) lose checksum
  offload before the network core chooses segmentation, which also forces
  software GSO. Ordinary IP traffic retains hardware TSO. This is not a global
  `ethtool tso off` workaround and does not change the device-tree TSO flags.

The LED and TSO behavior must still be checked on hardware after flashing:
leave GSO/TSO enabled, compare large HTTP/TCP transfers through both four-port
switch groups, and check link/activity/disconnected LED states. Compilation
alone does not establish that the original slow-transfer symptom is fixed.

## File layout

* `apply.sh`, `prepare_dts.py`: install the pinned driver patch and board DTS.
* `configs/bdy_g98.config`: OpenWrt package and BusyBox selections.
* `kernel/config`: boot-critical Linux kernel options.
* `kernel/export.sh`: export the complete local kernel bundle.
* `kernel/init`: target initramfs entry point.
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
* `kernel-release`, a rootfs SHA-256 binding and archive checksums.

Local build example on the development machine:

```sh
./build.sh ophub_bdy_g98_immwrt container
sudo bash wrt_core/ophub_package.sh --board bdy-g98 \
  --rootfs-dir firmware/ophub-immortalwrt \
  --kernel-bundle firmware/ophub-immortalwrt/local-kernel \
  --output firmware/ophub-immortalwrt
```

The wrapper checks archive checksums and confirms that the kernel bundle was
exported alongside the selected rootfs. It seeds `kernel/stable/<release>`
and changes only the selected model's kernel tag. Original remake functions
and board hooks run unchanged. G98's independent remote-kernel updater is
disabled; use complete images for upgrades.

Hardware acceptance still requires serial-console boot, rootfs mounting,
Ethernet/DSA, NVMe and thermal/fan checks on a G98.
