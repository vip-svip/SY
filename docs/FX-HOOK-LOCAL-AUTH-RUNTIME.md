# FX Hook 1.0.0 — Local authorization runtime test seam

## Scope

This integration is for a developer-owned Android application. The application
explicitly calls `DeveloperLocalStateTestSeam.resolve(...)` at its own local
repository boundary. It can exercise a complete local-state snapshot:

- login: logged out, logged in, expired session, refresh required, error;
- entitlement: free, VIP, expired, revoked, pending;
- billing presentation: idle, purchased, pending, canceled, failed, refunded, restored;
- update presentation: not checked, up to date, update available, force update, check failed;
- optional membership expiry and sanitized scenario ID.

## Fail-closed conditions

The test scenario is selected only if all conditions hold:

1. the target application build is debuggable;
2. the developer explicitly opts in;
3. runtime package name exactly matches the configured test package;
4. an enabled `AuthorizationSimulationController` is supplied.

Otherwise the original application-local snapshot is returned unchanged. Release
builds and package mismatches do not select a scenario. The test seam does not
write application preferences, databases, files, keystore entries, login tokens,
or purchase records. It does not intercept or suppress network traffic.

## Example integration

At the owned app's repository boundary, obtain the real local snapshot first,
then pass it to the seam. Feed the returned snapshot only into the app's
debug/test presentation or integration-test adapter. Keep the production
repository path unchanged for release builds.

A scenario with `LOGGED_IN + VIP + UP_TO_DATE` exercises the signed-in VIP UI
without changing persisted credentials or purchase records. A scenario with
`LOGGED_OUT + FREE + UPDATE_AVAILABLE` exercises the opposite state.

## Validation status

JVM tests cover debug opt-in, exact package matching, release fallback, local
state preservation, VIP/login projection, and update-prompt projection. These
are host-side tests. They do not establish successful installation or behavior
on a physical Android device. The seam is an explicit repository integration
point, not a universal automatic hook for unknown applications.
