# FX 1.0.0 — 历史需求补齐跟进（2026-10-25）

## 本轮实际修改

- QuickJS 宿主新增可选的单次运行结果路径参数；旧版直接调用方式仍回退到 `jsruntime/last-result.json`。
- `runner.sh` 为每次运行创建 `result-$$.json`，读取对应结果并在退出时清理，避免并发脚本互相覆盖共享 `last-result.json`。
- 新增 `scripts/tests/v1.0.0-jsruntime-isolated-result-regression.sh`，检查结果路径隔离和临时文件清理契约。
- 保留此前已合入的直连免节点逻辑、VPN 页面移除应用选择器、订阅事务与证书子模块保护等修改。

## 本轮验证

- ZIP `testzip()` 检查通过，重新解压后再次验证。
- 全部 shell 脚本通过 `sh -n`。
- `scripts/jsruntime/host.js` 通过 `node --check`。
- 打包后通过的定向测试：QuickJS argv、隔离结果文件、第三方 API 兼容契约、直连免节点、脚本订阅生命周期、脚本订阅同步、分页编辑器。
- 其他既有 `v1.0.0-*` 与 `v1.10.77`–`v1.10.85` 回归脚本已逐项通过。`v1.10.86` 会嵌套执行一组旧测试；单独运行曾通过，但在本轮完整批量执行中耗时异常，因此本轮不把全套测试宣称为一次性全部通过。

## 仍未完成或无法在沙盒证明

- QuickJS 的 `$task.fetch` 网络操作目前仍由同步原生 HTTP 桥接完成后包装为 Promise；这不等于真正的非阻塞异步网络 API。
- `$notify` / `$notification` 当前落地为模块状态目录中的 JSONL 记录，不等于 Android 系统通知栏通知。
- 第三方脚本生态不是全量原生兼容；不同应用的完整 API、定时器/后台行为、证书 pinning、HTTP/2、QUIC/HTTP/3 及双向 TLS 不可据此宣称已支持。
- HTTPS MITM、Android CA/APEX/SELinux 行为、OnePlus 12 真机流量路径、断网恢复和完整卸载效果仍需设备实测。
- 当前工程仍不能被描述为已完整融合官方 AdGuard Home 全部功能；需继续核对 DNS 服务的实际二进制、生命周期、规则转发和故障恢复闭环。

## 版本和备份

- 对外版本号继续为 `1.0.0`。
- 本文件记录的是本轮代码与沙盒验证范围，不代表真机验收报告。
