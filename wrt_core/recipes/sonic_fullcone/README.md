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
- 安装成功后，确认同目录下存在非空的 `001-sonic-fullcone.patch`，再移除已知冲突的旧补丁：
  - `package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch`
  - `package/network/config/firewall/patches/fullconenat.patch`
- 关闭旧 `kmod-nft-fullcone` 的选包，并移除 firewall4 Makefile 中对它的强制依赖，避免旧 `nft_fullcone` 与 Sonic 的 `nft_masq` 注册同名 expression。其他补丁（例如 bridge flowtable）保留；libnftnl / nftables 的同名 FullCone 补丁由上游脚本覆盖。
- 不注入运行时默认设置：全局 Full Cone 开关保持上游默认关闭，开启后还需要单独开启 zone。

本 recipe 跟随上游 `master`，不固定提交，也不自行改写上游补丁。上游目前声明支持 OpenWrt master / 25.12 / 24.10 和内核 6.6 / 6.12 / 6.18，不支持 23.05。默认进入构建计划不代表所有目标上游都兼容；上述已知旧补丁以外的 Full Cone 定制仍需检查。上游输出的 `applied` 仅表示复制补丁，实际兼容性以构建和设备测试为准。

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
