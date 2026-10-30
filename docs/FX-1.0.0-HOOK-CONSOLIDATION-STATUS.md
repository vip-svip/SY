# FX 1.0.0 Hook consolidation status

## Current verified state

Latest unified Hook validation: GitHub Actions run `41057506685`, commit `b746c44af0450d5f3e9cbb73f5a727059de594ff`, completed successfully. It passed exact API82/API101 source restoration, host regressions, JUnit unit tests, debug APK assembly, signature/DEX/metadata checks and artifact upload. Artifact `FXHook-API82-API101-single-apk-validation` ID `12977491990`, archive SHA-256 `4fd04b79c390c6a2b39eb35f21acebba60fc0d138cf96705c1d726bceefb3f32`. This remains a debug-signed validation artifact, not the production-signed APK or final KernelSU ZIP.

The isolated branch fx-v1.0.0-cloud-validation builds the API-101 Hook APK. The latest run completed all CI steps successfully: unit tests, debug APK assembly, APK signature verification, modern LSPosed metadata checks, and artifact upload.

The API-101 source restoration pipeline applies bounded, hash-checked patches before compilation. Verified privacy additions in this pipeline are:

- Android ID privacy: app-scoped transformation; shared-package processes fail open.
- Sensor enumeration and sampling-rate controls: opt-in and single-package guarded.
- Clipboard read protection: reads only; writes are untouched; shared-package processes fail open.
- Clipboard isolation: opt-in, process-local in-memory clipboard for one selected package; read blocking takes precedence. Multi-process synchronization and clipboard change-listener notifications are not implemented.
- Microphone hardware metadata hiding: opt-in AudioManager input-device and AudioRecord metadata filtering; unknown APIs/devices fail open.
- Biometric hardware metadata hiding: independent fingerprint and face capability flags; the generic BiometricManager result reports no hardware only when both modalities are hidden, preserving any unhidden modality.
- Audio fingerprint mitigation: opt-in low-amplitude perturbation of AudioRecord byte/short/float/ByteBuffer read buffers; `mic_block` takes precedence. This changes captured audio samples and is not a guarantee against every audio-fingerprinting technique.
- Notification, usage-statistics and accessibility surface privacy: opt-in enumeration/query filtering with single-package fail-open policy; does not remove underlying system permissions or disable those system services.
- EXIF read-time metadata redaction.
- Wi-Fi scan-result redaction: opt-in, returns an empty result list only for a single-package process.
- Cell-location/cell-info redaction: opt-in, nullable/list-compatible return values, single-package guarded.
- Camera ID enumeration redaction: opt-in and fail-open guarded.
- Ad UI handling for splash/feed/overlay surfaces, with bounded view traversal and package attribution from the view context.
- Rewarded-ad lifecycle and VIP/member state diagnostics are read-only. No reward callback, server validation, purchase state, entitlement, or balance is modified.

These are CI/build and static regression results. They are not proof of behavior on a OnePlus 12 or every target app.

## Installer migration

The module-side installer now accepts only optional/FXHook.apk and installs only applicationId de.privacyguard.adhook. If the unified artifact is absent, installation fails closed; there is no two-APK fallback. The remover tracks the unified package and retains narrowly scoped cleanup for a previously FX-owned legacy API82 package from older installations; this is uninstall cleanup only, never a second install path. Host regression coverage verifies one-package installation and verifies that split APKs are refused. This installer change does not mean FXHook.apk has already been built or included in the current KernelSU archive.

## Current dual-entry prototype (2026-10-30)

The isolated validation branch now stages the exact API-82 `MainHook.java` source snapshot (SHA-256 `77cec8b8e28b3673b4c8badc93aa1e1a49dff2f289779d4ca72b97b1f0dcc562`) alongside the API-101 source. The single Android application project has:

- One `applicationId`: `de.privacyguard.adhook`.
- Legacy `assets/xposed_init` pointing to `de.privacyguard.hook.MainHook`.
- Modern `META-INF/xposed/java_init.list` pointing to `de.privacyguard.adhook.AdVisibilityHook`.
- Legacy Xposed Manifest metadata and modern libxposed module metadata.
- Both framework APIs as `compileOnly` dependencies, so framework classes are not packaged into the APK.
- A reflective API-101 runtime check in the legacy entry to avoid duplicate hook registration, plus a legacy shared-UID fail-open guard.

The dual-entry static regression, exact API82 source restoration, unit tests, APK compilation, signature verification and metadata/DEX checks most recently passed in GitHub Actions run `41052177773` (commit `b608ed9678d8b94dd4f8a8431391c55692b45d88`). This run also passed the microphone privacy regression and its JUnit tests. Artifact `FXHook-API82-API101-single-apk-validation` (artifact ID `12974079489`, archive SHA-256 `51ae857a080e98eb55437efa9da38dd6010e09c34550ee50f864fb25d7b2926cae`) contains one `app-debug.apk`. Earlier run `41050895875` produced an inspected APK with both entry descriptors and both Hook classes in the same APK. This remains a debug-signed build validation, not a release-signed update package. Framework discovery/loading on API 82 and API 101 runtimes remains unverified. The final KernelSU ZIP is not rebuilt.

The local FX root-side generator was inspected: it derives the legacy `xposed.conf` and modern LSPosed Remote Files payload from the same `settings.conf`. Legacy target-app hooks still read the legacy mirror; modern hooks read Remote Files. This is a dual-publication bridge, not proof of identical feature semantics. The root-side generator and UI were audited in the extracted working FX tree; their per-app API101 flags, Remote Files serialization and multi-user rollback pass host regressions. The full root source tree is not yet checked into this isolated validation branch. Exact source hashes and test results are in `docs/FX-1.0.0-ROOT-HOOK-CONFIG-STATUS.md`.

## API-82 and API-101 consolidation

A one-APK dual-entry prototype now compiles and passes CI packaging checks. It uses one applicationId (`de.privacyguard.adhook`) and contains both `assets/xposed_init` and `META-INF/xposed` entry descriptors. The validation APK is a debug-signed prototype, not yet a release-ready or device-verified Hook.

Remaining proof requirements:

1. Verify that legacy API-82-capable LSPosed/Xposed discovers and loads only the `assets/xposed_init` entry.
2. Verify that API-101+ LSPosed discovers and loads only the `META-INF/xposed` entry; confirm the reflective arbitration guard prevents duplicate hook registration if both loaders expose both entries.
3. Verify legacy `xposed.conf` and modern Remote Files receive equivalent target settings from the same root-side FX configuration source. They are separate transport formats, not one shared runtime file.
4. Build a single shared feature registry and reconcile every legacy feature switch. A similarly named modern flag is not proof of semantic parity.
5. Validate update/signature continuity using a stable release signing key before replacing the currently installed API101 package.
6. Validate activation, scope, enable/disable, update and uninstall on both framework families.

The legacy entry has a reflective API-101 runtime check and a fail-open UID-to-package identity check. CI proves source restoration, Java compilation, unit tests, APK signing and descriptor presence only; it does not prove framework discovery, runtime arbitration, or real-device behavior. Do not call the Hook production-merged until the framework matrix and signing continuity pass.

## Microphone hardware and audio fingerprint migration checkpoint (2026-10-30)

API-101 now parses and serializes independent per-target `mic_hw_hide` and `audio_fp_block` flags.

- `mic_hw_hide`: filters source/input devices from `AudioManager.getDevices(GET_DEVICES_INPUTS)`, returns an empty list for `AudioManager.getMicrophones()` and `AudioRecord.getActiveMicrophones()`, and returns null for `AudioRecord.getRoutedDevice()`. Output devices are retained. This does not hide `PackageManager.FEATURE_MICROPHONE`, every vendor-specific API, native service state, or every hardware fingerprint.
- `audio_fp_block`: applies bounded low-amplitude sample perturbation after successful `AudioRecord.read()` calls for byte[], short[], float[] and ByteBuffer overloads. It is enabled only for one selected package and only while the privacy master switch is on. If `mic_block` is also enabled, microphone silence takes precedence and the perturbation hook is not installed.
- The legacy `mic_block` mode variants (`error` / `noise`) are not fully represented by the current API-101 bit-only schema; API-101 currently implements the explicit silence behavior. `MediaRecorder`, AAudio/Oboe and native capture remain outside these API-101 hooks.
- Audio sample perturbation can degrade recording quality. It is a privacy signal transformation, not a guarantee that audio-derived identification is defeated.

GitHub Actions run `41054381942` (commit `d4463acaa595d77753c7b903850d66da611b18d3`) passed the exact-source hash checks, all host regressions, JUnit tests, API82+API101 single-APK compilation, APK signature verification, DEX/metadata checks and artifact upload. Artifact `FXHook-API82-API101-single-apk-validation` ID `12975833069`, archive SHA-256 `0de3831b3f916eb5539cdc24c4616c746f7a51b30945b4dde46e4710076b3a8f`. This remains a debug-signed validation artifact; framework loading and actual audio behavior on OnePlus 12 are not verified. The final KernelSU ZIP has not been rebuilt.

## Notification, usage, accessibility and clipboard migration checkpoint (2026-10-30)

API-101 now parses and serializes four additional independent per-target flags:

- `block_notif_listen`: hides active-notification query results from `NotificationManager` and `NotificationListenerService`, using return-type-compatible empty arrays/lists.
- `hide_notif_perm`: reports `NotificationManager.areNotificationsEnabled()` as false for the selected target. It does not revoke the actual Android permission.
- `usagestats_off`: returns an empty list from `UsageStatsManager.queryUsageStats()`; this does not cover every usage-statistics API.
- `a11y_hide`: returns empty lists from `AccessibilityManager.getEnabledAccessibilityServiceList()` and `getInstalledAccessibilityServiceList()`. This may break accessibility-dependent app features and must remain explicitly opt-in.

These hooks require the privacy master switch, exactly one package in the process, and a selected per-app flag. System, FX Hook, LSPosed Manager, unknown and shared-package processes fail open.

The parallel clipboard-isolation migration is also staged in the same API-101 source pipeline: it keeps reads/writes in a process-local in-memory clipboard and does not modify the Android system clipboard. It does not cover multi-process apps or clipboard-change listeners. `clipboard_read_block` takes precedence over isolation.

GitHub Actions run `41056196261` (commit `244fbef0138310d211acd867775e1a849162ff7b`) passed exact-source hash checks for the full API101 patch chain, clipboard isolation and notification/system-surface regressions, JUnit tests, single-APK compilation, APK signature/DEX/metadata checks and artifact upload. Artifact `FXHook-API82-API101-single-apk-validation` ID `12977450642`, archive SHA-256 `4367fe733ccd34867da8aeea1eec5c65b70cf2ed282c45ddb8baff21a55cdbc6`. The debug APK is a validation artifact only; no real LSPosed injection or OnePlus 12 behavior is proven. The final KernelSU ZIP has not been rebuilt.

## Biometric hardware privacy migration checkpoint (2026-10-30)

API-101 now has independent per-target `hide_fingerprint_hw` and `hide_face_hw` flags.

- Fingerprint hiding returns false from framework `FingerprintManager.isHardwareDetected()` and `hasEnrolledFingerprints()`, plus the matching AndroidX compatibility methods when that library is present.
- Face hiding returns false from `FaceManager.isHardwareDetected()` and `hasEnrolledFaces()` when those methods exist on the device.
- When either biometric-hardware flag is enabled, `BiometricManager.canAuthenticate()` reports `BIOMETRIC_ERROR_NO_HARDWARE` (12), matching the legacy API82 behavior.
- The flags are independent for their respective manager APIs; the combined `BiometricManager` result reports no biometric hardware if either selected flag is active. This can break biometric login flows and is deliberately opt-in.
- This is app-facing API concealment only. It does not remove biometric hardware, change Android Keystore state, or cover every OEM/vendor biometric API.

The policy requires the privacy master switch, one package in the process, and a selected target. Protected and shared-package processes fail open.

GitHub Actions run `41057506685` (commit `b746c44af0450d5f3e9cbb73f5a727059de594ff`) passed the biometric policy/parser/serializer tests, pinned source hash, all existing regressions, JUnit tests, single-APK compilation, signature/DEX/metadata checks and artifact upload. Artifact `FXHook-API82-API101-single-apk-validation` ID `12977491990`, archive SHA-256 `4fd04b79c390c6a2b39eb35f21acebba60fc0d138cf96705c1d726bceefb3f32`. It remains a debug-signed validation APK; actual biometric behavior on OnePlus 12 and LSPosed injection are unverified.

## Input-method enumeration privacy migration checkpoint (2026-10-30)

API-101 now parses and serializes `block_ime_logging`. For the selected app it returns empty lists from `InputMethodManager.getEnabledInputMethodList()`, `getInputMethodList()` and `getEnabledInputMethodSubtypeList()`. It does not disable the keyboard, change the system's selected IME, or alter actual input-method settings. It can still break apps that enumerate keyboards or subtypes, so it remains opt-in.

The policy requires the privacy master switch and a single-package process; system, FX Hook, LSPosed Manager and unknown targets fail open.

GitHub Actions run `41058264335` (commit `caf1e6b1861a34ed1fea79fdb70752814f59fb9c`) passed the pinned input-method source hash, parser/serializer and policy tests, all prior privacy regressions, JUnit tests, single-APK build and APK verification. Artifact `FXHook-API82-API101-single-apk-validation` ID `12976843889`, archive SHA-256 `0c6cc339027584916391461008141c0d621d930587aa1ba30f632d3d1fdafcfa`. This is still a debug-signed validation artifact, not the final FX KernelSU ZIP or a OnePlus 12 runtime test.

## Deferred high-disruption legacy flags

The following legacy flags are deliberately not being bulk-copied into API-101 yet: `block_pm_query`, `app_list`, `block_process_list`, `block_mounts`, `hide_mounts`, `block_netstats`, `block_net_ifaces`, `fs_*`, and root/kernel/SELinux visibility flags. The legacy source itself marks many of these as destructive because empty package/process/network/mount results can crash or disable ordinary app features. Each needs an explicit per-app safety tier, return-type-correct filtering, fail-open handling and targeted regression tests before migration.

Location spoofing flags (`mock_location`, `perapp_mock`, `gnss_spoof`, `gps_accuracy`) also remain separate work: the current API101 passive-location suppression is not equivalent to location spoofing. Do not count similarly named switches as feature parity.

## Root publisher/UI integration blocker

The extracted working FX tree now has matching per-app UI fields and a root-side Remote Files publisher for the API101 schema; host regression tests pass. However, these root files are not yet part of this isolated GitHub branch or a rebuilt KernelSU ZIP. Treat the bridge as source-audited, not yet proven in an installed end-to-end module.

## APK signing continuity blocker

The currently bundled legacy API101 APK and the new dual-entry validation APK do not share a signing certificate:

- Existing bundled `optional/FXAdHook.apk` certificate SHA-256: `813D183D0EB10810E449AEFFEF5E5C938EED102E9CA66B24AD68F9EA4751080C`.
- New dual-entry debug validation APK certificate SHA-256: `2491272DA7C16DEA9A53C194C490ED92737CD73DDA3F9A50CFB4B9CC905D88FB`.

Therefore, the debug validation APK must not be pushed as an in-place update to an installed `de.privacyguard.adhook` package. A production build needs a stable release keystore, and the first migration from the old signing identity requires a controlled uninstall/reinstall (or a deliberately changed applicationId). The installer must continue to fail safely on signature mismatch and must not silently uninstall user apps. The API82+API101 validation artifact is not the final deployable APK.

## Region and entitlement boundaries

The Hook can diagnose app locale/time-zone configuration, explain region-related failures, and expose official app-side region settings where supported. It must not claim to remove server-side country restrictions without a VPN, falsify network location, or override account eligibility.

For rewarded ads, the Hook can identify and preserve the real rewarded-ad flow and diagnose its lifecycle. It must not synthesize reward callbacks or bypass the provider's server-side validation. For VIP, it can observe read-only billing/member state and help diagnose display/state inconsistencies; it must not forge purchase receipts or grant paid entitlements.

## Remaining integration work

- Consolidate API-82 and API-101 into one APK only after runtime and config-bridge validation.
- Reconcile remaining legacy feature switches against actual modern implementations; `mic_hw_hide` and `audio_fp_block` now have API101 target-level implementations with the explicit coverage limits recorded above. Many other legacy flags remain unmigrated.
- Connect the Hook's single target/config registry to the FX UI and root-side config publisher.
- Validate the complete KernelSU ZIP and module lifecycle separately from the Hook APK.
- Perform real-device verification on the OnePlus 12; CI cannot substitute for it.

## Microphone privacy migration checkpoint (2026-10-30)

API-101 now wires the existing `mic_block` config flag into opt-in `AudioRecord.read()` interception. The root config parser already accepts `mic_block`; the new `AudioPrivacyPolicy` keeps suppression disabled unless the privacy master switch is enabled, exactly one package is attributed to the process, and that package's own `mic_block` flag is enabled. System, FX Hook, LSPosed Manager, unknown targets and shared-UID processes fail open.

The interceptor zero-fills supported `AudioRecord.read()` byte[], short[], float[] and ByteBuffer buffers and returns the number of zeroed elements/bytes. It does not claim to cover `MediaRecorder`, native audio capture, vendor-specific paths or every OEM implementation. It must be verified on target devices before describing it as complete microphone protection.

GitHub Actions run `41052177773` (commit `b608ed9678d8b94dd4f8a8431391c55692b45d88`) passed all regression checks, JUnit tests, API82+API101 single-APK compilation, APK signature verification and metadata/DEX checks. Validation artifact `FXHook-API82-API101-single-apk-validation` ID `12974079489`, SHA-256 `51ae857a080e98eb55437efa9da38dd6010e09c345ee50f864fb25d7b2926cae`. This is a debug-signed validation artifact only, not the final release APK or KernelSU ZIP, and does not establish runtime loading on either framework or real-device microphone behavior.

## API101 privacy migration checkpoint — 2026-10-30

GitHub Actions run [41057506685](https://github.com/vip-svip/SY/actions/runs/41057506685), commit `b746c44af0450d5f3e9cbb73f5a727059de594ff`, completed successfully. It passed exact-source restoration, API82/API101 single-APK wiring checks, host regression scripts, JUnit tests, APK assembly, APK signature/DEX/metadata verification and artifact upload.

New opt-in API101 migrations in this validated build include:
- `mic_hw_hide`: input-device/hardware enumeration privacy. It does not prove microphone capture is disabled.
- `audio_fp_block`: bounded low-amplitude perturbation on supported `AudioRecord.read` buffer overloads; it is not a guarantee of defeating audio fingerprinting and does not cover MediaRecorder, AAudio/Oboe or native capture.
- `clipboard_isolate`: process-local, memory-only clipboard reads/writes for a selected single-package process. It does not isolate multi-process applications or clipboard change listeners; `clipboard_read_block` takes precedence.
- Notification-listener/notification-permission visibility, UsageStats and accessibility-service visibility controls, each opt-in and guarded by single-package/protected-package fail-open policy.
- Biometric hardware enumeration privacy flags for fingerprint/face capability surfaces.

Regression output confirms these suites passed in run 41057506685: microphone hardware, audio fingerprint, clipboard isolation, notification/usage/accessibility, and biometric hardware. The unified API82/API101 debug APK artifact is ID `12977491990`, archive SHA-256 `4fd04b79c390c6a2b39eb35f21acebba60fc0d138cf96705c1d726bceefb3f32`. The API101 source snapshot artifact is ID `12977601764`, archive SHA-256 `ba87b1ebd7fe11f81f2938485fc48e2f466d546d736f46a13a369daddbb410f4`.

These are CI and static/host-test results only. They do not verify runtime injection on API82/API101 LSPosed devices, behavior on the OnePlus 12, or compatibility with arbitrary third-party applications. The artifact is still a debug-signed validation APK; no release key is available, and the final KernelSU ZIP has not been rebuilt.

## Complete source export checkpoint — 2026-10-30

The latest successful GitHub Actions run is [41058540824](https://github.com/vip-svip/SY/actions/runs/41058540824), commit `c95ebf8f315cdacabee9e76d6f75c48c098ada45`. It passed exact source restoration, API82/API101 single-APK wiring, host regressions, JUnit tests, APK assembly, signature/DEX/metadata verification, and artifact uploads.

- Unified debug APK artifact: `12978570987`, archive SHA-256 `f60e340aabcce39b78f286fa8525538c0112b17d87b6fd27bffb32b3179ebf65`.
- Complete Java source artifact: `12978585976`, archive SHA-256 `ba31268eb0a238792b4e9f85ed33987e09da1e7e79f437a78cb290192442bb9e`.
- Compiled API101 `AdVisibilityHook.java` SHA-256: `abe61fe86118a3f0586dde534a7a638b596c61ba9cf7530479c8c79416f87bb4`.
- Patched API82 `MainHook.java` SHA-256: `89318e226aaedaca2b9a5917791426c815ada47b29d4b16f3dd6e25774235017`.

This snapshot includes input-method enumeration privacy in addition to the previous opt-in privacy migrations. The complete source artifact was downloaded and synchronized into the recovered local FX working tree. This is still a debug-signed validation build; framework runtime discovery/injection, config publication on device, release signing, and OnePlus 12 testing remain unverified. The final KernelSU ZIP has not been rebuilt.
