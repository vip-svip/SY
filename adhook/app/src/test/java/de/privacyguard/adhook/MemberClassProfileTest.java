package de.privacyguard.adhook;
import org.junit.Test;
import static org.junit.Assert.*;
public class MemberClassProfileTest {
    static class MembershipState {
        boolean active; long expiresAt; String tier;
        boolean isActive(){return active;} long getExpiresAt(){return expiresAt;}
    }
    static class OrdinaryProfile { String name; String email; String getName(){return name;} }
    static class a { boolean b; int c; boolean d(){return b;} int e(){return c;} }
    @Test public void profilesNamedMembershipType() {
        MemberClassProfile.Result r=MemberClassProfile.inspect(MembershipState.class);
        assertTrue(r.namedCandidate); assertTrue(r.isCandidate());
        assertFalse(r.fields.isEmpty()); assertFalse(r.methods.isEmpty());
        assertTrue(MemberClassProfile.summarize(r).contains("class=MembershipState"));
    }
    @Test public void rejectsOrdinaryProfileShape() {
        MemberClassProfile.Result r=MemberClassProfile.inspect(OrdinaryProfile.class);
        assertFalse(r.namedCandidate); assertFalse(r.obfuscatedStateShape); assertFalse(r.isCandidate());
        assertEquals(0, MemberCandidateClassifier.nameScore("OrdinaryProfile"));
    }
    @Test public void detectsObfuscatedStateShapeFromDeclarationsOnly() {
        MemberClassProfile.Result r=MemberClassProfile.inspect(a.class);
        assertTrue(r.obfuscatedStateShape); assertTrue(r.isCandidate());
    }
    @Test(expected=IllegalArgumentException.class) public void rejectsNullClass() {
        MemberClassProfile.inspect(null);
    }
}
