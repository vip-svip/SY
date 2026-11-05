# FX v1.0.0 沙盒审计与修复记录（2026-10-25）

## 本轮实际修改

1. WebUI：从 VPN 主页面删除“快速配置”卡片及其点击委派逻辑。
2. WebUI：删除 VPN 配置面板中的“分应用代理”“分流模式”“应用列表”入口及应用选择浮层和相关选择器代码；未删除与 VPN 页面无关的隐私设置。
3. WebUI：顶部标题加大加粗，底部 Tab 栏加高，订阅列表启用/停用按钮增大。
4. WebUI：直连提示明确为无需节点；只有全局/规则代理需要节点。直连模式点击“启动核心”会说明无需核心，不再误导用户。
5. 后端：`vpncore_start` 和 `vpn_core_ensure` 在 `vpn_mode=direct` 时提前返回，不再为直连模式查找/下载/生成代理核心配置。
6. 新增 `scripts/tests/v1.0.0-vpn-direct-no-node-regression.sh`，实际调用后端入口并验证直连分支不访问核心二进制。
7. QuickJS 宿主桥：`console` 日志写入 `jsruntime/script-logs.jsonl`，修复原本可能静默丢弃脚本日志的问题；`$prefs` 读取前刷新磁盘数据，减少并发脚本间的陈旧读取。新增 `scripts/tests/v1.0.0-jsruntime-diagnostics-regression.sh`。

## 沙盒验证结果

- 33/33 个 `scripts/tests/v1.0.0-*.sh` 回归测试通过。
- 15/15 个现存 `v1.10.77` 至 `v1.10.92` 历史证书/事务回归测试通过（个别测试需要延长超时；该归档中不存在 v1.10.88 测试文件）。
- 31/31 个 WebUI 内联 JavaScript 代码块通过 `node --check`。
- 80/80 个 shell 脚本通过 `sh -n`；新加测试脚本也通过实际执行。
- `mitm` Go 单元测试 `go test ./...` 通过。
- 最终 ZIP `FX-v1.0.0-Integrated-Rebuild.zip` 重新解压验证通过；`ZipFile.testzip()` 无损坏条目；ARM64 `qjs` 和新测试脚本权限保留。
- 最终包 SHA-256：`477311083e121b7dc03a23f4c8d1ab928d5c87621e0798caee8a30addddcb38a`。最新包另存为沙盒备份 `FX-backups/FX-v1.0.0-latest-backup.zip`，哈希一致。

## 明确未声称完成的验证

- 没有在 OnePlus 12 真机上测试 KernelSU 挂载、iptables/IPv6、SELinux、DNS、断网恢复或实际代理节点连通性。
- 没有浏览器/设备视觉自动化；本轮 UI 检查为 HTML 解析、代码路径核对和 JavaScript 语法检查。
- QuickJS 兼容层是有限 API 子集；`$task.fetch` 网络请求目前同步执行，不能等同于各第三方客户端的完整异步运行时。脚本日志目前写入 JSONL 文件，尚未实现 Android 系统通知栏通知。
- MITM 目前限制为 TCP/443 上的 TLS HTTP/1.1；不支持 QUIC/HTTP3、证书固定绕过、客户端证书和所有应用兼容保证。证书信任及真实应用 HTTPS 改写尚未真机验证。
- 本轮未宣称所有第三方脚本、规则语法或所有 VPN 应用叠加情形完全兼容。
