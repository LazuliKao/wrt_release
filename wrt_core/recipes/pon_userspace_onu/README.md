# pon_userspace_onu

将 `ponwrt` 上游的 `pon_userspace` feed（`pbs05/openwrt-pon-userspace`）替换为 [naoki66/OpenWrt_ONU_CONFIG](https://github.com/naoki66/OpenWrt_ONU_CONFIG)，并启用该仓库提供的全部用户态工具与 LuCI 插件：

- `airoha-ponctl`
- `airoha-pond`
- `airoha-pon-debug`
- `luci-app-onu`（及中文语言包 `luci-i18n-onu-zh-cn`）
- `luci-app-pon-status`

同时会在 `pre_defconfig` 阶段自动复制该仓库中的 `patches/firewall4/010-fw4-zone-device-flowtable.patch` 到 `package/network/config/firewall4/patches/`，以支持通过 zone `device` 列表配置的 PPPoE 上联硬件卸载。

## 启用方式

两个 recipe 默认均为关闭状态（`"enabled": false`），不开启时保持上游 `pbs05/openwrt-pon-userspace` 不变。

如需开启，可在设备配置 `wrt_core/compilecfg/<target>.ini` 的 `ADD_RECIPES` 中加入 `pon_userspace_onu`（会自动拉起依赖的 `pon_userspace_onu_feed`）：

```ini
ADD_RECIPES=airoha_an7581,luci_app_airoha_npu,pon_userspace_onu
```

或使用交互式配置：

```bash
./build.sh <target> recipe_config
```
