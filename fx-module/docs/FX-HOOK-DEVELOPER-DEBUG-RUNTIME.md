# FX Hook 1.0.0 — Developer-owned Debug runtime fixtures

This is a runtime method hook, not a scanner-only feature. It is deliberately limited to a package that is both explicitly configured and built with Android's `FLAG_DEBUGGABLE`.

## Configuration

Add one or more exact descriptors to the package row in the existing version-1 remote config:

```ini
schema_version=1
ads_enabled=0
privacy_enabled=0
[list:targets]
com.example.owned,dev_test_vip_method=com.example.owned.auth.AuthRepo#isVip()Z,dev_test_login_method=com.example.owned.session.SessionRepo#isLoggedIn()Z,dev_test_hide_update_method=com.example.owned.update.UpdatePolicy#shouldShowUpdate()Z
```

Each owner class must be inside the configured package namespace. The descriptor is exact: `fully.qualified.Class#method()Z`. Only a method declared on that class, with no parameters and primitive `boolean` return type, is accepted. No fuzzy method-name search or overload guessing is performed.

## Runtime behavior

When the package loads, FX checks the target's `ApplicationInfo.FLAG_DEBUGGABLE`, exact package match, explicit descriptor opt-in, class name, method name, parameter list, and return type. If any check fails, no test hook is installed.

For accepted descriptors, the Debug-only fixtures are:
- `dev_test_vip_method`: returns `true` (VIP presentation path).
- `dev_test_login_method`: returns `true` (logged-in presentation path).
- `dev_test_hide_update_method`: returns `false` (hide the update prompt predicate).

These hooks replace only the configured local boolean getter result in the debuggable process. They do not write preferences/databases/files, create login tokens or purchase receipts, change billing state, forge server responses, or grant production API/resource access. They must not be configured for a release or third-party app.

To disable, remove the descriptor(s) from the remote config and force-stop/restart the target process so it is created without those hooks. Existing process hooks are not dynamically reconfigured by editing the file while the process is alive.

## Validation

Host JVM tests cover descriptor parsing, exact package scoping, method resolution, return type/arity checks, missing methods, release builds, opt-out, and package mismatch. The GitHub Actions build is the next validation gate. A physical-device run is still required to verify LSPosed registration and behavior in the actual developer app.
