# FX 1.0.0 clipboard read privacy migration

The API-101 Hook now has an independent per-app `clipboard_read_block` option under the existing privacy master switch.

Behavior:
- Intercepts `ClipboardManager.getPrimaryClip()`, `hasPrimaryClip()`, and legacy `getText()` when the selected package is the only package known in the process.
- Read methods return `null` / `false`; clipboard writes are not intercepted.
- The privacy master switch must be enabled and the package must be selected in both FX configuration and LSPosed scope.
- Shared-package processes, unselected packages, protected system packages, missing configuration, and hook-registration failures fail open.
- This is not a per-app clipboard store and does not modify clipboard contents.

Regression coverage:
- Parser and serializer round-trip for `clipboard_read_block`.
- Privacy-master-off behavior.
- Pure policy tests for single-package enforcement, shared-process fail-open, and protected package fail-open.
- Root publisher regression verifies clipboard-only targets survive multi-user Remote Files publication.

GitHub Actions workflow `41027166801` passed the Java/Android unit tests, APK build, signature verification, and API-101 metadata checks. Real-device behavior on OnePlus 12 with the installed LSPosed version still requires physical validation.
