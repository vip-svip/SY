# FX 1.0.0 — APP UI migration contract

## Goal

FX APP is the only user-facing management entrypoint. The KernelSU module remains the privileged backend: boot lifecycle, DNS/Hosts, VPN/routing, filtering, certificate lifecycle, scripts, system changes, logs and rollback. The module WebUI and KernelSU manual action entry are removed from the final ZIP. KernelSU is used only to install/authorize the module and manage its lifecycle; all daily FX operations are performed in the FX App.

The visible FX management UI is rendered by native Android views inside the six-tab app shell. The complete compatible 1.0.0 WebUI is still packaged and loaded into an off-screen WebView only as a transitional runtime bridge for legacy configuration and script APIs. That WebView is invisible and excluded from the accessibility tree; it is not a visible page, navigation destination, or user-facing management screen. Remaining bridge-backed operations must be migrated to native Root/service APIs before the WebView runtime can be removed.

## Migrated screens and feature groups

- Main VPN page: direct/global/rule/TUN modes, subscriptions, node parsing/import, node selection, latency tests, status, core lifecycle, client config export and subscription export.
- Ad / network filtering: rule list, category counts, local recursive DNS status, UID network blocking, CA status and opt-in MITM lifecycle.
- Rules / Hosts: rule-set import/edit/enable/disable/export/delete, whitelist/blacklist, independent system hosts file and paged hosts editor.
- Privacy: app Hook controls, leak protection, DNS/VPN/IPv6 options, privacy lists and configuration import/export.
- Scripts / Hook: script subscriptions and status, LSPosed scope guidance, automatic built-in Ad recognition in eligible LSPosed-scoped processes, opt-in per-app privacy controls, read-only billing diagnostics and custom observe-only Hook rules.
- General: language, appearance, diagnostics, logs, crash triage and update checks.
- Advanced panels: Root/module state, deep network protection, network stack privacy, permission/API controls, sensors, location, device identity, audio/camera, file/storage, notifications/clipboard, kernel and miscellaneous settings.
- Existing custom editors, import dialogs, confirmation dialogs, local persistence and status cards are retained in the bundled UI.

## Bottom navigation and system authorization

The native APP shell has six persistent bottom tabs: VPN, Ad, Privacy, Scripts, Hook and Settings. The Ad tab keeps the short label `Ad`, but opens the merged Hosts/Rules page (`pageHosts`), where ad filtering rules and the local system Hosts editor coexist in one screen. Per-app splash/feed/overlay switches are removed; the built-in classifier runs automatically for eligible apps and does not depend on Remote Files being present. The Hook target editor retains only opt-in privacy, read-only diagnostics, and custom observation rules. Publishing optional Remote Files config writes a backup, atomically renames the validated temporary file, and reports its SHA-256. The former Ad controls/rules content belongs to this merged page; removed category master switches are not restored. Rule type recognition and dispatch are handled by the built-in engine. Settings opens the native Settings screen. Hook opens the native Hook and authorization hub. The same six-tab bar remains visible while navigating the Hook hub and per-app Hook screens.

The Hook hub separately reports whether LSPosed Manager is installed and provides a launch shortcut. The editable, extensionless local Hosts source is `$PG/local/hosts`; it remains independent of downloaded subscription files. The editor's separate live-system view reads `/system/etc/hosts` and is read-only. During apply, FX merges the local source with the enabled rule sources into a candidate, verifies and commits it transactionally, then bind-mounts the effective file onto `/system/etc/hosts`; it never edits the live bind-mounted file in place. Native per-app Hook configuration is persisted as `/data/adb/privacyguard/fx-native-hook-targets-<user>.conf`; the module's apply-time Remote Files generator prefers this validated overlay, so boot/apply cannot replace it with stale legacy targets. The APP also publishes a per-package ownership map so legacy API-82 hooks skip only features now handled by API-101, preventing duplicate interceptors. Manager installation is only a presence check; it does not prove that FX is enabled or that a target package is in scope. Built-in Ad recognition is independent of Remote Files and per-app config rows. Optional privacy/diagnostic rules still require successful Remote Files publication and a target-process restart. The user must still enable FX in LSPosed and select target-package scope in the Manager; the APP cannot silently grant LSPosed scope. The unified APK merge step preserves the modern and legacy Xposed entrypoints and injects the LSPosed module metadata/scope resource.

FX also declares an optional Android AccessibilityService. The user must explicitly enable it in Android Accessibility settings. The current service only tracks connection state: it does not retrieve window content, read screen text, click controls, or perform gestures. Accessibility authorization is separate from Root and LSPosed authorization.

## Native APP navigation and Hook authorization hub

- The APP shell owns six bottom tabs: VPN, Ad, Privacy, Scripts, Hook and Settings. The Ad tab contains the merged Ad/Rules/Hosts content; Settings is the sixth tab. The legacy in-page bottom bar is hidden inside the WebView so only one navigation bar is visible.
- The Ad tab is a label only: it opens the merged Hosts/Rules page from the top so the rule list remains visible alongside the local Hosts editor. Do not recreate the removed Ad category master switches; built-in rule recognition selects the handling path. The sixth Settings tab opens the advanced Settings page; there is no separate top-toolbar Settings button.
- The Hook tab opens a native authorization hub with LSPosed Manager detection/launch, per-app Hook settings and Android accessibility status.
- Root, LSPosed module activation/scope, and Android accessibility are independent states. The APP does not infer one from another.
- The optional accessibility service reports only whether it is connected. It declares `canRetrieveWindowContent=false`, does not inspect event payloads, text, passwords or other-app UI, and cannot perform gestures.

## APP bridge

- The compatibility runtime is served from `https://appassets.androidplatform.net/assets/webroot/index.html` via AndroidX WebViewAssetLoader while hidden from the user and accessibility tree. No remote page is loaded.
- A restrictive Content Security Policy blocks remote scripts, frames and network connections from the WebView. The WebView blocks navigation away from its appassets origin and disables file-scheme access.
- The compatibility shim preserves the existing WebUI `ksu.exec` calling convention inside the App only. Root commands are run asynchronously through the app's native bridge and `su -c`; no KernelSU WebUI or module action entry is exposed. Output is bounded and commands have a timeout.
- The bridge validates callback identifiers and caps command length. It also exposes the native Hook manager entrypoint and an Android Downloads export method.
- File imports use Android's system document picker. Exports use MediaStore Downloads on Android 10+ and the app-specific Downloads folder on Android 9.
- Root is not granted by a manifest permission. KernelSU must authorize the FX app; the UI reports the actual UID 0 result and does not simulate authorization.
- The native Hook page enumerates installed apps and stores per-target drafts independently. Publishing writes the versioned LSPosed Remote Files config; successful file writing alone does not claim that LSPosed scope or target-process injection is active.
- Root status separately checks actual UID 0, the FX module's version/disable/remove marker, and whether the KSU command-line tool exists. Tool presence is not reported as proof that the daemon is healthy; module files are not reported as proof of LSPosed injection.
- Custom Hook rules are observe-only in the native UI and only run for explicitly opted-in debuggable target apps. They record method identity, argument types, elapsed time and exception type, never argument or return values, and never replace VIP/login/update decisions.

## Single-entry packaging

The KernelSU packaging workflow copies the complete compatible WebUI into APK assets, then removes the module `webroot/` directory and `action.sh` before packaging. The final ZIP contains neither a KernelSU WebUI entry nor a manual execution button. The native App shell owns all visible screens; its bundled WebView remains off-screen as a transitional compatibility runtime for remaining legacy state APIs. The no-compile APP migration validation workflow stages the same source WebUI from the fixed 1.0.0 release archive.

## Build gate

The KernelSU workflow is the only compile/package workflow. It builds the unified APK once, copies that exact byte-for-byte APK into `optional/FXUnifiedHook.apk`, verifies the APK hash both before and after ZIP packaging, and uploads the same APK as a separate `FX-Hook-apk` artifact. It requires the repository variable `FX_FULL_APP_MIGRATION_COMPLETE=true`. Keep this variable unset until the six-tab routing (VPN, Ad, Privacy, Scripts, Hook, Settings), Hook authorization hub, complete WebUI bridge and packaging checks have all passed. The `build-fx-adhook.yml` workflow is static validation only and does not compile. Only then set the variable to enable the single final build.

## Verification boundary

Host-side source/regression checks do not prove real-device KernelSU authorization, WebView behavior on the OnePlus 12, file-picker/export behavior, LSPosed injection, DNS/VPN traffic flow, certificate trust, or system-hosts application. These require separate device verification after the gated build.
