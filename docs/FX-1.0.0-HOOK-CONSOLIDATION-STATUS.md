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

The dual-entry static regression, exact API82 source restoration, unit tests, APK compilation, signature verification and metadata/DEX checks passed in GitHub Actions run `41050895875` (commit `1b02ff187c2202aacf30dbd7c186c9a58be613bf`). Validation artifact `FXHook-API82-API101-single-apk-validation` (artifact ID `12974612431`) contains one `app-debug.apk`; APK SHA-256: `b1ec4131c92722a540edc42862a2f3c38b80b7924593a9410e26abf82dfa7a7d`. Inspection confirmed both entry descriptors and both Hook classes are present in the same APK. This is a debug-signed build validation, not a release-signed update package. Framework discovery/loading on API 82 and API 101 runtimes remains unverified. The final KernelSU ZIP is not rebuilt.

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

## Region and entitlement boundaries

The Hook can diagnose app locale/time-zone configuration, explain region-related failures, and expose official app-side region settings where supported. It must not claim to remove server-side country restrictions without a VPN, falsify network location, or override account eligibility.

For rewarded ads, the Hook can identify and preserve the real rewarded-ad flow and diagnose its lifecycle. It must not synthesize reward callbacks or bypass the provider's server-side validation. For VIP, it can observe read-only billing/member state and help diagnose display/state inconsistencies; it must not forge purchase receipts or grant paid entitlements.

## Remaining integration work

- Consolidate API-82 and API-101 into one APK only after runtime and config-bridge validation.
- Reconcile all legacy feature switches against actual modern implementations; port only semantically equivalent, tested behavior.
- Connect the Hook's single target/config registry to the FX UI and root-side config publisher.
- Validate the complete KernelSU ZIP and module lifecycle separately from the Hook APK.
- Perform real-device verification on the OnePlus 12; CI cannot substitute for it.
