# FXAdHook (LSPosed)

This is a separate opt-in LSPosed module shipped with FX. It does not fake VIP status and never modifies billing results or purchase tokens.

## Activation contract
1. In FX WebUI, enable the master switch and select one or more installed apps with ad categories.
2. The FX installer places both Hook APKs as ordinary Android apps under `/data/app` via PackageManager. This does not require a metamodule for the Hook APKs. Reboot after installing/upgrading FX so LSPosed scans the module; if install-time PackageManager installation fails, the boot service retries and logs to `/data/adb/privacyguard/adhook-install.log`.
3. In LSPosed Manager, enable FX Ad Hook and include the exact same apps in its scope.
4. Force-stop and reopen the target app after changing configuration.

Effects require both gates: the app is listed in the FX-generated target config and LSPosed actually loads this module into that process because the same package is in LSPosed Manager scope. The target process cannot read root files directly. FX publishes only the small hook target list to `/data/adb/lspd/modules/<user>/de.privacyguard.adhook/files/fx-hook-targets.conf`; the module reads it via modern libxposed API 101 `openRemoteFile()`. If Remote Files is unavailable, missing, unreadable, oversized, or malformed, it fails closed/no-op. The parser validates the entire payload transactionally: missing/duplicate master switches, duplicate packages/options, invalid flags, unsupported sections, and malformed rows reject the whole config instead of activating a partial target list.

## Privacy-hook migration status

The unified API 101 entry contains opt-in Android ID isolation and a first read-time EXIF redaction migration slice. When the unified config has both `privacy_enabled=1` and a target row with `privacy=1`, calls to `Settings.Secure.getString(..., ANDROID_ID)` receive a stable app-specific 16-hex identifier. Other secure settings are passed through unchanged. EXIF redaction is independently selected per target with `exif_strip=1` under the privacy master switch. It redacts GPS, device Make/Model, and DateTime values returned by framework/AndroidX ExifInterface getters; it does not rewrite image files or intercept every third-party metadata parser. These are narrow migration slices, not parity with the legacy PrivacyGuard hook set.

Important: the current FX root-side publisher still emits the legacy ad-only format. The parser deliberately forces privacy off for that format, so this privacy hook will remain inactive until the root-side generator and UI are migrated to publish the versioned unified schema. Do not enable it by manually changing unrelated legacy switches. This work has not been verified on a physical device.

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
- Scans are bounded (max 1,800 views/depth 20), triggered on Activity resume, `Dialog.show()` / `PopupWindow` show calls, and late `ViewGroup.addView()` events inside an explicitly LSPosed-scoped target process. Added children are checked after attachment and only their bounded subtree is scanned; there is no continuous whole-screen polling.
- Class/resource naming is app-specific. No generic heuristic can guarantee all proprietary apps; unrecognized layouts need an app-specific resource/class rule. If a target app misclassifies a broad SDK namespace, disable that category for that app rather than enabling all categories globally.

## Membership diagnostics
member_diag is read-only. If Google Play Billing is present, it hooks the concrete `BillingResult.getResponseCode()` and `Purchase.getPurchaseState()` getters and records only their numeric values. It intentionally does not claim that abstract `BillingClient` declarations were hooked. It never records SKU/product IDs, account data, purchase JSON or tokens; it never modifies callback results, purchase state or entitlement and is not a VIP unlocker. A status code is diagnostic evidence, not an entitlement override.

## Config validation and tests
The CI runs JVM regression tests for valid metadata-bearing rows, disabled targets, missing master switch, malformed rows, duplicate target/option entries, protected framework packages, invalid package names, and unsupported sections. The build must pass these tests before producing the APK. These are host-side parser tests, not a real-device LSPosed injection test.

## Config
The main FX module publishes list:hook_targets rows in this form; the root-side generator mirrors only `hook_ads_enabled` and this list into LSPosed Remote Files:
com.example.app,splash=1,feed=1,overlay=0,member_diag=1|LSPosed应用Hook|1

Top-level hook_ads_enabled=1 is required. `lsposed_enabled` controls the older PrivacyGuard hooks, not this separately-scoped ad module. API 101 Remote Files support is required; older legacy-only Xposed hosts won't run this modern module. The module's LSPosed scope is intentionally opt-in: choose each target both here and in LSPosed Manager.


## Installer boundary
The bundled Hook APKs are stored under `optional/`, not `system/priv-app/`, and `scripts/install_adhook_app.sh` stages them under `/data/local/tmp` then installs them as ordinary apps. It checks the APK SHA-256, skips unchanged installs, retries a few times, and never edits DNS/VPN/firewall settings. The same helper is exercised by a host-side PackageManager stub test. Note that FX's separate `/system/etc/hosts` overlay still requires a compatible KernelSU metamodule for that hosts feature; this change only removes that requirement from Hook APK deployment.


## EXIF privacy migration slice

The API-101 module supports an opt-in `exif_strip=1` feature independently per target, under the global privacy master switch. It redacts GPS, Make/Model, and DateTime values returned by framework/AndroidX ExifInterface getters only; it does not rewrite files or intercept every third-party EXIF parser. The matching source snapshot is published alongside the APK in GitHub Actions.


Clipboard read protection is a separate opt-in per-target privacy feature (`clipboard_read_block=1`). It blocks `getPrimaryClip`, `hasPrimaryClip`, and legacy `getText` reads while leaving clipboard writes untouched. To avoid cross-package side effects, it fails open in processes where more than one package is loaded.
