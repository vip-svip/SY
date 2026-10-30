# FX 1.0.0 EXIF Hook publisher/UI integration

The recovered FX package source was updated to complete the missing API-101 configuration path:

- `scripts/gen_xposed_conf.sh` now accepts `exif_strip=0|1`, preserves it in the modern LSPosed Remote Files schema, and permits an EXIF-only target. The legacy `xposed.conf` format remains unchanged.
- `webroot/index.html` now exposes a per-app “EXIF 元数据脱敏” checkbox, preserves the setting on app-list refresh, validates it, and serializes it into `hook_targets`.
- `scripts/status.sh` counts either Android ID isolation or EXIF redaction as an active privacy target.
- The publisher regression now covers multi-user publication, privacy-master behavior, and an EXIF-only target.

Host verification on the recovered package:
- Shell syntax checks for `gen_xposed_conf.sh` and `status.sh`: PASS.
- Node syntax check for all 33 inline WebUI scripts: PASS.
- `v1.0.0-lsposed-remote-file-config-regression.sh`: PASS.
- `v1.0.0-lsposed-ad-hook-target-scope-regression.sh`: PASS.
- `v1.0.0-lsposed-remote-status-ui-regression.sh`: PASS.
- `v1.0.0-lsposed-ui-single-apply-pipeline-regression.sh`: PASS.
- `v1.0.0-fxhook-migration-baseline-regression.sh`: PASS.

This closes the previously missing root-publisher/UI serialization path for the already-built API-101 EXIF option. It is host-verified only; OnePlus 12 / LSPosed runtime behavior remains unverified. The API-82 legacy APK is still separate and has not been represented as merged.
