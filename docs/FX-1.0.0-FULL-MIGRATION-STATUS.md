## Native privacy settings migration progress (2026-11-03)

- Current branch source revision: `73adacc20ae5442c5edba70d50867913df079162` (same source tree as CI revision `b073b1dc9ee3d0361fcbd30ee5e20e692094b98f`).
- Added `fx-patches/patch_native_privacy_settings.py`: generates the 12 native privacy category metadata panels from the restored canonical WebUI source, but only includes settings that are declared as top-level boolean flags in the module's `scripts/default.conf`. Section settings and editable values are intentionally excluded from switch generation.
- Added `fx-patches/native-privacy-settings.sh`: validates allowlisted top-level boolean keys, refuses writes during known settings transaction markers, writes through the module's existing `pg_set`, and invokes `scripts/apply.sh fast`. Its result distinguishes persisted-but-not-applied (exit 10) from a confirmed save/apply.
- Updated the native privacy category dialog in `MainActivity.java`: reads generated metadata and the module's real `/data/adb/privacyguard/settings.conf` through the Root command path, then writes changes through the module helper. The advanced-category toggle path no longer reads or writes the hidden WebView DOM.
- Added `scripts/tests/fx-native-privacy-settings-regression.sh` and integrated the generator/test into both Hook APK and KernelSU source-patch workflows.
- CI evidence at the time of this entry: KernelSU run `41517471761` passed the complete source compatibility patch step (including the new privacy regression) and QuickJS build step; package build was still running. Hook APK run `41517471775` passed source restoration/Hook merge and static migration checks; complete host regression and APK compilation were still running. Do not mark either full artifact build complete until the workflows finish successfully.
- Migration status remains **partial migration**: this implementation covers only top-level boolean settings that pass the schema generator. Section-scoped settings, text/list/choice editors, non-boolean privacy operations and the rest of the six-page native migration remain unfinished. Existing WebView-backed settings code outside the migrated category-toggle path has not been removed.
- Verification level: regression exercised in CI source-patch step on the same source tree; Java/Kotlin compilation and complete artifact build pending at this entry; no real-device verification.

# FX 1.0.0 Full Migration Status

> Baseline audit: 2026-11-03 (Asia/Tokyo)
> Repository: `vip-svip/SY`
> Branch: `fx-v1.0.0-unified-hook-integration`
> Audited HEAD before this document: `637216345d68e60d9a736dce3f51f2097eae46ed`
> Product version remains **FX 1.0.0**.
>
> This is an evidence-based tracking file, not a completion claim. A feature is not complete merely because a page, class name, or toggle exists. Device verification is never inferred from CI.

## Source re-audit at commit eaf19e6 (2026-11-03)

- Audited source commit: `eaf19e6986f88ea8ac1050944b382fd0837f3d64`.
- Audit record committed on the same branch as `364ff4d19d42607d20000fc4a71758fce8922b1e`; this documentation-only commit does not alter the audited application source.
- The previous successful Hook APK and KernelSU runs are both for `b1b852308dfae9a910032df179b4a217e4529b37`, not the current HEAD. The current HEAD has no matching run in the branch's latest Actions listing; do not treat the older artifacts as builds of this HEAD.
- Current HEAD CI status lookup returned no combined status entries. This is absence of reported status, not a pass.
- The native Compose shell is not yet a fully native app: its business-page body still uses a bundled WebView for VPN, Hosts/Ad, Privacy and Script routes. The Hook manager and Settings surfaces are native.
- Privacy advanced-category panels are native Android dialogs/controls, but their data source and persistence are not native: `showNativeSettingsGroup()` reads WebUI DOM rows, `PGB.model.sw`, `VPN_EDIT` and `secVal()`; `saveNativeSettingsEdit()` writes through WebUI `VPN_EDIT`, `secSet()` and `pgPersistNow()`. These are compatibility-bridge UI, not completed native migration.
- Hosts/managed-list mutations also remain WebView-backed: `mutateNativeManagedList()` calls `pgListArr()`, `pgPersistNow()` and `pgQueueAutoApply()`. Do not mark Hosts CRUD as native until its data repository and apply path no longer depend on the hidden WebView.
- This re-audit is source inspection only. The audit-record commit changed documentation only; no application code was changed, no test was run, and no real-device verification was performed during this batch.

## Native advanced privacy settings migration (2026-11-03)

- Replaced the advanced-category data bridge in `MainActivity.showNativeSettingsGroup()`: the 12 privacy panels now load their labels/descriptions from a generated APK asset and read the top-level flags from `/data/adb/privacyguard/settings.conf` through the Root command path. This path does not inspect WebView DOM or call `evaluateJavascript`.
- Added `fx-patches/patch_native_privacy_settings.py` to extract all 12 category schemas from the restored canonical module WebUI at build time. The generated asset contains 102 unique switch definitions; the original labels/descriptions are retained.
- Added `fx-patches/native-privacy-settings.sh`; it validates the requested key/value, reuses the module's existing `scripts/util.sh` `pg_set()` atomic writer, refuses writes while the WebUI transaction markers are present, and invokes `scripts/apply.sh fast`. It distinguishes persisted-but-apply-failed (exit 10) from a failed write.
- Wired the patcher and host regression into both APK and KernelSU build workflows. The built-APK regression checks that the generated schema is packaged.
- Earlier CI source-patch regression passed for the 12-panel / 102-control generator and Root writer. The latest regression additionally checks that native boolean toggle methods do not call the hidden WebView bridge, while non-boolean edit controls remain available through an isolated compatibility path; that latest assertion is pending CI.
- Earlier source revision `b073b1d` completed the Hook APK workflow successfully. That build predates the later compatibility-editor restoration and is not evidence for current HEAD. Current HEAD CI run `41518343462` is testing host regressions; run `41518343673` is testing the KernelSU package. No Android device interaction has been performed; do not mark this migration as device-verified.
- Scope note: this migrates the advanced privacy category switches backed by top-level settings.conf flags. It does not establish that every underlying privacy policy is fully enforced on every Android version/device; those runtime behaviors remain individually partial until separately tested.

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
| Privacy page | Native cards exist for advertising ID, clipboard, Wi-Fi scan, location, microphone, camera, sensors, notifications, media/EXIF and read-only diagnostics. The 12 advanced categories now use generated native metadata, Root reads of the module settings.conf top-level flags, and a module-side atomic writer/apply command; local host regression passed. | 部分迁移 | Await CI/build evidence; verify runtime enforcement, per-policy failure handling, reboot-only behavior, stop/uninstall and real-device compatibility; per-app privacy controls and remaining privacy functions are not complete |
| Script page | Native list/add/edit/delete/enable, JSON export/import and manual local JS execution are connected to module backends. Local source is stored losslessly as `FXSRC_B64:` in `settings.conf`; HTTPS subscriptions remain distinct and are handled only by `sync-subs.sh`. The native page invokes `local-run.sh` → `runner.sh` → QuickJS-NG for enabled local entries, with a 25-second timeout, 64 KiB source limit, SHA-256 snapshot guard, private bounded metadata-only run log, explicit run confirmation, and no execution of HTTPS subscription rows. | 部分迁移 | Implemented and included in both build pipelines. CI run `41512933779` passed static checks, complete host regressions, Java/Kotlin compilation, APK packaging, archive/entrypoint checks and navigation/UI regressions; run `41512933874` passed KernelSU package, post-package CA smoke tests, ZIP integrity and embedded APK checksum checks. Regression `fx-native-script-local-run-regression.sh` covers enabled/disabled gating, exact source bytes, HTTPS rejection, stale hash rejection, invalid indices, lock cleanup, metadata-only logs and runner installation. APK debug artifact `13174586444`; KernelSU artifact `13173972955`. KernelSU ZIP SHA-256 `0c0b7020b4ae2685cc94e249f7cead281964865f9399ff3af8791dc3e4db2864`; embedded release APK SHA-256 `57d90e1cfdb6fcb2d858a8c420039613c08db36a741063118b360565a654422d`; standalone debug APK SHA-256 `fca1f1d5cdf0f06ccdb2834920ed669fa062cec815f0d231a848efe71b438dd9`. Still incomplete: QuickJS host API compatibility matrix, unsupported syntax diagnostics, richer execution lifecycle/cancellation, URL metadata validation, and real-device execution tests. Do not count script format compatibility or runtime integration as complete until tested. |
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

1. Continue the native UI audit. Script list/CRUD/import/export and manual local QuickJS execution now use module command backends. Advanced privacy categories and rule-list mutations still use the hidden WebView compatibility bridge and remain the next UI/backend migration targets.
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
