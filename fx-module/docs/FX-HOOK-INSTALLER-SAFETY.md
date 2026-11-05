# FX Hook APK installer safety

The Hook APK installer now classifies PackageManager signature-update failures (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, “signatures do not match”, or equivalent signing-certificate text) from the current install attempt.

On mismatch it records an explicit `signing certificate differs` error, stops retrying that APK, and does not uninstall the existing package or touch its app data. The installer still verifies APK SHA-256 before staging and keeps idempotent update markers.

The host regression simulates a signature mismatch after an existing FXAdHook install and verifies that the installed package remains, no uninstall call occurs, and the diagnostic is present in the log. This test does not substitute for installing signed APKs on a physical Android device.
