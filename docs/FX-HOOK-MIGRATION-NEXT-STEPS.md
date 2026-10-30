# FX Hook migration next steps

## Verified legacy source availability (2026-10-30)

The complete legacy source needed for migration is present in the user's current Library archive `FX-v1.0.0-KernelSU.zip`, extracted in the active working copy at:

`lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java`

Verified size: 2,073 lines / 96,340 bytes. This is the full historical API-82 entrypoint in the supplied FX ZIP, not the much smaller 8 KB `MainHook.java` found on the old GitHub branch. The Iter5 archive itself is not separately present in the Library listing; do not conflate the two.

The source declares `IXposedHookLoadPackage`, `XC_MethodHook`, `XposedBridge`, and `XposedHelpers`, and reads `/data/local/tmp/privacyguard/xposed.conf`. It cannot be copied unchanged into the API-101 module: the callback API differs and target-app processes must use LSPosed Remote Files rather than assuming root-side config paths are readable.

## Migration requirements

Preserve the full legacy feature inventory and per-feature switches while porting API-82 callbacks to libxposed API 101. Do not silently drop legacy features or claim the two APKs are unified until CI builds a single APK and device injection is verified.

Configuration must be read through LSPosed Remote Files, parsed transactionally, and support independent ad and privacy switches. Invalid, missing, oversized, malformed, or unsupported configuration must install no hooks.

## Current verified state

- The modern `AdVisibilityHook` runtime uses `UnifiedHookConfigParser.parse(content)` and LSPosed Remote Files.
- The legacy entrypoint is 2,073 lines / 96,340 bytes in the current FX ZIP; it is available for source migration.
- The modern API-101 runtime contains package-scoped ad View observers, read-only Billing diagnostics, Android ID transformation, EXIF redaction, clipboard-read policy, and sensor privacy policy. Source presence is not proof of device behavior.
- API-101 now includes Chinese rewarded-flow UI evidence, bounded member DEX candidate scanning, dynamic class-load observation, and capped read-only candidate getter hooks. GitHub Actions verified compilation, signing, Xposed resources and the expected DEX markers; no OnePlus 12 runtime verification has been performed.
- Billing and membership handling must remain read-only. Never synthesize rewarded-ad callbacks, purchases, or server-side entitlements.
- The two APK package identities remain separate: `de.privacyguard.hook` and `de.privacyguard.adhook`.
- The KernelSU module package workflow must fail closed if required module source files are missing; never emit a partial ZIP.

## Remaining migration sequence

1. Create a method-by-method inventory from the supplied 2,073-line legacy source and map each switch to its existing UI/config key.
2. Continue porting deterministic, low-risk privacy protections with independent opt-in switches, package-scope checks, API guards, and fail-open compatibility behavior. The bounded membership observer is diagnostic-only and must not change entitlement state.
3. Keep destructive or high-breakage transforms (package/process hiding, telephony, location, camera/microphone, filesystem and system-property manipulation) disabled until each has dedicated API/OEM regression tests.
4. Port the ad runtime and read-only membership diagnostics without changing ad reward callbacks, purchase state, or server-side validation.
5. Consolidate package identity, LSPosed metadata, entrypoint, target scope and Remote Files transport only after every retained feature has an explicit migration status and the single APK builds in CI.
6. Require host regression tests, APK signature/resource checks, and separate OnePlus 12 LSPosed injection/behavior verification before calling the deliverable complete.
