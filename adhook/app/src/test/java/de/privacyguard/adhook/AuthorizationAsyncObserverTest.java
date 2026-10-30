package de.privacyguard.adhook;

import org.junit.Test;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import static org.junit.Assert.*;

public class AuthorizationAsyncObserverTest {
    private static final class FakeClock implements AuthorizationTrace.Clock {
        long now;
        public long elapsedRealtimeMs() { return now; }
    }

    @Test public void observesCompletionWithoutReplacingStageOrValue() {
        FakeClock clock = new FakeClock();
        AuthorizationTrace trace = new AuthorizationTrace(8, clock);
        AuthorizationAsyncObserver observer = new AuthorizationAsyncObserver(trace, clock);
        CompletableFuture<String> original = new CompletableFuture<>();
        CompletionStage<String> returned = observer.observe(original, "entitlement_flow");
        assertSame(original, returned);
        clock.now = 23;
        original.complete("business-payload");
        assertEquals(2, trace.snapshot().size());
        AuthorizationTrace.Event result = trace.snapshot().get(1);
        assertEquals(AuthorizationTrace.Stage.ASYNC_OPERATION_RESULT, result.stage);
        assertEquals(AuthorizationTrace.Outcome.SUCCESS, result.outcome);
        assertEquals(23, result.durationMs);
        assertEquals("business-payload", original.join());
    }

    @Test public void recordsFailureWithoutSerializingExceptionDetails() {
        FakeClock clock = new FakeClock();
        AuthorizationTrace trace = new AuthorizationTrace(8, clock);
        CompletableFuture<Object> future = new CompletableFuture<>();
        new AuthorizationAsyncObserver(trace, clock).observe(future, "session_refresh");
        future.completeExceptionally(new IllegalStateException("secret-token-must-not-be-logged"));
        AuthorizationTrace.Event result = trace.snapshot().get(1);
        assertEquals(AuthorizationTrace.Outcome.ERROR, result.outcome);
        assertEquals("async_failed", result.detailCode);
    }
}
