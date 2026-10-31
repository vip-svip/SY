# FX 1.0.0 — APP UI migration contract

## Goal

FX APP is the only user-facing management entrypoint. The KernelSU module remains the privileged backend: boot lifecycle, DNS/Hosts, VPN/routing, filtering, certificate lifecycle, scripts, system changes, logs and rollback. The module WebUI is not shipped as a second management surface in the final ZIP.

The complete existing 1.0.0 WebUI is staged into `adhook/app/src/main/assets/webroot/index.html` and rendered inside the FX APK through an app-owned WebView. The application shell and per-app Hook manager remain native Android UI. This is a feature-parity migration into one installed APP, not yet a rewrite of every WebUI control into a native Android widget. This distinction is intentional: it preserves the existing complex editor, pagination, subscriptions, VPN controls and diagnostics instead of replacing them with incomplete placeholders.

## Migrated screens and feature groups

- Main VPN page: direct/global/rule/TUN modes, subscriptions, node parsing/import, node selection, latency tests, status, core lifecycle, client config export and subscription export.
- Ad / network filtering: rule list, category counts, local recursive DNS status, UID network blocking, CA status and opt-in MITM lifecycle.
- Rules / Hosts: rule-set import/edit/enable/disable/export/delete, whitelist/blacklist, independent system hosts file and paged hosts editor.
- Privacy: app Hook controls, leak protection, DNS/VPN/IPv6 options, privacy lists and configuration import/export.
- Scripts / Hook: script subscriptions and status, LSPosed target configuration, per-app ad/privacy controls, read-only billing diagnostics and custom observe-only Hook rules.
- General: language, appearance, diagnostics, logs, crash triage and update checks.
- Advanced panels: Root/module state, deep network protection, network stack privacy, permission/API controls, sensors, location, device identity, audio/camera, file/storage, notifications/clipboard, kernel and miscellaneous settings.
- Existing custom editors, import dialogs, confirmation dialogs, local persistence and status cards are retained in the bundled UI.

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

The KernelSU workflow is the only compile/package workflow. It builds the unified APK once, copies that exact byte-for-byte APK into `optional/FXUnifiedHook.apk`, verifies the APK hash both before and after ZIP packaging, and uploads the same APK as a separate `FX-Hook-apk` artifact. It is scoped to the `fx-v1.0.0-unified-hook-integration` branch. The `build-fx-adhook.yml` workflow is static validation only and does not compile. The migration's no-compile validation passed before this build was enabled.

## Verification boundary

Host-side source/regression checks do not prove real-device KernelSU authorization, WebView behavior on the OnePlus 12, file-picker/export behavior, LSPosed injection, DNS/VPN traffic flow, certificate trust, or system-hosts application. These require separate device verification after the gated build.
