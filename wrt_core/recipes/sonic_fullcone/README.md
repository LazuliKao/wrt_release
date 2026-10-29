# sonic_fullcone

通过 [openwrt-sonic-fullcone](https://github.com/mufeng05/openwrt-sonic-fullcone) 的一键脚本，为 OpenWrt 源码集成 SONiC Full Cone NAT。

## 构建行为

- 所有目标默认启用本 recipe；不受 `RECIPE_SET` 限制。
- 在 `pre_defconfig` 阶段执行，此时项目已完成 feeds 更新、安装和源码修正，无需重复执行 `./scripts/feeds update -a` / `./scripts/feeds install -a`。
- 在 `BUILD_DIR` 下下载并执行以下脚本，下载或执行失败时终止构建：

  ```text
  https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh
  ```

- 上游脚本会 clone 仓库、检测内核版本、复制内核和用户态补丁、修改 LuCI，并清理自己的临时目录。recipe 会清理下载的临时脚本。
- 上游还会在 `package/libs/libnftnl/Makefile` 中加入 `PKG_FIXUP:=autoreconf`，避免修改 `Makefile.am` 后调用不存在的特定 automake 版本。
- 不额外勾选独立 Full Cone 模块；功能编译进现有 `nft_masq.ko` / `xt_MASQUERADE.ko`，后续由项目正常执行 defconfig 和编译。
- 安装前检查已安装的包（包括 `package/feeds` 符号链接）、相关包补丁、generic 和当前目标的内核补丁。不会扫描未安装的整个 feeds 仓库来判断冲突。
- 旧补丁按明确列出的完整路径处理，不要求内容匹配固定 SHA-256。旧包提供者和管理插件仍通过已审查的 Makefile 摘要识别；其他路径的冲突补丁、未知旧模块依赖及运行时逻辑会报告路径并停止构建。包说明、标题和注释中的 Full Cone 关键词本身不视为冲突。
- 上游安装成功且替代补丁存在后，定向移除以下两个旧补丁：
  - `package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch`
  - `package/network/config/firewall/patches/fullconenat.patch`
- libnftnl / nftables 的 `001-libnftnl-add-fullcone-expression-support.patch` / `002-nftables-add-fullcone-expression-support.patch` 由上游同名补丁覆盖。无关补丁（例如 bridge flowtable）保留。
- 保留 `fullconenat` / `fullconenat-nft` 包源码和 custom feed 导入行为，但关闭其四个旧输出包（包括 `y` 和 `m`）：`kmod-ipt-fullconenat`、`iptables-mod-fullconenat`、`ip6tables-mod-fullconenat`、`kmod-nft-fullcone`。目前识别 ponwrt 和 kenzok8/small-package 的已审查版本；遇到未知提供者会报错。
- 移除 firewall4 对 `kmod-nft-fullcone`、firewall3 对 `iptables-mod-fullconenat` 的确切依赖，避免 defconfig 重新选中旧模块。
- 对已识别的 MTK `luci-app-turboacc-mtk` 版本，关闭该管理插件及已选择的翻译包。该版本强制依赖旧模块，并在启动时写入 `nf_conntrack_nat_mode`，不能与 Sonic 混用；独立选中的 HNAT 内核驱动保留。其他 turboacc 版本不会按名称自动改写，检查到未知 Full Cone 依赖或旧运行时逻辑时会报错。
- `luci_app_airoha_npu` recipe 已移除 `luci-app-natmode` 的导入和默认选包；如果构建树中仍安装了已识别的旧版插件，关闭该插件及已选择的翻译包，避免重新依赖或加载 `nft_fullcone`。
- 冲突检查和定向替换均在本 recipe 的 `pre_defconfig` 阶段完成，依据当时的 `.config`、包 Makefile 和补丁内容进行检查。
- 构建树中的 `.sonic-fullcone-state.json` 记录本次上游补丁的内容摘要；重复执行时只信任内容未改变的已安装 Sonic 补丁。已有 Sonic 构建树如果没有此记录，应重新准备干净源码。
- 不注入运行时默认设置：全局 Full Cone 开关保持上游默认关闭，开启后还需要单独开启 zone。

本 recipe 跟随上游 `master`，不固定提交，也不自行改写上游补丁。需要构建主机提供 `python3`。上游目前声明支持 OpenWrt master / 25.12 / 24.10 和内核 6.6 / 6.12 / 6.18，不支持 23.05。默认进入构建计划不代表所有目标上游都兼容；未知冲突须先审查，再更新定向兼容规则。上游输出的 `applied` 仅表示复制补丁，实际兼容性以构建和设备测试为准。

## 使用

正常构建即可，或先预览计划：

```sh
./build.sh <target> recipe_preview
./build.sh <target> container
```

刷机后，在 LuCI 的“网络 → 防火墙”中开启全局 Full Cone，再编辑 WAN zone 开启 Full Cone 并选择协议。也可通过 UCI 配置；应按实际 zone 找到 WAN，不要假设它一定是 `@zone[1]`。规则检查：

```sh
nft list ruleset | grep fullcone
```

完整配置及验证方法见上游 README。已有连接不会因重启防火墙而自动改用新的 NAT 行为。

## 禁用与卸载

在 `wrt_core/compilecfg/<target>.ini` 的 `DISABLE_RECIPES` 中追加 `sonic_fullcone`，保留已有项：

```ini
DISABLE_RECIPES=sonic_fullcone
```

禁用 recipe 后，重新执行项目正常的干净源码准备和完整构建流程。仅禁用 recipe 不会撤销当前构建树中已经安装的补丁、LuCI 翻译、Makefile 修改或恢复已移除的旧补丁；不要直接复用已打补丁的构建树执行 make 来判断卸载结果。recipe 本身不提供自动卸载动作。

若需要原地维护构建树，请按上游卸载说明移除对应补丁，并检查安装脚本对源码和 feeds 的直接修改，再清理相关包及内核重新编译。

更新源码后应重新走 recipe，以补回可能被还原的 `PKG_FIXUP:=autoreconf`。如果 libnftnl 已因 automake 版本问题编译失败，还需在 OpenWrt 源码目录执行：

```sh
make package/libs/libnftnl/clean
```
