> **Current unified Hook checkpoint — 2026-10-30:** The branch compiles one API82+API101 dual-entry debug APK under one applicationId. API101 opt-in migrations include EXIF read-time redaction; clipboard read blocking and process-local clipboard isolation; sensor enumeration/rate controls; Wi-Fi scan and cell-info privacy; camera-ID enumeration privacy; AudioRecord microphone silence; microphone hardware metadata hiding; low-amplitude AudioRecord sample perturbation for audio-fingerprint mitigation; passive-location suppression; region diagnostics; MediaStore privacy; and notification, usage-statistics and accessibility enumeration/query privacy. Latest successful CI run `41056196261` (commit `244fbef0138310d211acd867775e1a849162ff7b`) passed source restoration, host regressions, JUnit tests, APK assembly/signature/DEX/metadata verification and artifact upload. Debug validation artifact ID `12977450642`, archive SHA-256 `4367fe733ccd34867da8aeea1eec5c65b70cf2ed282c45ddb8baff21a55cdbc6`. See `docs/FX-1.0.0-HOOK-CONSOLIDATION-STATUS.md` for exact coverage limits and blockers.
>
> **Do not treat this as full feature parity or production completion.** The root-side FX UI/config publisher is not yet proven to publish every new schema field to both legacy `xposed.conf` and API101 Remote Files. API82/API101 runtime discovery/arbitration, release signing continuity, complete legacy flag migration and OnePlus 12 validation remain open. The final KernelSU ZIP has not been rebuilt. Historical sections below describe earlier migration slices and must be read as history, not current status.
>
# FX 1.0.0 Hook migration — verified source and execution plan

> **Current checkpoint — 2026-10-30 (supersedes stale status statements below):** The branch now restores the full 97,918-byte legacy `MainHook.java` source into the single API-101 app project and compiles a dual-entry, one-`applicationId` debug APK. The APK contains both legacy `assets/xposed_init` and modern `META-INF/xposed` descriptors. GitHub Actions run `41052177773` (commit `b608ed9678d8b94dd4f8a8431391c55692b45d88`) passed source restoration, API82/API101 wiring regressions, JUnit tests, APK assembly, signature verification, DEX and metadata checks. Artifact `FXHook-API82-API101-single-apk-validation` ID `12974079489`, archive SHA-256 `51ae857a080e98eb55437efa9da38dd6010e09c34550ee50f864fb25d7b2926cae`. The artifact is debug-signed; production signing continuity and real framework injection on both runtimes remain unverified. The final KernelSU ZIP has not been rebuilt.
>
> API101 migration now includes opt-in AudioRecord `mic_block` silence for byte[], short[], float[] and ByteBuffer read paths, with shared-process/protected-package fail-open behavior. It does not cover MediaRecorder, AAudio/Oboe or native capture. The feature passed the above CI build and tests; OnePlus 12 behavior remains unverified. `audio_fp_block` and `mic_hw_hide` are now partially migrated; see the latest checkpoint for limits. `clipboard_isolate` is process-local only.
>
> The installer is now single-APK-only: it accepts `optional/FXHook.apk` and fails closed if absent. It no longer installs the old split `PrivacyGuardHook.apk` + `FXAdHook.apk` pair. The prior text below describing two active installs or missing API82 source is historical and superseded by this checkpoint.
>
> **Still incomplete:** runtime discovery/arbitration on API82-capable and API101+ LSPosed, shared config equivalence, release-key continuity, full 73-flag migration, complete KernelSU source integration and OnePlus 12 verification. Do not call this a production-complete Hook or final FX ZIP.
>
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
3. Build a shared versioned Remote Files schema and migrate the root-side config publisher/UI to it.
4. Port low-risk features first; add unit and package-scope regression tests for every port.
5. Replace the two-package installer only after the single APK has complete, tested feature coverage.
6. Run the GitHub Actions build and host regressions; report physical-device validation separately.

No unified APK or complete migration is claimed by this document.

## Latest validated checkpoint — 2026-10-30 (run 41057506685)

The one-APK API82/API101 debug validation build now passes GitHub Actions run [41057506685](https://github.com/vip-svip/SY/actions/runs/41057506685), commit `b746c44af0450d5f3e9cbb73f5a727059de594ff`. The run passed source restoration, wiring/static regressions, JUnit tests, APK assembly, signature/DEX/metadata checks and artifact upload.

The current API101 opt-in migration set now also includes:
- microphone hardware enumeration privacy (`mic_hw_hide`);
- bounded `AudioRecord.read` sample perturbation (`audio_fp_block`), not a full anti-fingerprinting guarantee;
- process-local memory-only clipboard isolation (`clipboard_isolate`), single-package only; read-block takes precedence;
- notification-listener and notification-permission visibility controls;
- UsageStats and accessibility-service visibility controls;
- fingerprint/face hardware enumeration privacy.

All corresponding host regression scripts passed in run 41057506685. Audio capture paths outside supported `AudioRecord.read` overloads remain uncovered. Clipboard change listeners and multi-process apps remain uncovered. Hardware enumeration privacy does not disable the underlying biometric hardware.

This checkpoint remains a debug-signed validation APK, not a release-signed installable production module. API82/API101 framework discovery and runtime arbitration, config equivalence between legacy xposed.conf and API101 Remote Files, release-signature migration, remaining legacy flag parity, complete module integration and OnePlus 12 verification remain open. The final KernelSU ZIP has not been rebuilt.
