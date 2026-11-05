# FX 1.0.0 — 安装包权限与 VPN 核心完整性修复（2026-10-27）

## 安装包权限问题

继续上轮审计时发现 UI 修复 ZIP 将直接执行入口压成 0644。修复包重新恢复原包 UNIX mode 元数据，并新增 `v1.0.0-runtime-entrypoint-permissions-regression.sh`。该回归在真实解包树检查所有关键入口仍有执行权限，且核对 QuickJS SHA-256 sidecar。

## sing-box 相同长度校验缺陷

`vpncore_install_builtin()` 以前只比较持久化 `$PG/bin/sing-box` 与模块内二进制的字节长度。不同内容只要长度相同，旧代码就直接 chmod 并当作可用；因此同长度损坏文件或旧核心可能绕过修复并在后续启动失败。

现改为：

1. 优先验证随包 `sing-box.sha256`，不匹配时拒绝使用损坏的模块内源。
2. 计算已释放文件摘要；只有与源摘要一致才直接复用。
3. 摘要不同则从验证后的内置源复制临时文件，核验复制后摘要，再原子替换。
4. 若 Android 环境没有可用 SHA-256 工具且无法建立可信摘要，记录明确日志；只有对没有 sidecar 的旧兼容来源才允许按长度回退。随包带 sidecar 的源无法通过摘要验证时不被当成可用核心。

为 ARM 与 ARM64 内置核心增加摘要文件，新增同长度损坏文件和源 sidecar 过期两种回归覆盖。

## 验证范围

- 从重新解包的新包执行 182 项 `v1.0.0-*` 回归。
- 所有 Shell 文件运行 `sh -n`。
- `webroot/index.html` 的 31 段内联 JavaScript 通过 Node.js 解析。
- MITM Go 的单元测试、`go vet` 与 race 检查通过。
- 没有 OnePlus 12 真机验证；这里的结果不是网络/VPN 实流测试。
