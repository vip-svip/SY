# FX 1.0.0 原始 APK 组件与迁移缺口审计

审计日期：2026-11-04  
仓库分支：`fx-v1.0.0-unified-hook-integration`  
审计时基线 HEAD：`130fa891ef18e4e1b08229e8fe2f6235122347e8`  
原始资料：GitHub Actions artifact `fx-apk-source-intake`，SHA-256 `5e8328d9c940d961fb49073ac9be8b2d2aac793148bafff700eed80a97851a3a`

> 本文是静态 Manifest / Smali / 资源清点，不代表功能已迁移或运行验证。AndroidX、WorkManager、Room、Sentry 等库自动组件不应为了凑数量而原样复制；每个组件都要按其业务职责映射、重构或明确弃用原因。

## 1. 组件数量对照

| 原应用 | 原始 Activity | Service | Receiver | Provider | 当前 FX Manifest 中的直接迁移组件 |
|---|---:|---:|---:|---:|---|
| Dia 23.11 | 57 + 1 alias | 4 | 5 | 3 | 10 个 Dia Activity、1 个 Wi-Fi 代理 Tile Service；未声明 Dia 专属 Receiver / Provider |
| 游龙广告 7.0.1 | 1 | 6 | 8 | 5 | 7 个 Ad Activity、1 个 Ad Tile Service、1 个 Tasker Receiver、1 个 Widget Provider |
| 游龙安全护盾 9.9.60 | 14 | 11 | 16 | 3 | 12 个 Shield Activity + 1 个 Stellar 管理 Activity、3 个 Shield Service、3 个 Shield Receiver；未声明 Provider |

直接组件数量不能代替页面与业务完成度。部分原 Activity 已改为 FX 内部四级页面或路由；必须逐项确认页面、数据和行为是否真实对应。

## 2. Dia 23.11

原始 Manifest 的关键业务组件包括：

- 页面：`MainActivity2`、`MainActivity`、`GPSActivity`、`MethodActivity`、`JSActivity`、`SelectAppActivity`、`FridaActivity`、`DexInjectActivity`、`SqlActivity`、`MonitorShellActivity`、`MonitorIntentActivity`、`MonitorJSONActivity`、`MonitorSocketActivity`、`MethodStackActivity`、`CodeEditorActivity`、`RuleGroupListActivity`、`RuleListActivity`、`RuleActivity`、`HttpActivity` 等。
- 后台 / 交互：`QuickStartService`、`RPCService`、`FloatyService`、`ShellMonitorReceiver`、`AlgorithmMonitorReceiver`、`SqlMonitorReceiver`。
- Provider：`LScopeProvider`、FileProvider、AndroidX 初始化 Provider。

当前 FX 中已有的 Dia 原生入口：Frida、备份、DEX 浏览、GPS 选择、Wi-Fi 代理、签名、Activity 浏览、Inspector、JSON、文件等 Activity。主路由还把若干原始功能映射到 FX Hook 或原生隐私设置页。

**明确缺口 / 需继续核对：**

1. 原始 57 个 Activity 不等于当前 10 个 Dia Activity 已完整覆盖。方法搜索、类/字段操作、代码编辑器、规则组/规则列表、HTTP/Socket/Intent/Shell/SQL/算法监控等必须逐项核实是否有真实运行逻辑，不能仅凭路由名称认定完成。
2. 原始 `RPCService`、`LScopeProvider`、悬浮服务及三个监控 Receiver 当前没有同名组件。若改为 FX 内部接口或统一服务，需补齐权限边界、调用方和行为测试；不能直接复制原有无权限导出的 RPC 入口。
3. 原始 `DexInjectActivity` 的 Smali 本身只有标题、布局加载和 `packageName` 读取；布局主要是 DEX 路径输入与说明图。真正注入行为尚需追踪其资源 / 主 JAR / 其他调用链，不能把一个输入框视为 DEX 注入功能已迁移。
4. 原始 FridaActivity 具有 Frida 版本配置、二进制下载 / 校验 / 部署、目标进程选择、脚本库、历史、日志、Gadget 配置等行为。FX 的 `FxDiaFridaActivity` 已有原生实现，但仍需按原始 Smali 方法逐项比对并做 Root/进程注入测试。

## 3. 游龙广告插件 7.0.1

原始关键服务：

- `AdBlockVpnService`：包含 `VpnConnectionSupervisor`、`VpnEngineCoordinator`、`GoTunnelAdapter`、`VpnTunnelBuilder`、`FirewallManager`、`FilterListRepository`、DNS 日志 DAO、重连 / 撤销处理、通知与状态管理。
- `RootProxyService`：包含 FirewallManager、GoTunnelAdapter、重试管理、watchdog、DNS 日志、UID 白名单、通知更新、暂停 / 重启 / 停止生命周期。
- `AdBlockTileService`：控制 VPN / Root 模式，并处理 VPN 冲突提示。
- 另有 BootReceiver、Widget / WidgetToggleReceiver、TaskerReceiver，以及 WorkManager / Room / Sentry 自动组件。

FX 当前刻意不声明原始 `AdBlockVpnService`，这是正确的 VPN 槽位设计：Android 同一用户 / Profile 不能让 FX 与原服务争抢两个活动 VpnService。**但不启动原服务不等于其功能已迁移。**

**明确缺口 / 需继续核对：**

1. 原服务中的连接监督、引擎协调、Go 隧道适配、DNS 查询日志、UID 白名单、watchdog、自动重连、暂停 / 恢复、通知状态，必须映射到 FX 共享 TUN 和 Root fallback 两条实际路径。
2. FX 有 Root / 应用防火墙脚本和原生 Ad 页面，但要证明它们覆盖 RootProxy 的生命周期与过滤语义；不能把 iptables 规则存在当成完整 Root Proxy。
3. 原始 Trie / Bloom 过滤规则的解析与匹配运行时仍需与 FX 当前规则引擎对照；列表 UI 和订阅更新不能代替匹配引擎。
4. Widget、Tasker、Boot、Quick Settings 的启停动作必须共用同一主开关和状态源，验证不会误启动第二个 VPN。
5. 原 AndroidX / Room / WorkManager / Sentry 组件若不再使用，应记录替代实现；不要无条件复制原 Provider / Service。

## 4. 游龙安全护盾 9.9.60 / Stellar

原始 Shield 业务页面包括安全首页、警告、黑白名单、白名单选择、批量清理、屏幕滤镜等；Stellar 自身另含 MainActivity、ManagerActivity、CommandShortcut、OpenSourceLicenses、RequestPermission、CommandWhitelist、CommandGuard。

原始关键后台组件包括 ForegroundService、ScreenFilterService、AdSkipService（Accessibility）、ProtectService、RescueWindowService、Stellar AdbPairingService、SelfStarterService、Boot / KeepAlive / NotifyUninstall / VirusInstall / StellarReceiver 等。

原始 `StellarManagerProvider` 是导出的跨用户 Provider，提供 packagesJson、daemonEnabled、accessibilityAutoStart、configJson、shizukuCompat、日志读写、配置保存 / 加载等调用。该 Provider 在当前 FX Manifest 中没有直接对应项。

**明确缺口 / 需继续核对：**

1. 当前 FX 有 Shield 页面、扫描、名单、救援、屏幕滤镜、完整性和一个 Stellar 管理 Activity；但原 Stellar Provider / ADB pairing / daemon / self-starter / Receiver 的职责是否已被安全重构并未得到证明。
2. Stellar 的应用授权、能力作用域、始终允许命令、配置持久化和日志需要一个统一、可审计的内部数据层；不能只迁移 Manager UI。
3. 原 `AdSkipService` 已按 Smali 核实：它只转发 `TYPE_WINDOW_STATE_CHANGED` 前台包名和音量键方向事件，不读取 Accessibility 节点树，也不执行点击。FX `FxAccessibilityService` 已实现对应的前台包名与音量键行为，音量事件返回 `false` 保留系统默认音量控制，并设置 `canRetrieveWindowContent=false` / `canPerformGestures=false`。这是符合最小权限的功能迁移，不是缺失的屏幕读取功能；除非发现另一个原始功能确实依赖节点树或手势，否则不要扩大无障碍权限。
4. NotifyUninstall、VirusInstall、StellarReceiver 和启动恢复事件需要逐项核对；当前仅有 KeepAlive、Boot、InstallScan 等部分 Receiver。
5. 批量清理必须验证队列持久化、卸载结果回读、失败重试、Activity 重建恢复和误删保护。

## 5. Manifest / 权限审计结论

当前 FX Manifest 的显式权限仅包括 QUERY_ALL_PACKAGES、INTERNET、POST_NOTIFICATIONS、SYSTEM_ALERT_WINDOW、PACKAGE_USAGE_STATS、FOREGROUND_SERVICE、FOREGROUND_SERVICE_SPECIAL_USE、RECEIVE_BOOT_COMPLETED。原三套 APK 声明权限更多，但不能机械复制。

下一步按功能建立权限矩阵：

- 每个原始功能需要的权限 / 特权；
- FX 当前声明与运行时检查；
- 用户授权入口和撤销处理；
- Android 12–16 限制及前台服务类型；
- 未授权时的真实降级行为；
- 明确不迁移的高危 / 系统签名权限及原因。

当前 Shield 三个 specialUse 前台服务已在 Manifest 声明对应 subtype property；继续验证 Android 14+ 实际启动限制和通知权限状态。

## 6. 本次审计后执行顺序

1. 先完成游龙广告共享 VPN / RootProxy / Trie-Bloom 业务映射与可执行测试。
2. 补齐 Stellar Provider 等价的内部数据服务及 ADB pairing / daemon / Receiver 行为审计。
3. 以原始 Dia Activity、菜单、布局、资源和 Smali 调用链逐项建立“原页面 → FX 页面 → 真实业务实现 → 测试”矩阵。
4. 按功能审计 Manifest 权限和后台组件，不复制无用的库自动组件，也不静默丢弃业务组件。
5. 所有缺口均通过源代码、自动化测试和设备验证后才能标记完成。

**本审计不触发最终 APK / KernelSU ZIP 构建。**


## 2026-11-04 follow-up verification — Dia Frida and Shield Accessibility

At branch checkpoint `ef1dcad78d6be573beb2e7cdc590ec53dd00c970`, the earlier gap statements above are narrowed by direct source comparison:

- **Dia Frida target loading is present in FX source.** `DiaFridaTargetHook` installs before `Application.attach(Context)`, requires an exact package/process match and a debuggable non-system user app, rejects symlinked native-library path components, verifies the FX marker and both SHA-256 digests, validates `127.0.0.1` Listen config, then calls `System.load()`. `FxDiaGadgetDeployment` provides the matching Root deployment/removal transaction. Regression: `scripts/tests/fx-dia-frida-gadget-deploy-regression.sh`. This is source-level integration only; Android LSPosed/Gadget execution remains unverified on OnePlus 12.
- The original Frida `code_inject` and `frida_listen` preferences default off. FX's explicit deployment marker is the per-app/per-process opt-in replacement; it is deliberately narrower than the original global preference path. The unified APK keeps this loader in the legacy Xposed entrypoint through the merge script, not in a second APK.
- **Shield Accessibility scope is verified.** Original `AdSkipService` only forwards foreground package changes and volume-key events; it does not read window node trees or automate clicks. FX's `FxAccessibilityService` mirrors those needed events and keeps window-content retrieval and gestures disabled. Do not increase Accessibility privileges to imitate behavior the original service did not perform.


## Yulong precompiled Trie edge-case finding (2026-11-04)

The original Go API `CheckDomainInTrieFile(filePath, domain)` loads the Trie and calls `ContainsOrParent(domain)` directly. That matcher splits raw dot labels; it does not strip ABP delimiters. Consequently, a terminal such as `adonweb.ru^` in the legacy Yulong precompiled asset cannot match a normal DNS query as a raw trie label. FX now treats a complete host plus a single ABP separator as an explicit migration-recovery case and records the behavior difference; it does not claim byte-identical parity. Prefix-only anchors, URL-start anchors, modifiers, paths, wildcards and IP literals remain outside active DNS/Hosts output.


## 2026-11-04 follow-up — Dia MethodActivity method_empty behavior

The original MethodActivity stores a per-target method_empty set. Module checks its separate method master, observes application ClassLoader attachment, and installs XC_MethodReplacement.DO_NOTHING for selected class/method names. This is an active method-body replacement feature, not merely a method list or metadata observer.

FX now exposes the narrower NO_OP_VOID action through the unified per-app custom Hook editor. It accepts exact Java/JVM executable descriptors and is gated by per-target developer opt-in plus the target app's debuggable flag. The modern runtime resolves the exact method again and rejects constructors, non-void methods, abstract methods and native methods before installing a no-original-body interceptor. This avoids the original UI's ambiguous class.method-only selection and prevents a null no-op result from being applied to primitive/object-returning methods.

This is not full parity with the original global method switch or its dynamic ClassLoader observer for future secondary loaders. It is a deliberately bounded, verifiable subset for developer-owned Debug apps. Release targets remain fail-open. Host/unit/CI verification is required; Android LSPosed runtime is device-pending.
