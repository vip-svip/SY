# FXHook single-APK merge audit — FX 1.0.0

Date: 2026-10-30

## Current facts

| Item | Legacy API-82 | Modern API-101 |
|---|---|---|
| applicationId | `de.privacyguard.hook` | `de.privacyguard.adhook` |
| Hook API | `de.robv.android.xposed:api:82` | `io.github.libxposed:api:101.0.1` |
| Entry | `MainHook` via `assets/xposed_init` | `AdVisibilityHook` via `META-INF/xposed/java_init.list` |
| minSdk | 27 | 28 |
| Config | legacy `xposed.conf` | LSPosed Remote Files `fx-hook-targets.conf` |

The installer currently installs two packages. API-101 is the future unified runtime, but it does not yet implement the complete legacy feature set.

## Why direct APK merging is unsafe

1. API-82's `XposedBridge` / `IXposedHookLoadPackage` entrypoint is not a libxposed API-101 entrypoint.
2. API-101 uses `XposedModule`, `onModuleLoaded` / `onPackageReady`, and Remote Files; API-82 uses `handleLoadPackage` and a legacy file config.
3. Changing both application IDs to the same value does not merge the runtime; it creates PackageManager update conflicts. Same-package upgrade also requires compatible signing identity and data migration.
4. API-101 minSdk 28 while API-82 minSdk 27. The unified runtime must explicitly decide whether API 27 support is dropped.
5. Scope, config schema, and initialization timing differ. Unmigrated features could silently stop working.

## Migration policy

Candidate features must be transparent, opt-in, independently gated, fail-open, and tested per target app. Examples include explicit camera/microphone access blocking, supported EXIF read-time redaction, sensor limits, notification-status query privacy, and process-local clipboard shadowing.

Do not port stealth/evasion or identity-forgery features as-is: root/kernel/module concealment, VPN visibility hiding, app/PackageManager/process-list hiding, IMEI/SIM/serial/MAC spoofing, fake location/GNSS, or permission/accessibility/usage-state deception. If privacy controls are needed, implement transparent permission controls rather than falsifying security signals.

## Merge route

1. Keep API-101 as the sole future entrypoint and port only approved features to libxposed interceptors.
2. Migrate supported legacy settings to versioned Remote Files; preserve unknown keys and provide rollback.
3. UI must distinguish migrated, legacy-only, and unsupported options.
4. Define package upgrade strategy: verify signing identity, back up both private configs, install unified APK, migrate config, verify LSPosed scope, then clean up old package. On any failure retain old APK and data.
5. Only after parity and upgrade tests should applicationId and installer be unified.
6. Test minSdk, signing, module metadata, scope, uninstall cleanup, and rollback.

## Remaining acceptance

- Most API-82 features are not migrated.
- Two APKs and two application IDs remain.
- Signing-compatible upgrade and rollback rehearsal is not complete.
- No OnePlus 12 + KernelSU + LSPosed device verification has been completed.
- Final acceptance requires one APK, one applicationId, one libxposed API-101 entrypoint, automated migration/upgrade/rollback tests, and physical-device validation.
