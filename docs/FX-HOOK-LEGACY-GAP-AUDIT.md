# FX 1.0.0 Legacy Hook Gap Audit

Branch: `fx-v1.0.0-unified-hook-integration`
Audit source: `FX-v1.0.0-Iter5.zip` (preserved; not modified)
Audit date: 2026-10-29

## Verified host-side checks

- `scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh`: PASS
- `scripts/tests/v1.0.0-lsposed-ad-hook-target-scope-regression.sh`: PASS
- These tests do not prove LSPosed injection or behavior on a physical OnePlus 12.

## Legacy implementation inventory

The Iter5 `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` contains the following distinct feature groups. The modern `adhook` runtime is not feature-equivalent; it currently implements ad-view observers, read-only membership diagnostics, and an opt-in package-scoped Android ID transform only.

| Legacy method/group | Migration status in modern runtime | Risk / next action |
|---|---|---|
| `buildSpoof`, `kernelVersionHide`, `sysPropsHide` | Not migrated | Preserve as legacy-only until API 101 equivalents and regression tests exist |
| `secureSettingsSpoof`, `serialSpoof`, `telephonySpoof` | Not migrated; Android ID transform is narrower | Do not claim IMEI/SIM/serial coverage |
| `btWifiMacSpoof`, `batterySpoof`, `screenSpoof`, `storageSpoof` | Not migrated | High compatibility risk; migrate individually with fail-open behavior |
| `sysSvcHide`, `clipboardGuard` | Not migrated | Validate API return types and avoid breaking normal app functionality |
| `appListHide`, `pmQueryHide`, `procListHide` | Not migrated | High false-positive / app-breakage risk; do not enable by default |
| `mediastoreHide`, `netIfacesHide`, `netStatsHide`, `vpnHide` | Not migrated | Must not interfere with VPN coexistence or network diagnostics |
| `imeHide` | Not migrated | Verify keyboard and input method compatibility |
| `locationMock`, `gnssSpoof`, `passiveLocHide`, `wifiScanHide`, `sensorHide` | Not migrated | Require explicit per-feature opt-in and API-specific tests |
| `cameraNull`, `micBlock`, `audioFpBlock`, `bioHide` | Not migrated | Potentially breaks camera, calls, audio and biometric authentication |
| `notifHide`, `notifPermHide`, `usageHide`, `a11yHide`, `exifStrip` | Not migrated | Separate privacy semantics from app functionality; test each independently |
| `rootHide`, `fsHooks` and filesystem attribute/VFS helpers | Not migrated | High stability risk; keep disabled until tested on target Android/OEM builds |
| `adIdUnify` | Not migrated | Distinct from Android ID; do not imply Advertising ID coverage |

## Configuration and activation invariants

1. The modern Remote Files payload is versioned and parsed transactionally.
2. Legacy ad-only configuration intentionally leaves modern privacy disabled.
3. The UI application selection and LSPosed Manager scope are both required; either gate missing means no target-process effect.
4. `lsposed_enabled` is the legacy MainHook master switch; `hook_ads_enabled` and `hook_privacy_enabled` control the modern ad/Android-ID runtime and are not interchangeable.
5. The root-side generator reports Remote Files publication status separately from legacy `xposed.conf`. A successful legacy config write is not proof that the modern APK can read its Remote Files.
6. Membership support remains read-only diagnostics. No purchase result or entitlement should be modified.

## Next implementation sequence

1. Add a single runtime ownership rule so old and modern modules cannot both install overlapping hooks unintentionally.
2. Keep legacy features explicitly labelled as legacy until each has a modern API 101 implementation and tests.
3. Migrate low-risk, deterministic features first; add API-level and package-scope tests before enabling any feature.
4. Test APK installation/update/removal and Remote Files access on a real LSPosed device.
5. Only then integrate a validated APK into the complete FX ZIP. Do not replace the preserved Iter5 archive with an unverified candidate.
