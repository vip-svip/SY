# FX 1.0.0 历史需求补齐记录（2026-10-25）

## 本轮实际代码修复

- `scripts/dnscheck.sh`：修复 DNS 主动探测的误报。部分 `nslookup` 在 NXDOMAIN/SERVFAIL/REFUSED/超时等失败情况下，仍会输出 DNS 服务器自身的 IP；旧逻辑只要输出中出现 IP 就可能误报成功。现在先识别明确的否定结果，再检查地址结果。
- 新增 `scripts/tests/v1.0.0-dns-probe-negative-result-regression.sh`：覆盖否定响应优先级和有界超时契约。
- 保留此前修复：直连模式不要求节点；直连时不尝试启动 sing-box；QuickJS 每次执行使用独立结果文件，避免并发覆盖；VPN 页面移除快速配置卡片与逐应用代理控件并调整标题、底部 Tab 和订阅开关。

## 沙盒验证

- 新 DNS 回归：通过。
- v1.0.0 定向回归：35 项通过、0 项失败。
- 历史 `v1.10.*-host-regression.sh`：15 项通过（`v1.10.86` 单项需更长超时，40 秒内通过）。
- Shell 语法：打包解压后的 `.sh` 文件全部通过 `sh -n`。
- WebUI：30 个非空内嵌 JavaScript 块通过 `node --check`；HTML 中共发现 31 个 script 标签，其中 1 个没有非空内联代码。
- MITM Go 测试：`go test ./...` 通过。
- ZIP：`testzip()` 通过；最新 ZIP 与备份 ZIP SHA-256 一致。
- DNS 模拟集成：包含 resolver IP 的 NXDOMAIN 输出判为 failed；包含有效答案地址的输出判为 success。

## 尚未完成或未真机验证

- **历史状态（已于 2026-10-27 部分覆盖）：**当日尚未集成官方 AdGuard Home。后续已加入默认关闭的 opt-in Android ARM64 DNS 服务生命周期；真实 OnePlus 12 启动、解析和接管行为仍未验证。
- `$task.fetch` 仍是同步网络桥接后包装为 Promise；通知写入 JSONL，不等于 Android 通知栏；第三方脚本生态并非全量原生兼容。
- MITM 仍有 HTTP/2、QUIC/HTTP/3、证书 pinning 等兼容边界。
- 未在 OnePlus 12 真机完成 KernelSU 安装、重启、流量路径、断网恢复、证书信任和卸载验收。

版本号保持 1.0.0。不得将本记录视为完整最终验收或真机通过证明。

## 2026-10-25 订阅缓存并发一致性补强

- `scripts/subfetch.sh` 新增按 URL 校验键隔离的原子目录锁，锁保护缓存正文、元数据恢复、强制刷新与本地读取的完整事务；等待上限 30 秒。
- 发现并修复的风险：同一 URL 被 UI 重复点击、后台刷新与前台导入同时触发时，两个进程可能先后覆盖正文和 `.meta`，导致元数据与最终正文对应不上。
- 锁持有者退出时清理锁；若进程异常退出留下锁目录，后续进程会检查 PID 并尝试回收失效锁；遇到仍忙的缓存则返回明确错误，不无限等待。
- 新增 `scripts/tests/v1.0.0-subfetch-concurrency-regression.sh`：以模拟 curl 传输并行触发两次强制刷新，核对最终正文大小/行数与元数据一致、两个请求均完成且锁被释放。
- 本轮复验：36 个 `v1.0.0` 回归脚本通过；15 个可用 `v1.10.*-host-regression.sh` 通过；所有 Shell 文件 `sh -n` 通过；31 个非空 WebUI 内嵌 JS 块通过 `node --check`；MITM Go 测试通过；ZIP 完整性通过。
- 边界：这是模拟并发/主机沙盒验证，不是 Android 真机网络测试。第三方脚本 API、MITM 协议限制与 OnePlus 12 真机验收仍未闭环；AdGuard Home 后续已提供 opt-in 生命周期，但真机验收仍待完成。

