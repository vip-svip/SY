# FX 1.0.0 EXIF Hook publisher/UI integration

The API-101 EXIF privacy feature is now connected end-to-end in this package:

- `webroot/index.html` exposes a per-app EXIF metadata redaction checkbox, preserves it on app-list refresh, validates it, and serializes it into `hook_targets`.
- `scripts/gen_xposed_conf.sh` accepts `exif_strip=0|1`, includes it in the modern LSPosed Remote Files schema, and allows an EXIF-only target. The legacy `xposed.conf` payload remains backward-compatible and does not receive the modern-only field.
- `scripts/status.sh` counts either Android ID isolation or EXIF redaction as an active privacy target.
- The modern APK parser/runtime and serializer support the same `exif_strip` field.

Host verification against this package:
- Shell syntax checks for `gen_xposed_conf.sh` and `status.sh`: PASS.
- Node syntax check for all 33 inline WebUI script blocks: PASS.
- `v1.0.0-lsposed-remote-file-config-regression.sh`: PASS.
- `v1.0.0-lsposed-ad-hook-target-scope-regression.sh`: PASS.
- `v1.0.0-lsposed-remote-status-ui-regression.sh`: PASS.
- `v1.0.0-lsposed-ui-single-apply-pipeline-regression.sh`: PASS.
- `v1.0.0-fxhook-migration-baseline-regression.sh`: PASS.

The API-101 APK was built and signed by GitHub Actions; it is debug-signed, not a production release signature. OnePlus 12 / LSPosed runtime behavior remains unverified. The API-82 legacy APK remains separate.
