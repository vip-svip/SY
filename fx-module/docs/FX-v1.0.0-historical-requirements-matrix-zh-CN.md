# FX 1.0.0 历史需求纳入矩阵

审计日期：2026-10-25。本文是交付边界说明，不把计划或静态检查写成真机验证。

## 本轮已合并并经沙盒回归的项目

- [x] 以用户提供的旧版 FX 1.0.0 ZIP 为基础，不递增版本号。
- [x] 保留 `certs/submodules/pg_https_ca` 与 `certs/submodules/pg_mitm_ca` 的独立证书子模块布局。
- [x] 保留 ARM64 QuickJS-NG `qjs` 二进制、脚本宿主桥、偏好持久化及 HTTP bridge 文件。
- [x] 本轮增强脚本诊断：`console.log/info/warn/error/debug` 写入 `jsruntime/script-logs.jsonl`，不再默认静默丢弃日志；偏好读取刷新磁盘状态，降低并发脚本读取旧缓存的概率。新增对应静态回归测试。
- [x] Hosts 本地规则与 VPN 节点订阅保持不同入口；保留现有订阅 SHA-256 缓存/回滚实现及其回归测试。
- [x] VPN 页移除“快速配置”、应用选择/分应用代理 UI；顶部标题加大加粗、底部 Tab 加高、订阅开关增大。
- [x] 直连模式不要求节点；`vpncore_start` / `vpn_core_ensure` 在直连时不查找、下载或启动代理核心；新增实际调用后端入口的回归测试。
- [x] ZIP 条目完整性、关键二进制校验和、shell/内联 JavaScript 语法、已有脚本回归及 MITM Go 单元测试通过（详情见沙盒审计报告）。

## 已有部分实现，但不能宣称完整兼容

- [~] QuickJS 第三方脚本宿主：提供 `$httpClient`、`$task.fetch`、`$done`、`$prefs` 等常见接口子集。`$task.fetch` 的网络桥仍是同步阻塞调用后包装 Promise，不等同于原生异步运行时；厂商专有 API 尚未全部实现。
- [~] 规则兼容：可转换 hosts、部分 AdGuard/Adblock Plus/uBlock Origin 纯域名网络规则；复杂选项、脚本let、cosmetic/DOM 过滤、扩展 API 不等同于完整 uBlock Origin。
- [~] MITM：现有引擎和证书子模块存在；支持边界及真机信任状态必须按审计报告理解，不能宣称兼容所有应用。
- [~] 外部 VPN 叠加：提供检测/实验性兼容路径；是否串联成功依赖目标 VPN 应用、UID 与路由策略，未在用户 OnePlus 12 上验证。
- [~] 订阅事务：已有 SHA-256 缓存与部分事务回滚逻辑；iptables/系统网络状态回滚不是原子事务，不能宣称所有故障都可无损恢复。

## 尚未完成，不能算作“全部历史需求已实现”

- [~] **部分完成，真机验收待定：**已集成官方 AdGuard Home v0.107.79 Android ARM64 服务端及默认关闭的 opt-in 生命周期；包含配置/二进制 SHA-256 校验、健康探测、接管前门控、IPv4/IPv6 重定向准备及卸载停止。不是默认主 DNS；崩溃重启、真实 Android 端口/SELinux、完整断网恢复和 OnePlus 12 网络验收仍需验证。参见 `FX-v1.0.0-AdGuardHome-ARM64-integration-status-2026-10-27.md`。
- [ ] 尚未实现所有第三方规则脚本生态的完整 API 与真正非阻塞网络请求。
- [ ] HTTPS MITM 的全链路应用层请求/响应改写、HTTP/2、QUIC/HTTP/3、证书固定绕过等不具备通用完整支持。
- [ ] 尚未在 OnePlus 12 + KernelSU 上进行真实安装、重启、断网恢复、IPv4/IPv6、SELinux、证书信任、代理节点和卸载残留验收。
- [ ] 未完成浏览器视觉自动化；本轮 UI 结论来自 HTML 结构、JS 语法及静态逻辑检查。

## 交付判定

本包是“旧版基础上合并当前已完成修复并通过沙盒回归的重建包”，不是所有历史需求全部闭环的最终成品。未完成项必须继续实现与验证，不得通过 UI 文案或文档把它们标成已完成。
