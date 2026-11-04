# FX 1.0.0 — Continuation Handoff (current migration state)

Updated: 2026-11-03, Asia/Tokyo
Repository: `vip-svip/SY`
Branch: `fx-v1.0.0-unified-hook-integration`
Target: `FX 1.0.0`, versionCode `10000`

## Latest continuation update — 2026-11-03

Branch checkpoint at this update: `35514f004a15fc870446e2c195d50a2de5c7f805`.

### Changes since the previous handoff checkpoint

- Dia 23.11 global settings is no longer routed to the generic pending page. `MainActivity.openImportedSuitePage()` now opens `FxDiaGlobalSettingsActivity`, declared non-exported in the Manifest.
- Added `FxDiaGlobalSettingsActivity.java` with original preference-key mapping from `res/xml/my_settings.xml`. The original `digXposed` namespace is retained with `MODE_PRIVATE`, not the old world-readable mode. Backup routes to the existing encrypted Dia backup activity. Language values are persisted but the original app-wide locale runtime is not claimed migrated. Activation-tip keys are stored but the original EMessage consumers are not yet integrated. LSPosed scope sync, framework-only restart, and standalone Dia updater are explicitly disabled with explanations.
- Added `FxDiaSystemExpandActivity.java` for the original SystemExpand page. Wi-Fi HTTP proxy routes to the existing FX implementation. `ro.debuggable`, global unknown-source installation, module toggle and package-installer restart remain explicitly unavailable; no unchecked Root property or Package Installer command is issued.
- Added `scripts/tests/fx-dia-global-settings-registration-regression.sh` and wired it into `.github/workflows/build-fx-adhook.yml`. It checks the native route, private Manifest declarations, original preference keys, backup route, and disabled/unmigrated security-sensitive controls.
- Network cache lock patcher: the restored-release test fixture uses a different subfetch worker command form from the source fixture. Removed the stale worker-command rewrite from `patch_atomic_cache_lock_release.py`; the per-curl event log remains the diagnostic path. Do not claim the subscription concurrency issue closed until the next host regression run passes.

### Validation at this checkpoint

- Latest Actions run: `41692586086`, commit `35514f004a15fc870446e2c195d50a2de5c7f805`; it was still in progress at the time of this update (DEX staging step). No result is inferred from a running job.
- Earlier Actions run `41692477232` (commit `7afd6bad...`) failed during restore-stage preflight because the old worker-command trace anchor did not match the restored release fixture. This was the condition addressed by the current patcher change; the new run must verify it.
- No successful Gradle build, install test or real-device test is recorded for this update. No final APK or KernelSU ZIP was generated or delivered.

### Next tasks

1. Confirm `41692586086` completes restore, all host regressions, the new Dia settings test and Gradle APK verification. Investigate any failure from job logs; do not weaken assertions.
2. Continue Dia page-by-page migration: Frida WAIT/RESUME/listener and message forwarding; original JS editor and scripts; method/class/field Hook pages; extensions; remaining settings/system expansion controls.
3. Complete the true LSPosed scope sync adapter only after porting/reviewing Dia's `dialog.box.lsp.LScope` and replacing hard-coded `dialog.box` package identity with the unified FX package. Until then keep the setting visibly unavailable.
4. Continue Yulong Ad filter engine compatibility and Shield Stellar transport migration.
5. Preserve honest verification levels. The no-compile/host suite does not prove Android install or OnePlus 12 functionality.


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


## Latest continuation update — 2026-11-04

Branch checkpoint before this handoff update: `cf173a06233262f43738a3aee23d2db132e51f0c`.

### Changes in this continuation batch

- Replaced the restored-release subscription cache `mkdir` lock with a POSIX `noclobber` exclusive file lock. The new patcher is `fx-patches/patch_subfetch_file_lock.py`; it rejects symlinks, writes the owner PID atomically with mode 0600, verifies owner identity before atomic rename/release, and conservatively recognizes old PID-bearing directory locks during upgrades. The patcher is run twice by `scripts/tests/fx-atomic-cache-lock-release-regression.sh` to verify idempotency. The canonical two-worker regression now keeps the first mocked transfer blocked until the second worker has had time to contend and checks that no second transfer starts early. The final assertion checks that no lock file/directory/symlink remains.
- A local Linux Shell reproduction using the same `subfetch.sh` and a gated mock curl passed: one request entered while the first transfer was held; the second began only after release; both forced refreshes completed in order, the cache retained the second response, and the lock pathname was removed. This is local host validation only; CI must still confirm the restored Release module source passes the full regression repeatedly.
- Dia 23.11 Frida script library now supports SAF JSON file import/export with a schema check, 1 MiB total limit, 64-script limit and 128 KiB per-script limit. Imported source is stored locally and never auto-executed.
- Frida script-library export now stages JSON in app-private cache. Activity saved state retains only a validated staged filename, not up to 1 MiB JSON bytes. The SAF callback streams the staged file, then deletes it; cancellation, invalid staged paths and launch errors also clean the file. Old abandoned temp files older than 24 hours are removed without deleting a recent pending export.
- Updated `scripts/tests/fx-dia-frida-script-library-saf-regression.sh` to guard private-cache staging, rotation filename restore, streamed export and the absence of JSON payload in Activity Bundle state.
- Fixed the Dia global-settings regression script structure so the original hidden console preference assertions are outside the preference-key tuple.

### Current validation state

- Latest Actions run at checkpoint: `41698321368`, commit `cf173a06233262f43738a3aee23d2db132e51f0c`; at this update it has completed source restoration and is running static migration checks. No outcome is inferred while it is still running.
- No Gradle/APK build result, install test or real-device result is claimed for this batch. The build/compile stage is only reachable after static migration checks and the complete host regression suite pass.
- No final APK or KernelSU ZIP was generated or delivered.

### Next actions

1. Resolve any failure from run `41698321368`; specifically verify the restored-release file-lock patch and all repeated subscription/Hosts contention tests.
2. Only after host regression passes, review the Gradle APK compilation result and inspect its artifacts/logs.
3. Continue Dia Frida original listener/message/console behavior against the 23.11 smali, then map remaining unported Dia pages.
4. Continue Yulong AdBlock Trie/Bloom compatibility and per-app DNS counters; do not relabel UID traffic bytes as DNS query counts.
5. Continue Shield Stellar Binder request/confirmation/response and original ProtectService semantics.
6. Keep real-device validation marked incomplete until installed and exercised on the target OnePlus 12; do not produce the final paired APK/KernelSU ZIP before all migrations and acceptance gates pass.


## Latest continuation update — 2026-11-04

Branch checkpoint before this handoff update: `9f9dedcda9d1deeeed29ada177a617d70634f38c`.

### Dia 23.11 — harden Frida Gadget config replacement

- `FxDiaFridaActivity.saveGadgetListenConfig()` no longer writes to the predictable `<config>.tmp.<pid>` path. It creates an unpredictable same-directory temporary file via `mktemp` after setting `umask 077`, verifies the temporary file is a regular non-symlink, writes and checks non-empty JSON, changes the final read mode, and atomically replaces the Gadget config.
- The writer rejects a symlink at the final Gadget library or config directory and checks that the final config is a regular non-symlink after replacement. Existing loopback-only listen behavior, port conflict policy, and WAIT/RESUME semantics are unchanged.
- Updated `scripts/tests/fx-dia-frida-gadget-config-regression.sh`: it now tests two separate writer processes, pre-creates the old PID-based temporary pathname as a symlink to an unrelated sentinel file, verifies the sentinel remains unchanged, and checks random temporary files are removed.
- Commits: `2d216df6bc3f9ca49a193f6d6838f27b41740e89` (implementation), `9f9dedcda9d1deeeed29ada177a617d70634f38c` (regression test).

### Verification

- Local Linux shell regression of two concurrent writers and a pre-planted legacy PID-path symlink: PASS.
- GitHub Actions run `41701536687`, commit `9f9dedcda9d1deeeed29ada177a617d70634f38c`: restore stage and static migration checks passed; full host regression was still in progress when this note was written. Do not infer completion from the running job.
- No new Gradle build result, APK installation test or real-device validation is claimed for this change. Android device availability of the target `mktemp` behavior and Gadget library load/runtime remain to be verified.

### Remaining Frida migration boundary

- The Gadget target-side loading path is present: `DiaFridaTargetHook.java` hooks `Application.attach(Context)`, verifies the selected package and exact process, requires a debuggable non-system app under a non-symlinked `/data/app` native-library path, checks the deployment marker schema/package/process/port, verifies SHA-256 for the library and config, validates loopback Listen mode, then calls `System.load()`.
- `FxDiaGadgetDeployment.java` performs Root-assisted deployment/removal with per-target ownership markers, exact process binding, ABI/source validation, staged atomic replacement, hashes and rollback. Deploy/remove regression and Frida session regression cover source contracts and a local mock lifecycle.
- This replaces the original broad `code_inject` + `frida_listen` preference pair with an explicit per-package/per-process deployment marker as the opt-in. This is a deliberately narrower scope and safer permission boundary, not a byte-for-byte UI preference port.
- The target-side loader is a legacy Xposed entrypoint packaged into the unified APK and registered by `merge_hook_single_apk.py`; it is not a second APK or a duplicate API-101 loader. Keep it registered in merged `assets/xposed_init`.
- Android LSPosed/Gadget execution, update/restart behavior and uninstall/rollback still require OnePlus 12 verification. Do not silently patch/repack arbitrary third-party APKs.


## Latest continuation update — 2026-11-04 (branch checkpoint ef1dcad78d6b)

### Completed source changes since the previous recorded handoff

- Native Hook app package-list lifecycle sync: `MainActivity` observes package install/uninstall/update while resumed, refreshes the visible app list, revalidates a selected target after Activity resume, and preserves a selected app's Hook configuration if that app is removed. API 33+ receiver registration is explicitly non-exported. Commit: `e0d70d269b83ec1c2b80ff69e67fe2b7b8fc4246`.
- Yulong per-app firewall package lifecycle reconciliation: an internal receiver reacts to package lifecycle changes only while the firewall master preference is enabled; the Root script refreshes UID rules for reinstall/UID changes, removes stale active UIDs after uninstall while retaining saved package selection, and preserves last-known-good rules if PackageManager enumeration fails. The same implementation is carried into the restored Release module overlay. Commits: `cdcc3132208c`, `c7a1818038ef`, `ef1dcad78d6b`.
- Repaired the Java compile blockers identified by the previous APK workflow: missing imports, incorrect `OutputStream` typing where `FileOutputStream.getFD().sync()` is required, and Yulong widget app-resource namespace import. The same batch hardened backup reads against symlinked module/settings paths. Commit: `73f6c2be14c7`.
- Original Dia Frida target loading is present and now accurately documented: the package-scoped Xposed loader and Root deploy/remove implementation exist in source. The original global injection/listen preferences are represented by an explicit per-package/process deployment marker rather than a global toggle. See `DiaFridaTargetHook.java`, `FxDiaGadgetDeployment.java` and `fx-dia-frida-gadget-deploy-regression.sh`.

### Validation state at this checkpoint

- Latest Actions run on this branch must be checked before asserting a build result. Do not infer a compile result from source restoration or host regression completion.
- The Frida session regression's local mock is host-only; it does not prove Android LSPosed/Gadget load behavior on the target device.
- No OnePlus 12 physical-device validation is recorded. No final APK or KernelSU ZIP was produced.

### Next source work

1. Continue Yulong AdBlock original Trie/Bloom matcher and DNS query-accounting parity. Do not present UID traffic counters as DNS query counts.
2. Continue Stellar Binder request/confirmation/response transport and compare the original Shield receiver/service lifecycle with FX's safe equivalents.
3. Reconcile the original Dia page/resource/method inventory with actual FX operations; prioritize method/class/field editing, JS runtime page behavior, and missing monitor event forwarding.
4. Keep final APK/KernelSU packaging blocked until every migration gate closes; real-device verification is a separate required gate.


## 2026-11-04 Yulong Trie terminal recovery — commit b85e961

- Reviewed the original Go matcher call path: `CheckDomainInTrieFile` passes the query unchanged to `MmapTrie.ContainsOrParent`; the matcher reverses raw dot labels and does not strip ABP `^` syntax. Therefore the 28 terminal strings ending in a single caret in the legacy 7.0.1 bundle are not byte-for-byte matchable as DNS labels in that precompiled Trie. FX's conversion is documented as a **migration repair/recovery of intended ABP domain-boundary syntax**, not as exact legacy runtime parity.
- Recovery is restricted to complete `domain^` and `||domain^` tokens. Prefix-only `||domain`, single-pipe URL anchors, modifiers, paths, wildcard forms, IP literals and malformed tokens are not promoted into DNS host rules.
- The decoder now writes unsupported raw terminals to `Yulong_AdBlock_Review.jsonl`, keyed by the source Trie; this file is not connected to AdGuard Home or Android Hosts. Cosmetic selectors remain in the separate cosmetic file.
- Local inspection of the original four TRIE/BLOOM pairs validated all headers and node/terminal counts. The four assets contain 28 caret-terminated host-shaped terminals; the safe recovery yields 21 additional unique hostnames after de-duplication. 81 other non-cosmetic entries remain review-only, and 3,476 mobile cosmetic selectors remain separate. These are source-data counts, not device traffic measurements.
- Focused local synthetic verification passed the allow/reject matrix and TRIE v2 encode/decode round-trip. The checked-in regression is also wired into the manual KernelSU source-import pipeline; no KernelSU ZIP was built.


## 2026-11-04 continuation — Stellar local operation audit

- Added an audit-log view and clear action inside the Shield Stellar manager. It displays successful FX-local runtime-permission, AppOps and allowlisted secure-setting actions, capped at 500 records; it is not represented as the original Stellar daemon/Binder's full service log.
- Added logs and clear-logs commands to the Stellar Root controller. Clearing uses a same-directory randomized temporary file and atomic replacement.
- The audit log contains only successful operations recorded by the FX shell controller, rejects symlinked state files, and is not a substitute for Binder service telemetry.
- Added host regression coverage for 500-record retention, read/clear and secure log-file paths. Targeted validation is pending the next Actions run.
- No APK build, installation or device test is implied by this source change.

### Remaining Stellar Binder boundary
- Original IStellarService and StellarProvider expose asynchronous Binder readiness, permission-request callbacks, confirmation-result dispatch, service logs, remote processes and service metadata.
- FX's Root-backed safe command manager is a restricted replacement for selected controls, not a drop-in Binder client and not full Binder/daemon parity. Keep that gap open until a compatible in-process/service transport is implemented and verified.

## 2026-11-04 continuation — Dia MethodActivity safe void method suppression

- Compared the original MethodActivity.smali and Module.smali: the original per-target method_empty preference feeds a ClassLoader observer that replaces configured methods with XC_MethodReplacement.DO_NOTHING when its separate method master is on.
- FX adds NO_OP_VOID to the unified custom Hook rule model. It requires an exact Java/JVM signature with return type void; constructors and other return types are rejected. The runtime re-resolves the method and independently checks target package scope, developer opt-in, FLAG_DEBUGGABLE, non-abstract and non-native method status before skipping the original body.
- This is a safer subset, not full parity with the legacy class.method-only selector or its future ClassLoader observer. It does not act on release targets. Regression coverage: parser rejection/acceptance, serializer round-trip, native UI/runtime source contracts and the static migration workflow. OnePlus 12 LSPosed runtime testing remains outstanding.


## Latest continuation — 2026-11-04: Frida server ownership and Yulong watcher lock

- Dia Frida's local server lifecycle was hardened. Start now serializes attempts, rejects symlinked state/PID/lock/log/server paths, uses a randomized same-directory PID-record temporary file with mode 0600 and atomic rename, and detects an already-running exact server process before spawning. Ownership is checked against exact argv[0], the listen argument and the loopback endpoint; substring grep matching was removed.
- Stop reads the stored server path/port, checks exact process identity before SIGTERM, treats zombie/dead PIDs as stopped, and retains the PID record when stop times out or the PID appears reused. It does not use pkill/killall or force-kill.
- Yulong watcher lifecycle no longer removes an ownerless lock directory after a short delay. That directory may belong to a live starter paused between mkdir and owner-PID publication; deleting it could let two processes claim the same lifecycle lock. Regression coverage now exercises the fail-closed case using a bounded retry setting.
- Added scripts/tests/fx-dia-frida-server-lifecycle-regression.sh to the manual source-import workflow.
- Verification boundary: source changes only. The new regression and complete GitHub Actions run must pass before this batch is CI-verified. No Android install/OnePlus 12 device result and no final APK/KernelSU ZIP are claimed.


## 2026-11-04 — Yulong watcher startup readiness handshake

- The watcher process now atomically publishes its own PID record only after entering `watch-loop`; the starter no longer pre-publishes the PID based on `$!` and waits until the child marker plus exact process identity are visible before releasing the lifecycle lock.
- This closes the startup window exposed by the CI delayed-`nohup` concurrency fixture. Empty/stale PID records are cleared only while holding the same lifecycle lock; the child PID marker is private and uses a randomized same-directory temp file.
- The targeted concurrent-start regression now validates the real child-published marker and mode 0600, alongside the existing single-spawn and start/stop-race checks. CI must pass before this fix is treated as verified.
