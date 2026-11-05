# FX GKD Selector

FX compiles the exact GKD-XA v1.4.8 selector module in a single JVM library project.

- Upstream repository: https://github.com/84593320z/GKD-XA
- Pinned commit: `8a6ce935da11671dac7e1a7595416ec99ee07436`
- Upstream source: `vendor/GKD-XA/gkd-selector`
- License: GPL-3.0; retain `vendor/GKD-XA/LICENSE`, copyright and attribution.
- Source sets: upstream `commonMain`, `jvmMain`, `commonTest`, and `jvmTest`.
- FX target: JVM 17, using the FX Kotlin 2.4.21 toolchain. GKD-XA's standalone app, AGP 9.4.1, Java 21 and Android runtime are not imported.

The FX app consumes only `:fx-gkd-selector`. The upstream `:gkd-app` is deliberately excluded: it would add a second Application/Launcher and its own Accessibility, notification, boot and Shizuku service lifecycle. Those must be integrated deliberately into FX before any service or UI is enabled.

This module contributes the selector/parser/query engine only. It does not yet implement GKD subscription storage, rule execution scheduling, snapshots, AI providers, history, or the unified FX Hook/Accessibility event pipeline.
