# FX Hook 1.0.0 — Developer entitlement test seam

## Purpose

This adds a concrete integration seam for an application the developer owns.
The app's entitlement repository can call `DeveloperEntitlementTestSeam.resolve`
after obtaining its server-verified state and before mapping that state into
application UI/business test fixtures.

When all gates pass (debuggable build, explicit opt-in, exact process/configured
package match, and an enabled simulation controller), the returned decision uses
the selected scenario. Otherwise it returns the server-verified state unchanged.
The decision records its source so test runs can distinguish simulated state from
server state.

## Integration sketch

```java
DeveloperEntitlementTestSeam.Decision decision =
    DeveloperEntitlementTestSeam.resolve(
        serverEntitlementState,
        fxSimulationController,
        BuildConfig.DEBUG,
        fxTestOptIn,
        BuildConfig.APPLICATION_ID,
        configuredFxTestPackage);

// Feed decision.state into the app's debug/test entitlement presentation path.
// Keep production API authorization and billing validation on serverEntitlementState.
```

The target app must explicitly integrate this seam at its own repository boundary.
The FX LSPosed module does not silently replace arbitrary methods in third-party
processes. This is intentional: method names and return types alone cannot prove
that a method is the authoritative entitlement decision point.

## Coverage

Host JVM tests verify debug/opt-in/package gating, VIP test scenario projection,
expiry/scenario metadata propagation, and server-state fallback. Android runtime
and target-app end-to-end tests remain outstanding.
