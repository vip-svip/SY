# FX 1.0.0 Legacy Hook Gap Audit

Branch: `fx-v1.0.0-unified-hook-integration`
Audit date: 2026-10-30

## Source of truth

The active Library archive `FX-v1.0.0-KernelSU.zip` contains the full legacy API-82 entrypoint at `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` (2,073 lines / 96,340 bytes). It is available for migration in the extracted working copy. The separate `FX-v1.0.0-Iter5.zip` archive was not independently located in the Library listing; do not describe the current ZIP as that archive.

The legacy entrypoint imports `IXposedHookLoadPackage`, `XC_MethodHook`, `XposedBridge`, and `XposedHelpers`, and reads `/data/local/tmp/privacyguard/xposed.conf`. It cannot be copied unchanged into the modern libxposed API-101 APK. Target-app processes must use the modern LSPosed Remote Files transport.

## Legacy feature inventory and migration status

| Legacy method/group | API-101 status | Notes |
|---|---|---|
| `buildSpoof`, `kernelVersionHide`, `sysPropsHide` | Not migrated | Device/build property spoofing remains disabled |
| `secureSettingsSpoof`, `serialSpoof`, `telephonySpoof` | Not migrated | Android ID transform is narrower; no IMEI/SIM/serial claim |
| `btWifiMacSpoof`, `batterySpoof`, `screenSpoof`, `storageSpoof` | Not migrated | Requires per-API/OEM tests |
| `sysSvcHide` | Not migrated | High compatibility risk |
| `clipboardGuard` | Partially migrated | Modern clipboard-read policy is wired to independent per-target config; writes remain untouched; physical compatibility still pending |
| `appListHide`, `pmQueryHide`, `procListHide` | Not migrated | High false-positive/app-breakage risk; do not enable by default |
| `mediastoreHide`, `netIfacesHide`, `netStatsHide`, `vpnHide` | Not migrated | Must not interfere with VPN coexistence or diagnostics |
| `imeHide` | Not migrated | Requires keyboard/input-method compatibility tests |
| `locationMock`, `gnssSpoof`, `passiveLocHide`, `wifiScanHide` | Wi-Fi scan partially migrated; location/GNSS not migrated | Wi-Fi scan uses independent global and per-target gates; location/GNSS transformations remain disabled and are not ported |
| `sensorHide` | Partially migrated | Sensor enumeration hiding and sampling-rate policy exist; not full parity |
| `cameraNull`, `micBlock`, `audioFpBlock`, `bioHide` | Not migrated | Can break camera, calls, audio and authentication |
| `notifHide`, `notifPermHide`, `usageHide`, `a11yHide` | Active-notification read suppression partially migrated; permission-query masking is source-only/dormant; usage/accessibility not migrated | `notification_listen_enabled` + target `notification_listen_block` are published end-to-end. `notification_permission_hide_enabled` + target `notification_permission_hide` exist in API-101 parser/runtime but are absent from the current FX target editor and root publisher, so that hook cannot be activated through FX UI yet. No OS permission is revoked or changed |
| `exifStrip` | Partially migrated | Read-time EXIF redaction exists; verify GPS getter coverage on device |
| `rootHide`, `fsHooks` and filesystem/VFS helpers | Not migrated | High stability risk; keep disabled pending device tests |
| `adIdUnify` | Not migrated | Advertising ID is distinct from Android ID |

## Modern API-101 source verified

- Package-scoped ad View observers and ad marker matching.
- Read-only Billing diagnostics for concrete response/purchase-state getters.
- Opt-in Android ID transformation, EXIF getter redaction, clipboard-read policy, sensor enumeration/rate policies, Wi-Fi scan suppression, and active-notification read suppression. Notification permission-query masking is parser/runtime source only; publisher/UI wiring is missing.
- Remote Files configuration is bounded, UTF-8 validated, parsed transactionally, and fails closed when unavailable/invalid.
- UI target selection and LSPosed Manager scope both gate target-process effects.

These are source-level facts, not proof of LSPosed injection or behavior on a physical OnePlus 12.

## Remaining gaps and safety constraints

- API-101 now includes opt-in, bounded member-class discovery: it caps APK files, scanned class entries, candidate classes, elapsed scan time and automatic getter hooks. It observes only selected candidate methods, caps member-state log observations, avoids retaining raw UI text, and never changes returned values. GitHub Actions compiled the APK and verified the discovery markers in DEX.
- API-101 now recognizes the requested Chinese rewarded-flow UI evidence, preserves matching rewarded-flow views from ad hiding, and records bounded observe-only lifecycle candidates. It does not fabricate reward callbacks or alter server validation.
- Membership/Billing handling remains read-only. Never modify purchase state, forge VIP entitlements, or bypass anti-fraud controls.
- The packages remain separate: `de.privacyguard.hook` and `de.privacyguard.adhook`. There is no verified single Hook APK.
- Do not enable destructive legacy transformations until individually ported, scoped, tested, and equipped with fail-open behavior.

## Next implementation sequence

1. Port low-risk deterministic privacy features with independent switches and API-level tests.
2. Implement bounded, opt-in member-state diagnostics only; never mutate membership or purchase results.
3. Complete ad UI/lifecycle observation without synthesizing reward success.
4. Port the remaining legacy features individually and maintain an explicit parity matrix.
5. Consolidate package identity, LSPosed metadata, entrypoint, scope, and Remote Files only after CI builds and verifies one APK.
6. Verify host regressions and APK signature in CI; separately verify OnePlus 12 injection and behavior.


## Latest API-101 build provenance (2026-10-30)

- Documentation/config integration commits: `9b6a2eb3` and `024c9ce6`.
- Latest CI: [41074509939](https://github.com/vip-svip/SY/actions/runs/41074509939) — success; parser/deployment regressions, unit tests, debug APK assembly, APK signature, Xposed metadata/resources, and DEX marker checks passed.
- APK SHA-256: `3a113bcecedd203f7aab32f1b84803a85cd11282b4ec47d4ddbec1b819bf8822`.
- Artifact: `FXAdHook-apk`, ID `12985798934`, artifact ZIP SHA-256 `8895c8a458570c289a1a34656eee971a3e3234dc3a07fb8504cd22018ce9d83c`, expires 2027-01-28.
- This remains a standalone debug API-101 APK, not a unified FXHook APK or full KernelSU package.


- Source/workflow commit: `55c356f061643401a62042d9809806c38c5f5537`
- GitHub Actions run: [41060759194](https://github.com/vip-svip/SY/actions/runs/41060759194) — success
- APK SHA-256: `195735e1754fd236b0feb0d2f8877b8eab2e7310360cdb3fa1ab476c36cc8374`
- CI verified: Java/Gradle compile, unit tests, APK signature, modern LSPosed metadata/resources, and bounded member/rewarded-flow DEX markers.
- The artifact is an API-101 Hook APK build artifact, not yet merged with the legacy API-82 Hook and not yet inserted into the complete KernelSU ZIP.
- No physical OnePlus 12 LSPosed injection or runtime behavior test has been performed.
