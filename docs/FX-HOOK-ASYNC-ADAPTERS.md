# FX Hook 1.0.0 — Async state discovery and test adapters

## Async state discovery

`AsyncStateSourceProfiler` inspects declared field, method-return, and method-parameter
types for asynchronous API shapes, including Kotlin coroutine/Flow, LiveData, Rx-style
streams, CompletionStage/Future, and Deferred-like declarations. It records declaration
names and type names only. It does not subscribe to streams, await futures, invoke
methods, or inspect emitted values.

The profiler is bounded to 128 fields and 128 methods per class. A detected async
declaration is a lead for source tracing, not proof that it represents login or
membership state.

## Developer test adapter registry

`DeveloperTestAdapterRegistry` allows an explicitly registered, developer-authored
provider to supply an `AuthorizationSimulationProfile` to a dedicated test UI.
Registration requires a debuggable build, explicit opt-in, and an exact package-name
match. Adapter IDs are constrained to a small safe character set and length.

The registry is not a runtime hook and does not patch target methods. It cannot
intercept or replace production authorization, server responses, purchase receipts,
billing state, login tokens, or update policy. Production entitlement decisions
must continue to use server-verified state and the official billing flow.

## Verification

Host JVM tests cover async declaration discovery and registry gating/lookup/clear.
These tests do not constitute Android-device or production integration testing.
