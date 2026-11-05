# FX Hook migration: Wi-Fi scan privacy

Date: 2026-10-30

Legacy switch: `block_wifi_scan`.

Modern API 101 wire keys: global `wifi_scan_enabled` and per-app `wifi_scan_block`.

The existing global setting is published independently from the app's selected target. The API-101 runtime intercepts only `WifiManager.getScanResults()`, `startScan()`, and `isScanAlwaysAvailable()`. Wi-Fi association, DHCP, sockets, VPN routing, DNS, and connectivity APIs are not intercepted.

Shared-package processes, unknown package state and protected framework/FX/LSPosed packages fail open. Hook registration failures preserve original behavior.

Host-side parser/serializer/policy and shell publication regressions pass. Android Gradle CI and OnePlus 12 device injection are pending. The legacy API 82 APK remains separate; this migration does not complete the unified Hook merge.
