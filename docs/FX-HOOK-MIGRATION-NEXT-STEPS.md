# FX Hook migration next steps

## Verified source availability

The historical project notes refer to an Iter5 archive, but that archive is not present in the current `vip-svip/SY` branch tree or the Library search results available during the 2026-10-30 continuation. The only legacy source currently located in the repository is the small `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` implementation on the older `fx-v1.0.0-privacyguardhook-build` branch; it is not the complete legacy Hook implementation.

Do not state that the full legacy source is available until the archive itself is recovered and inspected. The Library contains a SHA-256 sidecar for `FX-v1.0.0-KernelSU.zip`, but a digest alone cannot reconstruct the ZIP.

## Migration requirements

The migration must preserve feature switches and package scope while porting API 82 callbacks to libxposed API 101. The APIs are not source-compatible. Do not claim a unified APK until CI builds it and device injection is verified.

Configuration must be read through LSPosed Remote Files, parsed transactionally, and support independent ad and privacy switches. Invalid or missing configuration must disable hooks safely.

## Current verified state

- The modern `AdVisibilityHook` runtime calls `UnifiedHookConfigParser.parse(content)`.
- Legacy ad-only configuration remains backward compatible and must not silently enable privacy hooks.
- Android ID privacy transformation is package-scoped and the process-level interceptor registration is guarded against duplicate registration.
- Billing-related behavior remains read-only diagnostics; do not alter purchase state or forge entitlement results.
- The two APK packages are still separate; the current installer installs `de.privacyguard.hook` and `de.privacyguard.adhook` independently.
- The KernelSU module source tree is incomplete. The package workflow must continue to fail closed rather than produce a partial ZIP.

## Remaining migration sequence

1. Recover and inspect the actual Iter5 archive or complete legacy source tree.
2. Build a feature-by-feature API 82 to API 101 migration matrix, preserving explicit per-app scope and opt-in switches.
3. Port only supported privacy-protection behaviors; retain read-only diagnostics for billing and do not bypass server-side entitlements, anti-fraud, or anti-cheat controls.
4. Consolidate the two APKs only after the package identity, LSPosed metadata, module entrypoint, scope, config transport, and migration tests are unified.
5. Restore the missing KernelSU module sources from the original implementation; do not replace them with placeholder scripts or UI.
6. Require CI, APK signature/resource checks, host-side regression tests, and separate OnePlus 12 device verification before calling the deliverable complete.
