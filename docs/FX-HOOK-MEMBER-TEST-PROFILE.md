# FX Hook member diagnostics and UI test profile

## Scope

This change adds metadata-only discovery hints and a fail-closed UI test profile for
applications owned by the developer. It does not implement generic method-result
rewriting, purchase-token fabrication, server-response tampering, or entitlement bypass.

## Discovery

`MemberCandidateClassifier` inspects method/field names and declared Java types only.
It recognizes Boolean, integer, long, string, enum, object/bean, Kotlin suspend
(Continuation parameter), and common async container signatures. It never invokes
candidate methods or reads field values. Scores are triage hints, not proof of a
membership API.

## Test profile

`MemberTestGate` requires all of:
- a debuggable build;
- explicit user opt-in;
- exact equality between the current process package and configured test package.

Protected system and FX packages are rejected.

`MemberUiTestProfile.resolveUiState` is for UI previews and test screens only.
Entitlement checks must call `resolveEntitlementState` and continue to use the
server-verified result. Production builds must not enable the UI test gate.

## Integration contract

An owned application should keep a single authoritative entitlement object populated
from its authenticated backend. UI components may consume a test presentation state
behind the gate; API clients, billing, download gates, and protected operations must
consume only the server-verified entitlement object.

## Verification

JUnit tests cover type classification, unrelated-method filtering, fail-closed
package/build gating, and separation of UI presentation from entitlement decisions.
