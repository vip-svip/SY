# FX 1.0.0 — APP UI migration contract

## Goal

FX APP is the only user-facing management entrypoint. The KernelSU module remains the privileged backend: boot lifecycle, DNS/Hosts, VPN/routing, filtering, certificate lifecycle, scripts, system changes, logs and rollback. The module WebUI is not shipped as a second management surface in the final ZIP.

The complete existing 1.0.0 WebUI is staged into `adhook/app/src/main/assets/webroot/index.html` and rendered inside the FX APK through an app-owned WebView. The application shell and per-app Hook manager remain native Android UI. This is a feature-parity migration into one installed APP, not yet a rewrite of every WebUI control into a native Android widget. This distinction is intentional: it preserves the existing complex editor, pagination, subscriptions, VPN controls and diagnostics instead of replacing them with incomplete placeholders.

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

The native APP shell has six persistent bottom tabs: VPN, Ad, Privacy, Scripts, Hook and Settings. The Ad tab keeps the short label `Ad`, but opens the merged Hosts/Rules page (`pageHosts`), where ad filtering rules and the local system Hosts editor coexist in one screen. Per-app splash/feed/overlay switches are removed; the built-in classifier runs automatically for eligible apps and does not depend on Remote Files being present. The Hook target editor retains only opt-in privacy, read-only diagnostics, and custom observation rules. Publishing optional Remote Files config writes a backup, atomically renames the validated temporary file, and reports its SHA-256. The former Ad controls/rules content belongs to this merged page; removed category master switches are not restored. Rule type recognition and dispatch are handled by the built-in engine. Settings opens the bundled advanced Settings page. Hook opens the native Hook and authorization hub. The same six-tab bar remains visible while navigating the Hook hub and per-app Hook screens.

The Hook hub separately reports whether LSPosed Manager is installed and provides a launch shortcut. The editable, extensionless local Hosts source is `$PG/local/hosts`; it remains independent of downloaded subscription files. The editor's separate live-system view reads `/system/etc/hosts` and is read-only. During apply, FX merges the local source with the enabled rule sources into a candidate, verifies and commits it transactionally, then bind-mounts the effective file onto `/system/etc/hosts`; it never edits the live bind-mounted file in place. Native per-app Hook configuration is persisted as `/data/adb/privacyguard/fx-native-hook-targets-<user>.conf`; the module's apply-time Remote Files generator prefers this validated overlay, so boot/apply cannot replace it with stale legacy targets. The APP also publishes a per-package ownership map so legacy API-82 hooks skip only features now handled by API-101, preventing duplicate interceptors. Manager installation is only a presence check; it does not prove that FX is enabled or that a target package is in scope. Built-in Ad recognition is independent of Remote Files and per-app config rows. Optional privacy/diagnostic rules still require successful Remote Files publication and a target-process restart. The user must still enable FX in LSPosed and select target-package scope in the Manager; the APP cannot silently grant LSPosed scope. The unified APK merge step preserves the modern and legacy Xposed entrypoints and injects the LSPosed module metadata/scope resource.

FX also declares an optional Android AccessibilityService. The user must explicitly enable it in Android Accessibility settings. The current service only tracks connection state: it does not retrieve window content, read screen text, click controls, or perform gestures. Accessibility authorization is separate from Root and LSPosed authorization.

## Native APP navigation and Hook authorization hub

- The APP shell owns six bottom tabs: VPN, Ad, Privacy, Scripts, Hook and Settings. The Ad tab contains the merged Ad/Rules/Hosts content; Settings is the sixth tab. The legacy in-page bottom bar is hidden inside the WebView so only one navigation bar is visible.
- The Ad tab is a label only: it opens the merged Hosts/Rules page from the top so the rule list remains visible alongside the local Hosts editor. Do not recreate the removed Ad category master switches; built-in rule recognition selects the handling path. The sixth Settings tab opens the advanced Settings page; there is no separate top-toolbar Settings button.
- The Hook tab opens a native authorization hub with LSPosed Manager detection/launch, per-app Hook settings and Android accessibility status.
- Root, LSPosed module activation/scope, and Android accessibility are independent states. The APP does not infer one from another.
- The optional accessibility service reports only whether it is connected. It declares `canRetrieveWindowContent=false`, does not inspect event payloads, text, passwords or other-app UI, and cannot perform gestures.

## APP bridge

- The bundled page is served from `https://appassets.androidplatform.net/assets/webroot/index.html` via AndroidX WebViewAssetLoader. No remote page is loaded.
- A restrictive Content Security Policy blocks remote scripts, frames and network connections from the WebView. The WebView blocks navigation away from its appassets origin and disables file-scheme access.
- The compatibility shim exposes only the KernelSU `ksu.exec` shape used by the existing UI. Root commands are run asynchronously through `su -c`; output is bounded and commands have a timeout.
- The bridge validates callback identifiers and caps command length. It also exposes the native Hook manager entrypoint and an Android Downloads export method.
- File imports use Android's system document picker. Exports use MediaStore Downloads on Android 10+ and the app-specific Downloads folder on Android 9.
- Root is not granted by a manifest permission. KernelSU must authorize the FX app; the UI reports the actual UID 0 result and does not simulate authorization.
- The native Hook page enumerates installed apps and stores per-target drafts independently. Publishing writes the versioned LSPosed Remote Files config; successful file writing alone does not claim that LSPosed scope or target-process injection is active.

## Single-entry packaging

The KernelSU packaging workflow first copies the complete WebUI into APK assets, then replaces the module's `webroot/index.html` with a small migration notice. The final module ZIP therefore does not expose a parallel copy of the management UI. The no-compile APP migration validation workflow stages the same source WebUI from the fixed 1.0.0 release archive.

## Build gate

The KernelSU workflow is the only compile/package workflow. It builds the unified APK once, copies that exact byte-for-byte APK into `optional/FXUnifiedHook.apk`, verifies the APK hash both before and after ZIP packaging, and uploads the same APK as a separate `FX-Hook-apk` artifact. It requires the repository variable `FX_FULL_APP_MIGRATION_COMPLETE=true`. Keep this variable unset until the six-tab routing (VPN, Ad, Privacy, Scripts, Hook, Settings), Hook authorization hub, complete WebUI bridge and packaging checks have all passed. The `build-fx-adhook.yml` workflow is static validation only and does not compile. Only then set the variable to enable the single final build.

## Verification boundary

Host-side source/regression checks do not prove real-device KernelSU authorization, WebView behavior on the OnePlus 12, file-picker/export behavior, LSPosed injection, DNS/VPN traffic flow, certificate trust, or system-hosts application. These require separate device verification after the gated build.
