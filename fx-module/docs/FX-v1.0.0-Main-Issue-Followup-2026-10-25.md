# FX 1.0.0 主问题修复续记 — 2026-10-25

## 本轮变更

- 修复自定义 DNS 分支仅重定向 UDP/53、未处理 TCP/53 的不一致。TCP DNS 常用于大响应及 UDP 截断后的回退；在 `dns_forward=0` 且 `dns_block=1`、`custom_dns=1` 时，原实现会让 TCP 查询绕过指定解析器。
- 自定义 DNS 分支现在对 IPv4 UDP/53 与 TCP/53 都执行 DNAT，并输出 `udp+tcp/53` 日志。
- 新增 `scripts/tests/v1.0.0-custom-dns-tcp-fallback-regression.sh`，检查自定义 DNS 分支同时包含 UDP/TCP 规则，避免仅由另一个 `dns_forward` 分支掩盖回归。
- 继续保留上一轮修复：不会把 UDP/53 重定向到 TCP-only 的 sing-box redirect 入站。

## 沙盒验证

- 本轮新增专项测试：通过。
- 全部 `v1.0.0` 测试脚本：38 项通过，0 项失败。
- Shell 语法：85 个脚本检查通过，0 个语法错误。
- `mitm` Go 测试：通过（缓存结果）。
- ZIP 完整性：打包后执行 `testzip()` 检查。

## 未完成/限制

- 本轮只修复自定义 DNS 的 IPv4 TCP 回退；没有实现 IPv6 自定义 DNS 的 IPv4/IPv6 resolver 映射，也没有实现 VPN 透明接管 UDP DNS 的真实 TProxy/DNS 入站。
- 历史 host 回归测试批次在沙盒中执行超时，不能声称该批次本轮全部通过。
- 没有 OnePlus 12 + KernelSU 真机、真实网络环境或 Android UI 自动化环境，不能据此宣称真机无网问题已完全解决。
