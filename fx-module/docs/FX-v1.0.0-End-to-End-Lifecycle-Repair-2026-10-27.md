# FX 1.0.0 — 端到端生命周期修复记录（2026-10-27）

> **状态勘误（2026-10-27 后续修订）：**本文下方“已确认但本轮未虚构为完成”中的 AdGuard Home 缺口记录保留了当时审计结论；后续已加入 Android ARM64 服务端、默认关闭的 opt-in 生命周期、配置/校验和/健康探测、IPv4/IPv6 DNS 重定向门控及卸载停止路径。当前真实设备验收仍未完成，详见 `FX-v1.0.0-AdGuardHome-ARM64-integration-status-2026-10-27.md`。

## 本轮已修复

1. **升级不再清除用户明确的 CA 授权。** `customize.sh` 仅在没有 `ca-trust-optin` 时坚持默认禁用；存在该标记时保留各 CA 子模块原有启用/禁用状态。
2. **开机后恢复已授权的 CA 信任视图。** `service.sh` 等待 `sys.boot_completed` 后，仅在 `ca-trust-optin` 存在时调用 `certmgr.sh builtin sync`，并把成功/失败写入 `boot.log`。没有授权标记时不自动启用 CA。
3. **修复 `apply.sh` 中悬空 CA 后台任务等待。** CA 同步没有在这里启动任务，因此移除未初始化的 `_CERT_BG_PID` 和对应 `wait`，保留 LSPosed 配置生成任务的等待。
4. **打通 MITM 专用 CA 与运行时密钥。** WebUI 启用 `pg_mitm_ca` 时调用 `mitm-engine.sh trust-ca`，不再把普通静态 CA 子模块启用误当作运行时 MITM CA 已配好。
5. **为 MITM 流量重定向提供真实后端控制。** 新增状态刷新、显式确认启用、停止/撤销按钮；调用 `mitm-redirect.sh`，按真实 iptables/监听状态显示结果；在 MITM CA 禁用或移除前先要求确认本模块的流量重定向已清理。操作忙碌时避免重复提交。
6. **新增 CA/MITM 生命周期回归保护。** `scripts/tests/v1.0.0-ca-mitm-lifecycle-integration-regression.sh` 检查 CA 授权升级持久化、开机恢复、悬空等待和 UI→后端调用链。
7. **修复 MITM 运行时 CA 的实际挂载断点。** 仅更新随包模板并不能改变已释放的 `pg_mitm_ca` 子模块；现在会先备份并原子替换实际子模块中的 `.0` 证书，按完整 SHA-256 指纹校验，再调用证书管理器启用/同步。子模块不存在或带 `remove` 标记时交由启用流程从更新后的模板重建；失败则尝试恢复原模板、索引和子模块。修复了“模板已更新但实际仍信任旧 CA”的关键断链，并加入 `v1.0.0-mitm-runtime-ca-child-sync-regression.sh`，覆盖既有子模块和缺失子模块两种路径。
8. **FX 规则源与真实仓库打通。** 已从私有仓库 `vip-svip/FX` 的 `FX.txt` 生成随包 `fxrules/anti_fraud_96110.txt`，并把新安装默认配置、老用户幂等迁移、FX-only hosts、IPv4/IPv6 防火墙与有限域名 VPN route 连接起来。用户编辑时的本地副本优先于内置源；缺少其它 `fxfile://<id>` 源时仍明确跳过，不伪造内容。加入 `v1.0.0-fx-bundled-source-lifecycle-regression.sh` 与 `v1.0.0-fx-master-gates-vpn-routes-regression.sh` 验证配置→展开→hosts/防火墙/route 路径。

## 本轮验证

- 224 个 Shell 文件通过 `sh -n`。
- `webroot/index.html` 的 31 个内嵌 JavaScript 代码块通过 `node --check`。
- MITM Go 包 `go test ./...` 通过，`go vet ./...` 无报告。
- 本轮重点网络/证书/升级回归 14 项通过，包括 CA/MITM 生命周期、升级保留网络配置、MITM 信任预检、主机挂载失败安全、DNS 生命周期 fail-open、VPN 共存、直连无需节点、订阅事务、脚本同步、卸载防火墙链安全等。
- 当前修订的 173 个 `v1.0.0-*` 回归脚本分 4 批顺序执行，173/173 通过；另有 16 个历史版本回归脚本通过。
- 新增第三方 VPN DNS fail-open 与真实调用 hosts 挂载所有权事务测试，避免只封 DNS 不转发和挂载模拟格式错误导致的漏测。
- 未在 OnePlus 12 上安装和进行真实流量验收；主机侧测试不代表真机结果。

## 已确认但本轮未虚构为“完成”的架构缺口

- **已由后续修订覆盖的历史缺口：**该条记录生成时尚无官方 AdGuard Home 完整接入。当前已加入默认关闭的 opt-in 服务生命周期，但仍不能宣称 OnePlus 12 真机全链路验收通过。
- FX 规则源已随本修订包包含。源仓库没有独立 `96110` 域名或可阻止蜂窝电话的 DNS 规则；不得声称能拦截 96110 电话本身。原 `FX.txt` 中“反诈中心”标注的 IP 沿用原标签，但未逐条独立核验当前归属，可能共享/变化并误拦截其它服务。
- `vpn_mode=direct` 的 hosts 只能匹配明确写出的主机名与 suffix 根域名，不会把 `DOMAIN-SUFFIX` 变成 hosts 通配符；完整后缀匹配依赖 hostname-aware VPN route。当前 sing-box `redirect` 入站无法可靠命中 `PROCESS-NAME`，诊断日志已明确提示，不能把它计为已执行。FX 内置目标 App 的 `PACKAGE-NAME` 另由 Android UID 防火墙路径处理。
- QuickJS 第三方脚本 API 兼容仍为部分兼容；不能宣称 Shadowrocket、Surge、Loon、Quantumult X、Stash、Egern、Clash/Mihomo、sing-box 全部脚本 API 完全兼容。
- MITM 当前仅为显式选择加入的 IPv4 TCP/443、HTTP/1.1 实验能力；不声称支持 IPv6 MITM、QUIC 解密、证书固定绕过或自定义 TLS 栈。

默认安全行为保持：安装不自动信任 CA，不自动启用 MITM 流量重定向；遇到防火墙状态未知时不宣称清理成功。


## 后续修订：FX 源实际接入与挂载所有权（2026-10-27）

当前修订从私有仓库 `vip-svip/FX` 的 `FX.txt`（blob SHA `ba2e792d448aba3ac0dcedd7e12f3b0dcfde998b`）取限定区段，生成 `fxrules/anti_fraud_96110.txt`：148 条规则（5 条域名规则、1 条国家反诈中心 App 包名规则、142 条源文件标注为“反诈中心”的 IPv4 `/32`）。不将 `userReject.yaml` 或 `anti_fraud_config.yaml` 整份塞入专用源；不包含宽泛政府站点或通用系统安装器规则。IP 当前归属仍未逐个独立核验。

随后修复了两个加载断点：

- `fx=0` 时，VPN 的 `vpnrule.sh` 原先仍可能编译 `[list:fx]` 的已勾选行。现已在 route compiler 入口加全局主开关门控，且仅将小型 `anti_fraud_96110` 源的域名同步编译到 VPN route；通用大规则集仍避免将数万行域名编译为路由对象。
- hosts 代码原先通过 `grep " $PG/hosts "` 判断是否为模块挂载，匹配条件与卸载路径实际使用的 `source on target` 格式不一致；关闭 hosts/FX 的路径还会无条件 `umount /system/etc/hosts`。现统一三态识别，并在 apply、早期启动、事务替换中保留第三方挂载。早期启动只挂载模式标记与当前开关一致的 hosts 产物。

新增回归：`v1.0.0-fx-master-gates-vpn-routes-regression.sh`、`v1.0.0-fx-hosts-mount-ownership-regression.sh`。

## 后续修订：第三方 VPN DNS fail-open（2026-10-27）

审计发现外部 VPN 检测原先晚于 `PGUARD` DNS 过滤规则的构建；同时 FX 已因外部 VPN 而停用本模块 DNS/NAT 重定向，但仍可能留下 `dns_leak=1` 的明文 DNS REJECT。用户若配置了自定义/全局可信 DNS，系统解析器继续使用 DHCP DNS 时可能出现解析失败。现把隧道检测前移到 DNS 过滤之前，并在外部 VPN 已接管路由时跳过本模块的通用明文 DNS 锁定，记录 fail-open 原因，避免只封不转。新增 `v1.0.0-external-vpn-dns-failopen-regression.sh`。

该修复以避免第三方 VPN 断网为优先；外部 VPN 接管后，其自身 DNS 及防泄露仍需由外部 VPN 配置和真机验证，FX 不宣称能够代管第三方 VPN 的 DNS。


## 2026-10-27 · FX 动作语义与路由目标一致性修复

- 修复 FX URL 规则展开丢失第三列策略的问题。远程规则行现在保留显式 `DIRECT/PASS/ACCEPT/REJECT` 等目标；只有没有策略的旧式黑名单行才默认补 `REJECT`。对 `no-resolve` 等修饰符，在缺少策略时会在修饰符前补默认策略，避免把修饰符误当 outbound。
- 修复 hosts 与 FX IP/包名防火墙消费端忽略动作字段的问题。`DIRECT/PASS` 行不再被无条件改写成 `0.0.0.0` 或 DROP/REJECT；只有空动作（FX 黑名单历史默认）或明确 `REJECT/BLOCK/DROP/DENY/REJECT-DROP` 才进入拦截路径。
- sing-box 目标映射增加 `PASS/ACCEPT/ALLOW/BYPASS` → `direct`，`DROP/DENY/REJECT-DROP` → reject/drop；未知目标仍按既有 proxy fallback，不静默放行。
- FX 执行诊断拆分 suffix、keyword、package、process 计数；明确告知 DIRECT hosts 只能屏蔽根域名与显式主机名，`PROCESS-NAME` 在当前 REDIRECT 入站下不可靠，不应宣称已执行。修正 FX-only hosts 日志的行数/字节标签。
- 新增 `v1.0.0-fx-action-semantics-regression.sh`：覆盖 FX URL 正规化、hosts 实际构建、IP 动作过滤、PASS/ACCEPT 路由目标、REJECT-DROP 与窄规则源边界。


## 最终重测结果（2026-10-27 本修订包）

- `v1.0.0-*` 回归：173/173 通过（50 + 50 + 50 + 23 分组执行）。
- 历史版本回归：16/16 通过。
- Shell 语法：224 个脚本/入口通过 `sh -n`。
- WebUI 内嵌 JavaScript：31 个代码块通过 `node --check`。
- MITM Go 代码：`go test ./...`、`go vet ./...`、`go test -race ./...` 通过。
- ZIP 完整性、FX 源存在性和 148 条规则类型/数量核对通过。
- 上述为主机侧自动化验证与模拟挂载，不等于 OnePlus 12 真机验收。


## 追加审计：OEM hosts 基线与 IPv6 本地映射
- 修复首次安装备份 `backup/hosts.orig` 的恢复路径：当 live `/system/etc/hosts` 被绑定挂载隐藏时，尝试原子恢复 OEM 基线；拒绝带 FX/PrivacyGuard 生成标记的备份。
- 修复完整 hosts 与 FX-only hosts 的本地映射解析，保留 `::1 host`、`2001:db8::1 host` 等 IPv6 映射。
- 追加回归测试覆盖可信备份恢复、生成文件拒绝递归和双栈本地映射。
