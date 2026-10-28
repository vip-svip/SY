# FX Unified Hook 1.0.0 — Integration Plan

Status: integration branch scaffold only. This document does not claim the two APKs have been merged or that a unified APK has been built.

## Goal

Ship one LSPosed module APK containing:
- the existing FXAdHook ad-visibility hooks (modern libxposed API 101);
- the complete legacy PrivacyGuardHook privacy-protection behavior from the FX Iter5 source archive;
- independent feature switches and a shared, fail-closed target-app scope;
- one package installed and enabled in LSPosed.

## Source-of-truth findings

- `adhook/` on the repository main branch is a modern libxposed API 101 module and uses LSPosed Remote Files for its target configuration.
- `fx-v1.0.0-privacyguardhook-build` contains a much smaller legacy `MainHook.java` (about 8 KB) that primarily hides VPN applications. It is not a substitute for the roughly 96 KB `MainHook.java` in the FX Iter5 archive.
- The legacy implementation imports API 82 types (`IXposedHookLoadPackage`, `XC_MethodHook`, `XposedHelpers`, `XposedBridge`). It cannot be merged into the modern APK by simply copying its Java file: the callback and hooking APIs differ.
- The old legacy config path `/data/local/tmp/privacyguard/xposed.conf` is not a proven readable transport for ordinary target-app processes. The modern ad hook's Remote Files config currently only carries the ad target list.

## Required implementation sequence

1. Import the complete legacy source from the FX archive into this branch and inventory every API-82 dependency and hook callback.
2. Port each legacy hook to libxposed API 101 (or build a tested compatibility adapter where the modern API supports it); do not silently drop hooks.
3. Replace direct reads of `/data/local/tmp` and `/data/adb` from target-app processes with LSPosed Remote Files. Publish a versioned, bounded config containing independent `ads_enabled`, `privacy_enabled`, and target-package entries.
4. Enforce both gates: the package must be in the FX target config and LSPosed scope. A missing, malformed, oversized, or unsupported config must install no hooks and log a concise reason.
5. Keep ad and privacy feature switches independent. Billing/purchase state must not be modified.
6. Add host-side parser/scope regression tests and API-port compile checks.
7. Build one APK in GitHub Actions; verify package ID, API metadata, APK signature, and SHA-256.
8. Package it into a new FX 1.0.0 iteration without overwriting earlier archives. Real-device LSPosed injection and target-process config-read validation remain mandatory before claiming runtime success.

## Acceptance criteria

- Exactly one Hook APK is installed and presented to LSPosed.
- Both feature sets remain independently configurable.
- Complete legacy hook inventory is accounted for; no silent feature loss.
- Config access works through Remote Files in a target process, not merely from a host/root shell.
- Missing/corrupt config fails closed.
- CI build and host tests pass; real-device status is reported separately.

## Current blocker

The complete legacy source is present in the user's FX Iter5 archive, but not in the repository's current build branch. The small GitHub legacy branch must not be used as the migration source. Importing the archive's complete source is the first code step; until that happens, an integrated build would risk losing functionality.
