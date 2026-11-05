# FX Hook migration: Wi-Fi scan privacy

Date: 2026-10-30

## Scope migrated

Legacy switch: `block_wifi_scan`.

Modern API 101 wire keys: global `wifi_scan_enabled` (mapped from the existing `block_wifi_scan` master switch) and per-app `wifi_scan_block`.

The Hook target editor stores `wifi_scan_block` per app. The root-side `gen_xposed_conf.sh` publishes the existing global `block_wifi_scan` master as `wifi_scan_enabled` and translates per-app selection into the versioned LSPosed Remote Files payload. `UnifiedHookConfigParser` validates the key; `UnifiedHookConfigSerializer` preserves it in deterministic output; `AdVisibilityHook` installs the opt-in `WifiManager` interceptors.

## Runtime behavior

- `WifiManager.getScanResults()` returns an empty list only for an explicitly selected package when the privacy master switch is enabled.
- `WifiManager.startScan()` and `isScanAlwaysAvailable()` return `false` for that same target.
- Wi-Fi association, DHCP, sockets, VPN routing, DNS, and connectivity APIs are not intercepted.
- Processes containing more than one observed package fail open. Unknown package state also fails open.
- Protected framework/FX/LSPosed packages fail open.
- Hook registration failures leave original behavior untouched (protective exception mode).

## Validation

- Pure Java parser/serializer/policy smoke test: PASS.
- Shell syntax check for config publisher: PASS.
- Focused source regression: PASS.
- GitHub Actions run `41065767887`: PASS (unit tests, debug APK build, APK signature verification, LSPosed metadata/DEX checks, artifact upload).
- APK SHA-256: `f191a9fb3e51398614f331df26e6fe1447026d104d37ae6523c80b0d7af6fff7`.
- OnePlus 12 LSPosed injection and real-device Wi-Fi scan behavior: pending device verification.

This is one migrated feature, not completion of the historical Hook parity. The old API 82 APK remains installed separately until the remaining legacy switches are migrated and parity tests are complete.
