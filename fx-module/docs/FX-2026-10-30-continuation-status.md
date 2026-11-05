# FX 1.0.0 continuation status — 2026-10-30

## Completed in this continuation

- Added a focused bottom-navigation persistence repair to `webroot/index.html`:
  - bottom navigation is a non-shrinking final flex row of `#screen`;
  - explicit visibility, opacity, pointer-event and z-index protection;
  - lifecycle recovery on `pageshow`, viewport resize/orientation change and return from background;
  - if the navbar or one of its original tab buttons is detached, the guard restores it to the app shell;
  - five original tabs and their existing click handlers are retained; no visual redesign.
- Added `scripts/tests/v1.0.0-bottom-nav-persistence-regression.sh`.
- Confirmed external editor round-trip is already present in this package: `fileedit.sh` has guarded `import-external`, and the WebUI polls stable hashes before importing the external editor's saved copy.

## Static validation performed

- Bottom-navigation persistence regression: PASS.
- UI startup/layout integration regression: PASS.
- VPN responsive controls regression: PASS.
- LSPosed APK structure/entrypoint/checksum regression: PASS.
- LSPosed Remote Files config regression: PASS.
- LSPosed target-scope regression: PASS.
- External VPN + DNS fail-open regression: PASS.
- DNS lifecycle fail-open/uninstall regression: PASS.
- CA/MITM lifecycle integration regression: PASS.
- Subscription atomic metadata regression: PASS.
- All packaged shell scripts passed `sh -n`.
- All 33 non-empty inline JavaScript blocks passed Node syntax parsing.
- A broad run reached 99 passing shell regression scripts before the overall 300-second runner limit; no failures were recorded in those 99. The complete 286-script suite is not certified by this run.

## Confirmed blockers — do not mark complete

- The package still contains two separate APKs: `PrivacyGuardHook.apk` (`de.privacyguard.hook`) and `FXAdHook.apk` (`de.privacyguard.adhook`). The installer and uninstaller still manage both packages. Hook merge is NOT complete.
- The full historical `MainHook.java` (about 96 KB, from the user's Iter5 archive) is not present in this package or the currently located repository branch. The smaller `MainHook.java` found in `fx-v1.0.0-privacyguardhook-build` is only a VPN-app package-visibility implementation and is not feature-equivalent. Do not use it as a substitute for the complete legacy implementation.
- The modern API 101 hook currently includes ad-view observation/hiding for selected ad categories, package-scoped Android ID transformation, and read-only Billing/member diagnostics. Rewarded-ad flows are deliberately observe-only; no callback, purchase, or server reward is forged. VIP/entitlement remains read-only.
- Regional compatibility is not a universal region-lock bypass. The safe scope is diagnosing locale, account-region, network and app-availability mismatches and using official region settings/support; no forged eligibility or bypass of provider access controls.
- No OnePlus 12 + KernelSU + LSPosed real-device test was performed in this continuation. UI recovery and Hook injection remain device-unverified.

## Fixed project identity

- Module name: FX
- Version: 1.0.0
- Output filename: `FX-v1.0.0-KernelSU.zip`

## Additional migration completed in this continuation

- Migrated legacy `block_wifi_scan` into the API-101 Hook path.
- Added independent Remote Files gates: `wifi_scan_enabled` (existing global master) and per-app `wifi_scan_block` (Hook target editor).
- Runtime intercepts only `WifiManager.getScanResults()`, `startScan()`, and `isScanAlwaysAvailable()`; it does not alter Wi-Fi association, DHCP, sockets, DNS, VPN routing, or connectivity APIs.
- Shared-package processes, unknown package state, and protected framework/FX/LSPosed packages fail open.
- Added parser/serializer/policy unit tests, a focused host regression, Remote Files publication assertions, UI/status integration, and migration-matrix status.
- GitHub commits: `01b9c57ce68392e4dee8c81a920b21d46592ea75` (feature migration), `7ec4185bbbac1818672ea9a8d89beed784ebcae0` (preserve existing sensor-test constructor compatibility).
- First CI run failed at unit-test compilation because the new `Target` constructor had removed the prior 14-argument sensor constructor. A source-compatible overload was added in the second commit; the replacement CI run `41065767887` passed after adding a source-compatible overload. APK SHA-256: `f191a9fb3e51398614f331df26e6fe1447026d104d37ae6523c80b0d7af6fff7`.
- Host-side checks: parser/serializer/policy smoke PASS; Remote Files publisher PASS; target scope PASS; sensor config PASS; 75-switch migration baseline PASS; bottom navigation PASS; UI JavaScript 33 blocks PASS; privacy runtime/claims PASS; Hook installer regression PASS.
- Android CI build passed; OnePlus 12 LSPosed runtime verification remains pending. The two APK architecture is not yet merged.
