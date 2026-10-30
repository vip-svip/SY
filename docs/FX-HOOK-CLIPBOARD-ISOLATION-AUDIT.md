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
