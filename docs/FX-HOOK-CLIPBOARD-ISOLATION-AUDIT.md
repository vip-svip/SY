# FXHook clipboard isolation migration audit

Date: 2026-10-30

## Legacy behavior
API-82 `clipboardGuard()` implements `clipboard_isolate` by retaining the current process's last successful `ClipData` write and returning that cached value from `getPrimaryClip()` and `hasPrimaryClip()`. This is process-local shadowing, not Android-wide clipboard isolation.

## API-101 implementation
- Independent global `clipboard_isolate_enabled` master and per-target `clipboard_isolate` flag.
- Both the global privacy master and clipboard isolation master must be enabled.
- Hooks `setPrimaryClip(ClipData)`, `getPrimaryClip()`, and `hasPrimaryClip()`.
- Shared-package processes fail open.
- Mutually exclusive with `clipboard_read_block`; parser rejects conflicting target configuration.
- UI target editor, Remote Files publisher, apply gate, and status JSON are wired in the FX 1.0.0 working package.

## Verification boundaries
Parser/serializer host round-trip checks and package shell/JS regressions are separate from Android APK build verification. This implementation is not system-wide isolation. Real-device behavior and Android API-level compatibility require testing on the target device. The two APKs are still separate; this does not complete the unified-app migration.


## CI result

- GitHub Actions run: https://github.com/vip-svip/SY/actions/runs/41080488374
- Source commit used for the build: `b6ad480bca8a2489aa4060ab8bf7ec8f9baf8930`
- Result: parser/serializer unit tests, Android debug APK build, APK signature verification, Xposed metadata checks, and DEX marker checks all passed.
- APK SHA-256: `778b07f84b924629969a849c4ef2b8ce68df3bed277e638190f583b2e79d9991`
- This verifies CI build output, not LSPosed injection or behavior on a physical OnePlus 12.


## Follow-up wording accuracy check

The root FX package settings UI was corrected to describe this as process-local clipboard shadowing. It no longer claims that different apps' clipboards are mutually invisible at OS level; it explicitly states that shared processes fail open and that this is not system-wide cross-app isolation. Host regression checks verify the UI claim.
