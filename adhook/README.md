# FXAdHook (LSPosed)

This is a separate opt-in LSPosed module shipped with FX. It does not fake VIP status and never modifies billing results or purchase tokens.

## Activation contract
1. In FX WebUI, enable the master switch and select one or more installed apps with ad categories.
2. Reboot after installing/upgrading FX so Android scans the FXAdHook system app.
3. In LSPosed Manager, enable FX Ad Hook and include the exact same apps in its scope.
4. Force-stop and reopen the target app after changing configuration.

Effects require both gates: the app is listed in xposed.conf as a selected target and LSPosed actually loads this module into that process. Missing or invalid config is a no-op.

## Built-in heuristic rules
- Splash/open-app: `splash_ad`, `splashad`, `ad_splash`, `open_ad`, `launch_ad`, `launchscreenad`, `splashpage`.
- Feed/banner/native: `native_ad`, `feed_ad`, `banner_ad`, `AdView`, `ad_container`, `ad_slot`.
- Interstitial/overlay: `interstitial`, `rewarded_ad`, `fullscreenad`, `ad_dialog`, `ad_popup`, plus scans for `Dialog.show()` and `PopupWindow` display calls.
- Built-in SDK namespace indicators include Google Mobile Ads, Pangle/穿山甲, Tencent 优量汇, Kuaishou, Baidu, AppLovin, Meta, Unity, Sigmob, Huawei HMS Ads, Xiaomi MiMo Ads, and commonly seen OPPO/Vivo/Honor/Meishu packages. Xiaomi developer docs identify `com.miui.zeus.mimo.sdk` and supported ad formats; Huawei documents `com.huawei.hms.ads`. SDK names are indicators, not proof that every matching View is an ad.
- A visible "广告" or "Sponsored" label alone is never enough to hide a view; a strong resource-id/class marker or matching parent container is required.
- Scans are bounded (max 1,800 views/depth 20), triggered on Activity resume and `Dialog.show()` / `PopupWindow` show calls, and retried four times; no continuous polling.
- Class/resource naming is app-specific. No generic heuristic can guarantee all proprietary apps; unrecognized layouts need an app-specific resource/class rule. If a target app misclassifies a broad SDK namespace, disable that category for that app rather than enabling all categories globally.

## Membership diagnostics
member_diag is read-only. If Google Play Billing's BillingClient class is present, it records method names and result types only. It does not alter returned results, entitlement flags, purchase state, SKU, account data, or purchase tokens; it is not a VIP unlocker.

## Config
The main FX module publishes list:hook_targets rows in this form:
com.example.app,splash=1,feed=1,overlay=0,member_diag=1|LSPosed应用Hook|1

Top-level hook_ads_enabled=1 is required. lsposed_enabled controls the older PrivacyGuard hooks, not this separately-scoped ad module.
