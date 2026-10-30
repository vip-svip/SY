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
| `clipboardGuard` | Partially migrated | Modern clipboard-read policy exists; validate Android API and target-app compatibility |
| `appListHide`, `pmQueryHide`, `procListHide` | Not migrated | High false-positive/app-breakage risk; do not enable by default |
| `mediastoreHide`, `netIfacesHide`, `netStatsHide`, `vpnHide` | Not migrated | Must not interfere with VPN coexistence or diagnostics |
| `imeHide` | Not migrated | Requires keyboard/input-method compatibility tests |
| `locationMock`, `gnssSpoof`, `passiveLocHide`, `wifiScanHide` | Not migrated | Requires independent opt-in and API-specific tests |
| `sensorHide` | Partially migrated | Sensor enumeration hiding and sampling-rate policy exist; not full parity |
| `cameraNull`, `micBlock`, `audioFpBlock`, `bioHide` | Not migrated | Can break camera, calls, audio and authentication |
| `notifHide`, `notifPermHide`, `usageHide`, `a11yHide` | Not migrated | Separate each behavior and test independently |
| `exifStrip` | Partially migrated | Read-time EXIF redaction exists; verify GPS getter coverage on device |
| `rootHide`, `fsHooks` and filesystem/VFS helpers | Not migrated | High stability risk; keep disabled pending device tests |
| `adIdUnify` | Not migrated | Advertising ID is distinct from Android ID |

## Modern API-101 source verified

- Package-scoped ad View observers and ad marker matching.
- Read-only Billing diagnostics for concrete response/purchase-state getters.
- Opt-in Android ID transformation, EXIF getter redaction, clipboard-read policy, and sensor enumeration/rate policies.
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


## Latest API-101 build provenance

- Source/workflow commit: `1d8de5ed4d5aaab3db3e4047f8ba9ab2d4a722aa`
- GitHub Actions run: [41060413338](https://github.com/vip-svip/SY/actions/runs/41060413338) — success
- APK SHA-256: `5985f74fa2819a9a64a1d53a8808e70bdf9f7b7dedec5d9831906c9de521126c`
- CI verified: Java/Gradle compile, unit tests, APK signature, modern LSPosed metadata/resources, and bounded member/rewarded-flow DEX markers.
- The artifact is an API-101 Hook APK build artifact, not yet merged with the legacy API-82 Hook and not yet inserted into the complete KernelSU ZIP.
- No physical OnePlus 12 LSPosed injection or runtime behavior test has been performed.
