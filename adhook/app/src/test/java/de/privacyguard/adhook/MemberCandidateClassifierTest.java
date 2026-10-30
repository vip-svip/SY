package de.privacyguard.adhook;

import org.junit.Test;
import java.lang.reflect.Method;
import static org.junit.Assert.*;

public class MemberCandidateClassifierTest {
    static class Sample {
        boolean isVip() { return false; }
        String getSubscriptionTier() { return "free"; }
        long getValidUntil() { return 0L; }
        Object getProfile() { return new Object(); }
        void unrelated() {}
    }

    @Test public void classifiesCommonReturnTypesWithoutInvokingMethods() throws Exception {
        assertEquals(MemberCandidateClassifier.Kind.BOOLEAN,
                inspect("isVip").kind);
        assertEquals(MemberCandidateClassifier.Kind.STRING,
                inspect("getSubscriptionTier").kind);
        assertEquals(MemberCandidateClassifier.Kind.LONG,
                inspect("getValidUntil").kind);
        assertEquals(MemberCandidateClassifier.Kind.OBJECT,
                inspect("getProfile").kind);
    }

    @Test public void unrelatedMethodsAreNotCandidates() throws Exception {
        MemberCandidateClassifier.Candidate candidate = inspect("unrelated");
        assertFalse(candidate.isWorthInspecting());
    }

    private MemberCandidateClassifier.Candidate inspect(String name) throws Exception {
        Method method = Sample.class.getDeclaredMethod(name);
        return MemberCandidateClassifier.inspect(method);
    }
}
