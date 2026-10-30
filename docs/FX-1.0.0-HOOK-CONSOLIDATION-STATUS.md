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

## API-82 and API-101 consolidation

The two implementations are not yet consolidated into one installable APK. The current validation APK is API-101 only.

A valid one-APK consolidation needs all of the following to be proven together:

1. One applicationId and one user-facing Hook app/configuration surface.
2. The legacy API-82 entry point and its assets/xposed_init metadata.
3. The modern API-101 entry point and META-INF/xposed metadata.
4. A runtime arbitration mechanism that prevents both entry points installing duplicate hooks in the same process.
5. A configuration bridge: legacy code currently reads /data/local/tmp/privacyguard/xposed.conf, while API-101 reads LSPosed Remote Files. Both must consume the same normalized per-app settings without relying on app-UID access to root-only paths.
6. One shared feature registry and explicit migration status for every legacy feature. A legacy switch is not considered migrated merely because a similarly named modern flag exists.
7. A build and metadata test on both a legacy API-82-capable framework and an API-101-capable LSPosed runtime.

The legacy source currently has a runtime check for the modern API class and a shared-UID fail-open guard, but that alone does not prove dual-entry loading or configuration compatibility. Do not label the Hook merged until the above checks pass.

## Region and entitlement boundaries

The Hook can diagnose app locale/time-zone configuration, explain region-related failures, and expose official app-side region settings where supported. It must not claim to remove server-side country restrictions without a VPN, falsify network location, or override account eligibility.

For rewarded ads, the Hook can identify and preserve the real rewarded-ad flow and diagnose its lifecycle. It must not synthesize reward callbacks or bypass the provider's server-side validation. For VIP, it can observe read-only billing/member state and help diagnose display/state inconsistencies; it must not forge purchase receipts or grant paid entitlements.

## Remaining integration work

- Consolidate API-82 and API-101 into one APK only after runtime and config-bridge validation.
- Reconcile all legacy feature switches against actual modern implementations; port only semantically equivalent, tested behavior.
- Connect the Hook's single target/config registry to the FX UI and root-side config publisher.
- Validate the complete KernelSU ZIP and module lifecycle separately from the Hook APK.
- Perform real-device verification on the OnePlus 12; CI cannot substitute for it.
