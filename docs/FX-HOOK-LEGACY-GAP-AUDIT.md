# FX 1.0.0 Legacy Hook Gap Audit

Branch: `fx-v1.0.0-cloud-validation`
Audit source: restored API82 MainHook.java snapshot plus API101 source patch chain (validation branch; original FX ZIP remains untouched)
Audit date: 2026-10-30

## Verified host-side checks

- `scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh`: PASS
- `scripts/tests/v1.0.0-lsposed-ad-hook-target-scope-regression.sh`: PASS
- These tests do not prove LSPosed injection or behavior on a physical OnePlus 12. Latest validation run 41058264335 passed the API82/API101 single-APK build, exact-source patch hashes, host regressions, JUnit tests, signature/DEX/metadata checks and artifact upload.

## Legacy implementation inventory

The Iter5 `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` contains the following distinct feature groups. The modern `adhook` runtime is not feature-equivalent; it currently implements ad-view observers, read-only membership diagnostics, and an opt-in package-scoped Android ID transform only.

| Legacy method/group | API101 migration status | Remaining coverage / risk |
|---|---|---|
| buildSpoof, kernelVersionHide, sysPropsHide | Not migrated | Device build/system property spoofing remains legacy-only; do not claim kernel or property concealment parity. |
| secureSettingsSpoof, serialSpoof, telephonySpoof | Android ID only | IMEI/SIM/serial/line number and secure-settings spoofing are not migrated. |
| btWifiMacSpoof, batterySpoof, screenSpoof, storageSpoof | Not migrated | Device identity and hardware property spoofing remain deferred pending API-specific compatibility tests. |
| clipboardGuard, sysSvcHide | Clipboard read block and process-local isolation migrated; system-service hiding not migrated | Clipboard isolation is process-local and in-memory; multi-process synchronization/listener notifications are not covered. |
| appListHide, pmQueryHide, procListHide | Not migrated | High app-breakage risk: package/process enumeration must be filtered type-safely and only under explicit safety tiers. |
| mediastoreHide, netIfacesHide, netStatsHide, vpnHide | MediaStore read/query privacy migrated; network/VPN concealment not migrated | Do not interfere with VPN coexistence, routing, network diagnostics or connectivity checks. |
| imeHide / block_ime_logging | Migrated | Empty-list responses cover InputMethodManager IME/subtype enumeration only; may break keyboard selection and subtype discovery. |
| locationMock, gnssSpoof, passiveLocHide, wifiScanHide, sensorHide | Passive-location suppression, Wi-Fi scan privacy and sensor enumeration/rate controls migrated | Location spoofing (mock_location, perapp_mock, gnss_spoof, gps_accuracy) remains unmigrated; passive-location hiding is not spoofing. Cell-info privacy is also migrated. |
| cameraNull, micBlock, mic_hw_hide, audioFpBlock, bioHide | mic_block silence, mic_hw_hide input enumeration, audio_fp_block sample perturbation and fingerprint/face capability-query concealment migrated | mic_block does not cover MediaRecorder/AAudio/Oboe/native capture; mic_hw_hide does not remove FEATURE_MICROPHONE or every OEM API; audio perturbation is not universal; cameraNull remains unmigrated. BiometricManager reports no hardware if either biometric concealment flag is active. |
| notifHide, notifPermHide, usageHide, a11yHide, exifStrip | Active-notification queries, notification-enabled query, queryUsageStats, accessibility-service enumeration and EXIF getter redaction migrated | These are app-facing query transformations; they do not revoke Android permissions, disable notification services or rewrite EXIF files. |
| hide_notif_perm, block_notif_listen, usagestats_off, a11y_hide | Migrated to independent per-target flags | Explicit opt-in only; accessibility and notification query hiding can break host-app features. |
| rootHide, fsHooks and filesystem attribute/VFS helpers | Not migrated | High stability and security compatibility risk; remain disabled pending per-API design and device tests. |
| adIdUnify | Not migrated | Distinct from Android ID; do not imply Advertising ID coverage. |
## Configuration and activation invariants

1. The modern Remote Files payload is versioned and parsed transactionally.
2. Legacy ad-only configuration intentionally leaves modern privacy disabled.
3. The UI application selection and LSPosed Manager scope are both required; either gate missing means no target-process effect.
4. `lsposed_enabled` is the legacy MainHook master switch; `hook_ads_enabled` and `hook_privacy_enabled` control the modern ad/Android-ID runtime and are not interchangeable.
5. The root-side generator reports Remote Files publication status separately from legacy `xposed.conf`. A successful legacy config write is not proof that the modern APK can read its Remote Files.
6. Membership support remains read-only diagnostics. No purchase result or entitlement should be modified.

## Next implementation sequence

1. Add a single runtime ownership rule so old and modern modules cannot both install overlapping hooks unintentionally.
2. Keep legacy features explicitly labelled as legacy until each has a modern API 101 implementation and tests.
3. Migrate low-risk, deterministic features first; add API-level and package-scope tests before enabling any feature.
4. Complete root-side FX UI/config publisher integration so every new per-target field is published consistently to legacy xposed.conf and API101 Remote Files; this is not yet proven in the validation branch.
5. Test APK installation/update/removal and Remote Files access on a real LSPosed device.
6. Only then integrate a validated APK into the complete FX ZIP. Do not replace the preserved Iter5 archive with an unverified candidate.
