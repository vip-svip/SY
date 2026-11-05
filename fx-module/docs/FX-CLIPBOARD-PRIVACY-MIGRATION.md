# FX 1.0.0 clipboard read privacy migration

The API-101 Hook has an independent per-app `clipboard_read_block` option under the existing privacy master switch.

Behavior:
- Intercepts `ClipboardManager.getPrimaryClip()`, `hasPrimaryClip()`, and legacy `getText()` for a selected target.
- Read methods return `null` / `false`; clipboard writes are not intercepted.
- Both FX target selection and LSPosed scope are required.
- The implementation only blocks reads when exactly one package is known in the process. Shared-package processes, unselected/protected packages, and privacy-master-off cases fail open.
- This is not a per-app clipboard store and does not modify clipboard contents.

Regression coverage includes parser/serializer round-trip, privacy-master gating, single-package enforcement, shared-process fail-open, protected-package fail-open, and root publisher coverage for clipboard-only targets.

The GitHub Actions build is the authoritative Java/Android compile and test result. OnePlus 12 physical-device behavior still requires validation.
