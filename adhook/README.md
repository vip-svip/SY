# FX Hook (LSPosed)

## FX APP unified interface
The FX APK is the single management entrypoint. Its native Android shell embeds the complete 1.0.0 management UI in an app-owned WebView and connects it to the KernelSU backend through an asynchronous `su` bridge. The original VPN, DNS, rules, subscriptions, Hosts, certificate/MITM, privacy, script, Hook, advanced settings, diagnostics, logs, crash and import/export screens are bundled into the APK; the KernelSU module remains the privileged service/backend. The module WebUI is replaced with a migration notice in the final package to avoid two competing management interfaces.

The Hook application manager remains a native Android screen. The built-in Ad classifier is automatic for eligible processes in which LSPosed loads FX; it does not require per-app splash/feed/overlay toggles or a Remote Files target row. The Hook target editor retains opt-in privacy controls, read-only billing diagnostics and custom observe-only rules. Save & Sync publishes only those optional per-app policies to the current Android user's LSPosed Remote Files directory. Runtime activation of the module still requires the user to enable FX in LSPosed Manager and include the desired app packages in its scope. The APP cannot silently grant that scope.

This is a separate opt-in LSPosed module shipped with FX. It does not fake VIP status and never modifies billing results or purchase tokens.

## Activation contract
1. Install or upgrade the FX unified APK and KernelSU module. The installer places the APK as an ordinary Android app under `/data/app`; it does not require a metamodule for APK deployment. Reboot after installation/upgrade so LSPosed can rescan the module. If PackageManager installation fails, the boot service retries and logs to `/data/adb/privacyguard/adhook-install.log`.
2. In LSPosed Manager, enable FX and select the app packages in which the built-in Ad classifier should run. Ad detection is automatic inside those LSPosed-scoped processes; there is no FX Ad master switch or per-app splash/feed/overlay selection.
3. Optional privacy controls, read-only diagnostics and custom observe-only rules are configured separately in the FX Hook app list and published with Save & Sync.
4. Force-stop and reopen target apps after changing LSPosed scope or optional Hook configuration.

Ad detection requires LSPosed to load FX into the target process; it does not require a Remote Files config or a target row. Optional privacy/diagnostic policies require a valid Remote Files config and the corresponding per-app opt-in flags. The target process cannot read root files directly. FX publishes optional policies to `/data/adb/lspd/modules/<user>/de.privacyguard.adhook/files/fx-hook-targets.conf`; the module reads it via modern libxposed API 101 `openRemoteFile()`. If Remote Files is unavailable, missing, unreadable, oversized, or malformed, optional policies fail closed while built-in Ad detection remains active. The parser validates the entire optional payload transactionally: missing/duplicate master switches, duplicate packages/options, invalid flags, unsupported sections, and malformed rows reject the whole optional config instead of activating a partial target list.

## Privacy-hook migration status

The unified API 101 entry contains opt-in Android ID isolation and a first read-time EXIF redaction migration slice. When the unified config has both `privacy_enabled=1` and a target row with `privacy=1`, calls to `Settings.Secure.getString(..., ANDROID_ID)` receive a stable app-specific 16-hex identifier. Other secure settings are passed through unchanged. EXIF redaction is independently selected per target with `exif_strip=1` under the privacy master switch. It redacts GPS, device Make/Model, and DateTime values returned by framework/AndroidX ExifInterface getters; it does not rewrite image files or intercept every third-party metadata parser. These are narrow migration slices, not parity with the legacy PrivacyGuard hook set.

Integration status (2026-10-30): the current FX-v1.0.0 KernelSU archive contains `scripts/gen_xposed_conf.sh`, which translates the root-side `hook_targets` list and independent master switches into the versioned API-101 Remote Files schema (`schema_version=1`). It publishes to `de.privacyguard.adhook/files/fx-hook-targets.conf` and records publication status. The publisher and APK parser must be kept in lockstep; verify the script shipped in the exact ZIP being installed rather than relying on this source-branch README alone. The unified APK carries the legacy API-82 and modern API-101 Hook entrypoints in one installed package. This does not imply identical behavior across every LSPosed host; validate each entrypoint and scope independently. Physical OnePlus 12 / LSPosed behavior remains unverified.

Unified config shape:
```text
schema_version=1
ads_enabled=1
privacy_enabled=0
[list:targets]
com.example.app,ads_splash=1,ads_feed=0,ads_overlay=1,member_diag=0,privacy=0,exif_strip=0
```

## Built-in heuristic rules
- Splash/open-app: `splash_ad`, `splashad`, `ad_splash`, `open_ad`, `launch_ad`, `launchscreenad`, `splashpage`.
- Feed/banner/native: `native_ad`, `feed_ad`, `banner_ad`, `AdView`, `ad_container`, `ad_slot`.
- Interstitial/overlay: `interstitial`, `rewarded_ad`, `fullscreenad`, `ad_dialog`, `ad_popup`, plus scans for `Dialog.show()` and `PopupWindow` display calls.
- Built-in SDK namespace indicators include Google Mobile Ads, Pangle/穿山甲, Tencent 优量汇, Kuaishou, Baidu, AppLovin, Meta, Unity, Sigmob, Huawei HMS Ads, Xiaomi MiMo Ads, and commonly seen OPPO/Vivo/Honor/Meishu packages. Xiaomi developer docs identify `com.miui.zeus.mimo.sdk` and supported ad formats; Huawei documents `com.huawei.hms.ads`. SDK names are indicators, not proof that every matching View is an ad.
- A visible "广告" or "Sponsored" label alone is never enough to hide a view; a strong resource-id/class marker or matching parent container is required.
- Scans are bounded (max 1,800 views/depth 20), triggered on Activity resume, `Dialog.show()` / `PopupWindow` show calls, and late `ViewGroup.addView()` events inside an explicitly LSPosed-scoped target process. Added views and nested descendants are checked after attachment; duplicate callbacks from delegating `addView()` overloads are coalesced. There is no continuous whole-screen polling.
- Class/resource naming is app-specific. No generic heuristic can guarantee all proprietary apps; unrecognized layouts need an app-specific resource/class rule. Because automatic classification runs for eligible LSPosed-scoped processes, test important apps carefully; if a proprietary layout is misclassified, narrow the heuristic in code rather than relying on removed per-app Ad category switches.

## Membership diagnostics
member_diag is read-only. If Google Play Billing is present, it hooks the concrete `BillingResult.getResponseCode()` and `Purchase.getPurchaseState()` getters and records only their numeric values. It intentionally does not claim that abstract `BillingClient` declarations were hooked. It never records SKU/product IDs, account data, purchase JSON or tokens; it never modifies callback results, purchase state or entitlement and is not a VIP unlocker. A status code is diagnostic evidence, not an entitlement override.

## Config validation and tests
The CI runs JVM regression tests for valid metadata-bearing rows, disabled targets, missing master switch, malformed rows, duplicate target/option entries, protected framework packages, invalid package names, and unsupported sections. The build must pass these tests before producing the APK. These are host-side parser tests, not a real-device LSPosed injection test.

## Config
The FX KernelSU archive's root-side generator converts `hook_targets` rows into the versioned Remote Files schema. The old API-82 bridge continues to receive the legacy `xposed.conf`; the API-101 runtime reads only its package-specific Remote Files payload. The two package identities remain distinct until feature migration and package/scope migration are complete:
com.example.app,splash=1,feed=1,overlay=0,member_diag=1|LSPosed应用Hook|1

Within the API-101 payload, `ads_enabled` and `privacy_enabled` are independent masters; legacy `hook_ads_enabled` is translated by the root-side generator and is not itself the Remote Files schema key. API 101 Remote Files support is required; older legacy-only Xposed hosts won't run this modern module. The module's LSPosed scope is intentionally opt-in: choose each target both in FX and in LSPosed Manager.


## Installer boundary
The bundled unified Hook APK is stored under `optional/`, not `system/priv-app/`, and `scripts/install_adhook_app.sh` stages them under `/data/local/tmp` then installs them as ordinary apps. It checks the APK SHA-256, skips unchanged installs, retries a few times, and never edits DNS/VPN/firewall settings. The same helper is exercised by a host-side PackageManager stub test. Note that FX's separate `/system/etc/hosts` overlay still requires a compatible KernelSU metamodule for that hosts feature; this change only removes that requirement from Hook APK deployment.


## Explicit camera access denial

A per-target `camera_access_block=1` option is available under the global privacy master. It intercepts legacy `Camera.open()` and Camera2 `CameraManager.openCamera()` calls and propagates a `SecurityException` to the requesting app. This is an explicit access denial, not a fake "camera hardware absent" response. The option is disabled by default; shared-package processes and unknown targets fail open. It does not alter system camera permission state and does not guarantee coverage of vendor-private camera APIs.

## Per-app MediaStore query privacy

A per-target `media_store_query_block=1` option is available under the global privacy master. It returns an empty cursor only for `content://media` queries from the selected app in a single-package process. Other content providers, direct file access, media writes, and downloads are not intercepted. The feature is disabled by default and fails open for shared-package processes or unrecognized targets. This is a read-query privacy boundary, not a filesystem permission replacement.

## Explicit microphone access denial

A per-target `mic_access_block=1` option is available under the global privacy master. It rejects `AudioRecord.startRecording()` overloads and `MediaRecorder.start()` with a `SecurityException`. This is distinct from `mic_silence=1`, which zeroes successful `AudioRecord.read()` buffers after capture. The access-denial option is disabled by default, does not fabricate noise or spoof microphone hardware state, and fails open for shared-package processes or unknown targets. It does not replace Android runtime permission controls and cannot cover every vendor-specific or native audio capture path.

## Explicit location access denial

A per-target `location_access_block=1` option is available under the global privacy master. It intercepts `LocationManager.getLastKnownLocation()`, `getCurrentLocation()`, `requestLocationUpdates()`, and `requestSingleUpdate()`, then propagates a `SecurityException` to the requesting app. This replaces fake-coordinate and location-spoofing behavior with an explicit access denial. It is disabled by default; shared-package processes and unknown targets fail open. It does not change Android's actual runtime permission grant and does not guarantee coverage of vendor-private location APIs.

## EXIF privacy migration slice

The API-101 module supports an opt-in `exif_strip=1` feature independently per target, under the global privacy master switch. It redacts GPS, Make/Model, and DateTime values returned by framework/AndroidX ExifInterface getters only; it does not rewrite files or intercept every third-party EXIF parser. The matching source snapshot is published alongside the APK in GitHub Actions.


Clipboard read protection is a separate opt-in per-target privacy feature (`clipboard_read_block=1`). It blocks `getPrimaryClip`, `hasPrimaryClip`, and legacy `getText` reads while leaving clipboard writes untouched. To avoid cross-package side effects, it fails open in processes where more than one package is loaded.


### Direct EXIF location accessors

The EXIF migration also intercepts `getLatLong(float[])` and returns `false` without writing coordinates, and intercepts `getAltitude(double)` to return the caller-supplied fallback. This closes common direct-access paths in the Android framework and AndroidX ExifInterface. It remains read-time API redaction only; it does not rewrite image bytes or cover arbitrary metadata parsers.


### Clipboard isolation (API-101, 2026-10-30)

`clipboard_isolate` is a distinct per-target privacy feature, gated by both `privacy_enabled=1` and `clipboard_isolate_enabled=1`. It shadows successful `setPrimaryClip(ClipData)` writes within the current process and returns that process-local shadow for `getPrimaryClip()` / `hasPrimaryClip()`. Shared-package processes fail open. It conflicts with `clipboard_read_block`; the parser rejects a target enabling both. This is process-local shadowing, not OS-wide cross-app clipboard isolation. CI build and device validation status are tracked separately.


### Single-APK merge status (2026-10-30)

The API-101 app is the intended future unified runtime, but it is not yet a replacement for the API-82 module. The two packages have different application IDs, Hook APIs, entrypoint lifecycles, config transports, and minimum Android versions. Do not merge by simply renaming package IDs or removing the legacy APK. See `docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md` for migration policy, upgrade/rollback requirements, and features that must not be ported as stealth/evasion behavior. The current KernelSU installer intentionally preserves both APKs until feature parity and a signing-compatible upgrade path are proven.
