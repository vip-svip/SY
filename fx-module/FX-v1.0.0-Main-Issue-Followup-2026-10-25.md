# FX 1.0.0 主问题修复续记 — 2026-10-25

## 本轮主问题

检查 VPN 流量路径时发现：开启 `vpn_dns_hijack=1` 后，IPv4 和 IPv6 规则都把 UDP/53 使用 `REDIRECT` 转发到 sing-box 的 `redirect` 入站端口。但此入站是 TCP 透明代理入站，并不是 UDP DNS/TProxy 入站。将 UDP 数据报送到 TCP 监听端口无法构成有效 DNS 转发，可能造成应用 DNS 失败，表现为“已连接但无法上网”。

## 修改

- `scripts/apply.sh`：移除 IPv4、IPv6 的 UDP/53 -> TCP redirect 规则。
- 保留显式的 TCP/53 转发规则。
- 日志明确说明 UDP/53 不会被该路径接管，避免把不支持的 UDP DNS 透明接管误报为已启用。
- 新增 `scripts/tests/v1.0.0-dns-udp-redirect-no-breakage-regression.sh`，检查 IPv4/IPv6 规则中不存在 UDP/53 被 REDIRECT 到 TCP 入站，同时确保 TCP/53 规则仍在。

## 验证

- 新增 DNS UDP redirect 回归测试：通过。
- `v1.0.0` 测试集：37 项通过，0 项失败。
- `scripts/` 下 Shell 语法检查：通过。
- MITM Go 单元测试：`go test ./...` 通过。
- ZIP 完整性检查：重新打包后执行 `ZipFile.testzip()`。

## 重要限制

- 本修复避免把 UDP DNS 数据报错误地送进 TCP 透明代理，不等于已实现 UDP DNS 劫持。
- UDP/53 目前保留系统解析路径；若未来要透明接管 UDP DNS，必须实现并验证真实的 DNS inbound/TProxy 路径，并配套生命周期与失败恢复，不能仅增加 iptables REDIRECT 规则。
- 未在 OnePlus 12 + KernelSU 真机上执行联网验证；不能据此宣称设备端“无网”问题已彻底解决。
- QuickJS 第三方 API 全量兼容、完整 AdGuard Home 服务集成及 HTTPS MITM 的广泛应用兼容性仍是未闭环项目。
