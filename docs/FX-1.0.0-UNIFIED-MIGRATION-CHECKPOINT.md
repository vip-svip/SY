# FX 1.0.0 — Unified Application Migration Checkpoint

Updated: 2026-11-03 (Asia/Tokyo)

## Authoritative GitHub location

- Repository: vip-svip/SY
- Working branch: fx-v1.0.0-unified-hook-integration
- Head when this checkpoint was written: bc8dfa36a39e46378db17be0a899a498aa7de891
- All migration changes are committed to this branch. Do not recreate a parallel branch or ask the user to re-upload the source intake artifact.
- Do not create numbered backups.
- Do not build or publish the final APK/KernelSU ZIP until the three application migrations are complete. The build workflows are manual-dispatch only during this phase.

## Unified APK requirement

The final deliverable remains one native FX Hook APK integrated with the FX KernelSU module. Do not use external APK launchers, WebView wrappers, or competing VpnService instances as substitutes for migration. Yulong AdBlock filter/DNS/Root Proxy functions must reuse FX's network architecture. Its original second VpnService must not be installed.

## Dia 23.11 — migrated into FX

Existing native integration surfaces include:

- Third-level suite page and original function-category/fourth-level navigation.
- Per-app Hook configuration and advanced privacy controls.
- Device test fixtures on debuggable target apps: Android ID, time zone, GPS coordinates/accuracy, Wi-Fi SSID/BSSID, and Wi-Fi/cellular network type. These are per-target process hooks and do not modify system identity, real network attachment, or system GNSS.
- Custom Hook manager: legacy owner#method()Z, Java exact signatures, Smali/JVM descriptors, per-rule OBSERVE/OFF, priority, JSON bulk import/export, and bounded per-target rule count.
- Frida environment, local loopback service control, debug-target selection, script import/export, original sample archive, and monitoring templates for HTTP, SQL/SQLCipher, algorithm methods, Intent, View, Fragment, Thread, Activity stack, Runtime, key events, Native exports, ClassLoader, and HPROF.
- Native Activity browser, DEX browser, signature information, database/memory inspector, and backup manager.
- Native JSON tool: offline format/minify/validate, JSON path lookup, and SAF import/export.
- Native file manager: SAF-granted folder browsing, create/import/preview/export/delete, plus read-only SO inventory for user-installed debuggable APKs.
- Original Dia JavaScript page remains distinct from Frida injection; FX QuickJS and Frida are not represented as the same runtime.

Remaining Dia work is not complete merely because a menu exists. Continue matching any remaining original Activity/layout behaviors and make every mapped page perform its actual operation. Features that are intentionally debug-only must remain scoped to debuggable targets.

## Yulong AdBlock 7.0.1 — migrated into FX

Existing native integration surfaces include:

- Native home, filter-source list CRUD, domain allow/block list CRUD, DNS settings, local DNS query log viewer, VPN/Root Proxy controls, scheduled enable/disable, app traffic statistics, and general diagnostics routing.
- Root-backed per-app IPv4/IPv6 firewall with a dedicated native UI and independent chain ownership; this is separate from FX per-app VPN routing.
- Root Proxy fallback reuses FX's Unbound/AdGuard Home and validates the external VPN path before DNS redirection; failures must roll back FX-owned rules.
- Tasker/automation action copy controls and original task actions.
- Local-only protection summary: active rule-source counts, allow/block counts, and at most the latest 500 local DNS query log entries. This sample must not be labelled as a complete daily total.
- Original AdBlock VpnService is not installed or started. FX continues to use one network ingress.

Remaining AdBlock work: continue bringing any remaining original settings/control behavior into the native page, preserving the original independent rule, DNS, firewall, Root Proxy, automation, and schedule semantics.

## Yulong Security Shield 9.9.60 — migrated into FX

Existing native integration surfaces include:

- Virus database and name/package matching, cached database, optional APK content signature scan, manual scan, installation/update scan, whitelist and control-list management.
- Contextual risk warning carrying the selected package, label, and match reason. Uninstall is always handed to Android's system confirmation UI.
- Batch cleanup queue that opens each system uninstall confirmation individually; no silent uninstall, force-stop, or freeze.
- APK signing/integrity view for the installed FX package.
- Foreground monitoring via Usage Access, with blacklist warning and whitelist exclusion.
- User-controlled foreground service with persistent notification.
- User-controlled volume-key and shake rescue notices; Accessibility is optional and is never silently re-enabled.
- Floating rescue overlay with explicit overlay permission flow.
- Boot recovery and a low-frequency 15-minute recovery Alarm while the user has enabled protection or rescue triggers.
- Daily summary for warning, install-scan, and rescue counters.
- Stellar manager remains inside the Shield suite, not an FX primary navigation tab.

Remaining Shield work: the original aggressive two-minute watchdog, forced Accessibility recovery, and some original overlay/permission-degradation behaviors have not been cloned. Do not silently restore permissions or force-stop target apps. Continue matching remaining original list/scan/backup/help behavior inside the suite.

## Packaging rule

No final package was generated for this checkpoint. The user explicitly requested that all code changes remain on GitHub and that the final package be created only after all three migrations are complete. A future package must be built from the then-current branch HEAD, and the APK embedded in the KernelSU ZIP must be byte-for-byte identical to the separately published paired APK. Do not reuse artifacts from an older commit.

## Verification wording

Source integration is not a successful build. A future successful CI build is not real-device verification. Do not claim device validation unless it has actually been performed on a device.
