### 2026-10-29 续接审计：HTTP 205 Reset Content 响应脚本边界
- 修复响应 Hook 的 `bodyEditable` 判定遗漏 `205 Reset Content` 的问题。205 响应禁止携带内容，Hook 不应将上游实体正文作为可编辑响应正文提供给脚本。
- 保持最终状态归一化逻辑：205 响应清空正文、`Content-Length`、`Transfer-Encoding`、`Trailer` 及对应结构字段，避免传输元数据与正文状态冲突。
- 新增 `TestResponseHookResetContentNeverForwardsBody` 回归测试。
- 验证：`go test -count=1 ./...`、`go test -race -count=1 ./...`、`go vet ./...` 通过；Android ARM64 MITM 二进制交叉编译成功。未在 OnePlus 12 真机验证。

> 状态说明：本文件包含多轮审计的历史记录；早期条目中“尚未接入/未确认”的描述仅反映该条目生成时状态。当前 AdGuard Home opt-in 接入状态以 `docs/FX-v1.0.0-AdGuardHome-ARM64-integration-status-2026-10-27.md` 为准，最新 VPN fail-open 修订见 Audit153 报告末尾。不要把历史快照当成当前构建状态。

# FX 1.0.0 后端整合变更记录

### 2026-10-28 续接审计：本地 DNS 看门狗锁竞争恢复
- 修复 `scripts/localdns-watchdog.sh` 的恢复路径：之前 `apply.sh fast` 被并发事务拒绝（例如锁超时返回 75）时，看门狗会忽略返回码，并在 DNS 引擎 PID 标记仍缺失时直接退出；这并不能证明 PGNAT 的 OUTPUT 跳转已经移除。
- 现在看门狗会记录实际返回码，在引擎标记缺失时保留监控并延迟重试 `apply.sh fast`，只有引擎标记重新建立后才继续健康探测；防火墙仍完全由 `apply.sh` 事务管理，看门狗不直接改写规则。
- 扩展 `scripts/tests/v1.0.0-localdns-watchdog-missing-engine-marker-recovery-regression.sh`：首轮模拟 apply 锁竞争返回 75，第二轮恢复引擎标记，验证看门狗不误报 fail-open、不提前退出且会重试。
- 参考设计原则：bindhosts 对不同 root manager / mount 路径显式区分；MagicNet 强调数据面状态必须可观测、事务切换可回滚，进程存在不等于流量路径健康。这里只移植与 FX 现有架构兼容的恢复/可观测性原则，没有复制它们的整个网络实现。
- 验证：本轮新增/相关 6 个定向 Shell 回归通过；310 个 `.sh` 文件通过 `sh -n`；ZIP `unzip -t` 完整性通过。全量 264 个测试脚本此前整体运行超时，因此不宣称全量测试通过。
- **设备边界：**未在 OnePlus 12 真机验证；此修复保证的是遇到 apply 锁竞争时持续重试并避免错误地把“退出”当成“已回滚”，不能单凭主机侧测试证明设备上所有 NAT 故障均能自动恢复。

### 2026-10-27 续接审计：DNS 生命周期闭环与 QuickJS 导入别名加固
- 将 Android ARM64 AdGuard Home v0.107.79 接入 `scripts/apply.sh` 的自动安全启用路径，移除用户可见的本地 DNS 开关；必须同时满足防护总开关、DNS 拦截、DNS 兜底转发、FX 直连模式、未检测到外部 VPN、未开启 DoT 阻断。
- 新增 `scripts/adguardhome.sh` 管理器：内置二进制 SHA-256 验证、生成只包含反诈中心 DOMAIN/DOMAIN-SUFFIX REJECT 项的配置、执行上游 `--check-config`、启动与 PID 身份核验、限时 loopback DNS 解析探测、健康失败停止及安全卸载。
- DNS 引擎健康探测成功且 IPv4/IPv6 NAT 规则都能建立时，才原子安装 OUTPUT 跳转；IPv6 NAT 不可用、规则提交失败或钩子安装失败时撤销部分规则、停止引擎并回到既有可信 DNS / fail-open 路径。外部 VPN 与 DoT 锁定下不启用此引擎。
- 新增 `docs/AdGuardHome-FX-runtime-config-v1.0.0.yaml` 作为运行时配置样例，并要求它与管理器实际输出逐字一致；官方 AdGuard Home v0.107.79 `--check-config` 在 GitHub Actions run `40477961866` 中通过。
- 新增 AdGuard 管理器动态主机回归，使用可控假服务程序验证 start/status/stop、健康探测失败清理和 SHA-256 不匹配拒绝启动。此项只验证控制流，不等同于真实 Android DNS 引擎运行测试。
- 修正两条过期 NAT 回归断言，使其检验新的 IPv4/IPv6 OUTPUT 原子钩子条件；网络实现未为通过旧断言而回退。
- QuickJS-NG v0.17.0 新构建明确拒绝 `qjs:std/os/bjson` 与裸别名 `std/os/bjson`，并拒绝 `.so` 动态导入；Android ARM64 CI run `40476252466` 构建、架构检查与导入探针成功，替换了包内 `bin/arm64/qjs` 并刷新 SHA-256。
- 本轮 200 个 Shell 回归脚本全通过，另有 4 个 sing-box JavaScript 回归、239 个 Shell 语法检查、MITM Go `test/vet/race` 检查通过。
- **设备边界：**真实 AdGuard Home Android 二进制尚未在 OnePlus 12 运行；端口 53 权限、SELinux、Android `nslookup` 格式、内核 IPv6 NAT、Private DNS/DoH 旁路与第三方 VPN 共存仍需真机验收。DNS 引擎保持默认关闭，不宣称全链路已通过。



### 2026-10-27 安全修复：QuickJS 特权模块动态导入绕过
- 复现远程脚本通过 `import('qjs:os')` 重新取得 `os.exec()` 并以 FX 模块权限启动系统命令的高危漏洞；只清空 `globalThis.os/std` 并不足以构成安全边界。
- QuickJS-NG v0.17.0 加入导入沙箱开关；在可信 `host.js` 预加载完成后、模块缓存查找之前，拒绝 `qjs:std`、`qjs:os`、`qjs:bjson` 与 `.so` 原生模块的动态导入。
- 将加固版 QuickJS-NG 重新交叉编译为 Android `arm64-v8a` / API 24 二进制，并替换包内 `bin/arm64/qjs`；二进制 SHA-256 记录在 `bin/arm64/qjs.sha256`。
- 新增 `scripts/jsruntime/privileged-import-smoke.js`、可重放的源代码补丁 `scripts/jsruntime/quickjs-import-sandbox-v0.17.0.patch` 与 `scripts/tests/v1.0.0-jsruntime-privileged-import-block-regression.sh`，覆盖特权模块导入、裸别名导入、原生 `.so` 导入、二进制摘要与接口完整性。
- 主机原生 QuickJS 实测：四类导入均被拒绝；`$task.fetch`、`$prefs`、`$done` 的回归流程通过；GitHub Actions Android ARM64 编译、ELF 架构和动态加载器校验通过。
- 安全边界仍非 Android/内核级进程隔离；脚本仍可调用 FX 主动暴露的 HTTP / 偏好存储 API。OnePlus 12 真机执行、SELinux 与完整流量链尚未验证，不能宣称整个项目已全部闭环。

## 本轮变更
- 通用下载器改为严格处理 HTTP 状态：curl 使用 `-f`，HTTP 4xx/5xx 不再被当作成功正文缓存。
- 下载器不再关闭 TLS 证书校验（移除 `--insecure` / `--no-check-certificate`）。证书异常或自签名源可能因此下载失败；失败应走现有缓存回退，而不是接受不可信响应。
- Hosts 订阅下载器采用同样的 HTTP 状态与 TLS 校验策略。
- 新增 `scripts/tests/v1.0.0-http-fetch-integrity-regression.sh`，覆盖 HTTP 错误页不得被判成功、有效响应可下载。
- 公开版本号继续固定为 `1.0.0`。
- 本轮后续增补已修改 `webroot/index.html`，接入脚本订阅刷新；不能再把 WebUI 描述为与旧基线字节级一致。

## 本轮验证
- HTTP 下载完整性回归测试：通过（模拟 curl）。
- 订阅缓存回归测试：通过。
- VPN 共存顺序回归测试：通过。
- 所有 Shell 脚本 `sh -n`：通过。
- MITM Go 单元测试：通过。
- WebUI 内联 JavaScript `node --check`：通过。
- ZIP 完整性：通过。

## 尚未闭环（不得视为已实现）
- 系统 `/system/etc/hosts` 的可编辑整文件视图仍未实现；当前仍是只读视图。
- 订阅规则仍会参与生成模块 hosts 输出；订阅与 Android 原生 hosts 的完全分离尚未实现。
- 尚未在 OnePlus 12 真机上验证；VPN 共存测试是主机侧/静态回归，不代表所有第三方 VPN 都兼容。
- 本轮没有实现订阅 SHA-256 来源校验；HTTP/TLS 校验不能替代内容签名/摘要验证。

### 本轮增补：订阅缓存双代回滚保护
- 为每个下载缓存保留一份已校验的上一代内容及 SHA-256 sidecar。
- 在替换当前缓存前先写入并校验上一代备份；如果更新中断导致当前缓存与 sidecar 不匹配，则仅在上一代文件和摘要匹配时恢复。
- 该 SHA-256 仍是本地静态完整性检查，不验证远端发布者身份，也不是签名验证。
- 回归测试覆盖：首次下载、成功更新、模拟当前缓存损坏/替换中断、网络失败时恢复上一代、无有效缓存时拒绝不完整下载。

### 规则生态兼容层补强（FX 1.0.0）
- 扩展静态导入器对 AdGuard / Adblock Plus / uBlock Origin 纯域名网络过滤规则的保守转换：`||domain^` 转拦截，`@@||domain^` 转独立白名单。
- 支持部分 Quantumult X 风格 `host` / `host-suffix` 规则别名，保留 `PROXY` 等策略语义，不把代理规则误写成 DIRECT。
- 带额外条件的过滤器、元素隐藏规则和复杂 L7 指令显式标记 SKIP，避免将有条件规则扩大为全域拦截。
- 新增 `docs/RULE-COMPATIBILITY-zh-CN.md` 与回归脚本 `scripts/tests/v1.0.0-rule-compat-regression.sh`，明确兼容边界。
- 本轮不实现客户端专有 JavaScript API 运行时，不代表 Surge/Shadowrocket/Quantumult X 等脚本已经可执行。

### QuickJS 真实执行链参数修复
- 修复宿主参数顺序，并改用 QuickJS `-I` 宿主预加载模式，使用户脚本在同一执行上下文内运行，Promise job 可在脚本退出前处理。
- 隐藏 `std` / `os` / `scriptArgs` 全局，强制 classic script 模式；宿主内部仍可访问文件与 HTTP 桥，用户脚本不直接获得系统文件/进程 API。
- MITM 实时请求/响应钩子可应用 `$done` 的受支持字段；脚本订阅支持 SHA-256 sidecar、上次有效缓存回退和显式 FX 触发元数据。
- Surge/Loon 风格的 `type=http-request|http-response,pattern=...,script-path=https://...` 可转换为 `[list:script]`，其余不支持的声明仍会明确跳过。
- 当前仍有明确边界：`$task.fetch` 的网络调用同步执行；第三方客户端私有 API 未全量复刻；MITM 不处理 QUIC/HTTP3、证书固定绕过或客户端证书。35 个 shell 回归脚本与 Go 单元测试通过，未在 OnePlus 12 真机验收。
- 增加必需参数校验，并新增 `v1.0.0-jsruntime-argv-regression.sh` 回归检查。
- 本次只确认静态参数映射与主机侧回归；尚未在 OnePlus 12 真机执行 ARM64 qjs 或验证第三方脚本兼容性。

## QuickJS-NG 后端补强（候选构建，尚未宣称最终验收）
- 将真实 Android ARM64 QuickJS-NG v0.17.0 `qjs` ELF 放入 `bin/arm64/qjs`，附带上游许可证。
- 新增显式脚本运行入口与宿主桥：`$done`、持久化 `$prefs`、常见 `$httpClient` 回调方法、`$task.fetch().then().catch()` 链式接口；HTTP bridge 限制 URL scheme、请求超时与头部换行，避免 `eval`/shell 命令拼接。
- MITM 引擎加入带 `FX-SCRIPT-TYPE` / `FX-SCRIPT-MATCH` 元数据的本地请求/响应钩子，支持受限的 `$done` 字段回写；正文只对未压缩且可识别的文本类内容（不超过 1 MiB）启用修改。
- 新增脚本元数据解析、头部注入防护、请求/响应 `$done` 回写与脚本订阅同步回归测试。
- 新增启用脚本订阅同步：只接受 HTTPS URL、限制 1 MiB、要求显式 FX 类型与匹配元数据、提交后校验 SHA-256；失败保留最后一次有效脚本，禁用/删除订阅时清理本同步器拥有的缓存。
- 未完成项：第三方 `[Script]` 声明不会自动转换成 FX 触发元数据；`$task.fetch` 虽返回原生 Promise，但网络请求仍同步执行；各客户端私有 API 兼容性、OnePlus 12 真机流量及证书链仍需验证。此候选包不能标记为“全部脚本生态兼容”或“最终成品”。


## QuickJS 入口参数实测

- 使用 QuickJS-NG v0.17.0 主机原生构建确认 `scriptArgs[0]` 为入口文件 `host.js`，业务脚本、事件文件、状态目录和 HTTP bridge 对应 `[1]` 至 `[4]`；宿主保持正确索引。
- 修正回归测试，使其验证实际 CLI 参数布局。
- 限制说明：这不是第三方脚本实时代理触发器，也不代表 HTTPS MITM 已在 OnePlus 12 上端到端验证。

- QuickJS 宿主隔离为 IIFE，防止与用户脚本顶层词法变量冲突；修正事件响应只提供 `status` 时 `statusCode` 默认值不一致的问题，并增加原生 QuickJS-NG 实际执行回归。


## 后续补强：脚本订阅接入 MITM 实时 hook
- 新增 `scripts/jsruntime/sync-subs.sh`：从启用的 `[list:script]` 项拉取 HTTPS 脚本，限制 1 MiB；支持 FX 显式触发元数据及常见 `@match` / `@include` / `@url` URL glob；不满足触发条件的脚本不会被误报为已生效。
- 更新采用临时文件、SHA-256 记录与提交后复核；发现校验不一致或 sidecar 提交失败时回滚到上一份文件。注意这是本地完整性校验，不是远端发布者签名验证。
- WebUI 的“刷新订阅”会先尝试同步脚本，再继续原有配置应用流程；脚本刷新失败不会阻断 hosts/DNS 应用。MITM 在每个新 TLS 连接重新读取 hook 清单。
- `pg-mitm` 已用 Go 1.23.2 交叉编译为 Android ARM64 新二进制；新增 hook URL glob、SHA-256 sidecar 与并发快照测试。
- 验证：Go race tests、全部 Shell 回归和语法检查通过；**仍未在 OnePlus 12 真机完成 TLS 端到端、系统证书信任、QUIC/HTTP3、VPN 共存及实际第三方脚本兼容验收**。不应宣称所有 Shadowrocket / Surge / Loon / Stash 脚本均可用。

### 后端继续补强（2026-10-24）
- `$done()` 不传参数时回传当前请求/响应对象，支持先修改 `$request` / `$response` 再结束脚本；第一次调用提交后不再被重复调用覆盖。
- 实时脚本事件显式携带 request/response 阶段。
- 订阅同步可识别常见 `@match` / `@include` / `@url` HTTP(S) URL glob 元数据，并以受限方式生成 FX hook 类型；未声明可匹配 URL 的脚本仍不执行。
- Android ARM64 MITM 引擎已重新构建；主机 QuickJS 语义回归、36 项 Shell 回归和 Go race 测试通过。
- 本构建仍不是经过 OnePlus 12 真机验收的发布版；完整异步语义及各第三方客户端专有 API 不作兼容保证。

### 第三方脚本宿主 API 补强（继续整合）

- `$httpClient` 超时范围改为 1–120 秒，并读取请求级 `timeout` 或宿主默认值；HTTP 响应对象补充 `statusText` 常见状态描述。
- 新增 `$utils` 常用工具入口：Base64、URL 编解码、JSON parse/stringify、UUID 和持久化存储转发。
- `$environment` 补充多个客户端常见版本字段；兼容检测标志明确保持为 FX（不伪装成已运行于 Surge/Loon/Shadowrocket）。
- 新增 `scripts/tests/v1.0.0-jsruntime-utils-regression.sh`。本次 39 项 Shell 回归通过，JavaScript 文件通过 Node 语法解析。
- 兼容边界不变：这些是常见 API 子集，不代表全量第三方 API；网络桥仍同步执行，客户端私有 API、异步事件语义和真机端到端行为仍未全部实现/验证。

### 第三方脚本兼容配置档案纠偏

- 新增按事件 `compatPlatform` / `platform` 选择的客户端兼容配置档案。
- 默认使用 FX 中性环境，不再同时伪报多个第三方客户端版本；选定档案才暴露对应版本标记。
- 此改动减少错误平台分支，不代表全部第三方 API 已完整实现。

## WebUI 重构补丁（2026-10-25）

- 编辑器分页读取增加 8 秒超时、可见错误和重试入口；过期请求不会覆盖新打开的文件视图。
- 底部导航增加 visualViewport / resize 键盘状态适配，键盘弹出时把导航区域移到键盘遮挡区，而不是显示在键盘上方。
- VPN 页面增加真实联动配置的代理总开关：关闭切换到 direct，开启在选择节点后切换到 global 并触发已有 Apply 流程。
- 增加外部 VPN/隧道接口提示；模块沿用 apply.sh 的外部 VPN 保护，不宣称两个 Android VPN 隧道可以同时建立。
- 增加编辑器键盘、超时重试和代理总开关回归脚本。

限制：此项目是 KernelSU/root 透明代理，不是 Android 应用内的 VpnService。另一个 VPN 应用占用系统 VPN 时，透明代理接管会被保护逻辑跳过；如需真正同时工作，必须由外部 VPN 提供可用的本地 SOCKS/HTTP 入站，或改为实现 Android 应用级 VpnService/隧道转发架构，不能仅靠 WebUI 开关解决。

### 编辑器恢复：传统分页文本编辑
- 恢复为传统分页式编辑器：当前页显示为可直接编辑的多行文本框，提供上一页、下一页、保存当前页和重新载入。
- 前端每次只读取 60 行、最多 64 KiB 的当前页；不会把整个大文件载入 textarea。
- 新增 `fileedit.sh replacepage` 后端操作，按页范围构建候选文件，通过现有备份校验与原子替换流程提交；保存失败时保留原文件并返回错误。
- 离开未保存页面或重新载入时会先询问，避免无意丢失修改；页面范围超出/文件已变化时拒绝不安全写入。
- 回归检查：全部 43 个 Shell 测试通过，31 个内联 JavaScript 块语法检查通过，Shell 语法检查通过。仍需在目标 Android WebView 上进行交互验收。

## 外部 VPN 叠加兼容（实验性）
- 新增 `vpn_external_compat=0` 默认关闭的显式兼容开关；关闭时沿用安全策略，检测到常见外部隧道后暂停 FX 透明接管。
- 开启后，在检测到外部隧道时允许 FX 的 PGVPN TCP REDIRECT 继续安装；通用 PGNAT DNS/透明代理仍暂停，避免重复劫持。
- WebUI 增加“外部 VPN 叠加兼容（实验）”开关和“检测出口”诊断入口。
- 新增 `scripts/vpn-overlay-check.sh`：尝试检查 root 的路由接口与公网 IPv4，并明确报告是否确认走检测到的隧道。
- 限制：不同 VPN 应用对 root/系统 UID、策略路由和隧道流量的处理不同；此模式不保证代理串联成功。检测接口/公网 IP 也不能代替实际应用端到端验证。版本号仍保持 1.0.0。
- 叠加模式会尝试识别外部 VPNService 的 owner UID，并把该 UID 从 FX 自身透明重定向中豁免，避免将外层 VPN 的 TCP 隧道连接重定向回 FX；无法识别 UID 时后端 fail-safe 暂停叠加。
- 叠加期间跳过可能破坏外部隧道的 QUIC/UDP 阻断、killswitch、IPv6 全阻断和 VPN 隐藏规则，因此这些防泄漏/隐藏功能会降级并在日志中记录。

## 订阅导入与 VPN 订阅链路修复（2026-10-25）

- 显式导入 URL 时请求强制刷新；下载器为订阅请求增加 `clash.meta` User-Agent、Accept 头、连接/总超时与一次重试，下载失败时仍保留并回退到已存在的缓存。
- 导入前校验订阅元数据、缓存 key、分块偏移、每块字节数和最终正文总字节数；遇到读取失败/截断不再静默把部分内容当作完整订阅解析。缓存文件存在但元数据缺失/大小不一致时会重新计算并修复元数据。
- 支持 Base64 包装的 Clash YAML；解析前去除 BOM、兼容 CRLF。
- 前端新增 sing-box JSON `outbounds` 解析，并保留 WebSocket network/path/Host 等关键字段；后端订阅更新新增 QuickJS-NG JSON→URI 转换器，使 URL 订阅可在后续更新时继续被识别。
- 订阅导入失败会区分网页/登录页、未知格式、YAML 无可用节点、sing-box JSON 无可导入出站等情况，不再统一显示模糊的网络错误。
- 新增 `scripts/tests/v1.0.0-vpn-subscription-import-regression.sh`，覆盖 BOM/CRLF 与 Base64 Clash YAML 的后端转换及导入完整性检查契约。

验证边界：已在本地测试环境验证前端解析样例、Shell 转换、模拟 HTTP 下载/分块读回、语法与回归测试；尚未在 Android 真机上验证机场的鉴权/限流行为，也未在 Android ARM64 上端到端执行新增的 QuickJS sing-box JSON 转换器。不同机场的专有 JSON/YAML 扩展和不支持的协议仍可能需要适配。

## 2026-10-25 订阅缓存并发一致性补强

- `scripts/subfetch.sh` 新增按 URL 校验键隔离的原子目录锁，锁保护缓存正文、元数据恢复、强制刷新与本地读取的完整事务；等待上限 30 秒。
- 发现并修复的风险：同一 URL 被 UI 重复点击、后台刷新与前台导入同时触发时，两个进程可能先后覆盖正文和 `.meta`，导致元数据与最终正文对应不上。
- 锁持有者退出时清理锁；若进程异常退出留下锁目录，后续进程会检查 PID 并尝试回收失效锁；遇到仍忙的缓存则返回明确错误，不无限等待。
- 新增 `scripts/tests/v1.0.0-subfetch-concurrency-regression.sh`：以模拟 curl 传输并行触发两次强制刷新，核对最终正文大小/行数与元数据一致、两个请求均完成且锁被释放。
- 本轮复验：36 个 `v1.0.0` 回归脚本通过；15 个可用 `v1.10.*-host-regression.sh` 通过；所有 Shell 文件 `sh -n` 通过；31 个非空 WebUI 内嵌 JS 块通过 `node --check`；MITM Go 测试通过；ZIP 完整性通过。
- 边界：这是模拟并发/主机沙盒验证，不是 Android 真机网络测试。第三方脚本 API、完整 AdGuard Home DNS 守护进程、MITM 协议限制与 OnePlus 12 真机验收仍未闭环。


### Audit32（版本号仍统一为 1.0.0）
- sing-box 配置先写临时文件并预检，通过后原子替换正式配置，避免生成中途失败破坏旧配置。
- 核心运行预检/启动失败时尝试恢复先前配置；无旧配置时清理本轮失败配置。
- 增加核心配置事务回归测试。

Audit98：加强 FX 防火墙规则可观测性。IP-CIDR/IP-CIDR6 规则现在分别统计 IPv4/IPv6 待提交条目与添加失败数；日志明确说明最终生效仍依赖防火墙批量提交和 OUTPUT 挂接验证，不再在此阶段提前写成“已拦截”。新增回归测试防止未来重新引入过度乐观的成功日志。


## 2026-10-27 可靠性补强
- 三次中断合并：本地 Hosts 旧列表一次性迁移和事务回滚、快速应用输入指纹与离线缓存回退、第三方脚本/规则导入后的真实运行时清单同步和 HTTP 管理头保护。
- 修复升级安装器会覆盖已有网络键的重大问题：现在仅补缺失默认键，已有 VPN 模式、DNS、hosts、killswitch 与拦截设置不被安装器强制重置。
- 更新回归覆盖；最终包内 177/177 Shell 回归、212 个 Shell 语法检查、31 个内嵌 JavaScript 语法检查及 Go test/vet/race 均通过。
- MITM Android ARM64 SHA-256：`da5682fb397e6385727e21927eccabc9300bb09598b3fb47fbcc6cf35e69c42d`。未进行 OnePlus 12 真机验收。

### 2026-10-27 UI 根结构与启动诊断修复
- 修复 CSS 注释泄漏到页面正文：所有 6 个静态样式块已按原有顺序移入 `<head>`。
- 启动异常会显示失败阶段与错误摘要，并提供重新检测入口；非关键列表、订阅状态和状态刷新仍按既有逻辑隔离处理。
- 软键盘弹出时底部 Tab 保持可点击，页面内容单独滚动。
- 新增 UI 结构集成回归测试。验证为静态/主机侧测试，尚未完成目标设备逐页视觉验收。


## 2026-10-27 · FX 内置规则贯通与 hosts 独立生效修复

- 从私有仓库 `vip-svip/FX` 的 `FX.txt` 筛选国家反诈中心域名、被源文件标注为“反诈中心”的 IP 条目与 `com.hicorenational.antifraud`；不将通用 Android Package Installer、OEM 通用安全中心及整个 `mps.gov.cn` / `miit.gov.cn` 站点加入 FX 专用源。
- 新增 `fxrules/anti_fraud_96110.txt`，并将其登记到新安装默认配置；旧安装升级时幂等补入 `[list:fx]`，保留用户已有的同 ID 条目和启停状态。
- 修复迁移函数引用未初始化的 `_mg_i1/_mg_i2` 临时变量、导致迁移补项分支始终跳过的问题。
- 修复 `fx=1`、`hosts_block=0` 时域名规则不进入系统 hosts 的断点：新增 FX-only hosts 构建路径，不顺带应用广告/遥测/订阅列表；保留系统 hosts 基线和独立用户本地 hosts。
- 将明确 `PACKAGE-NAME,...,REJECT` 的 FX 规则桥接到 FX 自有防火墙链，使直连模式也能按 Android UID 过滤目标 App 流量，而不只写入 sing-box 路由 JSON。
- 限制说明：源仓库没有独立的 96110 域名条目，不能通过 DNS/IP 规则拦截蜂窝电话；源文件 IP 归属未逐条独立验证，FX 主开关保持默认关闭。


## 2026-10-27 · FX/VPN/Hosts 三条加载链进一步打通

- 修复 VPN 规则编译器没有检查全局 `fx` 主开关的问题。现在 `[list:fx]` 的单条启用状态不能绕过 `fx=0`；FX 关闭时，sing-box route 配置不会继续包含 FX 路由规则。
- 针对小型内置源 `anti_fraud_96110`，将有限的 `DOMAIN` / `DOMAIN-SUFFIX` 规则同时编译进 sing-box 路由，避免内置 VPN 在远端 DNS/嗅探场景下只依赖 Android hosts；通用大规则源仍限制在 hosts 层，避免上万条域名膨胀路由。
- 修复 hosts 挂载所有权检测：统一识别本模块拥有、第三方拥有、未挂载三态；应用更新、FX 关闭、开机挂载与事务替换时都不会覆盖/卸载第三方挂载。
- 开机早期挂载改为检查当前 `fx`/`hosts_block` 设置与上次成功生成的 `hosts-mode` 标记，避免将旧的 full hosts 或 FX-only hosts 作为不匹配当前设置的文件挂上去。
- hosts 输入指纹纳入捕获的系统 hosts 基线，避免基线改变后快速应用错误复用旧产物。
- 新增 FX 总开关→VPN 路由与 hosts 挂载所有权回归测试。全部仍是主机侧/模拟挂载测试，未宣称目标设备已实测。

## 2026-10-27 · 第三方 VPN DNS 断网风险修复
- 将外部 VPN 隧道检测移至 DNS 过滤规则构建之前。发现第三方 VPN 接管路由、且 FX 选择暂停本模块 DNS/NAT 重定向时，不再单独留下 `dns_leak` / `block_plain_dns` 的 53 端口拒绝规则。
- 该路径改为明确 fail-open 并记录日志，让外部 VPN 自己管理 DNS，避免系统/DHCP DNS 与配置的可信 DNS 不一致时出现“VPN 已连接但域名全部无法解析”。这不代表 FX 能保证第三方 VPN 的 DNS 防泄露策略。
- 修正 hosts 事务测试中的 mount 输出模拟格式，并增加第三方 mount 真实调用 `pg_commit_hosts_candidate()` 的回归，验证源文件和候选文件都被保留、不调用卸载。


### 2026-10-27 · FX 规则动作语义与 VPN 路由最后一公里
- 远程 FX 规则展开保留第三列动作；动作缺失时按黑名单约定补 `REJECT`，不再把规则值误当路由目标。支持 `no-resolve` 等修饰符先插入默认动作。
- hosts、IP-CIDR、PACKAGE-NAME 过滤只消费空动作旧式黑名单或明确 REJECT/BLOCK/DROP/DENY/REJECT-DROP；显式 DIRECT/PASS/ACCEPT 不会被主机 hosts 或防火墙强制拦截。
- sing-box 路由目标补齐 PASS/ACCEPT/ALLOW/BYPASS 直连别名与 DROP/DENY/REJECT-DROP 拒绝别名。
- 诊断不再暗示 PROCESS-NAME 切换 VPN 模式后就一定有效；当前 REDIRECT 入站进程反查不可靠，日志会明确提示。
- 新增 FX 动作语义集成回归，覆盖内置源、远程 URL、hosts 构建、IP 过滤与 route 编译。


## 2026-10-27 · Hosts 基线恢复与 IPv6 本地映射
- 当 `/system/etc/hosts` 被模块 bind mount 隐藏时，优先从首次安装备份 `backup/hosts.orig` 原子恢复 OEM 基线；拒绝将带 FX/PrivacyGuard 生成标记的文件递归用作基线。
- 完整 hosts 与 FX-only hosts 模式均保留 `::1 host`、`2001:db8::1 host` 等本地 IPv6 映射；无主机名的裸 IP 行不作为有效映射写入。
- 新增可信备份恢复、生成文件拒绝递归、IPv4/IPv6 本地 hosts 解析回归测试。

## 2026-10-27 · WebUI 配置写盘事务与失败恢复
- 修复设置写入流程的重大风险：原流程在正式替换 `settings.conf` 后才检查字节数，尾部校验失败时旧配置已经丢失。
- 现在先写入临时文件并验证期望字节数；有旧配置时先复制、逐字节比对并保留备份，再写事务标记后原子替换；提交后再次验证大小与权限。
- 提交后验证失败时使用已验证的备份回滚；写盘进程中断时，下次配置写入先依据事务标记恢复旧状态。若恢复条件不满足，保留恢复标记/备份供后续诊断，不把未经验证的文件当作成功结果。
- 新增 `scripts/tests/v1.0.0-ui-config-write-transaction-regression.sh`，覆盖临时文件先验证、备份先于提交、提交后校验及失败回滚的执行顺序。另增加 `scripts/tests/v1.0.0-ui-config-write-transaction-runtime-regression.sh`，实际模拟成功写入、提交前失败、重命名后失败回滚和中断后恢复。
- 验证边界：命令顺序与主机侧模拟回归，不替代 Android 真机掉电/存储故障测试。

### 2026-10-27 · 中断续作最终回归摘要（FX 1.0.0）
- FX 规则源：随包 148 条（5 条域名、142 条 IPv4 /32、1 条国家反诈中心 App 包名）；FX 总开关仍默认关闭。没有将广告/水印、通用安装器/OEM 安全组件或后续国家平台/备案 IP 段混入 FX 专用源。
- 规则动作归一覆盖内置文件、`fxfile://` 本地副本、远程文本源与 hosts 行：动作缺失的黑名单条目默认 REJECT；DIRECT/PASS 等显式放行不被 hosts/IP 防火墙误判成拦截；`no-resolve` 等修饰符不再被误读成动作。
- UI 配置写入事务现在在提交前校验临时文件、保留经过比对的旧配置备份并写事务标记，提交后再校验字节大小/权限，失败回滚；中断后的下一次写入会先按标记恢复。
- 最终主机侧回归：`v1.0.0-*` 181/181 通过；Shell 文件语法 228/228 通过；WebUI 内嵌 JavaScript 31/31 通过；MITM `go test ./...`、`go vet ./...`、`go test -race ./...` 通过。
- 验证边界：未在 OnePlus 12 真机安装/测流。源仓库没有独立的 96110 蜂窝电话规则；规则列出的 IP 归属未逐条实时核验。独立 AdGuard Home DNS 服务与完整第三方脚本 API 兼容仍是未完成项，不应将其宣称为已实现。


## 2026-10-27 · 回归收口与恢复路径补强

- 全量回归暴露 `scripts/util.sh` 的 FX 规则归一化重构曾漏带 `pg_restore_system_hosts_base_from_backup()`。现已恢复原子恢复 OEM hosts 基线功能，拒绝把 FX 生成文件递归当作 OEM 基线，并补跑相关回归。
- 修正 WebUI 配置事务恢复命令的内嵌 JavaScript 字符串语法，更新事务测试以验证真实保障：临时文件清理与旧备份/事务标记保留策略。
- 当前工作树回归：176/176 个 `v1.0.0` 测试、15/15 个历史宿主兼容测试、227 个 Shell 语法检查、31 个内嵌 JavaScript 语法检查，以及 MITM Go `test`/`vet`/`race` 检查均通过。
- 全部为主机侧与模拟测试；本次未完成 OnePlus 12 真机网络、DNS、VPN、MITM/APEX 信任与 UI 交互验收。


## 2026-10-27 · MITM 监听器就绪与第三方 VPN 安全回退

- 发现重大风险：旧启动检查只验证 MITM 进程 PID/argv，进程仍在但 `127.0.0.1:18443` 没有 TCP LISTEN 时，可能仍安装 TCP/443 重定向。现在要求内核 `/proc/net/tcp` 精确出现 `0100007F:4813` 且状态为 `0A`，启动最多等待 6 秒；启动失败时不会安装重定向，已有进程端口不健康时拒绝继续。
- `mitm-engine.sh status` 与 `mitm-redirect.sh status` 现在区分 `running` 和 `unhealthy`，不再把仅存活的 PID 当作监听正常。
- 独立 MITM 启用入口现在检查常见外部 VPN 隧道；无法检查接口或检测到 tun/wg/ppp/ipsec/tap/utun/tailscale/zt 隧道时拒绝启用。启用后启动轻量看护进程；发现外部隧道或引擎监听退化时，仅尝试清理 FX 自有 `PGMITM27` 链并停止引擎，不修改第三方规则。
- 在安装重定向前重新同步 MITM 主机白名单；同步失败或白名单为空时拒绝把所有公网 TCP/443 绕进空白 MITM 引擎。
- `scripts/mitm-audit.sh` 改为报告实际状态，不再把“显式启用入口存在但默认关闭”错误标记为“未实现”。
- 新增监听器 readiness 回归，覆盖 loopback 精确地址/端口/LISTEN 状态、错误地址/端口/连接状态、外部 VPN 检测失败安全拒绝、空白名单拒绝。当前本轮 31 个聚焦回归、Shell 语法检查、JavaScript 语法检查、MITM Go test/vet 均通过。
- 验证边界：以上是主机侧/模拟测试；没有在 OnePlus 12 上验证真实 `/proc/net/tcp` 权限、iptables 命令兼容性、VPN 启停时序或 HTTPS 端到端效果。AdGuard Home Android 目标构建工作流已提交，但本轮未确认 CI 产物；当前安装包仍未接入独立 AdGuard Home DNS 引擎。

## 2026-10-27 · 代理模块 URL 正则与 Android DNS 引擎构建
- 修复常见 `https?:\\/\\/host\\/path` 脚本触发正则：Go regexp 不把 `/` 当作分隔符，因此 `\/` 会导致编译失败并让已导入脚本在运行期被跳过；现在按常见原始/双重转义模块元数据规范化，并增加 Bilibili feed 与 Aloha profile 匹配测试。
- GitHub Actions `40465966583` 成功产出 AdGuard Home v0.107.79 Android ARM64 二进制；确认 ELF64/AArch64、Android API 24、`/system/bin/linker64` 与依赖 `liblog.so`/`libdl.so`/`libc.so`。二进制 SHA-256：`e122e73b2baed66fefa2d8337f1a8b2ed6067102c939043d73e6f7c3da11ef39`。
- 该二进制作为未启用的引擎文件随包提供；尚未配置启动/停止、DNS 健康检查和防火墙事务，因此不会自动接管 DNS。必须完成 OnePlus 12 上真实 DNS/SELinux/第三方 VPN/失败回退测试后，才可连接到流量链路。
- 验证范围：主机 Go 单元测试、vet、Shell/JS 静态检查与模拟回归；未在 OnePlus 12 真机启动此二进制，也未宣称 AdGuard Home DNS 已生效。

## 2026-10-27 · UI 窄屏与 VPN 控件修复
- 将 VPN「应用当前模式」按钮移动到代理模式选择控件下方，避免与主开关、核心启停按钮挤在状态卡标题行。
- 小屏将 VPN 控制按钮切换为网格布局，四项状态摘要收敛为两栏；外部 VPN 诊断区改为响应式布局并明确说明实验叠加必须通过真实出口验证。
- 修复底部导航安全区重复计入 padding 与 margin 的问题，减少部分 Android WebView 上导航栏底部留白过大。
- 新增 `scripts/tests/v1.0.0-ui-vpn-responsive-controls-regression.sh`；该测试验证 DOM 控件位置、窄屏布局规则以及内联脚本语法，不替代真机视觉/触控测试。

## 2026-10-27 · 安装包权限与 VPN 核心完整性修复

- 修复 UI ZIP 重新打包丢失 UNIX 可执行权限的问题，并新增安装树入口权限回归，覆盖 `service.sh`、`customize.sh`、`apply.sh`、QuickJS、sing-box、MITM 与脚本桥接入口。
- 修复内置 sing-box 释放逻辑只比较文件长度的缺陷：同长度损坏或旧文件现在会按 SHA-256 与包内二进制核对后原子替换；包内源摘要不匹配时拒绝执行/覆盖。
- 为 ARM/ARM64 内置 sing-box 增加 SHA-256 sidecar。
- 新包解包后回归 182/182 通过；Shell 语法、UI 内嵌 JS、MITM Go 测试通过。设备端流量与 OnePlus 12 真机测试仍未完成。

### 2026-10-27 重大修复：VPN 订阅自动更新失败后的重试
- 发现 `service.sh` 在调用 `apply.sh vpn-sub` 之前就写入 `vpn-sub-last`；开机时网络尚未就绪或订阅/核心重载失败时，会错误推进成功时间戳，默认情况下可能拖延后续重试 24 小时。
- 提取为 `scripts/vpn-auto-update.sh`，仅在订阅事务和运行态协调均返回成功后，以临时文件 + 原子 `mv` 提交成功时间戳；失败保留上一次成功时间戳，下次服务执行可重试。
- 对 `auto_update_h` 的前导零、超大数值和异常时间戳做范围处理，避免 Android shell 算术异常。
- 新增 `scripts/tests/v1.0.0-vpn-auto-update-success-stamp-regression.sh`，涵盖失败不推进、即时重试、成功后间隔跳过、再失败仍保留旧戳、下一次再重试。

## 2026-10-27 · Audit153：第三方 VPN 安全边界与 DNS 上游修复

- **接口探测 fail-safe**：`ip` 缺失、执行失败、接口列表为空都按状态未知处理，不再把未知误判为“没有第三方 VPN”。未知时跳过 FX DNS/NAT/代理接管；通用 OUTPUT 过滤挂钩也会被抑制，优先避免把设备断网。
- **外层 VPN 保护**：检测到第三方 VPN 且能解析其 VPNService UID 时，在通用 `PGUARD` 过滤链前置 UID RETURN。UID 无法解析或双栈豁免安装失败时不挂接通用过滤链；VPN 的 QUIC/STUN/DoT/节点连接不会再被模块自己的通用规则先行误拦。
- **AdGuard Home DoT**：上游从 `tls://1.1.1.1` 等 IP 字面量改为 `tls://one.one.one.one` 与 `tls://dns.alidns.com`，并配置 `1.1.1.1`/`223.5.5.5` bootstrap。root-owned 引擎 bootstrap DNS 在 IPv4/IPv6 DNAT 与 DNS 锁定路径中前置豁免，避免 DNS 引擎查询自己的上游地址时被送回自己；无法安装必要豁免时拒绝接管。
- **QuickJS 安全边界**：更新 ARM64 QuickJS-NG 构建，阻止 `qjs:std/os/bjson`、裸 `std/os/bjson` 与原生 `.so` 导入，并加严拒绝原因回归。最新工作流构建成功。
- **验证**：203/203 个 Shell 回归、242/242 个 Shell 语法、31/31 个内嵌 JS、MITM Go test/vet/race 均通过；官方 AdGuard Home v0.107.79 配置 CI run `40480135241` 通过。QuickJS、sing-box、AdGuard Home SHA-256 和关键入口执行权限均已核对。
- **边界**：这些结果来自主机侧及官方配置校验，不是 OnePlus 12 真机验证。真实 DoT 握手、Android IPv6 DNAT/SELinux、第三方 VPN 共存、MITM/APEX 证书信任与完整第三方脚本生态仍需实机验收，不将其宣称为已验证。


### Audit154：本地递归 DNS（2026-10-27）

- 新增 Android ARM64 Unbound 1.26.2 递归 DNS 引擎，静态链接 OpenSSL/Expat；配套 `fx-dns-probe` 对随机未缓存域名执行真实 DNS 查询，避免只检查监听端口造成假健康。
- AdGuard Home 仅连接本机 `127.0.0.1:5353`；缓存未命中由 Unbound 直接查询根、TLD 与权威服务器，不再固定转发到腾讯/阿里/Cloudflare。双层本地缓存、DNSSEC 根信任锚、QNAME minimisation、Aggressive NSEC、prefetch 与过期缓存应答已纳入配置。
- 所有引擎二进制和 root hints/信任锚种子通过 SHA-256 清单校验；安装脚本明确恢复执行权限。Unbound 启动/配置/未缓存查询检查任一失败时，AdGuard Home 不接管，沿用原 DNS 或 fail-open。
- 编译和配置检查已通过；仍需 OnePlus 12 真机验证移动网络是否允许直接访问权威 DNS/53、实时 DNSSEC 和网络中断回退。

## 2026-10-27 · Audit155 本地 DNS 生命周期重大修复
- Watchdog 不再只检查 Unbound；现改为检查完整 `AdGuard Home → Unbound` 链，避免过滤前端死亡但递归后端仍正常时漏报。
- Watchdog 启动需验证子进程身份和存活；若无法确认，apply 主动撤销自有 IPv4/IPv6 OUTPUT 挂钩、清理 PGNAT、停止本地 DNS 服务。
- 卸载时在任何防火墙清理之前停止 watchdog，避免卸载过程并发 `apply fast` 重新安装 DNS/代理挂钩。
- root 递归查询的防自循环豁免从全 UID 0 放行收窄到 UID 0 的 UDP/TCP 目标端口 53；其他 root-owned 网络端口继续经过 FX 规则。
- 规范化 Unbound 二进制与根数据的 SHA-256 sidecar 路径，使其在模块根目录提取后直接 `sha256sum -c` 可用。
- 207/207 Shell 回归、248/248 Shell 语法、31/31 UI JS，以及 MITM Go test/vet/race 全通过；真实 OnePlus 12 网络验收仍待执行。


## 2026-10-27 · Audit155 续接：收窄 DNS 豁免并修复卸载漏停递归解析器

- 将 `PGNAT`/`PGUARD` 中本地递归 DNS 需要的 root 豁免限定为目标端口 53 的 UDP/TCP；不再对所有 UID 0 流量执行 `RETURN`。
- 卸载停止 AdGuard Home 失败时，仍独立尝试停止 Unbound；任一引擎无法确认停止都保留状态文件并告警。
- 验证 208 个 Shell 回归至少各通过一次、249 个 Shell 语法、31 个内嵌 JavaScript、4 个 sing-box JavaScript 与 MITM Go test/vet/race。watchdog 回归曾有一次批次瞬时失败，随后单独 12 次连续通过。
- Android 递归 DNS 构建与主机测试通过不代表 OnePlus 12 实机验收；本地递归网络可达性、DNSSEC、IPv6/SELinux、Private DNS/DoH 和第三方 VPN 行为仍待实机测试。

- Audit155 验证时修正 `localdns-watchdog-regression.sh` 自身的 disabled-start 竞态：改用已启用/双引擎 PID 已就绪的夹具验证生命周期，关闭开关作为独立静态门控校验；重跑 12/12 通过。


## 2026-10-28 Ad 页面逐条开关与自动应用

- 删除 Ad 页的分类总控（`ad_filter_master`、`dns_block`、`hosts_block`、`ip_block`、`mitm_block`、`waf_block`），条目启停由每一行规则自己的开关决定。
- 增加/编辑/删除/导入与单条开关共用自动应用队列；连续操作会合并，若已有 apply 运行，排队变更会在其结束后补应用。
- 移除 Ad 页“模块状态 / 应用 / 重载”卡片和按钮；日志与崩溃报告入口保留在“设置 → 诊断工具”。初始化失败时独立的“重新检测”提示仍保留。
- 本地递归 DNS 引擎和 Hook UID 阻断仍保留各自明确的可选开关；它们不是分类总控。规则覆盖概览继续位于规则页顶部。
- 250/250 Shell 回归、296 Shell + 7 独立 JS + 32 内联 JS 语法检查、MITM Go test/vet/race 全部通过；真机验收仍待执行。

## 2026-10-28 · 本地 DNS 看门狗停用路径修复

- 修复 `apply.sh` 的本地 DNS 资格判断分支：DNS 接管关闭、FX 非直连模式、第三方 VPN 接管或 VPN 状态不确定时，先停止旧的 `localdns-watchdog.sh`，再停止 AdGuard Home，避免看门狗把“按策略停用”误判为崩溃并无限调用 `apply.sh fast`。
- 修复 IPv6 loopback NAT 不可用时的回退路径：在停止本地 DNS 引擎、恢复已配置 DNS/fail-open 路径前，先停止对应看门狗；下次满足条件的 apply 仍会重新启动监视器。
- 将“显式停用”与“引擎启动失败”分开处理：前者停止看门狗，后者保留恢复重试机会；不让 watchdog 自行改防火墙。
- 扩展 `v1.0.0-localdns-watchdog-chain-health-regression.sh`，检查两条停用路径均先停看门狗再停引擎，并检查停用失败告警。
- 参考 bindhosts 的管理器/挂载模式边界、AdBlock-Pro-next 的 DNS 接管开关与失败回退语义、MagicNet 的状态可观测和事务边界；只移植适用于 FX 当前架构的原则，不引入第二套 DNS 核心。
- 主机侧定向回归通过；未进行 OnePlus 12 真机 DNS/VPN 测试，不能将其视为真机已验证。

### 2026-10-28 网络请求兼容性修复
- 修复 MITM 请求脚本对无正文 GET/HEAD 请求无条件添加 `Content-Length: 0` 的问题。
- 仅在原请求存在正文或脚本明确改写正文时重新设置 HTTP framing；新增 Go 回归测试。
- 重新构建 Android arm64 MITM 引擎并刷新校验和。
- 修正 URL Rewrite 集成回归测试的临时目录相互覆盖问题，避免测试转换器清理临时文件时删除测试夹具。

### 2026-10-28 续接审计：MITM 响应脚本状态码与无正文 framing
- 修复响应脚本将状态码改为 `204 No Content` / `304 Not Modified` 后，内部仍保留上游实体字节及可能不再适用的 `Content-Length` 元数据的问题；现在最终响应正文为空，并清除长度/传输编码字段。
- 响应脚本不再能将最终响应状态改为 1xx/101；这些状态涉及信息响应/协议切换，不适合作为普通响应 Hook 的状态码补丁。
- 新增 304 无正文 framing 与 101 状态拒绝回归测试，并更新 Android ARM64 `bin/arm64/pg-mitm`、SHA-256 与构建信息。
- 验证：MITM Go 单元测试、`-race`、`go vet`、Android ARM64 交叉编译及 7 个定向 Shell 回归通过；311 个 Shell 文件语法检查通过。
- **设备边界：**未在 OnePlus 12 真机执行 HTTP 线上回归；本轮结果仅证明主机测试和 ARM64 交叉编译通过。

### 2026-10-28 续接审计：MITM 脚本不能伪造 HTTP 消息 framing
- 发现请求/响应脚本可通过 `headers` 补丁写入不匹配的 `Content-Length`、`Transfer-Encoding` 或 `Trailer`，即使正文未改变也可能导致上下游对消息边界的理解不一致。
- 请求侧：原本无正文且脚本未改正文时，恢复原始 framing 头；原请求有正文或正文被脚本修改时，以实际缓存正文长度重建 framing，并移除 Transfer-Encoding/Trailer。
- 响应侧：正文未被脚本修改时，恢复传输层原始 framing；正文被修改时按新正文长度重建；HEAD 和禁止正文的状态仍走专门处理。
- 新增两项 Go 回归测试，分别模拟请求脚本向无正文 GET 注入伪造 framing、响应脚本在正文不变时伪造 framing，以及正文重写时清除结构化 TransferEncoding/Trailer 字段。
- 验证：Go 单元测试、race 检测、vet、Android ARM64 交叉编译通过；真机未测。

### HTTP framing regression follow-up (2026-10-28)
- Fixed response normalization order when a response script changes a `HEAD` response to a no-content status (`204`, `205`, or `304`): status-specific framing cleanup now runs before the general HEAD handling, preventing forbidden framing fields from surviving a script-selected `204`.
- Added a regression test that verifies body, `Content-Length`, `Transfer-Encoding`, `Trailer`, and their structured `http.Response` fields are cleared in the HEAD + 204 case.
- Validation: Go unit tests and `go vet` passed; Android ARM64 cross-build completed. The full race-enabled suite exceeded the execution time limit, so it is not reported as passed. Device testing remains outstanding.

### 2026-10-29 续接审计：脚本 Hook 阶段总时限
- 发现每个匹配脚本单独允许运行 12 秒，但多个脚本按顺序执行时，单个 HTTP 请求的最坏延迟可能随着匹配脚本数量累加。
- 新增每个请求 Hook 阶段、响应 Hook 阶段各 30 秒的共享 deadline；每个脚本仍有 12 秒单次上限。阶段 deadline 到期后跳过剩余 Hook，并通过进程组终止超时脚本及其子进程。
- 新增 `TestExecuteScriptHonorsSharedStageDeadline`，验证父阶段 deadline 能中止长时间运行的脚本。
- 验证：`go test -count=1 ./...`、`go test -race -count=1 ./...`、`go vet ./...` 均通过；Android ARM64 MITM 二进制交叉编译成功。未在 OnePlus 12 真机验证。

### 2026-10-29：VPN 订阅事务并发互斥

- 为 `vpn_update_subs` 增加进程间目录锁，覆盖下载、节点解析、`settings.conf` 候选生成与提交、默认节点选择和回滚的完整事务。
- 修复并发手动刷新、开机更新器或监控路径可能同时使用固定缓存文件及 `settings.conf.new`，造成候选文件互相覆盖、旧事务回滚覆盖新提交的竞态风险。
- 锁包含 PID 所有者记录、短暂等待 PID 发布、失效所有者回收、等待上限和退出清理；内层事务返回码原样传递。
- 新增 `v1.0.0-vpn-subscription-concurrency-lock-regression.sh`，覆盖两个并发事务不重叠、锁释放和失败返回码传递。

### 续审修复（2026-10-29）

- 修复 `vpn_repair_conf()` 自定义配置段恢复逻辑，避免默认配置段重复追加，并恢复默认骨架缺失时的用户自定义段。
- VPN 订阅锁遇到无有效 PID 的不确定状态时改为 fail-closed，不再按等待时间自动抢占可能仍在初始化的活动锁。
- 新增配置修复与订阅锁未知所有者状态回归测试。

### 2026-10-29 续审：失效锁回收竞态

- 订阅更新回收死锁前增加独立 sibling 回收声明与 PID 二次核对，避免延迟等待者误移动另一个新事务的锁。
- 并发锁回归覆盖失效数字 PID 锁恢复，并检查回收路径的串行化保护。


## 2026-10-29 — pg_set 原子提交失败传播修复

- 修复 `scripts/util.sh` 中 `pg_set()` 无论 `awk`/`mv` 是否成功都返回 0 的严重错误。现在使用同目录唯一临时文件，验证候选非空、限制键和值的换行注入、收紧文件权限，并且只有原子替换成功才返回 0。
- 新增 `scripts/tests/v1.0.0-pg-set-atomic-failure-regression.sh`，覆盖更新既有键、插入新键、临时路径/替换失败时保留原文件，以及非法键拒绝。
- 影响范围：任何依赖 `pg_set` 返回值判断配置是否持久化的调用方；此修复使失败能够正确触发现有回滚分支。主机回归不替代 Android 真机验证。


### 2026-10-29 — VPN 订阅事务崩溃恢复

- 为订阅配置提交增加原子恢复日志。进程在替换 `settings.conf` 后意外终止时，下一次订阅更新会先从本事务备份恢复整份配置，避免节点列表与 `vpn_node` 选择值跨事务混用。
- 恢复日志路径及备份文件均经过范围校验；恢复失败时保留日志并停止更新。
- 新增 `v1.0.0-vpn-subscription-crash-recovery-regression.sh`。主机侧回归通过；未进行 OnePlus 12 真机验证。

### 2026-10-29 续审补充：恢复日志路径穿越校验

- 发现恢复日志原先仅使用 `PG/backup/settings.conf.*` 通配前缀判断备份路径；Shell 通配符 `*` 可匹配路径分隔符，无法单独证明目标是备份目录的直接子文件。
- 现改为同时验证完整路径必须等于 `PG/backup/` + basename、basename 必须以 `settings.conf.` 开头，并拒绝多行日志；异常状态保留日志并 fail-closed。
- 扩展 `v1.0.0-vpn-subscription-crash-recovery-regression.sh`，增加 `../` 路径穿越形态及追加第二行的故障用例。相关回归及全量 Shell 语法检查通过。
- `.reaper` 声明若被强制终止后遗留，当前策略仍为 fail-closed；本轮没有实现自动回收，以免用时间阈值重新引入并发双持锁。


### 2026-10-30 Hook 配置链路补齐

- 将现有 `hide_notif_perm` 总开关接入 API-101 Remote Files 的 `notification_permission_hide_enabled`。
- FXHook 应用目标编辑器增加独立的“通知权限状态查询屏蔽”选项，按应用写入 `notification_permission_hide_block`，由发布器转换为 `notification_permission_hide`。
- `apply.sh` 在该总开关单独启用时也会触发 Remote Files 发布，避免功能只保存配置却不发布。
- `status.sh` JSON 与 UI 状态显示增加该功能的总开关和目标数量。
- 此功能只改变目标应用查询通知访问授权状态时的可见返回值，不授予/撤销通知权限，不改变系统授权状态。
- 回归：Remote Files 发布集成、通知隐私迁移、状态 JSON、Wi-Fi 扫描迁移、75 项迁移基线、KernelSU 包完整性均通过；33 个内嵌 JS 代码块语法检查通过。
- 仅完成主机侧验证，未在 OnePlus 12 真机/LSPosed 环境验证。

- 修正 Hook 剪贴板隔离设置文案：明确为进程级影子隔离，不再宣称不同 APP 的剪贴板在系统层面互不可见；共享进程仍按设计失败放行。

### Hook 迁移：AudioRecord 麦克风静音（2026-10-30）
- 新增按目标 APP 启用的 AudioRecord 读取缓冲区静音，受 Hook 隐私总开关控制。
- 仅覆盖已 Hook 的 AudioRecord 缓冲区重载；共享进程 fail-open，不等同于系统麦克风权限关闭。
- 不迁移合成噪声、音频指纹扰动及麦克风硬件隐藏。
- 当前已完成源码与 host smoke 检查；Android CI 和真机验证状态另行记录。
