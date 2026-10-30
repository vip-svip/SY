package de.privacyguard.adhook;

import java.util.concurrent.CompletionStage;

/**
 * Observes completion of Java CompletionStage implementations without reading
 * or transforming the completed value. The original stage is returned.
 */
public final class AuthorizationAsyncObserver {
    private final AuthorizationTrace trace;
    private final AuthorizationTrace.Clock clock;

    public AuthorizationAsyncObserver(AuthorizationTrace trace, AuthorizationTrace.Clock clock) {
        if (trace == null || clock == null) throw new IllegalArgumentException("trace and clock required");
        this.trace = trace;
        this.clock = clock;
    }

    public <T> CompletionStage<T> observe(CompletionStage<T> stage, String source) {
        if (stage == null) throw new IllegalArgumentException("stage required");
        final long startedAt = clock.elapsedRealtimeMs();
        trace.record(AuthorizationTrace.Stage.ASYNC_OPERATION, AuthorizationTrace.Outcome.STARTED,
                0, -1, source, "async_started");
        try {
            stage.whenComplete((ignoredValue, failure) -> {
                long duration = Math.max(0, clock.elapsedRealtimeMs() - startedAt);
                trace.record(AuthorizationTrace.Stage.ASYNC_OPERATION_RESULT,
                        failure == null ? AuthorizationTrace.Outcome.SUCCESS : AuthorizationTrace.Outcome.ERROR,
                        0, duration, source, failure == null ? "async_completed" : "async_failed");
            });
        } catch (RuntimeException attachFailure) {
            long duration = Math.max(0, clock.elapsedRealtimeMs() - startedAt);
            trace.record(AuthorizationTrace.Stage.ASYNC_OPERATION_RESULT, AuthorizationTrace.Outcome.ERROR,
                    0, duration, source, "observer_attach_failed");
        }
        return stage;
    }
}
