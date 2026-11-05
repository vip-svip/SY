# FX Hook member diagnostics and UI test profile

## Scope

This change adds metadata-only discovery hints and a fail-closed UI test profile for applications owned by the developer. It does not implement generic method-result rewriting, purchase-token fabrication, server-response tampering, or entitlement bypass.

## Discovery

`MemberCandidateClassifier` inspects method/field names and declared Java types only. It recognizes Boolean, integer, long, string, enum, object/bean, Kotlin suspend (Continuation parameter), and common async container signatures. It never invokes candidate methods or reads field values. Obfuscated state-holder candidates are selected through a bounded metadata shape heuristic; these candidates are not automatically rewritten.

## Test profile

`MemberTestGate` requires all of:
- a debuggable build;
- explicit user opt-in;
- exact equality between the current process package and configured test package.

Protected system and FX packages are rejected.

`MemberUiTestProfile.resolveUiState` is for UI previews and test screens only. Entitlement checks must call `resolveEntitlementState` and continue to use the server-verified result. Production builds must not enable the UI test gate. The current Hook APK contains these primitives and tests; they are not a generic production entitlement override.

## Integration contract

An owned application should keep a single authoritative entitlement object populated from its authenticated backend. UI components may consume a test presentation state behind the gate; API clients, billing, download gates, and protected operations must consume only the server-verified entitlement object.

## Verification

JUnit tests cover type classification, enum and suspend-like signatures, conservative obfuscated state shape detection, fail-closed package/build gating, and separation of UI presentation from entitlement decisions.
