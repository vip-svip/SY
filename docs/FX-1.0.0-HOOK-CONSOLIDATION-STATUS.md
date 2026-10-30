# FX 1.0.0 Hook consolidation status

## Current verified state

The isolated branch fx-v1.0.0-cloud-validation builds the API-101 Hook APK. The latest run completed all CI steps successfully: unit tests, debug APK assembly, APK signature verification, modern LSPosed metadata checks, and artifact upload.

The API-101 source restoration pipeline applies bounded, hash-checked patches before compilation. Verified privacy additions in this pipeline are:

- Android ID privacy: app-scoped transformation; shared-package processes fail open.
- Sensor enumeration and sampling-rate controls: opt-in and single-package guarded.
- Clipboard read protection: reads only; writes are untouched; shared-package processes fail open.
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

The local FX root-side generator was inspected: it derives the legacy `xposed.conf` and modern LSPosed Remote Files payload from the same `settings.conf`. Legacy target-app hooks still read the legacy mirror; modern hooks read Remote Files. This is a dual-publication bridge, not proof of identical feature semantics. The root-side generator itself is outside this API-only validation branch and must be carried into the final module integration.

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

