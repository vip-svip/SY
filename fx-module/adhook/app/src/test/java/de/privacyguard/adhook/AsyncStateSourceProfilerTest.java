package de.privacyguard.adhook;

import org.junit.Test;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import static org.junit.Assert.*;

public class AsyncStateSourceProfilerTest {
    static class KotlinLikeState {
        CompletableFuture<Boolean> entitlementState;
        CompletableFuture<Boolean> loadEntitlement() { return null; }
    }
    static class PlainState { boolean active; }

    @Test public void findsAsyncFieldAndMethodReturnDeclarations() {
        List<AsyncStateSourceProfiler.Source> found=AsyncStateSourceProfiler.inspect(KotlinLikeState.class);
        assertTrue(found.size()>=2);
        assertTrue(found.stream().anyMatch(s -> !s.method && s.kind==AsyncStateSourceProfiler.SourceKind.FUTURE));
        assertTrue(found.stream().anyMatch(s -> s.method && s.kind==AsyncStateSourceProfiler.SourceKind.FUTURE));
    }
    @Test public void ignoresSynchronousDeclarations() {
        assertTrue(AsyncStateSourceProfiler.inspect(PlainState.class).isEmpty());
    }
    @Test public void rejectsNullClass() {
        try { AsyncStateSourceProfiler.inspect(null); fail("expected IllegalArgumentException"); }
        catch(IllegalArgumentException expected) { }
    }
}
