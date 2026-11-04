# sonic_fullcone

直接通过 [openwrt-sonic-fullcone](https://github.com/mufeng05/openwrt-sonic-fullcone) 的上游一键脚本，为 OpenWrt 源码集成 SONiC Full Cone NAT。

## 构建行为

- 默认启用本 recipe，不受 `RECIPE_SET` 限制；使用 MT798x 源码的目标通过 `DISABLE_RECIPES=sonic_fullcone` 禁用，沿用其原有 Full Cone 实现。
- 在 `pre_defconfig` 阶段、项目完成 feeds 更新与安装后执行。
- 在 `BUILD_DIR` 中下载并运行上游脚本：

  ```text
  https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh
  ```

- 内核、用户态及 LuCI 的集成由上游脚本负责，跟随上游 `master`。
- 本地负责下载、执行和清理临时脚本；下载或执行失败时终止构建。
- 上游安装成功后，定向删除两个与新补丁冲突的旧补丁：
  - `package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch`
  - `package/network/config/firewall/patches/fullconenat.patch`
- 清除 firewall4 对 `kmod-nft-fullcone`、firewall3 对 `iptables-mod-fullconenat` 的旧依赖，避免 defconfig 重新选中旧模块。
- 保留旧包源码，关闭 `kmod-ipt-fullconenat`、`iptables-mod-fullconenat`、`ip6tables-mod-fullconenat`、`kmod-nft-fullcone`，以及旧管理插件 `luci-app-turboacc-mtk`、`luci-app-natmode` 和已选择的对应翻译包。
- 本地兼容处理采用明确路径和包名，不维护上游补丁清单，不扫描未知实现或校验补丁哈希。
- 运行时默认关闭，由 LuCI/UCI 开启。支持范围、配置和验证方法见上游说明。

## 使用

```sh
./build.sh <target> recipe_preview
./build.sh <target> container
```

刷机后，在 LuCI 的“网络 → 防火墙”中开启全局 Full Cone，再编辑 WAN zone 开启 Full Cone 并选择协议。规则检查：

```sh
nft list ruleset | grep fullcone
```

## 禁用

在 `wrt_core/compilecfg/<target>.ini` 的 `DISABLE_RECIPES` 中追加 `sonic_fullcone`，保留已有项：

```ini
DISABLE_RECIPES=sonic_fullcone
```

禁用后重新准备干净源码并构建；禁用 recipe 不会撤销已执行的上游修改。
