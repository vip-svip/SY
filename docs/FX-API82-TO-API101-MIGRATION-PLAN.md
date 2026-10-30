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

## Completed migration slice (2026-10-30)

- Added API-101 opt-in, per-target read-time EXIF redaction for framework and AndroidX `ExifInterface` getters.
- Redacts GPS tags, Make/Model, and DateTime tags; unrelated metadata remains unchanged.
- This is read-time API redaction only. It does not rewrite image files and does not cover every third-party EXIF parser.
- Added pure-Java policy tests, parser tests for independent `exif_strip=1` target selection, legacy-config fail-closed tests, and serializer round-trip coverage.
- GitHub Actions run `41025299195` passed on commit `526ff000217d2d6809406874dd9dcdd982910275`: parser/deployment regression tests, debug APK build, APK signature verification, and libxposed metadata checks.
- Built APK SHA-256: `7266bf40550a974cabd473d9041cbe52dda692b9e5cabce177203ab5c43579fd`.
- Artifact: `FXAdHook-apk` (ID `12963555891`), expires 2027-01-28. This is a debug API-101 APK artifact, not the final unified Hook APK.

Important integration blocker: the current FX package's root-side Remote Files publisher and the UI control for `exif_strip` are not yet wired to this schema. The feature compiles and parser/serializer tests pass, but cannot be treated as active in an installed FX module until that end-to-end publisher/UI path is connected. The legacy API-82 APK remains separate.

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
