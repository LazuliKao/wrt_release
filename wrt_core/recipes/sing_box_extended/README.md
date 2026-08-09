# sing-box-extended Recipe

本 recipe 为 OpenWrt 集成 `sing-box-extended`，替换 small-package 中的上游 sing-box 源码包。当前版本号保持为 `1.13.16`，源码固定为 `shtorm-7/sing-box-extended` 提交：

```text
00d3ed46bf84b0602e7e542bf9e949fef5080d7f
```

> 这不是官方 `SagerNet/sing-box` v1.13.16 原始源码包。版本号沿用 1.13.16，协议实现和构建标签来自扩展分支。

## Recipe 行为

`recipe.json` 默认关闭：

```json
"enabled": false
```

启用后执行以下操作：

1. 从 `kenzok8/small-package` 导入 `sing-box` 包。
2. 应用 `patches/use-sing-box-extended.patch`。
3. 将源码地址改为 `shtorm-7/sing-box-extended` 的固定提交。
4. 在 `full` 构建变体中启用扩展协议和底层构建标签。
5. 通过 `apply.sh` 刷新 small-package 中的 sing-box 版本元数据。

补丁还加入以下 linker flags：

```text
-X internal/godebug.defaultGODEBUG=multipathtcp=0
-checklinkname=0
```

其中 `-checklinkname=0` 是 `badlinkname` 所需的 Go 链接器参数。

## 构建标签

当前 `full` 变体使用：

```text
with_acme,with_clash_api,with_dhcp,with_gvisor,with_quic,with_tailscale,with_utls,with_wireguard,with_masque,with_mtproxy,with_ccm,with_ocm,with_openvpn,with_trusttunnel,with_sudoku,with_snell,with_musl,badlinkname,tfogo_checklinkname0
```

### 官方基础功能

| 标签 | 作用 |
| --- | --- |
| `with_acme` | 启用 ACME TLS 证书签发、自动申请和续期。普通证书文件配置不依赖此标签。 |
| `with_clash_api` | 启用 Clash API 兼容接口，包括代理状态、流量统计和节点切换等。 |
| `with_dhcp` | 启用 DHCP DNS transport，通过 DHCP 获取 DNS 服务器。 |
| `with_gvisor` | 启用 gVisor 用户态网络栈，供 TUN 的 gVisor stack 等场景使用。 |
| `with_quic` | 启用 QUIC/HTTP3 相关功能，包括 QUIC DNS、Hysteria 和 QUIC V2Ray transport。 |
| `with_tailscale` | 启用 Tailscale endpoint。 |
| `with_utls` | 启用 uTLS TLS ClientHello 指纹模拟。它不是额外加密层，也不保证抗审查。 |
| `with_wireguard` | 启用 WireGuard endpoint 相关支持。 |
| `with_ccm` | 启用 Claude Code Multiplexer 服务。 |
| `with_ocm` | 启用 OpenAI Codex Multiplexer 服务。 |

### 扩展协议

| 标签 | 注册方向 | 作用 |
| --- | --- | --- |
| `with_masque` | outbound | 启用 MASQUE outbound。本分支实现面向 Cloudflare WARP MASQUE 隧道，支持 QUIC/HTTP2 和系统 TUN。 |
| `with_mtproxy` | inbound | 启用 MTProto Proxy 服务端，用于 Telegram MTProxy，并将连接交给 sing-box 路由。 |
| `with_openvpn` | outbound | 启用 OpenVPN 客户端出站，支持 TCP/UDP、TLS、用户名密码、`tls-auth` 和 `tls-crypt` 等。 |
| `with_trusttunnel` | inbound/outbound | 启用 TrustTunnel 协议，支持 TLS；出站实现支持 QUIC、拥塞控制和 multiplex 等选项。 |
| `with_sudoku` | inbound/outbound | 启用 Sudoku 协议，包含 AEAD、padding、动态 table、HTTP mask、复用和 TCP/UDP 支持。 |
| `with_snell` | inbound/outbound | 启用 Snell 协议及其 HTTP 混淆等选项。 |

这些扩展协议不是官方 SagerNet sing-box v1.13.16 默认功能；配置必须使用同一扩展分支的协议实现，不能直接套用官方 v1.13.16 的协议兼容性判断。

### 构建和链接相关

| 标签 | 作用 |
| --- | --- |
| `with_musl` | musl 环境下的构建模式标签，不是代理协议开关。主要影响 CGO/NaiveProxy/Cronet 等组件的链接方式。 |
| `badlinkname` | 允许使用 `go:linkname` 访问 Go 标准库内部函数，用于 kTLS、原始 TLS record 等底层能力。 |
| `tfogo_checklinkname0` | `badlinkname` 的配套构建标签；真正关闭 Go `go:linkname` 限制的是 `-checklinkname=0`。 |

## 运行时验证

查看版本、CGO 和构建标签：

```sh
sing-box version
```

查看 Go 构建信息和源码修订：

```sh
go version -m "$(command -v sing-box)"
```

重点确认：

- module/revision 指向扩展源码，而不是官方 v1.13.16；
- `-tags` 包含上述扩展标签；
- linker flags 包含 `-checklinkname=0`。

使用扩展协议时，可先用最小配置执行：

```sh
sing-box check -c /path/to/config.json
```

如果协议没有编译进二进制，通常会报未知的 inbound/outbound 类型；如果已经注册，则会进入对应字段校验。

确认是否静态链接，不要仅根据 `CGO: enabled` 判断：

```sh
file "$(command -v sing-box)"
ldd "$(command -v sing-box)"
```

## 参考资料

- Recipe 配置：[`recipe.json`](recipe.json)
- 源码替换补丁：[`patches/use-sing-box-extended.patch`](patches/use-sing-box-extended.patch)
- 官方构建标签说明：<https://sing-box.sagernet.org/zh/installation/build-from-source/>
- 官方 v1.13.16 默认标签：<https://github.com/SagerNet/sing-box/blob/v1.13.16/release/DEFAULT_BUILD_TAGS>
- 扩展分支默认标签：<https://github.com/shtorm-7/sing-box-extended/blob/extended/release/DEFAULT_BUILD_TAGS>
- 扩展分支协议注册表：<https://github.com/shtorm-7/sing-box-extended/blob/extended/include/registry.go>
- 固定源码提交：<https://github.com/shtorm-7/sing-box-extended/tree/00d3ed46bf84b0602e7e542bf9e949fef5080d7f>
