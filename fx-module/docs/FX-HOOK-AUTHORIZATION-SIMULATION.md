# FX Hook — Developer Authorization Simulation

This is a generic test-presentation scenario model for applications owned by the developer.
It is not a production authorization bypass.

## Scenario dimensions
- Login/session presentation: logged out, logged in, expired, refresh required, error.
- Entitlement presentation: free, VIP, expired, revoked, pending.
- Billing test presentation: idle, purchased, pending, canceled, failed, refunded, restored.
- Update test presentation: not checked, up to date, update available, force update, check failed.
- Optional display-only membership expiry and sanitized scenario identifier.

## Fail-closed gate
The controller is enabled only when the actual build is debuggable, the developer explicitly
opts in, and the running package exactly matches the configured test package. Protected
system/manager packages are rejected by the existing MemberTestGate. The caller must derive
the debuggable flag from the actual Android build; opt-in is off by default.

## Integration contract
Use snapshotForTestUi() only in a dedicated test/preview screen or UI automation harness.
entitlementForTestUi() is likewise presentation-only. Do not connect either method to network
authorization, purchase acknowledgement, token/session persistence, protected API requests,
content download gates, or production update enforcement.

For end-to-end testing, point the owned app's own API client and billing integration at a
developer-controlled staging backend / official billing sandbox. Validate signed test
entitlements there. Release builds must retain normal server-verified entitlement and update
paths.

## Scope of this commit
Adds the reusable model, gate, controller, and JVM unit tests. It does not automatically alter
arbitrary app methods, forge credentials, intercept/replace server responses, suppress production
update checks, or claim universal compatibility. DEX findings remain diagnostic hints; different
apps may still require a small explicit adapter or staging integration contract.
