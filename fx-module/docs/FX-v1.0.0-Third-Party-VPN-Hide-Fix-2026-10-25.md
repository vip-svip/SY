# FX v1.0.0 — 第三方 VPN 隐藏适配修复记录

日期：2026-10-25

## 本次修改

- 修复原逻辑在检测到第三方 VPN 隧道后主动暂停 `vpn_hide` 的问题。
- 第三方 VPN 的 `ownerUid` 尝试检测不再依赖 `vpn_external_compat=1`；即使 FX 自身处于直连模式，也能为独立隐藏过滤器尝试识别外部 VPN 服务 UID。
- 新增独立的“第三方 VPN 隐藏（FX 直连模式也可用）”路径：仅在 `vpn_hide=1`、FX 为直连、且检测到外部隧道时建立轻量 IPv4/IPv6 UDP 痕迹过滤链。
- 在隐藏过滤链最前面豁免已识别的第三方 VPN 服务 UID，避免 QUIC/STUN 过滤误伤外层隧道。
- 此独立路径不劫持 DNS、不强制封锁 IPv6、不尝试把第三方 VPN 的隧道流量再重定向进 FX，优先避免断网或 VPN 自循环。
- 增加 `scripts/tests/v1.0.0-third-party-vpn-hide-regression.sh` 回归测试。

## 沙盒验证

- `scripts/tests/v1.0.0-*.sh`：39 项通过，0 项失败。
- Shell 语法检查：86 个 `.sh` 文件，0 项语法错误。
- 本次新增回归测试通过。
- 外部 VPN 叠加兼容回归测试通过。

## 边界与未验证事项

- 以上是静态/沙盒回归验证，不等于已在 OnePlus 12 + KernelSU 真机上验证。
- 外部 VPN 接口名检测使用常见隧道命名规则，可能漏掉使用非标准接口名的 VPN。
- `dumpsys connectivity` 中 `ownerUid` 的提取依赖 Android 版本/输出格式；若无法识别 UID，日志会显示 `unknown`，此时无法保证外层隧道不会被某些过滤规则影响。
- 本修复的防火墙规则不能替代 LSPosed/系统钩子对应用可见 VPN 状态（如 `TRANSPORT_VPN`、TUN 网卡信息）的隐藏。是否能隐藏这些系统 API 痕迹取决于对应钩子是否安装、启用并兼容目标 VPN 应用。
- 对第三方 VPN 开启隐藏后，只能确认过滤规则生成逻辑通过沙盒测试；真实应用流量路径、DNS 出口及第三方 VPN 的系统级检测结果仍需真机验证。
