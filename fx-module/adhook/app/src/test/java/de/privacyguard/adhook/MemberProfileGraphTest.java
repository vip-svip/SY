package de.privacyguard.adhook;

import org.junit.Test;
import java.util.Arrays;
import java.util.List;
import static org.junit.Assert.*;

public class MemberProfileGraphTest {
    static class EntitlementState {
        boolean active;
        long expiresAt;
    }
    static class SessionState {
        static int invoked;
        EntitlementState entitlement;
        EntitlementState currentEntitlement() { invoked++; return entitlement; }
        void update(EntitlementState next) { entitlement = next; }
    }
    static class Unrelated {
        String label;
    }

    @Test public void indexesDeclaredCrossClassReferencesWithoutInvokingMethods() {
        MemberProfileGraph.Result result = MemberProfileGraph.build(
                Arrays.asList(SessionState.class, EntitlementState.class, Unrelated.class));
        assertEquals(3, result.nodes.size());
        List<MemberProfileGraph.Edge> edges = result.edgesFrom(SessionState.class.getName());
        assertTrue(edges.stream().anyMatch(e -> e.toClass.equals(EntitlementState.class.getName())
                && e.kind == MemberProfileGraph.ReferenceKind.FIELD_TYPE));
        assertTrue(edges.stream().anyMatch(e -> e.toClass.equals(EntitlementState.class.getName())
                && e.kind == MemberProfileGraph.ReferenceKind.METHOD_RETURN));
        assertTrue(edges.stream().anyMatch(e -> e.toClass.equals(EntitlementState.class.getName())
                && e.kind == MemberProfileGraph.ReferenceKind.METHOD_PARAMETER));
        assertEquals(0, SessionState.invoked);
    }

    @Test public void ignoresTypesOutsideSuppliedIndex() {
        MemberProfileGraph.Result result = MemberProfileGraph.build(Arrays.asList(SessionState.class));
        assertTrue(result.edges.isEmpty());
    }

    @Test public void rejectsNullInput() {
        try {
            MemberProfileGraph.build(null);
            fail("expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) { }
    }
}
