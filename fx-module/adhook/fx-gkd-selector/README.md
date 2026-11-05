# FX GKD Selector

FX compiles the exact GKD-XA v1.4.8 selector engine in one JVM library project.

- Upstream repository: https://github.com/84593320z/GKD-XA
- Pinned commit: `8a6ce935da11671dac7e1a7595416ec99ee07436`
- Upstream source: `vendor/GKD-XA/gkd-selector`
- License: GPL-3.0. Preserve upstream copyright, source provenance, the complete license text and modification notices.
- Source sets: upstream `commonMain`, `jvmMain`, `commonTest`, and `jvmTest`.
- FX target: JVM 17 on the FX Kotlin 2.4.21 toolchain. The upstream standalone app build (AGP 9.4.1 / Java 21) is not imported.

The FX APK consumes only `:fx-gkd-selector`. The upstream `:gkd-app` is deliberately excluded: FX retains its single Application, launcher, and AccessibilityService lifecycle.

## Current FX integration slice

The app-side integration is in:
- `FxGkdSelectorEngine.kt`: validates and matches upstream selectors against an immutable FX node snapshot.
- `FxGkdAccessibilitySnapshot.kt`: copies a bounded Accessibility tree and excludes text/description for password and editable nodes.
- `FxGkdRuleStore.kt`: stores up to 128 local rules, each scoped to one installed user app, with a default-off master switch and bounded cooldown. Versioned JSON import/export (256 KiB max) validates packages, selectors and cooldowns, merges without overwriting existing rules, and always imports rules disabled.
- `FxGkdAutomationRuntime.kt`: matches opted-in local rules and permits only a visible clickable node that is rechecked as non-password/non-editable immediately before ACTION_CLICK.
- `FxAccessibilityService.java`: reuses the existing FX service; it reads a window tree only when the user enables the GKD master switch and the event package has an enabled local rule.
- `FxGkdAutomationActivity.java`: Hook-tab UI for adding, enabling, disabling, deleting, importing and exporting local selector rules; targets can be selected from installed user apps.

The initial runtime is intentionally limited: no upstream subscriptions or cloud sync, rule groups/exclusions, AI providers, screenshots, trigger history, Shizuku/AIDL bridge, or GKD boot/notification/tile lifecycle have been migrated yet. It is not a claim of full GKD-XA feature parity.

The selector JVM test lane and the FX Android app compile/unit-test lane are separate checks. Passing selector JVM tests does not itself establish APK build success or device-level Accessibility behavior.
