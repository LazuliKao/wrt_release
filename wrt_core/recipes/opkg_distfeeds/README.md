# opkg_distfeeds

在 `post_defconfig` 阶段统一配置 OPKG/APK 软件源，并将内核 vermagic 对齐到匹配的已发布 kmod ABI。原 `fix_kernel_magic` 的功能已合并到此 recipe。

## INI 参数

| 参数 | 说明 |
| --- | --- |
| `OPKG_DISTFEEDS_CHANNEL` | `releases`（默认）或 `snapshots`，显式决定源通道。 |
| `OPKG_DISTFEEDS_VERSION` | release 版本，例如 `25.12.2`；snapshot 不使用此字段。 |
| `OPKG_DISTFEEDS` | 镜像预设 `nju`（默认）、`ustc`、`official`，或逗号分隔的自定义源行。 |
| `OPKG_DISTFEEDS_MIRROR` | 覆盖镜像根地址，同时用于通用 feeds、target 和自动发现的 kmods。 |
| `OPKG_DISTFEEDS_ARCH` | 覆盖软件包架构，默认读取 `.config`。 |
| `KERNEL_VERMAGIC` | 显式覆盖内核 hash；自动发现 kmod 时同时要求 hash 相同。 |
| `KERNEL_MODULES` | 显式覆盖 kmod 目录 URL，可带 `/packages.adb`；能从标准目录名提取 hash。与显式 `KERNEL_VERMAGIC` 冲突时终止。 |

PONWRT 的 an7581 和 HM2004-DU 配置均显式使用：

```ini
OPKG_DISTFEEDS_CHANNEL=snapshots
```

其通用 feeds 为 `{mirror}/snapshots/packages/{arch}/{feed}`，target 为 `{mirror}/snapshots/targets/{board}/{subtarget}`。这两个设备的 target 均是 `airoha/an7581`。APK 的每条地址均以 `/packages.adb` 结尾。

其他设备默认保留 release 通道。未指定版本时，版本号形式的 release 分支继续可用；`24.10` / `openwrt-24.10-6.6` 对应 `24.10.6`，`25.12` / `25.12-nss` 对应 `25.12.2`。其他分支使用现有默认值：APK `25.12.2`，OPKG `24.10.6`。`master`、`main` 和功能分支名不用于判定 snapshot；snapshot 必须显式配置通道。

## kmod 选择

1. 用源码树自身的 Makefile 求值 `LINUX_VERSION`，包含 subtarget 覆盖及 `CONFIG_TESTING_KERNEL`，要求完整版本（例如 `6.12.77`）。
2. 在当前 target 的 `kmods/` 中仅筛选该完整版本的 `版本-修订号-hash/` 目录。
3. 选择数值最大的修订号；若该修订号有不同 hash，则视为歧义。
4. 无法读取完整版本、无匹配、目录不可访问或存在歧义时，跳过自动内核覆盖和 kmod feed，仍生成通用与 target feeds；不会跨内核版本匹配。

仅抓取一次目录，内核覆盖和软件源使用同一结果。显式覆盖参数优先。官方地址形式的 `KERNEL_MODULES` 会沿用所选镜像，其他自定义 URL 保留。

APK 源写入 `default-settings/files/99-distfeeds.list`，安装后由默认设置迁移到 `/etc/apk/repositories.d/distfeeds.list`；OPKG 写入 `99-distfeeds.conf`，其中包含同一次选择得到的 kmod 源，无需额外的 OPKG 启动钩子。

## 检查

在有 Bash、GNU make 和 Python 3 的 Linux 环境运行：

```sh
python3 wrt_core/recipes/opkg_distfeeds/tests/test_distfeeds.py
```

测试使用临时源码树和本地目录响应，不依赖远端镜像的实时内容。
