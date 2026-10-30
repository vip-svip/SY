package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AuthorizationRequestTrackerTest {
    private static final class FakeClock implements AuthorizationTrace.Clock {
        long now;
        public long elapsedRealtimeMs() { return now; }
    }
    @Test public void mapsHttpOutcomesAndMeasuresDuration() {
        FakeClock clock=new FakeClock();
        AuthorizationTrace trace=new AuthorizationTrace(16,clock);
        AuthorizationRequestTracker tracker=new AuthorizationRequestTracker(trace,clock);
        AuthorizationRequestTracker.Request request=tracker.begin(AuthorizationTrace.Stage.LOGIN_REQUEST,"auth_api");
        clock.now=37;
        assertTrue(tracker.complete(request,200,null));
        AuthorizationTrace.Event result=trace.snapshot().get(1);
        assertEquals(AuthorizationTrace.Stage.LOGIN_RESULT,result.stage);
        assertEquals(AuthorizationTrace.Outcome.SUCCESS,result.outcome);
        assertEquals(37,result.durationMs);
    }
    @Test public void classifiesRejectedAndTransportFailure() {
        FakeClock clock=new FakeClock();
        AuthorizationTrace trace=new AuthorizationTrace(8,clock);
        AuthorizationRequestTracker tracker=new AuthorizationRequestTracker(trace,clock);
        tracker.complete(tracker.begin(AuthorizationTrace.Stage.ENTITLEMENT_REQUEST,"entitlement"),403,null);
        tracker.complete(tracker.begin(AuthorizationTrace.Stage.UPDATE_CHECK,"update"),0,new RuntimeException());
        assertEquals(AuthorizationTrace.Outcome.REJECTED,trace.snapshot().get(1).outcome);
        assertEquals(AuthorizationTrace.Outcome.ERROR,trace.snapshot().get(3).outcome);
    }
    @Test public void completionIsIdempotent() {
        FakeClock clock=new FakeClock();
        AuthorizationTrace trace=new AuthorizationTrace(8,clock);
        AuthorizationRequestTracker tracker=new AuthorizationRequestTracker(trace,clock);
        AuthorizationRequestTracker.Request request=tracker.begin(AuthorizationTrace.Stage.LOGIN_REQUEST,"auth");
        assertTrue(tracker.complete(request,200,null));
        assertFalse(tracker.complete(request,500,null));
        assertEquals(2,trace.snapshot().size());
    }
    @Test public void rejectsNonRequestStage() {
        FakeClock clock=new FakeClock();
        AuthorizationRequestTracker tracker=new AuthorizationRequestTracker(new AuthorizationTrace(),clock);
        try { tracker.begin(AuthorizationTrace.Stage.LOGOUT,"auth"); fail(); }
        catch (IllegalArgumentException expected) { }
    }
}
