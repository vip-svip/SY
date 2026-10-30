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
- Modern config parser supports the versioned unified schema. The recovered FX KernelSU ZIP includes `scripts/gen_xposed_conf.sh`, which publishes `schema_version=1` through LSPosed Remote Files, with independent ad/privacy/Wi-Fi/notification masters and per-target feature fields. The legacy API-82 bridge still consumes its old `xposed.conf`; the two config paths remain separate.
- Modern runtime source currently includes ad-view observation, read-only Billing/member diagnostics, a narrow Android ID transform, EXIF getter redaction, clipboard read protection, selected sensor enumeration/rate controls, Wi-Fi scan suppression, and active-notification read suppression. Notification permission-query masking is wired end-to-end in the recovered FX ZIP: publisher emits the global `notification_permission_hide_enabled` master and per-target `notification_permission_hide`; parser/runtime gate the selected target. It masks only the target app's status query and does not change OS permission state. It remains pending physical-device verification. These are source/host-test slices, not complete API-82 parity or physical-device proof.
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

Integration status update (2026-10-30): the recovered FX ZIP's root-side publisher emits the versioned Remote Files schema and includes the `exif_strip` target field. The API-101 parser and serializer cover this field. The legacy API-82 APK remains separate, and OnePlus 12 / LSPosed runtime behavior remains unverified.

## Second migration slice: clipboard read protection (2026-10-30)

- Added independent per-target `clipboard_read_block=1` under the privacy master switch.
- API-101 intercepts `ClipboardManager.getPrimaryClip()`, `hasPrimaryClip()`, and legacy `getText()`; reads return `null` / `false`, writes are untouched.
- A pure policy gate permits blocking only when exactly one package is known in the process. Shared-package processes, protected packages, unselected targets, and privacy-master-off cases fail open.
- Added parser, serializer, and policy tests. GitHub Actions run `41027166801` passed the unit tests, APK build, signature verification, and API-101 resource checks.
- Root FX publisher/UI integration was applied to the recovered KernelSU ZIP: the per-app checkbox persists through `hook_targets`, the publisher includes the new schema field, and status accounting includes clipboard-only targets.
- Physical OnePlus 12 / LSPosed validation is still pending. This does not implement the old `clipboard_isolate` per-app clipboard store or the legacy fake-text mode.

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
3. Keep the versioned Remote Files schema, root-side publisher, UI keys, and parser/serializer synchronized; add an end-to-end fixture test from actual FX `hook_targets` config to the API-101 parser.
4. Continue porting low-risk features first; add unit and package-scope regression tests for every port. Current next candidates are explicit, non-spoofing privacy controls that do not falsify device identity or interfere with networking.
5. Replace the two-package installer only after the single APK has complete, tested feature coverage, stable package identity/upgrade strategy, and a real LSPosed injection test.
6. Run the GitHub Actions build and host regressions; report physical-device validation separately.

No unified APK or complete migration is claimed by this document.


## 2026-10-30 feature triage — camera and microphone

The complete API-82 source remains preserved in the current KernelSU ZIP at `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` (96,340 bytes). It is the authoritative baseline; do not substitute the reduced API-82 branch copy.

### Microphone

Legacy `micBlock()` hooks `AudioRecord.read()` and either zeroes returned PCM samples, adds synthetic noise, or returns an error from `startRecording()`. Only the explicit silence/error modes are candidates for a transparent user-controlled privacy feature. The synthetic-noise path (`mic_block= noise`) and `audio_fp_block` perturbation are not to be migrated: they alter sensor data to mislead downstream consumers and are not equivalent to revoking microphone permission. Even a zero-buffer hook would cover only AudioRecord paths, not every capture API (MediaRecorder, camera audio, native paths), so UI must state the limited coverage and must not imply OS-wide microphone denial.

### Camera

Legacy `cameraNull()` and `cam_hw_hide` need separate review. Returning null or falsifying hardware availability can break camera clients and misrepresent device capabilities. Do not port the old implementation as-is. A replacement must be an explicit per-target camera-use privacy control with clear failure behavior and verified Camera1/Camera2/CameraX coverage; otherwise mark unsupported and direct users to Android's actual camera permission controls.

### Next port order

1. Port only a bounded, opt-in AudioRecord silence control after confirming method overloads and buffer semantics on API 28–35; keep MediaRecorder/native capture explicitly out of scope.
2. Add parser, serializer, publisher, UI, and policy unit tests before enabling the feature.
3. Add a target-process instrumentation test proving that unrelated targets and shared-package processes pass through unchanged.
4. Do not change Android permission state or claim full microphone/camera denial.


## 2026-10-30 third migration slice — AudioRecord read-buffer silence

- Added opt-in per-target `mic_silence=1` under the existing privacy master.
- API-101 hooks supported `AudioRecord.read` overloads for byte[], short[], float[], and ByteBuffer buffers. It calls the original read exactly once and zeroes only the successfully returned region.
- Process-scoped authorization fails open when more than one package is observed in the process. Hook registration failure also leaves capture unchanged.
- No `startRecording()` interception, microphone hardware hiding, synthetic-noise injection, MediaRecorder/camera audio interception, or native capture coverage is claimed.
- UI label explicitly states this is not equivalent to disabling Android's microphone permission.
- Parser/serializer round-trip and buffer-boundary tests added. GitHub Actions run `41085666969` passed Android debug compilation, unit tests, the dedicated AudioRecord regression, APK signature verification, and libxposed metadata checks. Built APK SHA-256: `b23b259e0f0f08a0c9b3ceb46b11cdf451a280e1f40e8a2128078448fbcbca01`. OnePlus 12 / LSPosed runtime verification remains pending.
