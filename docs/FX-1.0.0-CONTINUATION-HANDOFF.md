# FX 1.0.0 — Continuation Handoff (current migration state)

Updated: 2026-11-03, Asia/Tokyo
Repository: `vip-svip/SY`
Branch: `fx-v1.0.0-unified-hook-integration`
Target: `FX 1.0.0`, versionCode `10000`

## Hard delivery constraints

- All changes stay on this branch.
- No interim APKs and no interim KernelSU ZIPs.
- The final paired `FXUnifiedHook.apk` and `FX 1.0.0` KernelSU ZIP are produced only after Dia 23.11, Yulong AdBlock 7.0.1 and Yulong Shield 9.9.60 source migrations are complete.
- Keep release workflows manual (`workflow_dispatch`) during migration.
- Do not claim real-device verification based on source inspection or CI.

## Migrated features already added to the FX source tree

### Unified Hook / manifest integration

- One FX APK remains the only installed app entry for the Hook runtime and migrated app screens.
- Unified Hook merge script now preserves migrated Activities, Services, Receivers and Providers when rebuilding the manifest.
- Hook target list/search/paging, Root permission and optional Accessibility service remain inside FX.
- Custom Hook rules accept Java signatures, JVM/Smali descriptors and the legacy zero-argument boolean format. The native editor has priority, per-rule OBSERVE/OFF toggles and JSON import/export. Runtime observer behavior remains limited to debuggable target packages and logs only metadata, not argument or return values.

### Dia 23.11

- Settings third-level Dia hub and four-level feature tree remain inside FX.
- Native Activity browser and DEX browser are present.
- Launcher hiding is implemented by disabling only a user app's launcher Activity component; it does not disable the whole package or touch system apps. FX records which entries it disabled so only those can be restored from this screen.
- Frida manager includes the original sample archive and help assets.
- Monitor templates cover HTTP host-only observation, SQLite method/length/duration, user-edited algorithm methods and explicit HPROF snapshots. HPROF files contain process-private memory; use only with owned debuggable test apps.
- Local JSON backup/restore is present. GitHub Contents and HTTPS WebDAV adapters are included in the Dia backup screen. Backup data covers module settings, Hook preferences, Shield preferences, Stellar authorization policy files and FX-hidden launcher state. SHA-256 verification and rollback are used for module config restore.
- Still incomplete: exact original Frida WAIT/RESUME/listener lifecycle, message/console forwarding and remaining Dia editor screens that are still routed to FX equivalents.

### Yulong AdBlock 7.0.1

- Native FX Ad page includes filter list controls, allow/deny domain lists, DNS controls, certificate/log routes, per-app firewall and per-app traffic display.
- The app-level firewall uses its own dual-stack OUTPUT chains and UID refresh. It is independent of FX per-app VPN routing.
- Independent ad-filter master uses `/data/adb/privacyguard/yulong-ad-filter.disabled` and gates only `[list:rule]`; it does not disable domain lists, anti-fraud lists, VPN or Hook privacy.
- Quick Settings tile and Tasker broadcast control the same master.
- The final build staging step must copy `yulong-ad-control.sh`, `yulong-app-firewall.sh` and `yulong-stellar-control.sh` into the staged module and patch the module's `pg_list_enabled()` function.
- Still incomplete: exact original proprietary trie/bloom runtime and per-app DNS query/interception counts. UID traffic-byte statistics are not DNS query counts.
- The original `AdBlockVpnService` / `RootProxyService` are not started as competing VPN services. FX continues to use its single VPN/TUN and root fallback paths.

### Yulong Shield 9.9.60

- Virus database/cache, read-only app scan, install/update scan receiver, blacklist and whitelist UI are integrated.
- Batch cleanup opens Android's uninstall confirmation one selected app at a time; no silent uninstall or freeze.
- User-opt-in foreground protection checks Usage Access and applies the blacklist/whitelist reminder behavior.
- Volume-up sequence and accelerometer shake rescue reminders are opt-in and never consume the hardware key.
- JobScheduler service-health check is persisted at the 15-minute minimum interval; the boot receiver only re-schedules when the user's protection opt-in remains enabled. The watchdog stops when Usage Access is revoked or the user switches protection off.
- `roro.stellar.manager.authorization` remains inside the Shield hub. The policy manager works with the original Stellar whitelist/scope/always-allow files. Read-only scopes are available; higher-privilege settings/AppOps/runtime-permission scopes require confirmation; terminal-command scope is deny-by-default.
- Still incomplete: original Stellar Binder command request/confirmation/response transport and the complete original privileged server engine. Current screen is a policy-file manager, not a claim that the whole Stellar backend has been ported.
- Still incomplete: original Shield self-defense beyond the opt-in Usage Access/JobScheduler health check.

## Remaining items before final build

1. Reconcile every original Dia screen/resource against the restored 23.11 package; complete Frida listener WAIT/RESUME and the remaining in-app editors. Keep location/device identity anti-detection and hardware-forgery behavior disabled for release targets.
2. Complete Yulong AdBlock built-in trie/bloom compatibility and original per-app DNS query counters; do not substitute UID traffic totals and call them DNS counts.
3. Complete/verify Yulong Shield's original Stellar command prompt transport and remaining ProtectService self-defense semantics.
4. Ensure both build workflows stage all three Yulong helper scripts, patch the rule-list master gate and preserve every manifest component.
5. After source migration is complete, run the final host/Gradle regression and paired packaging workflows once. Device behavior must remain marked unverified until tested on the target device.

## Verification state

- The work in this continuation batch is source/connector work.
- No final build was intentionally started for this batch.
- No OnePlus 12 real-device verification is recorded.
- No final APK/KernelSU ZIP should be published yet.
