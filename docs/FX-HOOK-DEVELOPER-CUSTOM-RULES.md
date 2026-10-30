# FX Hook 1.0.0 — Developer-owned VPN Debug rules

The custom rule engine is for an explicitly selected developer-owned application running a debuggable build. It is not a production entitlement mechanism.

## Rule syntax

A target row can contain up to 16 rules. Each rule is a comma-delimited config field whose value uses pipe separators:

```ini
schema_version=1
ads_enabled=0
privacy_enabled=0
[list:targets]
com.example.vpn,dev_hook_enabled=1,dev_rule_1=vip|com.example.vpn.auth.AuthState#isVip()Z|RETURN_TRUE|100,dev_rule_2=login|Lcom/example/vpn/auth/Session;->isLoggedIn()Z|RETURN_TRUE|50,dev_rule_3=update|com.example.vpn.update.Policy.shouldShowUpdate()Z|RETURN_FALSE|10,dev_rule_4=trace|com.example.vpn.auth.AuthState#isEnabled()Z|OBSERVE_ONLY|0
```

Field order is `id|method-descriptor|action|priority`. For the same exact descriptor, the highest-priority rule wins; `DISABLED` entries are inert and do not shadow lower-priority active rules. Among active rules, the highest priority wins. Equal priorities preserve config order. `dev_hook_enabled=1` is mandatory; without it all custom rules remain inert even for a debuggable package.

Supported method descriptor forms:
- Exact JVM form: `Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;`
- Java source form: `com.example.vpn.Trace#dispatch(java.lang.String,int[])java.lang.Object`
- Dotted Java source form: `com.example.vpn.Trace.dispatch(String,int[])Object` (simple `java.lang` names are accepted)
- Exact constructor form: `Lcom/example/vpn/Trace;-><init>(I)V`
- Legacy Java form: `com.example.vpn.auth.AuthState#isVip()Z` (zero-argument boolean only)
- Dotted legacy form: `com.example.vpn.auth.AuthState.isVip()Z`

JVM descriptors and Java source signatures resolve the exact declared executable, including overload parameters, primitive/object/array types and return type. Java source signatures must specify erased types; generic type arguments are rejected rather than guessed. `OBSERVE` / `OBSERVE_ONLY` supports methods and constructors. The observer calls the original executable and records only argument type names, result type, instance type, exception class, duration and a bounded hit count; it never serializes argument values, tokens, credentials or returned objects. Constructor observations report the constructed instance type after successful construction.

Value-replacement actions (`true` / `RETURN_TRUE`, `false` / `RETURN_FALSE`) remain restricted to exact zero-argument primitive-boolean methods in the existing Debug fixture path. They are not a general-purpose result mutator and cannot be used to alter network authorization, billing responses, purchase tokens or server entitlements. Non-boolean methods, parameterized methods and constructors are observation-only.
## Preset use cases

- `vip`: make a local VIP presentation predicate return true in a Debug build.
- `login`: make a local logged-in UI predicate return true in a Debug build.
- `update`: make a local update-prompt predicate return false in a Debug build.

These are local UI/state fixtures only. They do not mint credentials, create purchase receipts, change backend entitlement, bypass an identity provider, or suppress an update API/network request. To test a true no-login product flow or disable version checks end-to-end in the VPN app, implement a dedicated build-flavor feature flag at the VPN app's own authentication/update repository boundary; do not infer or mutate hidden production authorization state.

## Guardrails and recovery

Rules install only when the selected package is marked `ApplicationInfo.FLAG_DEBUGGABLE`, the package matches the configured package exactly, and the owner class belongs to that package namespace. The module fails closed when a descriptor cannot be parsed or resolved. Remove the rule and force-stop/restart the app to start a process without the fixture. Existing hooks are not dynamically removed from a live process by editing Remote Files.

Host-side tests cover syntax normalization, package scoping, explicit opt-in, duplicate detection, action handling, invalid signatures, rule limits and serializer round-trip. GitHub Actions is the build gate; device-level LSPosed verification remains separate.
