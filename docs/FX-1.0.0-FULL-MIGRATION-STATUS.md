## Latest continuation checkpoint — 2026-11-03 (Asia/Tokyo)

Source branch: `fx-v1.0.0-unified-hook-integration`.
All changes below are source-tree work only. No final APK/KernelSU package is being
published during this migration phase.

### Yulong per-app firewall — unknown transport safety

- Corrected a transport-classification hazard in the per-app firewall: unknown/vendor-specific network interfaces are no longer blocked by a catch-all rule.
- Wi-Fi and mobile restrictions continue to use explicit known interface families; Ethernet, USB, VPN and other named transports retain their explicit fallback rules.
- Unknown interfaces fail open until their transport class is verified. This avoids silently turning a Wi-Fi-only rule into a block on vendor-specific cellular interfaces, or a mobile-only rule into a block on an unknown Wi-Fi interface.
- The schedule watcher still reconciles when interface inventory changes. Host regression now asserts that it re-applies while refusing to create a packet-block rule for an unclassified vendor interface.
- Host regression coverage added; no physical-device vendor-interface classification has been performed.

### Yulong Ad Plugin 7.0.1 — Tasker broadcast compatibility

- The single FX automation receiver now accepts the original
  `app.pwhs.blockads.TASKER_START` and `TASKER_STOP` actions as aliases for
  the FX ad-filter master enable/disable actions.
- The legacy actions change only the Yulong/FX ad-filter source master. They do
  not start the original AdBlockVpnService or allocate another Android VPN slot.
- The native automation panel exposes copy buttons for both new and original
  broadcast action names; result broadcasts remain package-scoped to FX.

### Yulong Ad Plugin 7.0.1 — DNS upstream configuration

- The native DNS page now exposes FX's existing custom_dns/global_dns controls and
  their address lists, plus the VPN remote_dns/cn_dns fields.
- Address writes are limited to one to three IPv4 literals per list; config-section
  replacement is atomic and uses the existing FX apply transaction.
- Local AdGuard Home to Unbound recursive DNS remains the default. The UI separates
  custom/global forwarding from VPN DNS and does not claim full parity with every
  original DoH/DoT upstream protocol option.

### Yulong Ad Plugin 7.0.1 — weekly schedule integration

- Native Ad settings now include a weekly schedule editor: enable/disable, local
  start/end times, and Monday-through-Sunday selection.
- The schedule watcher is staged into the restored FX module by
  `patch_yulong_ad_master.py`; the module boot service starts it and uninstall
  stops it. The watcher reevaluates every 60 seconds and immediately after save.
- Cross-midnight windows are supported. Equal start/end time means the full
  selected weekday. Device local timezone is used.
- Scheduling gates only the Yulong ad filter source in `[list:rule]`; it does
  not change FX anti-fraud/96110 rules, Hosts allow/block lists, DNS upstreams,
  or VPN/node routing.
- All source changes are on the unified integration branch. Final package
  generation remains deferred until the three source-app migrations are complete.

### Yulong Ad Plugin 7.0.1 — additional integrated work

- Added a native per-app statistics screen using Android `TrafficStats` UID
  counters. It shows cumulative RX/TX since boot, sort/search/refresh, and clearly
  marks unsupported UIDs. These bytes are not misrepresented as DNS query counts.
- Added the Root Proxy DNS fallback script and native settings/status switch.
  It reuses FX AdGuard Home + Unbound; it does not install a second VpnService.
- The Root Proxy requires a known external VPN interface and owner UID, an UP
  interface with an IPv4 address, route checks through that interface, a successful
  local DNS probe, and enabled DNS forwarding/compatibility settings. Failure
  removes only FXYRP-owned rules and leaves third-party VPN DNS unchanged.
- `fx-patches/patch_yulong_root_proxy.py` is wired into the KernelSU build workflow
  after the stable Release module archive is restored. It adds the Root Proxy,
  pins Unbound's source address to the route-checked egress marker, starts/stops
  the fallback from the module apply flow, and removes its own rules on uninstall.
- `vpn_external_dns_proxy` is exposed in the native DNS control page and defaults
  on for compatible external VPN operation; user can disable it.
- Remaining: exact per-app DNS request/block counters, RootProxy behavior on each
  vendor VPN implementation, and real-device route/packet-path verification.
  Do not claim universal VPN coexistence based only on host-side code.

### Yulong Security Shield 9.9.60 — screen-filter service

- Added a native fourth-level Screen Filter page inside the Shield suite.
- The UI exposes standard/game presets and brightness, contrast, saturation and
  temperature controls. Values persist under `shield_prefs`.
- Added a user-authorized foreground service that owns one non-touchable
  `TYPE_APPLICATION_OVERLAY` view, matching the original color-matrix/tint
  overlay behavior. It has an explicit notification stop action and removes
  only its own view on stop/destroy.
- This service requires manual overlay permission and notification permission.
  It is not an accessibility service and does not inspect or intercept screen
  content or touch input.

### Yulong Security Shield 9.9.60 — scoped Stellar management

- Removed a duplicated detached command-dialog fragment from the Stellar activity
  that was outside any method body.
- Added package-scoped runtime permission grant/revoke and AppOps mode controls.
  Each action requires the target app to be Stellar-authorized, the corresponding
  capability scope to be explicitly granted, and an extra confirmation dialog.
- The command backend accepts only fixed permission, AppOps operation and mode
  allowlists; arbitrary Shell execution remains disabled. Changes are logged under
  the original Stellar guard data directory.
- Added the missing explicit `SECURE_SETTINGS_WRITE` scope switch alongside the
  existing three-key safe writer (`show_ime_with_hard_keyboard`,
  `screensaver_enabled`, `long_press_timeout`); enabling it requires a separate
  high-privilege confirmation. The helper rejects all other secure-setting keys
  and validates the permitted value ranges before writing and read-back verification.

### Yulong Security Shield 9.9.60 — additional integrated work

- Repaired the in-app Stellar authorization manager bridge: Root script lookup,
  explicit package authorization, per-scope grants, read-only always-allow command
  records, and refresh rendering. `roro.stellar.manager` remains inside the Shield
  subtree, not a new FX main tab.
- Added a user-authorized floating rescue bubble. It requires the system overlay
  permission, starts its own foreground service, and only opens the Shield hub.
  It does not read or click other apps' UI.
- Removed duplicate live-protection controls in the Shield hub. The user-controlled
  foreground monitor remains based on Usage Access and blacklist/whitelist rules.
- Remaining: full original Golden Dragon/Stellar privileged command runtime parity,
  automatic boot/KeepAliveAlarm watchdog, original overlay rescue behavior, and
  permission-degrade recovery. The current floating bubble is an explicit rescue
  shortcut, not a full clone of the original watchdog.

### Dia 23.11 — per-app telephony identifier privacy

- The existing per-app privacy master now also masks TelephonyManager reads for
  IMEI/device ID, MEID, subscriber ID, SIM serial, line number, NAI and group ID
  in the selected target process. The hook returns the same null/unavailable
  shape Android commonly returns when identifier access is not granted.
- It is package-scoped and opt-in through the existing privacy target flag.
  It does not fabricate a carrier identity or modify system telephony, SIM state,
  radio configuration or network registration.

### Dia 23.11 — expanded per-app GPS test fixture

- The existing per-app latitude/longitude/accuracy fixture now also hooks
  android.location.Location.getLatitude(), getLongitude() and getAccuracy()
  within the explicitly selected debuggable target process. This covers callers
  that receive Location objects through fused/provider callbacks and later read
  their coordinate getters, in addition to LocationManager last-known queries.
- The UI copy now states the exact scope. No system-wide GNSS/provider setting,
  real hardware location, route, or other application's location is changed.

- The native Dia Custom Hook editor now has per-target rule groups. Users can
  create groups, move individual rules, remove an unused group without deleting
  its rules, and round-trip group membership through JSON import/export. The
  runtime config remains the same four-field rule format; group metadata is
  local UI organization and does not change target-hook semantics.

### Dia 23.11 — original monitor Activity routing

- Added distinct fourth-level routes for the original Intent, Socket, Shell/Process,
  method-stack, View click, ViewGroup, Fragment lifecycle, Thread startup and
  ClassLoader monitor screens. Each page opens the matching Frida template rather
  than a generic menu or a dead-end placeholder.
- Added a Socket observer template for Java `Socket.connect(SocketAddress[, timeout])`.
  It records endpoint host/port, timeout, elapsed time and exception class only;
  it never reads or records socket payload bytes.
- These are Frida script templates and still require an explicitly selected
  user-installed debuggable test target plus the local Frida runtime. They do not
  claim a replacement for Dia's built-in monitor daemon or native socket tracing.

### Dia 23.11 — broader HTTP and algorithm observers

- HTTP template now observes URLConnection, HttpURLConnection status, OkHttp
  execute/enqueue and Volley URL access. It records method/host/status/duration
  only; paths, query strings, headers, cookies and bodies are not serialized.
- Algorithm template now auto-hooks the Java JCA MessageDigest, Cipher, Mac and
  Signature method families. It records algorithm family/name, byte lengths,
  elapsed time and exception class, never cryptographic payloads or keys.
- This expands the built-in metadata observers; native/custom app-specific
  algorithms and non-Java networking stacks still require a manually authored
  Frida template and are not claimed as complete parity.

### Dia 23.11 — direct monitor entry integration

- The original fourth-level HTTP, SQL and algorithm menu entries now open the
  matching Frida page with the corresponding working script template preloaded.
  SQL defaults to the SQLite/SQLCipher/WCDB family observer; Native method and
  key-event entries also preload their matching templates.
- The templates intentionally record metadata only: HTTP host, SQL call type/
  argument count/string length/duration, and algorithm call count/duration.
  They do not serialize authorization headers, SQL values, arguments or results.
- The target still must be selected explicitly and must be a user-installed
  debuggable app; template loading never auto-injects or runs against a target.

### Dia 23.11 — additional integrated work

- Added the native privacy-settings Asset: seven panels covering notifications/
  clipboard, sensors, device identifiers, location/GNSS, network, filesystem and
  system diagnostics. The KernelSU build workflow now stages
  `native-privacy-settings.sh` into the restored module so those panel switches
  can read/write the actual module configuration through the Root allowlist helper.
- Added per-app Wi-Fi identity testing: fake SSID/BSSID values are serialized into
  the LSPosed Remote Files config and only override `WifiInfo.getSSID()` /
  `getBSSID()` inside user-installed debuggable target apps.
- Added per-app network transport testing: a debuggable target may report Wi-Fi or
  cellular through `NetworkInfo` and `NetworkCapabilities.hasTransport()`; the
  system's real routes, VPN and physical connection are not changed.
- Added launcher-only component hiding mode to the native Activity manager. It
  lists MAIN/LAUNCHER components, confirms before changing state, and allows
  re-enabling the launcher component from the same page.
- Added debug-only boolean test replacements to the custom Hook runtime. Rules
  support OBSERVE, RETURN_TRUE and RETURN_FALSE; replacement is restricted to
  exact-package, zero-argument boolean methods on debuggable targets. Rule import/
  export preserves enabled state and base action. Production apps and server-side
  membership/authorization are not modified.
- Database Inspector lists databases and reads `sqlite_master` schema only when a
  local sqlite3 CLI is present; it does not read business rows. Memory Inspector
  shows process status, PSS/RSS and bounded memory maps, not raw memory dumps.
- HTTP/SQL/algorithm instrumentation is still provided as editable Frida templates
  in the native Frida manager. That is not equivalent to a full Dia built-in
  instrumented runtime. DEX browser, Activity manager, Frida bridge and local/
  GitHub/WebDAV backup adapters are integrated.
- Remaining: broader Dia activity screens, full HTTP/SQL/algorithm runtime
  instrumentation, complete method/native function interception parity, advanced
  GPS/time/telephony identity simulation, and real-device LSPosed behavior checks.

### Packaging policy remains unchanged

- Push-triggered package builds stay disabled while migration is in progress.
- Continue committing to this same branch; do not create interim release ZIPs.
- Once source migration is complete, run the unified APK + KernelSU build from one
  exact commit, verify the embedded APK matches the standalone APK, generate
  SHA-256 checksums, verify ZIP integrity, and then publish the final artifacts.
- Host build/regression results are not real-device verification.

---

### Dia 23.11 — monitor page and rule-group integration

- The fourth-level Dia menu now exposes separate Intent, Socket, Shell/Process,
  method-stack, View click, ViewGroup, Fragment lifecycle, Thread startup,
  ClassLoader, SQL and algorithm monitor pages. Each mapped page opens its
  corresponding Frida template; it does not claim a built-in monitor daemon.
- Added a Java Socket connection observer for Socket.connect(SocketAddress[, timeout]).
  It records host/port, timeout, duration and exception class, not socket payloads.
- Dia Custom Hook rules now have per-target named groups, group creation/deletion,
  per-rule reassignment and group-preserving JSON import/export. Group membership
  is local UI metadata; the four-field runtime rule protocol is unchanged.
- The source still requires the selected user-installed debuggable target and an
  explicitly available Frida runtime for these monitor templates.

### Yulong Security Shield 9.9.60 — AdSkipService callback migration

- Merged the original foreground-window callback into the optional FX
  AccessibilityService: only `TYPE_WINDOW_STATE_CHANGED` package names are
  forwarded to the app's non-exported receiver. No accessibility node tree or
  event text is read.
- Merged the original volume-key callback: volume up/down direction metadata
  is broadcast only to the same app package. Key events are not consumed.
- The Shield protection service consumes foreground-package events immediately
  and reuses its existing blacklist/whitelist warning rules. UsageStats polling
  remains as a fallback when Accessibility is not enabled.
- The Screen Filter page optionally uses volume-up/down to change filter
  brightness by five units per press. This requires the user to enable FX
  Accessibility and leaves normal system volume behavior intact.

### Yulong Security Shield / Stellar source cleanup

- Removed a duplicated obsolete implementation tail appended after the closing
  brace of `FxStellarManagerActivity`. The retained class contains the current
  package-scoped authorization manager, read-only command scopes, and separately
  confirmed runtime-permission/AppOps controls.
- This is a source repair only; no build or device behavior is claimed here.

## 2026-11-03 migration continuation checkpoint

Source of truth: branch `fx-v1.0.0-unified-hook-integration`.
This note is the durable handoff for the current full three-app migration. Do not
replace it with a package-only summary or revert to empty menu scaffolding.

### Changes now present in the branch

**Yulong Ad Plugin 7.0.1**
- Added `scripts/decode_yulong_ad_tries.py` and `scripts/integrate_yulong_ad_rules.py`
  to decode the 7.0.1 bundled TRIE assets into DNS-safe Hosts entries and a separate
  cosmetic-rule file, then register the source in FX's existing rule pipeline.
- Added attribution for AdGuard DNS/Mobile, Peter Lowe, anti-AD, EasyList China,
  ADgk and AdGuard Chinese filter source lists.
- Added `fx-module/scripts/yulong-app-firewall.sh` plus a native FX Hook Activity.
  The firewall is separate from per-app VPN routing, writes only FXYUL_A/FXYUL_B
  OUTPUT chains, refreshes package UIDs at apply time, applies IPv4 and IPv6 as a
  transaction, and rolls back settings if either family fails.
- The module boot hook reapplies the firewall and module uninstall removes only
  the firewall's own chains. The original AdBlockVpnService is not added as a second
  VpnService; FX continues to own the single Android VPN/TUN.
- Remaining: original per-app traffic statistics, full RootProxyService fallback
  compatibility for a third-party VPN, some DNS/HTTPS preference screens and
  exact behavior parity with every original AdPlugin diagnostic screen.

**Yulong Security Shield 9.9.60**
- Added the native shield hub, virus database manager, installed-app scanner,
  content-signature database, whitelist, blacklist and install/update scan receiver.
- Unified `shield_prefs` keys with the original app's `blacklist_pkgs`,
  `whitelist_pkgs`, `protect_on`, `shake_trigger_on` and `volume_trigger_on`
  keys so the migrated services and list UIs share the same state.
- Added a user-controlled foreground service that reads only Usage Access foreground
  package names, applies blacklist/whitelist rules, and sends warnings. It does not
  force-stop, disable, freeze or uninstall apps and does not change accessibility
  settings on the user's behalf.
- Added opt-in volume-up sequence and accelerometer-shake rescue notifications.
  The accessibility service does not consume volume keys; the sensor listener is
  registered only while the user enables the shake trigger.
- Automatic install/update scanning uses the existing package scanner and can
  optionally use the original APK content-signature database.
- Remaining: exact Stellar/Golden Dragon privileged runtime, original overlay rescue
  workflow, foreground watchdog/KeepAliveAlarm, permission-degrade handling and
  legacy UI-driven force-stop/uninstall automation. Those intrusive actions are not
  silently re-created; any later replacement must remain explicit and user-confirmed.

**Dia 23.11**
- The Settings > migration-app tree and category/fourth-level navigation exist.
- Supported routes use FX's existing native installed-app Hook list, native privacy
  controls, local QuickJS script UI, Hosts/rules UI and runtime log UI.
- Added multiple-format custom Hook rule management in the native Hook target page:
  Java exact signature, legacy `Class#method()Z` and Smali/JVM descriptors;
  priority; per-rule OBSERVE/OFF; 64-rule limit; JSON bulk import/export.
- All custom rules remain exact-package scoped and read-only. The runtime does not
  rewrite production app authorization, account, login or membership decisions.
- Added an internal Frida manager that can start/stop an already-installed
  `frida-server` on loopback only and use an already-installed `frida-inject` to
  attach scripts to user-installed debuggable apps. It does not bundle/download
  Frida binaries and verifies its own PID file before stopping a process.
- Added a read-only DEX class-name browser for installed APK/split-APK files. It
  enumerates class names without loading target classes or reading app-private data.
- Added an Activity component browser for user-installed non-system apps, with
  explicit confirmation and Root-backed enable/disable actions for declared Activity
  components.
- Remaining: Dia device-property/location/network simulation, complete HTTP/SQL/
  database/algorithm monitor implementations, memory snapshots, backup adapters,
  full Activity/method rewrite parity and the remaining Dia-specific screens.
  QuickJS remains separate from Frida and is not presented as its replacement.

### Build / packaging policy
- Automatic push-triggered runs in both `.github/workflows/build-fx-adhook.yml` and
  `.github/workflows/build-fx-kernelsu.yml` were paused during migration; they are
  manual-dispatch workflows only. Do not restore automatic packaging for each
  incremental migration commit.
- No final KernelSU ZIP or APK is claimed for this continuation checkpoint.
- After all three source scopes are migrated, run the full source regressions, build
  the unified FX Hook APK and KernelSU ZIP from one exact commit, verify the APK
  embedded in the ZIP matches the paired standalone APK, verify checksums and ZIP
  integrity, and only then publish the final artifacts.
- CI/build evidence is host evidence only; real-device verification remains a
  separate final step.

## Latest continuation audit (2026-11-03, Asia/Tokyo)

- Current branch: `fx-v1.0.0-unified-hook-integration`; current branch HEAD at documentation update: `c4e24f4a545d78ba5af929317dd933d2d891640d`.
- Build source commit: `86a342f5c8e048f6eb4cd8176cf0904516a0cfa7` (parent of the documentation-only commit).
- Hook APK workflow `41523045826`: **success**. Static migration checks, complete host regression, Gradle compile, APK structure checks, and artifact upload all passed.
- KernelSU workflow `41523045838`: **success**. QuickJS-NG v0.17.0 ARM64 / NDK r26b compilation, shell/checksum validation, focused LSPosed Remote Files regressions, complete host regression, removal of legacy KernelSU WebUI entrypoints, ZIP packaging, and artifact uploads all passed.
- Canonical paired build outputs from the KernelSU workflow: `FX-v1.0.0.zip` SHA-256 `f86efa5178abdfa354ed6b9ed5287cc9609c437a03bded95f422f3b38e53fc23`; `FXUnifiedHook.apk` SHA-256 `e443d37369a4044431e760679f62b35f95f305da7031832d2ab9c2462758ff0b`. The ZIP passed `unzip -t`; embedded APK hash matches the separately uploaded paired APK artifact.
- An earlier Hook-only workflow artifact on the same source commit produced a different-sized APK. The KernelSU workflow's paired APK is the canonical artifact because its byte-for-byte SHA-256 matches the APK embedded in the final ZIP; do not substitute the earlier Hook-only artifact.
- The APK schema includes 13 native settings panels (VPN plus 12 privacy panels). The 12 privacy panels use Root-backed native boolean controls. No real-device verification has been performed.
- The current source now has native primary tabs, a paged local Hosts editor, Root-backed `ruleList` / `domainList` / `blockList` CRUD, and a native editor for the canonical `[conf:vpn]` text/list/choice settings. These source migrations are on the active branch; no current-HEAD package or real-device verification has been performed.
- Hook UI currently has native installed-app list/search/paging and target configuration surfaces, but a complete runtime verification matrix across Root, LSPosed, and Accessibility has not been device-tested.
- Do not mark any page/device behavior as device-verified based on CI.


## Source re-audit at commit eaf19e6 (2026-11-03)

- Audited source commit: `eaf19e6986f88ea8ac1050944b382fd0837f3d64`.
- Audit record committed on the same branch as `364ff4d19d42607d20000fc4a71758fce8922b1e`; this documentation-only commit does not alter the audited application source.
- The previous successful Hook APK and KernelSU runs are both for `b1b852308dfae9a910032df179b4a217e4529b37`, not the current HEAD. The current HEAD has no matching run in the branch's latest Actions listing; do not treat the older artifacts as builds of this HEAD.
- Current HEAD CI status lookup returned no combined status entries. This is absence of reported status, not a pass.
- The four primary business tabs (VPN, Ad/Hosts, Privacy, Scripts) are now rendered by `MainActivity.renderNativePage()` as native Android views; Hook and Settings are also native. The WebView remains only as a compatibility/runtime resource for legacy bridges and imported tools, not as the primary tab body.
- Privacy advanced-category panels are native Android dialogs/controls backed by generated `native-privacy-settings.json` metadata and `scripts/native-privacy-settings.sh`. Boolean controls use allowlisted root config writes and apply; the VPN text/list/choice fields are now handled by `scripts/native-vpn-config.sh` and no longer read `VPN_EDIT` or WebView DOM.
- The local Hosts text editor is native and paged: it reads/writes the single extensionless source `/data/adb/privacyguard/local/hosts` via Root `fileedit.sh`, supports external-editor import/export, and rebuilds the generated `/system/etc/hosts` mount. Rule subscriptions and domain allow/block lists now use `scripts/native-managed-lists.sh` with atomic config writes and apply rollback; their native UI no longer calls `pgListArr()`, `pgPersistNow()` or `pgQueueAutoApply()`.
- This re-audit is source inspection only. The audit-record commit changed documentation only; no application code was changed, no test was run, and no real-device verification was performed during this batch.

## Native advanced privacy settings migration (2026-11-03)

- The generator emits 13 non-empty panels (VPN advanced settings plus 12 privacy categories) and 112 unique top-level boolean flags from the canonical restored module source.
- `showNativeSettingsGroup()` and `renderNativePrivacySettingsGroup()` read the generated metadata and the filtered Root helper output. Boolean toggles use the module's real config writer and apply command; those two rendering methods do not access the hidden WebView DOM.
- `loadNativePrivacyEditEntries()` now exposes the native VPN advanced editor only. The editor reads and writes the allowlisted canonical `[conf:vpn]` keys through `scripts/native-vpn-config.sh`; it no longer uses `VPN_EDIT` or WebView DOM values.
- The Root helper returns only top-level boolean values to the App, checks all known settings transaction/temp markers (including `settings.conf.tmp.PID` from `pg_set`), and reports save/apply outcomes separately.
- Current CI and local-test evidence is recorded in the progress section above. The current-HEAD APK compile and KernelSU ZIP packaging are not yet verified.
- Scope note: these controls do not establish that every Android privacy policy is enforced on every Android version/device. No real-device test has been performed.


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
| Native app shell | Compose bottom navigation exposes six destinations; `MainActivity.renderNativePage()` renders the four primary business pages as native Android views, with native Hook and Settings pages | 已完成源码迁移 | Current-HEAD build and device state-restoration verification remain pending |
| Legacy WebUI Hook entry | Retirement patch exists and is wired into both workflows | 已通过测试 | Verify final APK has no duplicate Hook manager entry |
| VPN controls | Native VPN controls, per-app route manager, subscription manager and advanced `[conf:vpn]` text/list/choice editor are present | 源码迁移已完成，设备验证待做 | Verify service-derived state, real traffic path, direct/global/rule mode, subscriptions, third-party VPN coexistence and recovery |
| Ad / Hosts | Native paged local Hosts editor, native subscription/domain list CRUD, Yulong app whitelist, and separate proxy/firewall app lists are present | 源码迁移已完成，设备验证待做 | Verify real Android hosts file editing, external-editor sync, subscription parsing, UID bypass in TUN/Root DNS, and safe apply/rollback |
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
| Class/method/field search | `FxDiaDexBrowserActivity` + `FxDiaDexIndex` read DEX/APK inputs, build a class/member index, search descriptors and member names, inspect call-site metadata, and export matching signatures with generation-cancellable background work | 部分迁移 | Verify multidex/split APK edge cases, malformed DEX handling, large-APK memory use and device performance; this is offline DEX analysis, not a live ClassLoader/call graph |
| JVM descriptors and Smali parsing | `DeveloperExecutableDescriptor`, `DeveloperHookRule` | 部分迁移 | Validate full parameter/return/array/object descriptor matrix and runtime use |
| Rule groups, CRUD, import/export, enable/disable | Some target config parser/serializer exists | 部分迁移 | Full group lifecycle and round-trip tests |
| AppEntryHook, ClickBtnHook, FragmentHook, ViewGroupHook | No complete equivalent verified | 未检查 | Per-hook semantics and target SDK compatibility audit |
| IntentHook, RuntimeHook, ThreadHook, StackHook | No complete equivalent verified | 未检查 | Implement only with explicit target scope and observable diagnostics |
| ClassLoader and call relationship analysis | No complete equivalent verified | 未检查 | Analysis backend, large-app performance and export |
| Frida runtime/service/process attach | `FxDiaFridaActivity` is a genuine Frida management path separate from QuickJS: it accepts user-provided/imported `frida-server` and `frida-inject`, starts the server on `127.0.0.1:27042`, checks PID ownership, and limits targets to installed non-system debuggable apps | 部分迁移 | Frida binaries are not bundled or fetched by FX; verify user-supplied ABI/version compatibility, SELinux/root behavior and actual attach on supported devices; host/source checks do not prove device runtime |
| Frida script load/unload, WAIT/RESUME, multi-process | Frida-inject supports manual multi-PID selection or current-process auto enumeration with package/PID revalidation; Gadget configuration exposes `on_load=wait/resume`, and an external Frida CLI session can load the current script and release WAIT. The Gadget path explicitly requires the target to load the Gadget library | 部分迁移 | Full Dia lifecycle parity is not established: automatic process-start tracking, universal script unload/reload and device-side WAIT/RESUME behavior still require real Frida/target verification; `frida-inject` is not the remote Gadget CLI |
| HTTP request/response and Socket monitoring | Dia Frida templates include in-process `HttpURLConnection` and WebView navigation metadata observers; FX MITM remains a separate network-proxy path | 部分迁移 | No general raw Socket/TLS stream recorder is claimed; verify supported HTTP client versions, target-process attach and privacy redaction on-device |
| Network rewrite rules | Existing script/rule infrastructure | 部分迁移 | Verify request/response rewrite semantics, target scope, association and redaction |
| SQLite, SQLCipher, WCDB monitoring | Dia Frida template generation covers Android SQLite, `SQLiteStatement`, SQLCipher/Zetetic and WCDB statement paths; emitted telemetry is limited to method, duration and exception type | 部分迁移 | Verify concrete library versions and overload coverage on real debuggable targets; this remains Frida instrumentation, not a standalone database daemon |
| DEX class tree/method finder/signature conversion | Native DEX browser provides paged class/member details, class/method/field descriptors, call-site display and matching-signature export; a separate APK signature page reports signer history and SHA-256/SHA-1/MD5 certificate digests | 部分迁移 | Verify malformed/multidex APKs, certificate rotation and multi-signer edge cases; no claim of a full decompiler or whole-program call graph |
| Algorithm tracing | A target-scoped Dia Frida algorithm-observation template is available in the native Frida manager | 部分迁移 | It is an editable template, not a universal algorithm tracer; requires a user-selected debuggable target, real Frida runtime and device verification |
| App signature analysis | `FxDiaSignatureActivity` reads installed APK version/install metadata, current signers or signing-certificate history, multi-signer state, SHA-256/SHA-1/MD5 digests and X.509 subject/issuer/validity | 部分迁移 | Verify signing-certificate rotation, split APK and multiple-signer cases on supported Android releases |
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
| DNS request/error logs and statistics | AdGuard Home query logging is user-opt-in and disabled by default, with 30-day local retention; native summary returns numeric `queries`, `blocked`, `unblocked` totals from retained records and never displays domains, client IPs or raw query JSON | 部分迁移 | Error counters, retention behavior on device and full resolver logging UX remain to verify; totals cover retained log records, not per-app DNS queries |
| DNS cache | Native DNS page has an explicit-confirmation cache action that restarts only enabled local AdGuard Home/Unbound engines, checks each stop/ensure/apply result and reports disabled-engine no-op separately | 部分迁移 | Host regression covers engine combinations, missing helpers, lock contention and failure propagation; this does not clear Android's system DNS cache |
| Custom DNS rules/providers | FX host/domain rules exist; DNS provider CRUD and full DNS rule semantics not verified | 部分迁移 | Add precedence, import/export, conflict diagnostics and provider management |
| Ad/tracker/malicious-domain filtering | Multiple filter lists and FX domain-rule pipeline exist | 部分迁移 | Verify parser coverage, list updates, offline behavior, conflict resolution and rollback |
| VPN DNS tunnel/service coordination | sing-box/VPN core and DNS components exist | 部分迁移 | Verify actual traffic capture, tunnel DNS path, retry/recovery and app scope |
| VpnEngineCoordinator/VpnRetryManager equivalents | Existing VPN scripts/stop guards exist | 部分迁移 | Verify service coordinator state machine and retry limits |
| Third-party VPN coexistence | Existing UI/patches claim coexistence intent; actual traffic coexistence not proven | 未检查 | Must test traffic path on supported devices/VPN combinations |
| Per-app DNS/UID scope | No complete equivalent verified | 未迁移 | Implement and test per-app resolver/proxy scope |
| Root Proxy and iptables DNS redirect | `yulong-root-proxy.sh` requires the explicit external-VPN DNS compatibility switches, a unique current VPN owner UID/interface, an UP tunnel, matching route lookups for two root DNS addresses, and a validated VPN-side IPv4 egress; pins Unbound to that egress, builds FX-owned IPv4/IPv6 NAT chains, bypasses root/VPN-owner/whitelisted UIDs, and removes only its own chains on uncertain state | 部分迁移 | Host regressions cover route/UID proofs, whitelist bypass, dual-stack setup, symlink guards and fail-open rollback; still require real packet-path and third-party VPN coexistence tests on supported devices |
| HTTPS/MITM and CA management | FX MITM engine, certificate manager and status surfaces exist | 部分迁移 | Validate supported protocol/traffic scope, CA lifecycle, safe passthrough and pinning limitations |
| TLS passthrough and safe downgrade | Some MITM redirect/status guards exist | 部分迁移 | Verify security-critical domain passthrough and fail-safe behavior |
| App network scope/firewall controls | Native per-app firewall now stores independent Wi-Fi/mobile flags and daily local-time windows; Root applies owned dual-stack OUTPUT chains by current package UID, watches time/interface inventory changes, and deliberately fails open for unknown vendor interfaces. Host regression covers legacy config migration, transport isolation, schedule boundaries, UID reinstall and watcher ownership | 源码与宿主回归已覆盖，设备验证待做 | Validate actual interface naming/routing on supported Android/OEM devices, VPN coexistence and no cross-app collateral effects; unknown/vendor interface classification is intentionally not guessed |
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

1. Continue the source migration against the original Dia 23.11 / Yulong 7.0.1 / Yulong Shield 9.9.60 screen and behavior inventory. Primary tabs, local Hosts editing, managed Hosts lists, VPN advanced values, Yulong firewall/whitelist and Shield foreground protection have native source implementations; compare any remaining source pages and backend behaviors, then complete migration before requesting the final paired build.
2. Audit each of the six destinations against the source module's real functions and keep each control on its correct page. Do not move feature controls into Settings.
3. Add native repository/service interfaces and persistent state only where the existing module backend cannot be used safely; retain existing proven backend behavior.
4. For every UI migration, add interaction/state/error regression tests and preserve existing functions.
5. Continue with Dia runtime analysis and Yulong DNS/network parity after the six-screen UI audit is complete.

## Acceptance evidence ledger

| Deliverable | Evidence required | Current state |
|---|---|---|
| Hook APK | Successful build + artifact inspection + SHA-256 | Earlier build passed at older HEAD `6372163`; current HEAD build is pending after test correction. Artifact contents/checksum still require per-feature audit |
| KernelSU ZIP | Successful build + ZIP contents/permissions + embedded APK checksum | Earlier package passed at older HEAD `6372163`; current HEAD package is pending. Real device installation not established |
| Automated regression | Relevant test names and CI job result | Earlier source-patch checks passed, but latest Hook APK validation failed in `fx-native-privacy-settings-regression.sh` because a duplicated `if` lacked its closing `fi`; corrected in commit `462960e`. Current rerun required; full coverage of migration matrix is incomplete |
| Real device | Device model/Android version, steps, logs, traffic assertions | Not yet recorded |
| Final report | Completed/partial/unmigrated matrix, known defects, checksums | Not complete |

## Update protocol

After each implementation batch:
- Update the relevant row(s) and attach commit/test/build evidence.
- Never promote a feature to a higher status without evidence.
- Record blocked features with exact technical/licensing reason and a viable alternative.
- Keep FX version at 1.0.0 and work on the existing integration branch.

## Current unified migration continuation (2026-11-03, same branch)

- Continuation branch: fx-v1.0.0-unified-hook-integration.
- Source HEAD before this checkpoint: 08750f9c866e8b7636fd342bf957af71c40dfbc2.
- All migration changes are kept in this branch. Both build workflows are currently manual-only (workflow_dispatch); no intermediate ZIP/APK packaging is intended. Do not restore automatic build triggers until the three source applications are migrated.
- No final package is produced by this checkpoint.

### Dia 23.11 — new integrated native surfaces

- The Dia entry in Settings now opens its own third-level hub and separate fourth-level pages.
- FxDiaDexIndex parses APK DEX tables without loading/initializing target classes. It indexes class definitions, fields, method names, JVM descriptors, direct/virtual methods and split APK DEX files. The browser supports class/member search and copies descriptors.
- FxDiaSignatureActivity reads package version metadata, signing-certificate history/current signers and SHA-256/SHA-1/MD5 X.509 fingerprints.
- Frida manager remains a real Frida path, not QuickJS relabeled as Frida: it checks user-supplied frida-server/frida-inject, binds the server to 127.0.0.1:27042, and limits attach targets to user-installed debuggable apps.
- Frida templates now include HTTP, SQLite, algorithm, HPROF, Intent, View click, ViewGroup, Fragment lifecycle, Thread start, Activity stack and Runtime/Process launch observation. Metadata templates omit text, extras, command contents, argument values and return values.
- Custom Hook UI accepts Java exact method signatures, JVM/Smali descriptors and legacy zero-argument boolean descriptors. It supports up to 64 per-target entries, priority, OBSERVE/OFF state and JSON import/export. The runtime remains read-only and debuggable-target scoped; method-return replacement is not exposed as a working capability.
- Still not migrated one-to-one: Dia's full original module/Hook inventory, automatic process-start tracking and universal script unload/reload lifecycle, complete rule-group backend, whole-program class-loader/call-graph analysis, and all original backup/monitor adapters. Gadget WAIT/RESUME and multi-process `frida-inject` source paths now exist, but a visible control or template is not device-level runtime evidence.

### Yulong AdBlock 7.0.1 — new integrated runtime and DNS surfaces

- Third-party VPN DNS fallback reuses the existing active Android VPN interface and owner UID; it does not package or start the original second AdBlockVpnService. Root Proxy activates only after route and DNS probes pass, and removes FX-owned redirects on uncertain state.
- A distinct per-app firewall uses FX-owned FXYUL_A / FXYUL_B dual-stack OUTPUT chains, resolves current package UIDs at apply time, independently selects Wi-Fi/mobile blocking and daily local-time windows, watches time/interface inventory changes, fails open for unknown interfaces, and removes only its own chains during disable/uninstall.
- Root Proxy configuration is exposed in the dedicated VPN/Root Proxy fourth-level page, including external-VPN DNS fallback and compatibility toggles. The actual patcher is wired into the KernelSU workflow.
- The AdGuard Home query log is user opt-in and off by default, with 30-day local retention. The native summary reads the current retained querylog and returns only numeric query/blocked/unblocked totals; it does not expose domains, client IPs or raw query records. The DNS page also has a confirmed local-engine cache restart action; it does not claim to clear Android's system DNS cache.
- Filter-list CRUD, domain allow/block lists, DNS settings, app firewall, per-UID traffic statistics, Tasker broadcast actions and the Quick Settings tile remain in the Yulong Ad native page family.
- Still incomplete: exact parity for the original task/schedule subsystem, per-app DNS query counters (the current per-app statistics view is network-byte based and must not be presented as DNS query counts), complete upstream/DNS protocol UI parity, and device-level verification of external VPN coexistence.

### Yulong Security Shield 9.9.60 — new integrated native surfaces

- Settings now routes to a dedicated third-level Shield hub and separate fourth-level pages for the safety center, virus database, app scan, whitelist, control list, Stellar and rescue/recovery. Stellar remains inside the Shield suite, not a new bottom tab.
- Installed-app scan and install/update-time scan reuse the migrated virus-name/package database and optional APK-content database. Automatic scans only notify and store results; they do not silently disable or uninstall packages.
- FxYulongProtectionService supports opt-in foreground-package monitoring against the original blacklist_pkgs/whitelist_pkgs keys. It uses Usage Access only when foreground monitoring is enabled.
- Volume-up sequence and accelerometer shake rescue triggers are independently opt-in; volume events require the user to enable FX Accessibility manually. The service does not retrieve window text, click UI, alter accessibility settings or consume the volume key.
- The overlay rescue shortcut is user-authorized and only opens the FX Shield hub. Boot restore and a 15-minute low-frequency keepalive are limited to previously opted-in Shield monitor/shake/overlay functions; the keepalive is not an always-on hidden watchdog.
- A local daily summary records current-day foreground alerts, install scans and risk hits; it does not claim data for events that were not recorded.
- Still incomplete: the original Stellar privileged runtime/command bridge parity, original multi-mode automatic remediation and full rescue overlay workflows. Automatic force-stop/freeze/uninstall and permission re-grant behaviors were not migrated; only explicit user review/notification is retained.

### Packaging policy for this branch

1. Keep all commits on fx-v1.0.0-unified-hook-integration; do not create numbered backup branches or intermediate deliverable ZIPs.
2. Do not start final build until the remaining Dia, Yulong Ad and Yulong Shield feature scopes are implemented.
3. At finalization, run the Hook APK and KernelSU ZIP workflows against the same exact commit; publish only the paired APK embedded in that ZIP, with SHA-256 and ZIP integrity evidence.
4. Automated CI is host evidence only. Device behavior must remain marked unverified until a real Android device test is recorded.

## Continued native migration record (2026-11-03)

- The Yulong Shield 9.9.60 native hub now has an opt-in foreground protection service. It uses Usage Access to observe only the foreground package, reads the migrated `blacklist_pkgs` / `whitelist_pkgs` preferences, and sends rate-limited warnings. It does not force-stop, freeze, disable, or uninstall applications.
- Shield install/update scanning now calls the existing per-package scan engine, stores the latest result, and notifies only on a finding. Manual all-app scanning remains separately available.
- Shield rescue triggers include an opt-in volume-up sequence through FX Accessibility and an opt-in accelerometer shake trigger. Neither reads screen text or consumes hardware keys. Accessibility must be enabled by the user in Android Settings.
- Dia 23.11 native migration now includes Activity/component management, Frida runtime/script import/export and target selection, Dex indexing/browsing, database/memory inspection, JSON tools, file/SAF management, signature inspection, GitHub/WebDAV/local backup workflows, and native HTTP/JCA/SQL/algorithm monitor templates. Runtime remains scoped to the chosen app and depends on the required Root/Frida/debuggable-target permissions; no claim of device verification is made.
- Yulong AdBlock 7.0.1 includes a separate native app whitelist. Its `[list:yulong_app_whitelist]` data is independent from `[list:vpn_app]` (proxy routing) and the per-app firewall list. The package workflow patches the restored module so these UIDs are excluded from FX sing-box TUN, legacy PGNAT/PGVPN/PGVPN6 redirects, and the FX-owned external-VPN Root DNS Proxy chains.
- The whitelist manager is a native fourth-level Activity under Settings → 迁移应用 → 游龙广告插件 7.0.1 → 应用管理 → 应用白名单. Its backend writes atomically and runs the normal FX apply transaction; it is not a second VPN service.
- All changes remain on `fx-v1.0.0-unified-hook-integration`. The KernelSU and Hook build workflows are manual-dispatch only while migration continues. No final package has been regenerated for these changes. These are source-level implementations, not real-device verification.


### Dia 23.11 — Frida Gadget listen-mode migration (2026-11-03)

- Added a native Frida Gadget Listen configuration editor to the Dia Frida page.
- Preserves the original WAIT/RESUME semantics through Gadget's `interaction.type=listen` and `on_load=wait|resume` settings.
- Writes the Android-compatible adjacent config filename (`<gadget-library-basename>.config.so`) and provides ADB loopback port-forward commands.
- The Gadget listener is fixed to `127.0.0.1`; the UI does not expose an unauthenticated LAN listener.
- This writes configuration only. The selected debuggable target must actually load the corresponding Frida Gadget library; this does not claim to patch or inject Gadget into a third-party APK.
- The existing local frida-server and frida-inject path remains separate and unchanged.


### Yulong AdBlock backend staging re-audit (2026-11-03)

- The full canonical backend already exists at `scripts/yulong-ad-control.sh` (approximately 14 KB), and `.github/workflows/build-fx-kernelsu.yml` already stages it into the restored module with `install -D`.
- A shorter duplicate backend and a redundant patcher were briefly added during this continuation, then removed because they would have overridden the more complete existing implementation.
- The build workflow continues to use the original full backend, including DNS query-log tail/clear, allow/block lists, rule CRUD, DNS settings, schedule, cache refresh, Root Proxy status and logs.
- No intermediate package was generated.

## Native Hosts and VPN editor cutover (2026-11-03)

- `scripts/native-managed-lists.sh` is installed into the module at package-build time. It maps the app's native list IDs to `[list:rule]`, `[list:domain]` and `[list:block]`, preserves row order/notes/enabled state, and uses atomic update + apply + rollback.
- `MainActivity.showNativeManagedListDialog()`, add/edit/toggle/delete flows now call the Root backend. The main Activity no longer contains the legacy `pgListArr()`, `pgPersistNow()` or `pgQueueAutoApply()` calls.
- `scripts/native-vpn-config.sh` is installed into the module and exposes an allowlisted reader/writer for canonical `[conf:vpn]` keys. The native VPN editor exposes local/mixed ports, DNS, URLs, update interval, routing mode, core version/path/auto-download, log level, cache lifetime, auto-selection thresholds and hide options.
- `MainActivity.loadNativePrivacyEditEntries()` now opens that native VPN editor. The unused `VPN_EDIT` / `secVal()` / `secSet()` WebView editor and save/poll methods have been removed from `MainActivity`.
- Both build workflows remain manual-dispatch only during migration. The above are source-level changes only; no final ZIP/APK has been rebuilt for this state and no device verification is claimed.

## Native migration continuation — 2026-11-03 (latest batch)

- Yulong Stellar manager: added an explicit SECURE_SETTINGS_WRITE action path. The UI requires the per-package scope and a confirmation. The Root backend accepts only show_ime_with_hard_keyboard (0/1), screensaver_enabled (0/1), and long_press_timeout (100–1000 ms); arbitrary secure-setting keys are rejected. The script verifies the value after writing and records the action.
- Yulong AdBlock schedule: schedule writes now use an exclusive lock and per-process temporary file, preserve the previous schedule, apply the new schedule, ensure the background watcher is running, and restore the previous schedule if applying or starting the watcher fails.
- Yulong Shield rescue: the overlay shortcut now opens a dedicated native Rescue Center instead of only returning to the Shield home page. It can stop foreground protection, pause volume/shake triggers, close the overlay entry, inspect the latest foreground package, open Android app info/uninstall confirmation, add the foreground app to the whitelist, remove it from the blacklist, clear the blacklist after confirmation, and open Usage Access / Accessibility / overlay settings.
- Rescue operations are user initiated. No automatic app force-stop, freeze, uninstall, arbitrary permission grant, or accessibility permission restoration was added.
- All changes remain on fx-v1.0.0-unified-hook-integration. No intermediate APK/KernelSU ZIP was generated. This batch has source-level changes only; it does not claim a current-HEAD build or device test.

## Migration continuation — additional native integrations (2026-11-03)

- Dia custom Hook groups: portable JSON exports now include source package, group names (including empty groups), per-rule group, action, enabled state and priority. Import supports old JSON arrays and the portable object format. When importing between package targets, only the class-owner package prefix is remapped; the existing parser then validates that each method belongs to the destination package. Method parameters and return descriptors are not rewritten.
- Dia Frida: target process selection supports multiple running process PIDs. Empty selection means auto-enumerate the target application's current processes. Before each attach, FX re-reads the PID/name pair and requires the process name to equal the target package or its colon-suffixed process; stale/reused PIDs are skipped. Injection continues for other selected processes if one process fails.
- Dia DEX index: the read-only parser now reads DEX code_item instruction streams, extracts direct invoke-virtual/super/direct/static/interface and invoke-polymorphic edges, and displays a bounded class-local call graph. The class browser also displays superclass and implemented interfaces. It does not load or execute code from inspected APKs. Limits: 512 edges per class, 150,000 edges per DEX, and 2 million code units per method.
- Dia backup: the existing local/GitHub/WebDAV backup format now includes the separate fx_dia_frida preferences as well as MainActivity Hook preferences, Shield lists, Stellar authorization metadata and module settings. SAF document/tree URI grants and process IDs are intentionally excluded.
- Yulong AdBlock: schedule writes use an exclusive lock, unique temporary files, previous-file rollback, evaluate/apply and watcher-start confirmation. Custom/global DNS and VPN DNS writes also use per-process temporary files.
- Yulong Root Proxy: fixed unintended escaping of shell variable references in the runtime source, and added a build-patcher guard to reject a source containing escaped variable references. The workflow copies this source into the restored release module before packaging. It remains a single-VPN-slot design: no second VpnService is created.
- Shield protection runtime: foreground-list protection requires Usage Access, while shake-only rescue mode can run without Usage Access. If Usage Access is revoked while shake mode remains enabled, only foreground protection is disabled; the shake listener may continue. Notification permission remains required for visible alerts.
- These changes are source commits on fx-v1.0.0-unified-hook-integration. Automatic package generation remains disabled during migration; no intermediate APK or KernelSU ZIP was produced in this batch. No current-HEAD build or device test is claimed.

## Continuation checkpoint — 2026-11-03 (latest native migration work)

- All changes below are committed on 'fx-v1.0.0-unified-hook-integration'; do not rebuild the final ZIP between migration batches.
- Yulong Ad 7.0.1 custom DNS now accepts up to three plain IPv4, DoH (https://), DoT (tls://) or DoQ (quic://) upstreams. A separate IPv4 fallback list is persisted under [conf:yulong_dns_fallback] and can be cleared from the native UI. Global DNS replacement remains IPv4-only and semantically separate.
- fx-patches/patch_yulong_dns_upstreams.py is staged in the KernelSU workflow. At package-build time it patches the bundled scripts/adguardhome.sh renderer to read the FX settings file. With custom DNS disabled, AdGuard Home continues to use 127.0.0.1:5353 (the local Unbound recursive resolver). With explicit custom DNS enabled, configured upstreams and fallback servers are emitted into AdGuard Home YAML; encrypted-upstream bootstrap DNS is emitted only for custom encrypted endpoints. The UI warns that DoT/DoQ can be blocked by the corresponding DoT/QUIC blocking switches.
- Dia 23.11 Frida support now includes a WebView-only HTTP navigation template that emits host metadata for WebView.loadUrl / postUrl without logging request bodies, page text, cookies or full URLs. SQL monitoring now also observes SQLiteStatement execution paths for Android SQLite, SQLCipher, WCDB and Zetetic SQLCipher; it emits method, duration and exception type only.
- Yulong Shield screen-filter drawing now uses the configured Paint color matrix for the overlay itself. The UI explicitly describes the capability as a non-touch transparent overlay and does not claim pixel-level transformation of the underlying screen for contrast/saturation.
- Dia component manager now resolves the active Android user rather than hard-coding user 0; its Intent import was restored.
- Yulong schedule validation rejects duplicate/invalid weekdays, and disabled schedules stop their minute-polling watcher.
- Yulong Ad DNS filtering response mode is now native-configurable: NXDOMAIN (default), REFUSED, or custom null-address response (0.0.0.0 / ::); the AdGuard Home runtime renderer reads this setting at startup.
- No final KernelSU ZIP or APK was produced in this continuation batch. The build workflows remain manual-dispatch only, so subsequent source commits do not package prematurely. No real-device verification is claimed.

## Yulong AdBlock 7.0.1 convenience-component migration (2026-11-03)

- Added a single-APK FX home-screen AppWidget. It reads the actual yulong-ad-control.sh master state, toggles only the FX ad-filter master setting, opens the native Yulong Ad page, and never starts the original AdBlockVpnService or RootProxyService.
- The widget shows today's blocked-query sample count only when local AdGuard Home query logging is enabled and log timestamps can be parsed. Empty/disabled/unparseable logs are surfaced explicitly; the most recent 500 records are not presented as a complete daily total.
- Widget state refreshes after native Yulong Ad page changes, Tasker changes and Quick Settings tile changes.
- Added the original Yulong VPN-toggle launcher shortcut action to FX. It uses the existing FX status.sh and native apply.sh path to toggle between the current proxy mode and direct mode, remembers the last non-direct mode, and requires an existing selected node before starting proxy mode. It does not create a second VPN service.
- The Tasker receiver still accepts both the new FX actions and original app.pwhs.blockads.TASKER_START/STOP actions. Its result action now broadcasts the requested state, source action, success flag and exit code so external automation apps can receive it.
- Corrected shell-command quoting and line/delimiter parsing in the native Yulong Tasker, Quick Settings and ad-control screens so the Root command strings and backend output parsing match the actual shell format.
- All source changes are committed to fx-v1.0.0-unified-hook-integration. Build workflows remain manual-only and no intermediate/final ZIP or APK has been generated for these changes. This is source migration work; current-HEAD build and device behavior remain unverified.


## Dia 23.11 — SQL monitor option migration (2026-11-03)

- The native fourth-level SQL monitor page now exposes the original backend selection as independent options: Android SQLite, SQLCipher, Tencent WCDB, and Zetetic SQLCipher.
- A separate optional call-stack switch is available; it defaults off to limit overhead and log volume.
- The Frida monitor template is generated from the selected backends, including each backend's database and statement classes.
- SQL monitoring remains metadata-only: method name, argument count, first SQL-string length, elapsed time, and exception class. It does not serialize SQL text, bound values, query results, or result rows.
- Options persist in the FX Dia Frida preference namespace and apply to the next generated/attached script.
- Source change is committed on `fx-v1.0.0-unified-hook-integration`. No intermediate APK/KernelSU ZIP was generated; this is not device verification.



## Yulong AdBlock 7.0.1 — bulk domain-list import (2026-11-03)

- The native domain-list page now supports multiline import for both allowlist and blocklist entries, with optional `domain|note` rows.
- The Root backend validates every domain and note before the first write, accepts at most 2,000 rows / 64 KiB per batch, and applies the changes through one existing FX transaction. A failed write or failed apply causes the transaction to restore the previous settings.
- Blank lines and comment lines beginning with `#` are ignored. Duplicate domains update their note instead of creating duplicate entries.
- The source updates are committed on `fx-v1.0.0-unified-hook-integration`; no package was produced. Per the current migration instruction, no test workflow was run in this batch.



## Yulong AdBlock 7.0.1 — batch domain import rollback (2026-11-03)

- The Root control backend now supports `allow-import` and `block-import` for multiline domain entries. It validates every row before the first mutation and enforces the 2,000-row / 64 KiB batch limits.
- The native fourth-level domain page exposes separate bulk import editors for the allowlist and blocklist. Rows may use `domain` or `domain|note`; blank lines and comment lines are ignored.
- The shared Yulong Ad transaction now restores the previous settings file if either the mutation function or the FX apply step fails, then reconciles the restored runtime configuration. This closes the partial-write rollback hole that would otherwise matter during a batch import.
- Source changes remain committed to the unified branch. No APK/KernelSU package or test workflow was run in this batch, as requested.

## Dia 23.11 — Android Framework DEX browser integration

- The original `assets/android_framework.dex` is staged into the FX Hook APK build from the preserved source-intake artifact.
- The native Dia DEX browser now indexes this standalone framework DEX as well as installed application APK/split DEX files. It uses the same bounded, read-only parser and displays framework classes, fields and methods without defining or executing inspected code.
- The Framework DEX is shipped inside the single FX Hook APK under `assets/dia/android_framework.dex`; no second APK or external entry is introduced.
- Both the Hook APK and paired KernelSU workflow stage the same source asset. Workflow dispatch remains manual-only during migration; no package was generated for this source change.

## Yulong Shield 9.9.60 — read-only FX module integrity check

- The fourth-level integrity page now supplements the current FX APK signer fingerprint with a Root-backed, read-only inspection of the installed KernelSU module.
- It verifies module identity/version/enabled markers, presence of core FX and migrated Yulong scripts, shell syntax, and the ARM64 QuickJS executable bit.
- The page reports missing or malformed files but does not auto-repair, restart services, force-stop/freeze apps, re-enable the app, or restore accessibility permissions. These invasive legacy SelfDefense actions remain intentionally outside the FX migration.
- Source-only change on the unified branch; no build or device test was run.


## Dia 23.11 — native GPS map picker integration

- Added `FxDiaGpsPickerActivity` inside the single FX Hook APK, restoring the original Dia GPS screen's AMap picker destination at `https://lbs.amap.com/console/show/picker`.
- The map helper accepts AMap's `longitude,latitude` coordinate text, validates coordinate ranges, and returns latitude/longitude to the selected app's existing GPS simulation editor.
- Added the native `高德地图选点` action next to the per-app GPS test fields. Returning from the picker fills the current target's latitude/longitude draft; the existing explicit `保存并发布 GPS 测试位置` action remains the point at which the config is published to LSPosed Remote Files.
- The picker WebView has JavaScript enabled only for the map page, exposes no JavaScript bridge, disables file/content access and mixed content, permits only HTTPS AMap/Gaode navigation, and cancels TLS errors.
- This does not change the device's real GNSS/provider state. GPS mocking remains scoped to an explicitly selected debuggable target process.
- Source commit only; the paired APK/KernelSU package remains deferred until all three application migrations are complete.


## Dia 23.11 — native system Wi-Fi HTTP proxy migration

- Added a dedicated fourth-level `FxDiaWifiProxyActivity` and routed Dia's `HTTP 代理` page to it instead of the generic network settings panel.
- The page configures Android's global `http_proxy` using explicit KernelSU Root authorization. It is separate from the FX VPN, node proxy and Root DNS Proxy; the UI explains that it can affect all apps using the system HTTP proxy.
- Enabling stores the previous global proxy value, applies the requested host/port, and reads the value back. Replacing an already FX-managed proxy preserves the original pre-FX value.
- Disabling restores the saved original value only if the system setting still equals the value last written by FX. When another app or the user has changed it, FX reports a conflict and leaves the external value untouched.
- Default state remains disabled. No ADB/Wireless Debugging pairing implementation is claimed by this Root-only migration.
- Source-only commit on the unified branch; no intermediate APK/KernelSU ZIP was generated.


## Dia 23.11 — GPS provider-enabled simulation migration

- Added an independent per-target option for the original `gps_open_server` behavior. In a selected debuggable target, FX can report `LocationManager.isProviderEnabled()` / `isLocationEnabled()` as enabled without changing actual GPS hardware/provider state.
- The option is separate from coordinate spoofing and from the location-access-block policy. FX does not fake Android permission grants; the OS permission checks remain authoritative.
- The native per-app GPS editor now saves the provider-state option with the existing coordinate fixture and publishes both through the unified LSPosed Remote Files config.
- Source-only commit; no package was generated.


## Dia 23.11 — Wi-Fi proxy Quick Settings tile and conflict recovery

- Added `FxDiaWifiProxyTileService` to the unified FX APK and registered the original Wi-Fi proxy quick-setting entry under the FX identity.
- The tile reads the live Android global `http_proxy` value when it starts listening; it does not create or start any VPN service.
- Tile enable/disable uses the same saved-previous-value and compare-before-restore rules as the native proxy page.
- Added a recovery action that clears only FX's local proxy-management metadata while leaving the current Android proxy value untouched. This lets the user recover from an external-setting conflict without FX overwriting another app's value.
- Source-only commits; no intermediate APK/KernelSU ZIP was produced.


### Yulong Security Shield 9.9.60 — batch-cleanup queue continuity

- Fixed the empty-scan result so repeated scans replace the result content instead of
  appending duplicate summary cards to the page.
- The user-selected batch-uninstall queue now survives Activity recreation and
  process restoration: package list, labels, reasons, current position and already
  missing packages are saved/restored with instance state.
- The queue is capped at 100 entries, validates package identifiers, rechecks
  installation state before opening the system uninstaller, and continues only
  through explicit user actions. FX still never confirms, force-stops, freezes or
  silently uninstalls a target application.


### Yulong Security Shield 9.9.60 — keep-alive permission degradation

- The 15-minute recovery receiver now handles overlay permission revocation the
  same way as boot restoration: it disables only the now-unavailable overlay
  rescue option, records the reason, and recalculates the alarm schedule.
- When the overlay permission is still granted and the service start request is
  accepted, stale overlay-restore errors are cleared. If this was the last enabled
  Shield feature, the next schedule refresh cancels the idle recovery alarm.
- Foreground-service behavior and permission revocation still require Android
  device verification; this change prevents a known repeated wake-up loop but does
  not claim OEM-wide background-survival parity.


### Yulong Security Shield 9.9.60 — install-scan correctness and shared scan preference

- The manual scanner's APK-content switch now reads and writes the same `shield_prefs/automatic_content_scan_enabled` preference used by the Shield automatic-install scanner; the two screens no longer silently diverge.
- Automatic install-scan results now remain explicitly inconclusive when the virus database is empty, the scan throws, or the target package could not be enumerated. Only a completed package scan with no match is reported as "not matched"; failures are never represented as a clean result.
- Risk notifications and their activity PendingIntents now use a stable package-specific ID so separate installed applications do not overwrite one another's warning notification.


### Dia 23.11 — encrypted local and remote backup format

- New backup exports are wrapped in an authenticated AES-256-GCM envelope. The key is derived from a user-entered passphrase using PBKDF2-HMAC-SHA256 (210,000 iterations), a random 16-byte salt and a random 12-byte nonce; the envelope schema is authenticated as AAD.
- A SHA-256 digest catches transport/file corruption before decryption; GCM authentication rejects wrong passwords or modified ciphertext. The passphrase is not persisted in SharedPreferences or the backup file.
- Local JSON, GitHub Contents and HTTPS WebDAV uploads all use the same encrypted envelope. Restore paths decrypt before inspecting the inner FX-DIA backup and continue to verify the embedded settings/Stellar file hashes.
- Legacy `FX-DIA-BACKUP-1` JSON remains importable for compatibility, but it was not encrypted and may contain readable VPN credentials; users should re-export it in the new encrypted format.

## 2026-11-04 — Managed Hosts list backend validation repair

- Removed an accidentally duplicated function tail after the CLI case terminator; latest Actions had stopped at a POSIX shell syntax error on line 262 before executing this regression.
- Domain/block values now pass the same LF, control-byte, separator and AWK-escape checks as subscription values before normalization. This prevents command substitution from silently trimming a trailing newline into a valid domain.
- Failed mutations now reconcile with the apply mode used by that mutation (full for subscription/rule changes; fast for allow/block domain changes).
- The CLI `apply [full|fast]` branch is now reachable before managed-list ID resolution; the default remains full.
- The regression now asserts the checked-in module backend matches the source backend, covers LF inside notes and trailing-LF values, rejects backslash-based AWK escape payloads and invalid subscription edits, and checks rollback/apply mode behavior.
- The current module-tree backend is synchronized from the source implementation. CI must still complete successfully after this repair. No APK/KernelSU ZIP or real-device test is claimed.

## 2026-11-04 — Shield KeepAlive permission-degradation recovery

- Boot recovery now refreshes the alarm only after all permission checks and preference updates, preventing a stale 15-minute alarm when overlay permission was revoked and overlay rescue was the only enabled feature.
- KeepAlive now detects overlay permission revocation, disables only `overlay_rescue_on`, records the permission reason, and then recalculates the schedule. A still-authorized overlay start clears a stale restore error; transient foreground-service start failures keep the user's opt-in so the bounded retry can recover.
- The rescue overlay service now reconciles the KeepAlive alarm when its persisted feature flag is already off, when Android overlay permission has been revoked, and when WindowManager refuses to attach the bubble. Runtime attach failures are recorded rather than silently disabling the feature.
- Extended the Shield native regression to verify private receiver registration, boot/KeepAlive permission ordering, post-degradation schedule recalculation, and overlay-service failure cleanup. This remains host/static verification; OEM background restrictions and actual permission revocation must still be checked on a device.

## 2026-11-04 — Yulong firewall watcher lock publication race

- The exclusive lock path is visible before its four-line PID/protocol/script/start-time record is populated. A contending process can briefly observe a transitional snapshot.
- Lock acquisition now waits briefly and re-reads a snapshot that initially failed identity validation. A changed snapshot is retried; a stable foreign record remains a hard conflict. Stale cleanup compares the settled record before unlinking.
- Existing concurrent start/start and start/stop regression coverage remains the runtime host simulation; static assertions now pin the settle/re-read and compare-before-delete contract.
- Android/OEM background execution still requires device validation. No APK/KernelSU archive is claimed.
