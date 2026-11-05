# FX GKD Selector Adapter

This module compiles the selector engine directly from the repository-pinned GKD-XA v1.4.8 submodule:

- Upstream repository: https://github.com/84593320z/GKD-XA
- Pinned commit: `8a6ce935da11671dac7e1a7595416ec99ee07436`
- Upstream module: `gkd-selector`
- License: GPL-3.0 (see `vendor/GKD-XA/LICENSE` and the upstream notices).

Only `gkd-selector/src/commonMain` and its JVM `actual` source set are on this module's compile classpath. This is a single-APK library dependency. It does **not** add the upstream `gkd-app`, its Application/Launcher, its own database, Shizuku/AIDL runtime, AccessibilityService, receivers, providers, tiles, or a second APK.

FX Java/Kotlin compilation remains on JDK/JVM 17. The upstream selector sources are not modified in place; upstream GPL notices and provenance remain in the pinned submodule. The adapter itself is glue/build metadata and FX smoke tests.

This is the first GKD runtime component migration only. Subscription storage, rule execution, snapshots, AI providers, logs, permission lifecycle, unified Accessibility event dispatch and the Hook UI are still separate integration tasks.
