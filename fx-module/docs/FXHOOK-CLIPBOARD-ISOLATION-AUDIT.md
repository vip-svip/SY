# FXHook clipboard isolation audit — FX 1.0.0

## Finding

The legacy API-82 `clipboardGuard()` implements `clipboard_isolate` as process-local clipboard shadowing: after a successful `setPrimaryClip()`, it stores the supplied `ClipData` in a static process field; `getPrimaryClip()` and `hasPrimaryClip()` return that field. This is not equivalent to the API-101 `clipboard_read_block` feature, which simply suppresses reads.

The legacy behavior is not OS-level cross-app isolation. It is only process-local shadow state, and shared-process packages can observe the same state. Do not describe it as a system clipboard sandbox.

## Migration contract

- Add a distinct per-target `clipboard_isolate` bit throughout editor, publisher, parser, and runtime.
- Cache only after the original `setPrimaryClip()` succeeds.
- Read APIs return the process-local cached value only for a single-package process.
- Shared-package process, missing config, and unavailable hooks fail open to the original platform API.
- Keep `clipboard_read_block` independent; reject simultaneous activation unless precedence is explicit and tested.
- Do not modify system clipboard service state, permissions, or OS privacy indicators.

## Status

Audit and acceptance criteria only. API-101 runtime/config/UI wiring is not implemented. No physical-device verification has been performed.


## Implementation update (2026-10-30)

The current FX 1.0.0 working package now contains an API-101 process-local shadow implementation and distinct per-target `clipboard_isolate` configuration. It hooks `setPrimaryClip`, `getPrimaryClip`, and `hasPrimaryClip`; shared processes fail open. The editor and publisher are wired. Host parser regression coverage is added. Real-device/API-level verification remains pending, and this must not be described as system-wide cross-app isolation.


## UI claim correction

The root settings description now calls this **process-local clipboard isolation** and explicitly states that shared processes fail open and that the feature does not provide system-wide cross-app isolation. This avoids claiming stronger privacy semantics than the API-101 implementation provides.
