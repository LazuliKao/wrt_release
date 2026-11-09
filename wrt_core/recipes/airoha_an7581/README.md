# Airoha AN7581 平台适配

## Wi-Fi NPU 编译期开关

在启用了 `airoha_an7581` recipe 的设备配置 `wrt_core/compilecfg/<target>.ini` 中设置：

```ini
ENABLE_WIFI_NPU=0
```

- `0`（默认，包括未设置或空值）：不注入 Wi-Fi NPU 专用内存预留，并清理本 recipe 旧版本生成的 `an7581-npu-clanker.dtsi` 及其 include。
- `1`：为 recipe 管理的 AN7581 设备树注入 `an7581-npu-clanker.dtsi`，引入上游 `an7581-npu-wlan.dtsi`。当前上游布局包含约 **110 MiB + 26 KiB** 的 Wi-Fi NPU 专用预留区；缺少该上游文件时会报错。
- 其他非空值会报错。

`lk_h3c_hm2004_du.ini` 和 `lk_an7581_ponwrt_mini.ini` 已显式设为 `0`。需要 Wi-Fi NPU 专用预留时，将对应配置改为 `1` 后重新构建。

此开关控制 recipe 注入的设备树内存预留，不是运行时无线开关，也不会自动实现或验证无线驱动的 NPU 卸载。普通 Wi-Fi、上游 NPU 固件包选择、基础 `npu_binary` 预留及 FTTR/PPE 配置均不由此开关修改。上游设备树自己引入的 Wi-Fi NPU 配置（例如其他无线芯片的专用 DTSI）仍由上游管理。

切换后需要重新运行构建准备流程，使本 recipe 的 `pre_defconfig` 阶段再次执行，再重新编译并刷入固件、重启；直接恢复到 `make` 的构建流程不会重新执行 recipe。复用同一源码目录时，关闭开关会清理之前的 recipe 注入项。
