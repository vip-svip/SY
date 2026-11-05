package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AuthorizationTraceTest {
    @Test public void recordsLifecycleMetadata() {
        AuthorizationTrace trace=new AuthorizationTrace(4);
        trace.record(AuthorizationTrace.Stage.LOGIN_RESULT,AuthorizationTrace.Outcome.SUCCESS,200,42,"auth.client","session_created");
        AuthorizationTrace.Event event=trace.snapshot().get(0);
        assertEquals(AuthorizationTrace.Stage.LOGIN_RESULT,event.stage);
        assertEquals(AuthorizationTrace.Outcome.SUCCESS,event.outcome);
        assertEquals(200,event.httpStatus);
        assertEquals(42,event.durationMs);
        assertEquals("auth.client",event.source);
    }
    @Test public void keepsOnlyMostRecentEvents() {
        AuthorizationTrace trace=new AuthorizationTrace(2);
        trace.record(AuthorizationTrace.Stage.LOGIN_REQUEST,AuthorizationTrace.Outcome.STARTED,0,-1,"auth","");
        trace.record(AuthorizationTrace.Stage.LOGIN_RESULT,AuthorizationTrace.Outcome.SUCCESS,200,10,"auth","");
        trace.record(AuthorizationTrace.Stage.TOKEN_REFRESH,AuthorizationTrace.Outcome.STARTED,0,-1,"auth","");
        assertEquals(2,trace.snapshot().size());
        assertEquals(AuthorizationTrace.Stage.LOGIN_RESULT,trace.snapshot().get(0).stage);
    }
    @Test public void sanitizesLabelsAndRejectsInvalidStatus() {
        AuthorizationTrace trace=new AuthorizationTrace();
        trace.record(AuthorizationTrace.Stage.ENTITLEMENT_RESULT,AuthorizationTrace.Outcome.SUCCESS,200,5,
                "api.example.com/path?token=secret","vip active!");
        AuthorizationTrace.Event event=trace.snapshot().get(0);
        assertFalse(event.source.contains("/"));
        assertFalse(event.source.contains("?"));
        assertFalse(event.detailCode.contains(" "));
        try { trace.record(AuthorizationTrace.Stage.LOGIN_RESULT,AuthorizationTrace.Outcome.SUCCESS,700,1,"auth",""); fail(); }
        catch (IllegalArgumentException expected) { }
    }
    @Test public void snapshotIsImmutable() {
        AuthorizationTrace trace=new AuthorizationTrace();
        trace.record(AuthorizationTrace.Stage.LOGOUT,AuthorizationTrace.Outcome.SUCCESS,0,1,"auth","");
        try { trace.snapshot().clear(); fail(); }
        catch (UnsupportedOperationException expected) { }
    }
}
