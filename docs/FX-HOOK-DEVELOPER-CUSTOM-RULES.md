# FX Hook 1.0.0 — Developer-owned VPN Debug rules

The custom rule engine is for an explicitly selected developer-owned application running a debuggable build. It is not a production entitlement mechanism.

## Rule syntax

A target row can contain up to 16 rules. Each rule is a comma-delimited config field whose value uses pipe separators:

```ini
schema_version=1
ads_enabled=0
privacy_enabled=0
[list:targets]
com.example.vpn,dev_rule_1=vip|com.example.vpn.auth.AuthState#isVip()Z|true|100,dev_rule_2=login|Lcom/example/vpn/auth/Session;->isLoggedIn()Z|RETURN_TRUE|50,dev_rule_3=update|com.example.vpn.update.Policy.shouldShowUpdate()Z|false|10
```

Field order is `id|method-descriptor|action|priority`.

Supported method descriptor forms:
- Java reflection form: `com.example.vpn.auth.AuthState#isVip()Z`
- JVM arrow form: `Lcom/example/vpn/auth/AuthState;->isVip()Z`
- Dotted form: `com.example.vpn.auth.AuthState.isVip()Z`

All forms normalize to an exact declared zero-argument primitive-boolean method. Fuzzy matching, overload guessing, parameters, object returns, and non-boolean methods are rejected.

Actions: `true` / `RETURN_TRUE`, `false` / `RETURN_FALSE`. Priority is an integer from -1000 through 1000; higher priority is installed first. If multiple rules point to the same method, the highest-priority rule wins because the runtime registry de-duplicates exact Method objects. The rule count is capped at 16 per package.

## Preset use cases

- `vip`: make a local VIP presentation predicate return true in a Debug build.
- `login`: make a local logged-in UI predicate return true in a Debug build.
- `update`: make a local update-prompt predicate return false in a Debug build.

These are local UI/state fixtures only. They do not mint credentials, create purchase receipts, change backend entitlement, bypass an identity provider, or suppress an update API/network request. To test a true no-login product flow or disable version checks end-to-end in the VPN app, implement a dedicated build-flavor feature flag at the VPN app's own authentication/update repository boundary; do not infer or mutate hidden production authorization state.

## Guardrails and recovery

Rules install only when the selected package is marked `ApplicationInfo.FLAG_DEBUGGABLE`, the package matches the configured package exactly, and the owner class belongs to that package namespace. The module fails closed when a descriptor cannot be parsed or resolved. Remove the rule and force-stop/restart the app to start a process without the fixture. Existing hooks are not dynamically removed from a live process by editing Remote Files.

Host-side tests cover syntax normalization, package scoping, invalid actions/signatures, rule limits and serializer round-trip. GitHub Actions is the build gate; device-level LSPosed verification remains separate.
