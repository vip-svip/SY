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


## 2026-11-04 — Dia page lifecycle and unified Xposed entrypoint corrections

- Dia's fourth-level `运行日志` route now opens the target-specific Frida session log rather than the unrelated FX module log viewer. The last selected target package/label is persisted across fresh Dia Activity launches, but is reused only after PackageManager revalidates that it remains installed, user-owned and `FLAG_DEBUGGABLE`; stale or no-longer-eligible targets are cleared.
- Dia's `脚本编辑器` menu now opens the full-screen editor directly; `JS 脚本列表` continues to open the script library. Regression: `scripts/tests/fx-dia-frida-page-navigation-regression.sh`, wired into `.github/workflows/build-fx-adhook.yml`.
- The APK-level Hook regression now verifies both legacy `assets/xposed_init` adapters: `de.privacyguard.hook.MainHook` and `de.privacyguard.hook.DiaFridaTargetHook`. The test also checks both DEX classes plus the modern libxposed `AdVisibilityHook`. The two-line legacy list is intentional; requiring an exact one-line file had incorrectly rejected the Frida adapter.
- Commits: `7a4d1dc218` (Dia page lifecycle), `2091a8bc8f` (APK entrypoint assertions).

## 2026-11-04 — Yulong watcher and Dia Frida server lifecycle hardening

- The Yulong watcher no longer steals an ownerless lifecycle lock during the mkdir-to-owner-PID publication window. The final startup handshake moved PID publication into the watcher child itself: after entering `watch-loop`, it writes its own PID through a private randomized same-directory temp and atomic rename. The starter holds the lock until that exact child PID appears and `/proc/<pid>/cmdline` confirms the watcher identity.
- Concurrent-start regression additionally checks the published PID is the live child `watch-loop` process and that the PID file mode is 0600. The fixture delays `nohup` startup to exercise the handoff window. Test contract was updated to assert child-owned publication rather than the superseded parent-owned PID flow.
- Dia Frida server lifecycle now defines and uses exact process guards: PID liveness rejects zombie/exited states, and ownership requires exact `argv[0]`, `-l`, and `127.0.0.1:27042` matches from `/proc/<pid>/cmdline`. Start is serialized, writes a private atomic PID record, detects an unmanaged matching server rather than duplicating it, and verifies ownership before returning. Stop sends TERM only to the exact FX-owned process and keeps state on timeout/PID reuse.
- Commits: `9b0e5dd392` (initial ownership hardening), `3e1b6e83c1` (child readiness handshake), `96463dd486` / `ce70698b43` / `aa64adc1e5` / `132cecdbea` (readiness regression contract), `24cbb1b916` / `056212cdd6` (Frida exact process guard).
- Verification at this handoff revision: Actions run `41756139305` is the latest full source-validation run and must be checked before claiming regression success. Older run `41755952765` failed because its test still asserted the previous parent-owned startup loop; run `41755952765` did not reach APK compilation. No OnePlus 12 / Android device validation is recorded; no final APK/KernelSU ZIP was generated.

## Remaining source/runtime gates — do not mark complete yet

1. Yulong AdBlock: true per-app DNS query/block counters are still distinct from UID byte totals; Root Proxy compatibility needs vendor-VPN device verification; full upstream DNS protocol and original scheduler parity remain open.
2. Yulong Shield: current Stellar manager is an FX-local Root-backed scoped controller, not the original asynchronous IStellarService/StellarProvider Binder daemon. Full Binder readiness/request/confirmation/response/log transport, original multi-mode remediation and complete rescue overlay parity remain open.
3. Dia: Frida server/Gadget host lifecycle and page routes are source-integrated, but Android LSPosed/Gadget runtime is still device-pending. The original full class-loader/method/native interception and built-in HTTP/SQL/algorithm monitoring parity is not established by editable Frida templates alone.
4. Run the current source regression + Gradle APK build from one exact HEAD; only after all source migrations and acceptance gates close may the paired FX Hook APK + KernelSU ZIP be built. Keep OnePlus 12 / KernelSU / LSPosed verification explicitly pending until real device evidence exists.


## Dia editor correction — JavaScript stays JavaScript

- The shared full-screen Sora editor now accepts an explicit source-language extra. The original Java editor keeps the bundled Java tokenizer; the Frida caller selects JavaScript mode and no longer applies Java token highlighting to JS source.
- The current APK only bundles Sora core plus language-java. In JS mode the editor deliberately remains in Sora's default plain-text language and labels that mode honestly; source save/return limits and the 0x3039-compatible result contract are unchanged. A future grammar module is not claimed as included.
- Regression coverage checks both language paths and confirms that only the Java path installs JavaLanguage.


## 2026-11-04 — Dia LSPosed dynamic target scope

- Compared the original Dia `LScopeProvider`/`LScope` Binder flow with the modern libXposed Service contract. FX uses the official `io.github.libxposed:service` provider/helper rather than copying the old `dialog.box` authority or package identity.
- Added `FxHookApplication` registration for `XposedServiceHelper`, a process-singleton `FxLsposedScopeBridge`, and per-target Hook UI controls to read current scope, request LSPosed Manager approval, and remove that target's scope. Requests for system apps require a separate confirmation.
- The default `META-INF/xposed/scope.list` remains empty and `staticScope=false`; FX does not silently add targets on install. The screen distinguishes approved module scope from actual target-process injection.
- Added `scripts/tests/fx-dia-lsposed-scope-regression.py` to the manual validation workflow. Compile/CI and real OnePlus 12 LSPosed behavior remain to be verified; no final APK/KernelSU ZIP has been built.


## 2026-11-04 — Stellar authorization Binder transport migration

- Added a private, non-exported Android Messenger Binder service for the current FX Stellar authorization backend. The Activity binds through Android's service lifecycle, negotiates protocol version 1, sends request IDs and allowlisted backend operations asynchronously, and resolves each response to its matching callback.
- The service owns the single-thread bounded command executor and forwards actual RootAccess results (exit code, bounded output and denied flag). Request arguments and response output are capped; queue saturation and Binder disconnection are explicit failures. The Activity no longer invokes RootAccess.execute directly.
- Existing user confirmation dialogs, target selection, package/scope controls, audit log UI and shell-side allowlists remain in place.
- This is the FX in-app Binder transport layer, not binary/API parity with the original separate IStellarService/StellarProvider daemon. The original daemon protocol and full remediation/rescue parity remain open pending original interface sources and runtime evidence.
- Source regression and Gradle compilation are required on this exact commit; no Android device / OnePlus 12 claim is made.


## Dia DEX-to-Hook method picker

- The DEX browser now offers a direct method-to-rule path when opened from the Dia settings page. It only lists concrete non-abstract, non-native methods from a debuggable user application, emits an exact owner/method/JVM-descriptor tuple, and validates it with the same DeveloperHookRule parser before returning to MainActivity.
- MainActivity rechecks the target package, debuggable flag, system flag and descriptor, opens that package's native Custom Hook editor, and pre-fills an OBSERVE rule for explicit confirmation. Field signatures remain read-only/copyable; no arbitrary field write or class mutation is introduced.
- Added a dedicated host source-contract regression and wired it into the migration workflow. Android LSPosed behavior remains subject to current build and target-device verification.


## Yulong watcher lock redesign — atomic PID-bearing file lock

- Replaced the two-step lock-directory/owner.pid lifecycle lock with an exclusive POSIX noclobber file lock that writes the owner PID during the exclusive file creation. This removes the separate directory creation and owner publication race window.
- The lock code rechecks the owner PID before stale cleanup, rejects symlinked/non-regular paths, treats an empty in-progress lock as busy, and waits on a live FX script owner. It still recognizes and safely waits for/removes stale legacy owner.pid lock directories from older installs.
- Watcher identity now compares exact /proc command-line argument positions 2 and 3 against the script path and watch-loop command, not a substring. The regression now uses an empty file-lock fixture and asserts the published PID is the exact child process.
- The restored Release module receives the same canonical script through patch_yulong_app_firewall.py. CI must pass the repeated start/stop race before this is considered verified.


## 2026-11-04 — Yulong atomic-lock regression contract correction

- The watcher implementation was upgraded from a lock directory plus owner.pid file to a single exclusive POSIX noclobber lock file containing the owner PID. CI still asserted the superseded WATCH_LOCK_PID directory-owner design and failed before running the rest of the host suite.
- Updated the regression to assert the current implementation's atomic file creation, PID ownership verification, restrictive permissions and owner-only release. This is a test-contract correction, not a relaxation of the single-owner invariant.
- The current CI run must validate the complete host suite and APK compile before this migration batch is considered verified.


## 2026-11-04 — Build-time Hook Manager authority UI restore

- Added an idempotent source-restoration patcher and placed it immediately after the dual-entry Hook APK merge in CI. It ensures the Hook hub visibly states that LSPosed module enablement and per-target scope are separate Manager approvals; FX only submits requests and reads results.
- This is an actual native Hook page message, not a Settings-page relocation or a relaxed regression assertion. The patcher fails closed if the Hook hub structure changes unexpectedly.


## Latest continuation update — 2026-11-04 — QuickJS scheduler ownership and deployment

Branch checkpoint: `4d56a6810303f7b4a168de16f9ddfeb61af1e0c4`.

### Source changes

- Added `fx-patches/patch_native_script_scheduler.py`. It stages the reviewed scheduler into `fx-module/scripts/jsruntime/scheduler.sh`, makes it executable, and adds one idempotent stop hook to module uninstall. The patcher refuses a symlink target and rejects partial/duplicate uninstall markers.
- Replaced the old PID-only scheduler in the checked-in module snapshot with the owned-record implementation from `fx-patches/native-script-scheduler.sh`.
- Changed stop behavior from signalling the recorded PID to an owner-matched stop-request file. The scheduler polls the request while idle and exits through its own cleanup path; an unrelated PID is refused and is not signalled. A stale stop marker is reclaimed only after no active scheduler owner is found.
- Added `scripts/tests/fx-native-script-scheduler-regression.sh` for staging/idempotency, shell syntax, start/status/stop lifecycle, unrelated-live-PID refusal, symlink rejection and uninstall-hook presence.
- Wired the patcher and regression into both `.github/workflows/build-fx-adhook.yml` and `.github/workflows/build-fx-kernelsu.yml`, after module source restoration and before their relevant validation/package steps.
- Updated `fx-module/uninstall.sh` so an installed scheduler receives an owner-matched uninstall stop request.

### Changed paths

- `fx-patches/native-script-scheduler.sh`
- `fx-patches/patch_native_script_scheduler.py`
- `scripts/tests/fx-native-script-scheduler-regression.sh`
- `fx-module/scripts/jsruntime/scheduler.sh`
- `fx-module/uninstall.sh`
- `.github/workflows/build-fx-adhook.yml`
- `.github/workflows/build-fx-kernelsu.yml`

### Verification status

- GitHub branch writes were accepted and the branch was re-read at `4d56a6810303f7b4a168de16f9ddfeb61af1e0c4`.
- Source-level checks confirmed the new scheduler and module snapshot contain the cooperative stop marker and no longer contain the scheduler-PID `kill -TERM` path; both workflows contain the staging and regression commands.
- The new shell regression has **not been executed in this session**. GitHub commit status/workflow-run queries returned no status entries for the inspected commits; no CI pass is claimed.
- No Gradle build, APK build, KernelSU ZIP, install test or real-device test was run. No final package was generated.

### Remaining immediate checks

1. Confirm the new `fx-native-script-scheduler-regression.sh` passes in the next matching app-validation run; investigate rather than weaken any failed assertion.
2. The checked-in `fx-module/scripts/jsruntime/sync-subs.sh` path returned 404 during source inspection, although the scheduler invokes it and `native-script-list.sh` documents it as the subscription consumer. Verify the restored Release module source contains it. If absent there too, implement and test the real HTTPS subscription synchronization path before claiming remote script auto-update works.
3. Continue the larger migration backlog: Dia Frida listener/message forwarding and remaining editors/pages; Yulong Ad trie/bloom runtime and genuine DNS query counters; Shield Stellar Binder transport and remaining self-defense semantics. Keep all device-only claims unverified until target-device tests exist.



## Follow-up continuation — QuickJS runtime dependency gate

Checkpoint: `e63e59773093b49bd62d1e05445df87536710e23`.

The recursive Git tree for this branch contains only `fx-module/scripts/jsruntime/scheduler.sh` under the module's JS runtime directory. The scheduler invokes `sync-subs.sh`, while the native local-script runner expects `runner.sh` and the HTTP host bridge `host.js`; these files are not present in the checked-in module snapshot. The build workflows restore the full module from the published `FX-v1.0.0.zip` Release archive when the checkout is incomplete, so their presence in that archive still needs confirmation.

To prevent packaging a watcher that silently cannot perform its job, `patch_native_script_scheduler.py` now refuses to stage the scheduler unless the restored module contains non-empty `sync-subs.sh`, `runner.sh`, and `host.js`. The scheduler regression fixture now supplies explicit minimal dependency fixtures, and checks that the patcher enforces all three dependencies.

This is a fail-fast integration guard, **not** an implementation of remote subscription synchronization. No claim is made that subscription updates are working until the real synchronizer source is inspected and its end-to-end tests pass. The regression has been updated but was not executed in this session; CI and device verification remain outstanding.


## Latest continuation update — 2026-11-04 — QuickJS uninstall ownership + migration-only CI

Checkpoint: `9ab5a4af827b3958e325d414dd2509d5b7b60b14`.

### QuickJS scheduler / uninstall
- Corrected the scheduler's own-process start-time capture to call `pid_fields "$$"`. The prior checked-in form passed a literal `$` and could not publish its owner record.
- The module Release archive uses the legacy `PG=/data/adb/privacyguard` layout and still had a PID-only scheduler stop/delete block. The reviewed scheduler patcher replaces that block with an owner-bound cooperative stop request, and aborts uninstall cleanup if shutdown cannot be confirmed.
- The Release archive's old `v1.0.0-uninstall-scheduler-pid-reuse-regression.sh` asserted the removed direct TERM/SIGKILL implementation. The patcher now stages the canonical root regression into the restored module, rather than preserving that obsolete contract.
- The canonical regression starts a real test scheduler, mutates only the recorded process start-time field to simulate PID reuse, proves the unrelated/live process remains alive and no stop marker is created, restores the valid owner snapshot and proves cooperative shutdown, then rejects a legacy PID-only record.
- `scripts/tests/fx-native-script-scheduler-regression.sh` now requires the staged PID-reuse test to be byte-identical to the canonical test, preventing Release restore from silently reintroducing the stale test.

### CI / build gates
- The KernelSU package workflow is manual-only and requires the explicit `migration_complete=true` input on the FX integration branch. It has no push trigger.
- The Hook APK workflow still runs source migration and host regression lanes on branch pushes, but Java/Gradle/SDK/compile/upload steps require the same explicit manual migration-complete approval. Push validation therefore does not generate interim APKs.
- Corrected stale Dia LSPosed scope regressions to verify official libXposed service behavior, explicit opt-in, Manager approval, bounded queue behavior and token-owned cleanup. Updated the auto-scope extractor to use the actual adjacent method boundary and fully-qualified executor names.
- Updated the migration regression's workflow assertions to match the manual-only final package gate; the previous Release/branch test version expected package builds on push.

### Latest validation
- GitHub Actions run `41833507310`, commit `9ab5a4af827b3958e325d414dd2509d5b7b60b14`: source restoration passed; static migration checks passed; complete host suite passed with **309 total / 303 pass / 6 artifact-dependent skips / 0 failures / 0 timeouts**.
- The six skips are checks that require generated signed APK or Android ARM64 QJS build artifacts. This push lane intentionally did not compile or package.
- No APK compile, APK install, KernelSU ZIP, OnePlus 12 test, KernelSU device test, LSPosed runtime test or Frida Gadget device test was run or claimed.

### Continue migration
1. Continue Dia 23.11 source-to-native parity, especially Frida listener/message/console coverage and any remaining page/editor functionality not represented by real implementations.
2. Continue Yulong AdBlock's original trie/bloom runtime parity and per-app DNS query counters; UID traffic-byte totals must not be presented as DNS query counts.
3. Continue Yulong Shield's original Stellar Binder daemon/protocol parity and remaining ProtectService self-defense semantics. The FX Messenger transport is not the original daemon.
4. Do not set `migration_complete=true` or run the final paired APK/KernelSU packaging workflows until the source-migration acceptance gates genuinely close.

## 2026-11-05 — Developer Hook rule-slot capacity update

- The per-target Developer Hook rule-count cap of 64 has been removed from parser, serializer and native UI. Preference-backed slot enumeration now covers editor, group operations, import/export, rollback, rendering and config publication; sparse legacy slot IDs remain readable.
- Validation: Targeted Host run `42047046509` completed SUCCESS on HEAD `058e5683`; it passed the dynamic UI lifecycle check, 96-rule parser/serializer round-trip, streamed publication/rollback and 2,500-target parser stress checks.
- The former 16,384-character / 64 KiB JSON import ceiling has also been removed; custom Hook draft persistence is debounced at 400 ms and flushed on dialog close/submit and Activity lifecycle transitions. Developer rules have no fixed per-target count cap and use dynamically enumerated sparse-compatible slots.
- The manual APK gate remains closed. Do not set `migration_complete=true` until Dia 23.11, Yulong AdBlock 7.0.1 and Yulong Shield 9.9.60 source-to-behavior acceptance gates close. Remaining priorities: Dia Frida listener/message lifecycle, original AdBlock Trie/Bloom runtime and genuine per-app DNS query counts, and original Shield Stellar Binder transport / ProtectService parity.
- The Module Runtime workflow for HEAD `058e5683` was still in progress when this note was written. No APK build or physical-device validation is claimed.
