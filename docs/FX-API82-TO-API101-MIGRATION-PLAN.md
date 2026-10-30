# FX 1.0.0 Hook migration — verified source and execution plan

Status: source recovered; API migration and APK consolidation are NOT complete.

## Verified source of truth (2026-10-30)

The current Library artifact `FX-v1.0.0-KernelSU.zip` was materialized and inspected. It contains:

- `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` — 96,340 bytes, the complete legacy API-82 entry source.
- `optional/PrivacyGuardHook.apk` — legacy APK, 37,319 bytes.
- `optional/FXAdHook.apk` — modern API-101 APK, 66,263 bytes.
- `adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java` — modern runtime source, 53,733 bytes.
- `adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java` — versioned config parser.

The complete Java source is therefore available in the FX package even though it is not yet imported into this Git branch. The earlier statement that the source could not be recovered is superseded. Do not confuse the 96 KB package source with the approximately 8 KB VPN-package-hide-only implementation on the old build branch.

## Current architecture facts

- Legacy entry: `de.privacyguard.hook.MainHook`, API 82 (`IXposedHookLoadPackage`, `XC_MethodHook`, `XposedHelpers`).
- Modern entry: `de.privacyguard.adhook.AdVisibilityHook`, libxposed API 101 (`XposedModule`, Remote Files).
- Installer regression currently expects two package installs: `de.privacyguard.hook` and `de.privacyguard.adhook`.
- Modern config parser supports a versioned unified schema, but the root-side publisher still emits the legacy ad-only format; privacy therefore remains disabled for that legacy payload.
- Modern runtime currently has ad-view observation, read-only membership diagnostics, and a narrow opt-in Android ID transform. This is not legacy feature parity.
- Existing API-101 workflow validates/builds the modern AdHook module; it does not prove that the legacy API-82 implementation has been ported.

## Migration inventory and ordering

The recovered legacy source must be imported unchanged as an audit baseline before individual ports. Keep its original package/source snapshot identifiable; never delete it merely because a replacement compiles.

| Feature family | Legacy implementation group | Port gate |
|---|---|---|
| Device/build identity | build spoof, kernel version, system properties, secure settings, serial, telephony | Per-API tests; never spoof hardware identifiers by default |
| Network/privacy | Wi-Fi/Bluetooth identifiers, interfaces, traffic stats, VPN visibility | Must not break real network, VPN coexistence, or diagnostics |
| Package/process visibility | package queries, installed apps, process list | High breakage risk; per-app opt-in, compatibility tests |
| Storage/root visibility | mount tables, filesystem attributes, root paths, sysfs | Fail-open; test storage, updates, and app startup |
| Sensors/location | location, GNSS, Wi-Fi scans, sensors | Per-feature opt-in; preserve emergency/location functionality |
| Media/device capabilities | camera, microphone, audio, biometric, display, battery, storage | Do not disable normal device functions globally |
| User data/OS surfaces | clipboard, notifications, usage stats, accessibility, IME, MediaStore, EXIF | Validate each Android/OEM API and permission boundary |
| Advertising identity | Advertising ID handling | Separate from Android ID; explicit opt-in and scope |

## Mandatory invariants

1. One final APK must own the single LSPosed module identity, entrypoint, scope, and config reader.
2. FX UI package selection AND LSPosed Manager scope must both authorize a target process.
3. Missing, malformed, oversized, or unsupported config installs no hooks.
4. Ad and privacy switches remain independent; old ad-only config never enables privacy implicitly.
5. Migrate one feature family at a time; retain a compatibility-safe default and fail-open behavior.
6. Billing remains read-only diagnostics. Do not forge rewarded-ad callbacks, purchase state, VIP entitlements, or server authorization.
7. Region support work is limited to legitimate connectivity, locale, and app-configuration compatibility; do not spoof eligibility or bypass provider access controls.
8. Do not remove the legacy APK or change installer package IDs until the unified APK passes CI, signature/resource checks, install/update/uninstall tests, and real LSPosed injection on the OnePlus 12.

## Next concrete engineering steps

1. Import the 96,340-byte source from the recovered FX ZIP into a clearly marked migration-baseline directory in this branch.
2. Enumerate all legacy hook registrations and API-82 helper calls; map each to a libxposed API-101 implementation or mark it unsupported with a reason.
3. Build a shared versioned Remote Files schema and migrate the root-side config publisher/UI to it.
4. Port low-risk features first; add unit and package-scope regression tests for every port.
5. Replace the two-package installer only after the single APK has complete, tested feature coverage.
6. Run the GitHub Actions build and host regressions; report physical-device validation separately.

No unified APK or complete migration is claimed by this document.
