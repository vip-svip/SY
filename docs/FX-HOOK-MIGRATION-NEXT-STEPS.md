# FX Hook migration next steps

## Verified legacy source availability (2026-10-30)

The complete legacy source needed for migration is present in the user's current Library archive `FX-v1.0.0-KernelSU.zip`, extracted in the active working copy at:

`lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java`

Verified size: 2,073 lines / 96,340 bytes. This is the full historical API-82 entrypoint in the supplied FX ZIP, not the much smaller 8 KB `MainHook.java` found on the old GitHub branch. The Iter5 archive itself is not separately present in the Library listing; do not conflate the two.

The source declares `IXposedHookLoadPackage`, `XC_MethodHook`, `XposedBridge`, and `XposedHelpers`, and reads `/data/local/tmp/privacyguard/xposed.conf`. It cannot be copied unchanged into the API-101 module: the callback API differs and target-app processes must use LSPosed Remote Files rather than assuming root-side config paths are readable.

## Migration requirements

Preserve the full legacy feature inventory and per-feature switches while porting API-82 callbacks to libxposed API 101. Do not silently drop legacy features or claim the two APKs are unified until CI builds a single APK and device injection is verified.

Configuration must be read through LSPosed Remote Files, parsed transactionally, and support independent ad and privacy switches. Invalid, missing, oversized, malformed, or unsupported configuration must install no hooks.

## Current verified state

- The modern `AdVisibilityHook` runtime uses `UnifiedHookConfigParser.parse(content)` and LSPosed Remote Files.
- The legacy entrypoint is 2,073 lines / 96,340 bytes in the current FX ZIP; it is available for source migration.
- The modern API-101 runtime contains package-scoped ad View observers, read-only Billing diagnostics, Android ID transformation, EXIF redaction, clipboard-read policy, and sensor privacy policy. Source presence is not proof of device behavior.
- API-101 now includes Chinese rewarded-flow UI evidence, bounded member DEX candidate scanning, dynamic class-load observation, and capped read-only candidate getter hooks. GitHub Actions verified compilation, signing, Xposed resources and the expected DEX markers; no OnePlus 12 runtime verification has been performed.
- Billing and membership handling must remain read-only. Never synthesize rewarded-ad callbacks, purchases, or server-side entitlements.
- The two APK package identities remain separate: `de.privacyguard.hook` and `de.privacyguard.adhook`.
- The KernelSU module package workflow must fail closed if required module source files are missing; never emit a partial ZIP.

## Remaining migration sequence

1. Create a method-by-method inventory from the supplied 2,073-line legacy source and map each switch to its existing UI/config key.
2. Continue porting deterministic, low-risk privacy protections with independent opt-in switches, package-scope checks, API guards, and fail-open compatibility behavior. The bounded membership observer is diagnostic-only and must not change entitlement state.
3. Keep destructive or high-breakage transforms (package/process hiding, telephony, location, camera/microphone, filesystem and system-property manipulation) disabled until each has dedicated API/OEM regression tests.
4. Port the ad runtime and read-only membership diagnostics without changing ad reward callbacks, purchase state, or server-side validation.
5. Consolidate package identity, LSPosed metadata, entrypoint, target scope and Remote Files transport only after every retained feature has an explicit migration status and the single APK builds in CI.
6. Require host regression tests, APK signature/resource checks, and separate OnePlus 12 LSPosed injection/behavior verification before calling the deliverable complete.


## Legacy runtime switch inventory

A direct scan of the recovered 2,073-line API-82 `MainHook.java` found **73 distinct literal `on("...")` switches**. This is the verified Java runtime inventory; older UI/migration notes may count additional presentation/configuration keys separately.

| Feature group | Legacy switches | API-101 migration status |
|---|---|---|
| Device/build identity | `spoof_model`, `spoof_manufacturer`, `spoof_brand`, `spoof_hardware`, `spoof_fingerprint`, `spoof_version`, `patch_spoof`, `spoof_baseband`, `spoof_android_id`, `spoof_serial`, `spoof_imei`, `spoof_sim`, `telephony`, `block_cell_info` | Android ID only has a narrower modern opt-in transform; the other switches are not migrated |
| Radio/device state | `spoof_bt_mac`, `spoof_wifi_mac`, `spoof_battery`, `spoof_screen`, `spoof_storage` | Not migrated |
| Kernel/root/filesystem | `block_kernel_version`, `hide_kernel_debug`, `block_logcat`, `hide_su`, `hide_magisk`, `hide_ksu`, `block_rootcheck_libs`, `block_mounts`, `hide_mounts`, `hide_sysfs_nodes`, `fs_hide`, `fs_isolate`, `fs_rootlist`, `fs_attrs`, `fs_vfs` | Not migrated; keep disabled pending API/OEM tests |
| System/app visibility | `syssvc_hide`, `app_list`, `block_pm_query`, `block_process_list`, `k_task`, `block_mediastore`, `block_net_ifaces`, `block_netstats`, `vpn_hide` | Not migrated; high compatibility risk |
| Clipboard/input/notifications | `clipboard`, `clipboard_isolate`, `block_ime_logging`, `block_notif_listen`, `hide_notif_perm`, `usagestats_off`, `a11y_hide` | Clipboard read policy is partially migrated under a new explicit switch; remaining switches are not migrated |
| Location/Wi-Fi | `mock_location`, `perapp_mock`, `gps`, `gps_accuracy`, `gnss_spoof`, `disable_passive_loc`, `block_wifi_scan` | Not migrated |
| Sensors | `sensor_accel`, `sensor_gyro`, `sensor_light`, `sensor_magnet`, `sensor_pressure`, `sensor_prox`, `sensor_rate_limit` | Partially migrated with modern sensor selection/rate-limit policies; not full API-82 parity |
| Camera/audio/biometrics | `cam_null`, `cam_hw_hide`, `mic_block`, `mic_hw_hide`, `audio_fp_block`, `hide_fingerprint_hw`, `hide_face_hw` | Not migrated |
| Metadata/advertising ID | `exif_strip`, `ad_id_unify` | EXIF read-time redaction is partially migrated; Advertising ID unification is not |

Do not treat a parsed or serialized switch as an implemented hook. A switch becomes migrated only when its runtime behavior, package scope, independent opt-in, API guards, fail-open path, unit/host regression and device validation are all accounted for.


## KernelSU packaging blocker confirmed

The GitHub branch's `fx-module/` subtree currently contains only 7 tracked paths. The package workflow requires, among others, `customize.sh`, `post-fs-data.sh`, `uninstall.sh`, `fx-module/scripts/apply.sh`, `default.conf`, `util.sh`, `certmgr.sh`, and `webroot/index.html`; these required files are not present under that subtree. The workflow correctly fails closed and must not emit a partial KernelSU ZIP.

The current Library FX ZIP has the full module source at its archive root (including the root entrypoints, `scripts/`, and `webroot/`), not under `fx-module/`. Restoring the full module tree into the GitHub build layout is a separate required step before a complete GitHub KernelSU package can be produced. The successful API-101 Hook APK artifact is not yet embedded in that ZIP.
