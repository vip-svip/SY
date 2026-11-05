# FX Hook migration next steps

## Verified legacy source availability (2026-10-30)

The complete legacy source needed for migration is present in the user's current Library archive `FX-v1.0.0-KernelSU.zip`, extracted in the active working copy at:

`lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java`

Verified size: 2,073 lines / 96,340 bytes. This is the full historical API-82 entrypoint in the supplied FX ZIP, not the much smaller 8 KB `MainHook.java` found on the old GitHub branch. The Iter5 archive itself is not separately present in the Library listing; do not conflate the two.

The source declares `IXposedHookLoadPackage`, `XC_MethodHook`, `XposedBridge`, and `XposedHelpers`, and reads `/data/local/tmp/privacyguard/xposed.conf`. It cannot be copied unchanged into the API-101 module: the callback API differs and target-app processes must use LSPosed Remote Files rather than assuming root-side config paths are readable.

## Migration requirements

Preserve the full legacy feature inventory and per-feature switches while porting API-82 callbacks to libxposed API 101. The single-APK dual-entry packaging is now built and verified in CI; this does not mean all 75 legacy switches have been migrated or that device injection is verified.

Configuration must be read through LSPosed Remote Files, parsed transactionally, and support independent ad and privacy switches. Invalid, missing, oversized, malformed, or unsupported configuration must install no hooks.

## Current verified state (2026-11-01)

- The modern `AdVisibilityHook` runtime uses `UnifiedHookConfigParser.parse(content)` and LSPosed Remote Files. Missing, malformed or unsupported configuration remains fail-closed.
- The legacy API-82 `MainHook.java` source (2,073 lines / 96,340 bytes) is copied into the same APK and retained as a legacy Xposed entrypoint. The APK has one applicationId, `de.privacyguard.adhook`, with the legacy entrypoint and modern libxposed API-101 `AdVisibilityHook` entrypoint. The old standalone legacy APK is not packaged as a second app.
- API-101 currently wires package-scoped automatic ad View recognition, read-only Billing/member diagnostics, Android ID transformation, EXIF redaction, clipboard-read policy, process-local clipboard isolation, sensor enumeration/rate policy, Wi-Fi scan suppression, notification-listener read suppression, notification permission-query masking, microphone silence, explicit microphone/camera/location access denial, and MediaStore query suppression. These are narrower behaviors than several legacy spoofing/hiding switches; they must not be labeled full API-82 parity.
- `notification_permission_hide` and `clipboard_isolate` are no longer dormant: the native target editor, publisher master/per-target fields, parser/serializer, runtime gates, status reporting and regression coverage are wired. Clipboard isolation is process-local shadow state, not OS-wide cross-app isolation. Notification permission masking changes only selected app-visible permission-query results; it does not revoke or grant Android permissions.
- API-101 also includes Chinese rewarded-flow UI evidence, bounded member DEX candidate scanning, dynamic class-load observation, and capped read-only candidate getter hooks. Billing and membership handling remain read-only: never synthesize rewarded-ad callbacks, purchases, or server-side entitlements.
- The six-tab FX APP shell and native Hook hub are integrated into one APK. The existing complex management dashboard is bundled locally in an app-owned WebView; the per-app Hook manager is native Android UI. This is a single app entrypoint, not a complete rewrite of every dashboard widget as native views.
- The KernelSU package workflow restores the complete module source, builds and embeds the unified APK, and fails closed if required module files are missing. CI run `41250822004` passed APK v2 signature verification, the complete 302-test package regression suite, ZIP checksums and the embedded/external APK digest comparison. A separate source-migration run also passed 301 host regressions and the Hook APK build.
- No OnePlus 12 + KernelSU + LSPosed physical-device injection or behavior verification has been performed. Host tests and CI APK compilation do not prove OEM runtime behavior.

## Remaining migration sequence

1. Complete the method-by-method audit of all 75 legacy switches against the recovered `MainHook.java`, native UI, config publisher, modern runtime and legacy duplicate-suppression map.
2. Continue porting deterministic, low-risk privacy protections with independent opt-in switches, package-scope checks, API guards, and fail-open compatibility behavior. The bounded membership observer is diagnostic-only and must not change entitlement state.
3. Keep destructive or high-breakage transforms (package/process hiding, telephony, GNSS/location spoofing, hardware identity spoofing, filesystem and system-property manipulation) disabled until each has dedicated API/OEM regression tests.
4. Expand host tests for each retained API-101 behavior and verify that its legacy duplicate is suppressed only for the same package/feature. Do not treat parser/serializer presence as runtime parity.
5. The single-APK identity, both Xposed entrypoints, native Hook manager, Remote Files transport and KernelSU APK embedding are already built in CI; remaining work is feature parity, not another APK merge.
6. Require OnePlus 12 + KernelSU + LSPosed injection, per-feature behavior, reboot/upgrade/uninstall and rollback verification before calling the deliverable device-complete.


## Legacy runtime switch inventory

A direct scan of the recovered 2,073-line API-82 `MainHook.java` found **75 distinct literal `on("...")` switches**. This count is enforced by `scripts/tests/v1.0.0-fxhook-migration-baseline-regression.sh` against both the source and the 75-row migration matrix. Two entries are legacy literal labels (`Camera disabled by PrivacyGuard` and `Permission denied`); they are included because the runtime checks them through the same `on(...)` gate.

| Feature group | Legacy switches | API-101 migration status |
|---|---|---|
| Device/build identity | `spoof_model`, `spoof_manufacturer`, `spoof_brand`, `spoof_hardware`, `spoof_fingerprint`, `spoof_version`, `patch_spoof`, `spoof_baseband`, `spoof_android_id`, `spoof_serial`, `spoof_imei`, `spoof_sim`, `telephony`, `block_cell_info` | Android ID only has a narrower modern opt-in transform; the other switches are not migrated |
| Radio/device state | `spoof_bt_mac`, `spoof_wifi_mac`, `spoof_battery`, `spoof_screen`, `spoof_storage` | Not migrated |
| Kernel/root/filesystem | `block_kernel_version`, `hide_kernel_debug`, `block_logcat`, `hide_su`, `hide_magisk`, `hide_ksu`, `block_rootcheck_libs`, `block_mounts`, `hide_mounts`, `hide_sysfs_nodes`, `fs_hide`, `fs_isolate`, `fs_rootlist`, `fs_attrs`, `fs_vfs` | Not migrated; keep disabled pending API/OEM tests |
| System/app visibility | `syssvc_hide`, `app_list`, `block_pm_query`, `block_process_list`, `k_task`, `block_mediastore`, `block_net_ifaces`, `block_netstats`, `vpn_hide` | Not migrated; high compatibility risk |
| Clipboard/input/notifications | `clipboard`, `clipboard_isolate`, `block_ime_logging`, `block_notif_listen`, `hide_notif_perm`, `usagestats_off`, `a11y_hide` | Clipboard read policy and process-local clipboard isolation are wired with separate master/per-target gates; notification-listener read suppression and permission-query masking are also wired. These are limited API-level behaviors, not OS-wide isolation or permission changes. IME, usage and accessibility data protections remain unported |
| Location/Wi-Fi | `mock_location`, `perapp_mock`, `gps`, `gps_accuracy`, `gnss_spoof`, `disable_passive_loc`, `block_wifi_scan` | Wi-Fi scan partially migrated; all location/GNSS switches not migrated |
| Sensors | `sensor_accel`, `sensor_gyro`, `sensor_light`, `sensor_magnet`, `sensor_pressure`, `sensor_prox`, `sensor_rate_limit` | Partially migrated with modern sensor selection/rate-limit policies; not full API-82 parity |
| Camera/audio/biometrics | `cam_null`, `cam_hw_hide`, `mic_block`, `mic_hw_hide`, `audio_fp_block`, `hide_fingerprint_hw`, `hide_face_hw` | Not migrated |
| Metadata/advertising ID | `exif_strip`, `ad_id_unify` | EXIF read-time redaction is partially migrated; Advertising ID unification is not |

Do not treat a parsed or serialized switch as an implemented hook. A switch becomes migrated to API-101 only when its runtime behavior, package scope, independent opt-in, API guards, fail-open path and unit/host regression are accounted for; physical-device validation remains a separate acceptance gate. “Not migrated to API-101” does not mean absent from the unified APK: allowed legacy controls remain in the bundled legacy Xposed entrypoint. High-risk keys in `DISABLED_EVASION_KEYS` are deliberately disabled, and API-101-owned keys are suppressed in the legacy entrypoint to avoid duplicate hooks.


## Historical KernelSU source-layout blocker (resolved in CI, source-layout debt remains)

The GitHub branch's `fx-module/` subtree is still intentionally incomplete as a tracked source tree. The package workflow now restores the full module source from the published FX archive before applying reviewed patches, building QuickJS-NG and embedding the unified Hook APK. It validates required entrypoints and fails closed rather than emitting a partial ZIP.

This makes the current CI package build successful, but the build still depends on the published source archive as the source of truth for much of the module. Long-term maintainability would improve by tracking the complete module tree in GitHub rather than relying on release-archive restoration. The 2026-11-01 CI package contains one `optional/FXUnifiedHook.apk` with both Hook entrypoints; it does not ship separate `PrivacyGuardHook.apk` and `FXAdHook.apk` packages. The 75-switch API-101 feature-parity audit remains open.


## 2026-10-30 continuation — Wi-Fi scan and notification migration

- Migrated the historical `block_wifi_scan` behavior into API 101 as two independently validated gates: the existing global master (`wifi_scan_enabled`) and per-app target flag (`wifi_scan_block`).
- Runtime intercepts only `WifiManager.getScanResults()`, `startScan()`, and `isScanAlwaysAvailable()`; network association, DNS, VPN and socket paths are untouched.
- Shared-package processes and protected packages fail open. The old API 82 implementation remains in place until full parity and single-APK consolidation are complete.
- Host-side parser/serializer/policy checks and Android CI build pass; real-device injection and behavior remain pending.


## 2026-10-30 continuation — API-101 config/notification verification

- The FX KernelSU ZIP root-side publisher `scripts/gen_xposed_conf.sh` emits the versioned API-101 Remote Files schema; the old API-82 `xposed.conf` consumer remains separate.
- API-101 parses/serializes `notification_listen_enabled` + per-target `notification_listen_block`, and the FX publisher emits those fields.
- At the time of this 2026-10-30 note, permission-query masking was parser/runtime-only and dormant. It was subsequently wired through the native target editor, publisher, status reporting and regression suite; see the current verified state above.
- Active-notification read suppression is limited to selected read APIs; OS permission state and notification posting/display are not changed.
- Policy tests verify shared-package/protected-package/master-off fail-open behavior. CI run `41074509939` passed unit tests, APK assembly, signature verification, Xposed resource checks, and DEX marker checks.
- APK SHA-256: `3a113bcecedd203f7aab32f1b84803a85cd11282b4ec47d4ddbec1b819bf8822`. Standalone API-101 debug artifact only; not merged with API-82. No physical OnePlus 12 verification.


## 2026-10-30 continuation — notification permission-query wiring

- Updated the FX 1.0.0 package working copy to wire the existing `hide_notif_perm` master to API-101 `notification_permission_hide_enabled` and per-target `notification_permission_hide_block` to `notification_permission_hide`.
- Updated `scripts/apply.sh` publication gating so this feature alone triggers Remote Files publication when targets are selected.
- Updated `scripts/status.sh` JSON and FXHook UI status counts for this master/target pair.
- Updated per-app editor parse/default/validation/save paths; UI description explicitly says this masks only the app-visible permission-status query and does not alter Android authorization.
- Regression tests: Remote Files end-to-end fixture, notification migration, remote status JSON, Wi-Fi scan, migration baseline, package completeness; all pass. All 33 inline JavaScript blocks pass `node --check`; shell syntax checks pass.
- These root-side files are not present in the Hook-only GitHub branch, so this patch is in the current FX KernelSU ZIP working copy. It has not been tested on OnePlus 12 with LSPosed.


## 2026-10-30 continuation — clipboard isolation audit

- Audited legacy API-82 `clipboardGuard()`: `clipboard_isolate` caches the process's own successful `setPrimaryClip()` value and shadows `getPrimaryClip()` / `hasPrimaryClip()` reads. It is process-local shadow state, not OS-level cross-app isolation.
- API-101 `clipboard_read_block` is not equivalent and must not be used as a substitute.
- Added detailed migration acceptance criteria to `docs/FXHOOK-MIGRATION-MATRIX.md` and `docs/FXHOOK-CLIPBOARD-ISOLATION-AUDIT.md` in the FX 1.0.0 working ZIP.
- At the time of this audit, API-101 clipboard-isolation wiring was pending. It was subsequently implemented with process-local shadow state and separate master/per-target controls; no device verification.


## 2026-10-30 — clipboard isolation migration completed in CI/package

- API-101 parser, serializer, and runtime now implement distinct clipboard isolation master/per-target config and process-local shadow hooks.
- Root FX package working copy wires editor, publisher, apply publication gate, and status JSON/UI.
- CI run `41080488374` passed unit tests, Android debug APK build, signing/metadata checks, and DEX markers; APK SHA-256 `778b07f84b924629969a849c4ef2b8ce68df3bed277e638190f583b2e79d9991`.
- Shared processes fail open; `clipboard_isolate` and `clipboard_read_block` are mutually exclusive. This is not OS-wide cross-app isolation.
- At the time of this 2026-10-30 entry, APK consolidation was still pending. It was subsequently completed in CI as one dual-entry APK; remaining acceptance is OnePlus 12 physical-device LSPosed testing and the remaining legacy Hook migration.

## 2026-11-05 — Dia Activity entry observer event rendering

- The new appentry Frida template emits [DIA_APPENTRY] metadata records, but the native monitor-event parser previously treated that tag as unknown and silently discarded every record. The parser now maps it to the Activity 入口 category.
- The allowlist retains only stage, Activity class name, Intent action and Intent package. It intentionally drops Intent extras, URI/data, component objects and arbitrary payload fields; the existing safe-value grammar and event/input bounds remain active.
- Added JUnit coverage plus a standalone JDK host regression that compiles the exact production parser with javac -Xlint:all -Werror and checks APPENTRY visibility without leaking Intent payload.
- Verification scope: parser host test only. Android Gradle build, Frida injection, and OnePlus 12 + KernelSU + LSPosed behavior remain unverified on a physical device.

## 2026-11-05 — Fix Yulong VPN controller regression fixture

- The workflow host regression creates a temporary scripts/util.sh with pg_get/pg_set and exports MP/PG for child shell scripts, but later calls pg_set directly in the parent test shell without sourcing util.sh there. This made the suite stop at the no-external-VPN rollback case with `pg_set: not found`, before later checks or Android build.
- Source the same temporary helper in the test process after its fixture is created. Production controller behavior is unchanged; the test now exercises the actual helper contract it already declared.
- Verification scope: source-level fixture correction and shell syntax to be checked; full GitHub workflow and device behavior are not represented as passed.

## 2026-11-05 — Dia regex/resource-ID automatic click migration

- The original ClickBtnHook/ViewHelper implements active matching and clicking (TextView regex or resource ID, delayed main-thread performClick); FX previously had only a passive View.performClick observer. Added a separate native Dia page and executable Frida asset to restore this behavior without replacing the existing observer.
- The template is inert by default: both regex and ID rule arrays are empty. The user must edit explicit rules in the script editor and manually inject into the selected test target. It checks clickable/enabled/visible state, uses the Android UI thread, logs no button text, clamps delay to 0–10 seconds, and bounds scans to 1,500 nodes/depth 28 and eight scheduled clicks per process.
- The Dia monitor regression now verifies the page, loader, default-off rules, bounds, UI-thread execution and Node syntax. The original ViewGroup dialog-removal behavior is still separate and is not claimed as migrated here.
- Verification scope remains source regression and JavaScript syntax until the Android APK and a permitted target-app runtime are exercised.

## 2026-11-05 — Dia ViewGroup rule-based dialog removal

- Compared original ViewGroupHook/ViewGroupHook$1 Smali: the old hook reads alert_keyword/alert_id/disable_alert_mode, inspects view subtrees after addView and removes matched child views on the UI draw lifecycle. FX previously exposed only a ViewGroup hierarchy observer.
- Added a separate native Dia page and Frida asset for rule-based removal. Rules default empty and require manual injection. Default scope deliberately matches the original safe mode: only direct additions to DecorView or android.R.id.content; it never climbs from a nested addView and risks deleting an entire Activity content hierarchy. ALLOW_ANY_PARENT is an explicit opt-in, default false.
- Matching uses TextView regular expressions or resource names/IDs; matched text is not logged. Removal runs on Android's main thread and is bounded to 1,500 nodes/depth 28, five removals per process, eight 100 ms rechecks and 64 pending roots. Queue growth is capped.
- Expanded the Dia regression to check loader/menu wiring, empty-by-default rules, direct-root scope, operation limits, main-thread mutation and Node syntax. The auto-click tree queue now has the same strict outstanding-node bound.
- The Yulong widget regression's default “启动 VPN” caption belongs to the XML layout and is already checked there. The Provider replaces it with dynamic labels such as “启动防护”, “重试启动” and “停止 VPN” when refreshing live state; removed the stale assertion that incorrectly required the static default caption inside Java Provider code.
- Verification scope: source changes committed; latest GitHub workflow must still pass. Android build, Frida injection and physical-device runtime remain unverified.

## 2026-11-05 — Yulong schedule lock owner-publication grace

- Concurrency regression on Actions observed two distinct watcher PIDs during eight simultaneous starts. The lock already uses atomic `mkdir` plus atomic owner-file publication, but its ownerless-directory recovery grace was only five 200 ms probes. Under CI scheduling pressure, a contender could mistake a just-created lock directory (whose winner had not yet published the owner record) for an abandoned lock and remove it while the winner still held it.
- Increased only the ownerless-publication grace from 1 second to 12 seconds (60 probes). The overall lock acquisition timeout remains the existing bound; a genuinely orphaned ownerless lock is still reclaimable, but not during a short scheduler pause.
- This is a production lock-behavior correction, not a test-count relaxation. Re-run the existing concurrent-start regression before claiming the race is resolved; Android device filesystem/process behavior still needs device validation.
