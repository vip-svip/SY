# FX Hook — Generic asynchronous lifecycle observer

`AuthorizationAsyncObserver` provides a dependency-free Java adapter for `CompletionStage` implementations, including `CompletableFuture`.

## Contract

- The adapter attaches a `whenComplete` observer and returns the exact same stage instance.
- It never reads, serializes, logs, or transforms the completed value.
- It records only start/completion outcome, elapsed duration, and a sanitized source label.
- Exception messages and stack traces are intentionally not recorded.
- This is operation telemetry only. A successful future does not establish login, payment, or entitlement validity; the application must separately report server-verified domain state through `AuthorizationIntegrationAdapter`.
- The caller remains responsible for selecting the correct lifecycle boundary and avoiding sensitive source labels.

## Scope

This adapter covers the Java `CompletionStage` contract. Kotlin `Flow`, `LiveData`, RxJava, Reactor, and callback-based APIs require their own optional bridges or app-side adapters; this class does not claim automatic interception of those frameworks.
