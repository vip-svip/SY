# FX Hook APK installer signature-mismatch safety

The installer detects PackageManager signature-update failures, including `INSTALL_FAILED_UPDATE_INCOMPATIBLE` and “signatures do not match”. It writes an explicit `signing certificate differs` diagnostic, stops retrying that APK, and does not uninstall the existing package or touch its app data.

The host regression simulates a mismatch after an existing FXAdHook install and verifies that the package remains installed, no uninstall call occurs, and the diagnostic is written to the install log.

GitHub Actions run `41027907193` passed the installer regression, API-101 unit tests, APK build, APK signature verification, and Xposed resource checks. This is host/CI evidence, not a substitute for a physical-device install test.
