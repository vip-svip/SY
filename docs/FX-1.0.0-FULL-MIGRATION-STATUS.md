# FX 1.0.0 Full Migration Status

> Baseline audit: 2026-11-03 (Asia/Tokyo)
> Repository: `vip-svip/SY`
> Branch: `fx-v1.0.0-unified-hook-integration`
> Audited HEAD before this document: `637216345d68e60d9a736dce3f51f2097eae46ed`
> Product version remains **FX 1.0.0**.
>
> This is an evidence-based tracking file, not a completion claim. A feature is not complete merely because a page, class name, or toggle exists. Device verification is never inferred from CI.

## Status definitions

| Status | Meaning |
|---|---|
| 未检查 | FX implementation has not yet been compared with the source feature |
| 未迁移 | No corresponding implementation found |
| 部分迁移 | UI, compatibility bridge, policy, or partial backend exists, but the complete behavior is not established |
| 已实现 | UI, persistence, real backend, execution/state, error handling, and cleanup have been inspected |
| 已通过测试 | Relevant automated regression tests pass |
| 已构建验证 | The feature is present in a successful APK/KernelSU build artifact |
| 设备验证通过 | Verified on a real Android device |
| 暂不可迁移 | A concrete technical or licensing blocker is recorded |

## Current repository and CI facts

- Branch exists and is not protected; current HEAD at audit time: `637216345d68e60d9a736dce3f51f2097eae46ed`.
- The latest Hook APK workflow run at that HEAD completed successfully: run `41497624209`, job `125456591654` (`validate-migration`).
- The latest KernelSU workflow run at that HEAD completed successfully: run `41497624085`, job `125457327398` (`package`).
- Earlier failure at commit `ad0b9cf48535c7e1cebed67cbc1a834e52e92386` was a Java compile failure: two references to an out-of-scope `index` in native script-switch rollback. Subsequent commits `c19b358` and `6372163` changed the rollback/rebinding implementation; the later Hook APK workflow passed.
- The required progress file did not exist at audit time; this file establishes the first tracked baseline.
- Successful CI is host/runner evidence only. No real-device test result is established by these runs.
- Existing workflow artifacts are build evidence for their exact commit only; they do not prove every listed source feature is complete.

## FX application and UI baseline

| Area | Current evidence | Status | Remaining work |
|---|---|---|---|
| Six bottom destinations | Native Compose shell exposes VPN, Ad, 隐私, 脚本, Hook, 设置; regression suite checks routing | 已通过测试 | Verify all screen interactions/state restoration on device |
| Native app shell | Compose bottom navigation wraps an AndroidView page body | 部分迁移 | Replace remaining WebView-rendered business pages with native screens; do not count shell-only migration as complete |
| Legacy WebUI Hook entry | Retirement patch exists and is wired into both workflows | 已通过测试 | Verify final APK has no duplicate Hook manager entry |
| VPN controls | Native VPN control/API and transparent switch patchers plus regression tests exist | 部分迁移 | Verify service-derived state, real traffic path, direct/global/rule mode, subscriptions, third-party VPN coexistence and recovery |
| Ad / Hosts | Ad-to-Hosts patch exists; Ad route remains mapped to merged content | 部分迁移 | Verify real Android hosts file editing, paging, external-editor sync, subscription separation, whitelist, safe apply/rollback |
| Privacy page | Native cards exist for advertising ID, clipboard, Wi-Fi scan, location, microphone, camera, sensors, notifications, media/EXIF and read-only diagnostics; advanced privacy categories still use compatibility bridge | 部分迁移 | Audit each policy's actual runtime enforcement, persistence, failure handling, stop and uninstall behavior; migrate remaining page UI |
| Script page | Native list/add/edit/delete/enable and JSON export use the module `settings.conf` `[list:script]` through `native-list.sh`; HTTPS subscriptions stay as URLs, local JS source is stored losslessly as `FXSRC_B64:` and exported as source text (64 KiB per-entry cap) | 部分迁移 | Native CRUD/export is implemented. Local JS source is explicitly labelled stored-but-not-executed; QuickJS execution queue integration, JSON re-import, URL metadata validation, API compatibility, unsupported-syntax diagnostics, and execution/error lifecycle remain incomplete. Regression fixture fixes now include wrapped Base64 handling, lossless payload checks and idempotent WebUI codec patching; CI rerun is in progress at `c304597`. |
| Hook app list | Native installed-app list, search and paged row rendering exist | 部分迁移 | Verify large app lists, app details, per-target config and lifecycle on device |
| Custom Hook rules | Parser accepts package-scoped JVM/Smali-like descriptors; current developer rule seam is bounded and not a general Dia Hook runtime | 部分迁移 | Implement/verify authorized runtime integration, rule CRUD/import/export, grouping, enable state and diagnostics |
| Settings | Global settings/authorization/diagnostics separated from business pages | 部分迁移 | Verify no VPN/Privacy/Script/Hook business controls are misplaced here |
| Certificate manager | Native entry and status dialog exist; MITM patchers exist | 部分迁移 | Verify install/trust/remove/rollback and safe system/APEX behavior on supported rooted devices |
| Logs | Runtime log view and private-log patch exist | 部分迁移 | Verify opt-in, redaction, retention cap, deletion and sensitive-data handling |
| Lifecycle/uninstall | Multiple stop guards and cleanup patchers exist | 部分迁移 | End-to-end verify service crash, reboot recovery, module disable/uninstall and ownership-only cleanup |

## Dia 23.11 migration matrix

Source APK audit identified Java/DEX classes and native/helper assets. Discovery of a class is not proof that its behavior has been ported.

| Dia feature group | FX evidence found | Status | Required verification / gap |
|---|---|---|---|
| App-level Hook manager and target configuration | Native app list and target configuration surfaces | 部分迁移 | Actual injection/Hook runtime, package scoping, persistence and error reporting |
| Method Hook | Descriptor parser and bounded developer rule model | 部分迁移 | General runtime Hook backend and safe method lifecycle not established |
| Class/method/field search | DEX/parser-related source not yet established in FX | 未检查 | Inventory exact Dia UI and backend behavior; implement paged search/tree |
| JVM descriptors and Smali parsing | `DeveloperExecutableDescriptor`, `DeveloperHookRule` | 部分迁移 | Validate full parameter/return/array/object descriptor matrix and runtime use |
| Rule groups, CRUD, import/export, enable/disable | Some target config parser/serializer exists | 部分迁移 | Full group lifecycle and round-trip tests |
| AppEntryHook, ClickBtnHook, FragmentHook, ViewGroupHook | No complete equivalent verified | 未检查 | Per-hook semantics and target SDK compatibility audit |
| IntentHook, RuntimeHook, ThreadHook, StackHook | No complete equivalent verified | 未检查 | Implement only with explicit target scope and observable diagnostics |
| ClassLoader and call relationship analysis | No complete equivalent verified | 未检查 | Analysis backend, large-app performance and export |
| Frida runtime/service/process attach | QuickJS-NG exists, but it is not Frida | 未迁移 | Evaluate genuine compatible Frida runtime and supported Android/ABI/license matrix |
| Frida script load/unload, WAIT/RESUME, multi-process | No equivalent runtime verified | 未迁移 | Requires real Frida backend; do not relabel QuickJS as Frida |
| HTTP request/response and Socket monitoring | MITM/network modules exist for FX filtering; Dia per-process instrumentation not established | 部分迁移 | Distinguish proxy traffic inspection from in-process API/socket instrumentation |
| Network rewrite rules | Existing script/rule infrastructure | 部分迁移 | Verify request/response rewrite semantics, target scope, association and redaction |
| SQLite, SQLCipher, WCDB monitoring | No complete equivalent verified | 未迁移 | Runtime instrumentation, query timing/errors, database-family compatibility |
| DEX class tree/method finder/signature conversion | No complete native analyzer verified | 未迁移 | Parser integration, pagination, large DEX memory limits and export |
| Algorithm tracing | No complete equivalent verified | 未迁移 | Define supported tracing model and real execution backend |
| App signature analysis | No complete equivalent verified | 未检查 | Compare Dia feature and implement/report signatures |
| Anti-tamper diagnostics | Some privacy/diagnostic surfaces exist, not equivalent verified | 未检查 | Authorized diagnostics only; do not expand stealth/evasion |
| JavaScript injection/runtime management | QuickJS script engine exists | 部分迁移 | This is not proof of Dia injection semantics; isolate authorized targets and verify lifecycle |
| Proxy management | FX proxy/VPN infrastructure exists | 部分迁移 | Verify Dia per-app proxy semantics separately |
| Root file service | RootBridge/RootAccess exist | 部分迁移 | Verify permission boundaries, file operations and cleanup |
| LSPosed integration/configuration | LSPosed status and target configuration surfaces exist | 部分迁移 | Verify actual module entrypoint, scope, activation and target runtime behavior |
| ClipboardDisableHook, DevicePropsHook, DexInjectHook, DisableActivityHook, FakeXposedHook, FileHook, FridaInjectHook, HideDexHook, HideOnBackgroundHook, HideXposedHook, LocationHook, MethodHook, NotificationHook, PackageNameHook, ProtectHook, RandomFileHook, SensorDisableHook, SensorHook, SettingsHook, ShakeHook, SoLibraryHook, TimeHook, TimeZoneHook, ToastDisableHook, VPNHook, WebViewHook, WifiHook | FX has several privacy policies and Hook-related controls; no one-to-one semantic audit completed | 未检查 | Audit each hook independently; classify as supported, partial, not applicable, or restricted; never treat UI similarity as parity |

## 游龙广告插件 7.0.1 migration matrix

The original APK was inspected for architecture and feature clues. Its opaque Go native engine and registration material are not to be copied. Reimplement using auditable FX components and compatible licenses.

| Yulong feature group | FX evidence found | Status | Required verification / gap |
|---|---|---|---|
| DNS service/local resolver/upstream providers | AdGuard Home and Unbound are present in the existing FX module baseline | 部分迁移 | Verify start/stop, resolver chain, upstream configuration and health state |
| DNS request/error logs and statistics | DNS services exist; complete user-facing log/statistics contract not verified | 未检查 | Add bounded, privacy-protective logs and query/error statistics |
| DNS cache | Resolver cache likely available at engine layer; FX management/flush behavior not verified | 未检查 | Expose and test cache status/flush |
| Custom DNS rules/providers | FX host/domain rules exist; DNS provider CRUD and full DNS rule semantics not verified | 部分迁移 | Add precedence, import/export, conflict diagnostics and provider management |
| Ad/tracker/malicious-domain filtering | Multiple filter lists and FX domain-rule pipeline exist | 部分迁移 | Verify parser coverage, list updates, offline behavior, conflict resolution and rollback |
| VPN DNS tunnel/service coordination | sing-box/VPN core and DNS components exist | 部分迁移 | Verify actual traffic capture, tunnel DNS path, retry/recovery and app scope |
| VpnEngineCoordinator/VpnRetryManager equivalents | Existing VPN scripts/stop guards exist | 部分迁移 | Verify service coordinator state machine and retry limits |
| Third-party VPN coexistence | Existing UI/patches claim coexistence intent; actual traffic coexistence not proven | 未检查 | Must test traffic path on supported devices/VPN combinations |
| Per-app DNS/UID scope | No complete equivalent verified | 未迁移 | Implement and test per-app resolver/proxy scope |
| Root Proxy and iptables DNS redirect | No complete end-to-end Root Proxy verified | 未迁移 | Implement owned chain lifecycle, boot recovery, rollback and uninstall cleanup |
| HTTPS/MITM and CA management | FX MITM engine, certificate manager and status surfaces exist | 部分迁移 | Validate supported protocol/traffic scope, CA lifecycle, safe passthrough and pinning limitations |
| TLS passthrough and safe downgrade | Some MITM redirect/status guards exist | 部分迁移 | Verify security-critical domain passthrough and fail-safe behavior |
| App network scope/firewall controls | UID network-blocking UI and VPN controls exist | 部分迁移 | Verify actual enforcement and no cross-app collateral effects |
| Auto reconnect/network restoration | VPN retry and stop guards exist | 部分迁移 | Fault-injection and device-level network restoration tests |
| Widgets/status surface | No complete equivalent verified | 未检查 | Assess whether it fits FX architecture; not a blocker before core functions |
| Runtime stats and service health | Some status surfaces exist | 部分迁移 | Bind every displayed status to actual service/query data |

## Module and script-engine baseline

| Component | Current evidence | Status | Remaining work |
|---|---|---|---|
| AdGuard Home | ARM64 runtime/config exists in prior FX package audit | 部分迁移 | Validate current workflow artifact and live DNS query path |
| Unbound | ARM64 runtime/config exists in prior FX package audit | 部分迁移 | Validate recursive resolution, fallback, cache and stop behavior |
| sing-box | ARM64 VPN runtime exists in prior FX package audit | 部分迁移 | Verify modes, subscriptions, app scope and coexistence |
| QuickJS-NG | Workflow builds QuickJS-NG v0.17.0 for ARM64 with import sandbox patch | 已构建验证 | Test APIs, scheduler, resource limits and error propagation on target device |
| Script compatibility APIs | Existing JS runtime scheduler and compatibility code need per-API verification | 部分迁移 | Test `$httpClient`, `$task.fetch`, `$done`, `$prefs` and asynchronous semantics |
| Script formats | Existing parser handles a subset of common rules | 部分迁移 | Build a format-by-format compatibility matrix; unsupported syntax must be surfaced |
| 96110 anti-fraud rules | Separate FX rules/list files exist in prior package audit | 部分迁移 | Verify isolation from ad, watermark and splash-ad rules in generated package |

## Existing patchers and regression tests to reuse

Existing patchers include: `merge_ad_hosts_ui.py`, `merge_hook_single_apk.py`, `patch_hook_apk_regression.py`, `patch_hook_privacy_controls.py`, `patch_native_hook_config_overlay.py`, `patch_native_hook_status.py`, `patch_native_hook_uninstall.py`, `patch_native_vpn_api.py`, `patch_private_runtime_logs.py`, VPN switch/core/subscription patchers, `remove_kernelsu_ui_entrypoints.py`, `retire_webui_legacy_hook.py`, and `unify_hook_ui.py`.

Existing regression tests include: `fx-app-webui-migration-regression.sh`, `fx-hook-native-ui-regression.sh`, `fx-native-hook-overlay-patcher-regression.py`, `fx-native-single-navigation-regression.sh`, `fx-native-vpn-api-regression.sh`, `fx-vpn-transparent-toggle-regression.sh`, and the `v1.0.0-*` migration regressions. Extend these tests rather than duplicating coverage.

## Immediate next work (continue in order)

1. Continue the native UI audit. Script list and CRUD have moved off the WebView bridge to the module command backend; native JSON export is present. Advanced privacy categories and rule-list mutations still use the hidden WebView compatibility bridge and remain the next UI/backend migration targets.
2. Audit each of the six destinations against the source module's real functions and keep each control on its correct page. Do not move feature controls into Settings.
3. Add native repository/service interfaces and persistent state only where the existing module backend cannot be used safely; retain existing proven backend behavior.
4. For every UI migration, add interaction/state/error regression tests and preserve existing functions.
5. Continue with Dia runtime analysis and Yulong DNS/network parity after the six-screen UI audit is complete.

## Acceptance evidence ledger

| Deliverable | Evidence required | Current state |
|---|---|---|
| Hook APK | Successful build + artifact inspection + SHA-256 | Latest CI build passed at HEAD `6372163`; artifact contents/checksum still require per-feature audit |
| KernelSU ZIP | Successful build + ZIP contents/permissions + embedded APK checksum | Latest CI package passed at HEAD `6372163`; real device installation not established |
| Automated regression | Relevant test names and CI job result | Latest migration validation job passed; full coverage of migration matrix is incomplete |
| Real device | Device model/Android version, steps, logs, traffic assertions | Not yet recorded |
| Final report | Completed/partial/unmigrated matrix, known defects, checksums | Not complete |

## Update protocol

After each implementation batch:
- Update the relevant row(s) and attach commit/test/build evidence.
- Never promote a feature to a higher status without evidence.
- Record blocked features with exact technical/licensing reason and a viable alternative.
- Keep FX version at 1.0.0 and work on the existing integration branch.
