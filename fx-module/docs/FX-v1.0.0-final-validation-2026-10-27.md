# FX 1.0.0 · 2026-10-27 回归收口记录

## 本轮继续修复

- 恢复 `pg_restore_system_hosts_base_from_backup()`。FX 规则展开器重构时曾一并删除了该 helper，导致 `/system/etc/hosts` 被本模块 bind mount 遮住且需要从首次安装备份恢复时，基线恢复路径失败。现在恢复为原子复制、比对写入结果、拒绝模块生成标记文件并记录日志的实现。
- 修复 WebUI `pgWriteConf()` 恢复事务命令的 JavaScript 字符串语法，并将事务回归改成检查实际安全条件：写入失败只清理临时文件；恢复无法验证时保留 `.txn` 和已验证的 `.bak`，让下次写入能重试恢复。
- 保留 FX 规则动作统一归一逻辑：无动作旧黑名单行默认 `REJECT`；显式 `DIRECT`/`PASS`/`ACCEPT` 不会被改成 hosts 或 IP 拦截；`IP-CIDR,...,no-resolve` 会被规范成 `IP-CIDR,...,REJECT,no-resolve`，不会把 `no-resolve` 错读成策略。

## 当前工作树验证

- `v1.0.0-*.sh` 回归：176/176 通过，分 60 + 60 + 56 项执行。
- `v1.10.*-host-regression.sh` 兼容回归：15/15 通过。
- Shell 语法：227 个 `.sh` 文件通过 `sh -n`。
- WebUI 内嵌 JavaScript：31/31 个脚本块通过 `node --check`。
- MITM Go：`go test ./...`、`go vet ./...` 与 `go test -race ./...` 均通过。
- 包内含 `fxrules/anti_fraud_96110.txt`，来源为私有仓库 `vip-svip/FX` 的 `FX.txt`。范围只纳入源文件“国家反诈中心”域名、“反诈中心”标注的 IP 条目，以及 `com.hicorenational.antifraud`；不把通用 Android 安装器、OEM 安全中心或整片政府域名混入 FX 专用规则。

## 验证边界

所有结果均来自主机侧静态分析、模拟文件/挂载测试和回归测试。没有在 OnePlus 12 上安装运行，因此 DNS/VPN/MITM、APEX 信任视图、第三方 VPN 共存和真实流量仍未完成真机验收。源仓库 IP 的归属只沿用原有注释，未逐地址独立验证；FX 总开关应保持默认关闭，启用前应理解所选规则可能阻断命中的连接。

## Audit153 续作验收补充（2026-10-27）

以下是比上面旧快照更新的验收数字；前文的 176/176、227 个 Shell 文件是其记录时的历史结果，不代表当前最新总量。

- 全部 `scripts/tests/*.sh`：203/203 通过（包含当前 v1.0.0 测试与历史 v1.10 宿主兼容回归）。逐项结果记录于构建工作目录中的 `/tmp/fx-audit153-rerun.tsv`，未将单纯启动或静态 grep 冒充真机测试。
- Shell 语法：242/242 个 `.sh` 文件通过 `sh -n`。
- WebUI 内嵌 JavaScript：31/31 个脚本块通过 `node --check`。
- MITM Go：`go test ./...`、`go vet ./...`、`go test -race ./...` 均通过。
- 包内 QuickJS-NG ARM64 新构建 SHA-256：`88674653841015e6995ceb2ccab442303ff30f31dcd14a067ad9fe33479632d4`；`bin/arm64/qjs.sha256` 校验通过。ARM/ARM64 sing-box sidecar 和二进制也逐一通过摘要校验。
- 官方 AdGuard Home v0.107.79 `--check-config` 已验证 FX 运行时 YAML；最新 GitHub Actions 配置检查 run `40480135241` 成功。运行时只对 FX 反诈规则中的明确域名 REJECT 项生成 DNS 规则，未把广告、开屏或水印规则混入。
- Audit153 新增回归覆盖 VPN 接口探测缺失/错误/空结果的 fail-open、第三方 VPN UID 优先豁免或不确定时拆除 PGUARD OUTPUT 挂钩、DoT 主机名与 bootstrap DNS 及 root-owned DNS 避免自循环。
- 安装入口的 UNIX 可执行位与 ZIP 内权限必须在最终 ZIP 中再次确认；单独的测试源码通过不能替代包内验证。

## 仍未完成的设备验收

没有 OnePlus 12 实机或 adb 连接，因此不能声称已验证真实 DNS 响应、DoT/TLS 握手、IPv6 OUTPUT DNAT、KernelSU/SELinux 约束、私有 DNS/DoH 绕过、第三方 VPN 厂商行为、MITM 证书在系统/APEX 信任视图中的生效，或所有第三方脚本 API 兼容性。出现 VPN 接口状态未知时，当前实现以减少过滤能力换取联网安全，而不是继续强行接管。AdGuard Home 仍为 opt-in，默认关闭。

## Audit155 续接验收补充（2026-10-27）

- 已将本地 DNS 主链路视为 `Unbound 递归缓存 → AdGuard Home 反诈域名过滤 → FX DNS 重定向`，不是腾讯/阿里公共 DNS 转发模式。Unbound 直接访问根/TLD/权威服务器，缓存命中由本机响应；首次递归查询可能更慢，运营商若阻止 UDP/TCP 53 则须回退。
- 新发现并修复：看门狗只检测 Unbound、不检测 AdGuard Home；看门狗只写 PID 即报成功；卸载晚于防火墙清理才停看门狗；本地 DNS 引擎曾给所有 root-owned 包做宽泛 `RETURN`；CI SHA-256 sidecar 使用 runner 绝对路径。
- 修复后回归：207/207 Shell 回归，248/248 Shell 文件通过 `sh -n`，31/31 UI 内联 JS 通过语法检查；MITM Go `go test`、`go vet`、`go test -race` 均通过。全部 Unbound/AdGuard Home/QuickJS/sing-box 摘要检查通过。
- 看门狗现在验证完整 `AdGuard Home + Unbound` 健康；启动未经验证即回退 FX 双栈 NAT 接管；卸载在拆防火墙之前停止并验证看门狗；root DNS 自循环豁免只适用于 UDP/TCP 目的端口 53。
- 真机限制不变：未连接 OnePlus 12，无法确认真实运营商的直接递归 DNS 可达性、DNSSEC、IPv6 NAT、SELinux、Private DNS/DoH 绕过和第三方 VPN 实流行为。DNS 引擎仍默认关闭。

## Audit155 当前状态（2026-10-27，覆盖此前测试快照）

- 当前工作树回归脚本总数已增至 **208**。所有 208 个独立脚本均有通过结果；`localdns-watchdog-regression.sh` 的一次批次瞬时失败来自测试夹具把开关设为关闭却要求 `start` 存活的竞态，已修正夹具，并连续 12/12 通过。
- 当前 Shell 语法检查 **249/249**，Web UI 内嵌 JS **31/31**，sing-box JS **4/4**，MITM Go `test/vet/race` 通过。
- 修复 DNS root-owner 规则过宽：本地递归 DNS 的例外只针对 UID 0 发出的 UDP/TCP 目标端口 53，不会让所有 root-owned 连接绕过 FX 的代理/过滤。
- 修复卸载分支：即使 AdGuard Home 停止操作失败，也继续独立尝试停止 Unbound；停止失败会保留状态数据供重试。两项卸载回归通过。
- 以上仍不是 OnePlus 12 真机测试；DNSSEC、递归 UDP/TCP 53 直连、SELinux、IPv6 DNAT、Private DNS/DoH 绕行、第三方 VPN 实际共存仍需真机验收。
