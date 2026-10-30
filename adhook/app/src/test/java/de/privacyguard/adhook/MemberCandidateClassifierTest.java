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


    enum MembershipState { FREE, VIP }

    static class ObfuscatedStateHolder {
        boolean a;
        long b;
        boolean a() { return a; }
        long b() { return b; }
    }

    static class IncompleteStateHolder {
        boolean a;
        boolean a() { return a; }
    }

    static class ContinuationMarker {}

    @Test public void classifiesEnumAndKotlinSuspendLikeSignatures() throws Exception {
        Method enumGetter = SampleWithEnum.class.getDeclaredMethod("getState");
        assertEquals(MemberCandidateClassifier.Kind.ENUM,
                MemberCandidateClassifier.inspect(enumGetter).kind);
        Method suspendLike = SampleWithSuspend.class.getDeclaredMethod(
                "loadState", ContinuationMarker.class);
        assertEquals(MemberCandidateClassifier.Kind.ASYNC_FLOW,
                MemberCandidateClassifier.inspect(suspendLike).kind);
    }

    static class SampleWithEnum {
        MembershipState getState() { return MembershipState.FREE; }
    }

    static class SampleWithSuspend {
        Object loadState(ContinuationMarker continuation) { return null; }
    }

    @Test public void detectsConservativeObfuscatedFieldAndMethodShapes() {
        assertTrue(MemberCandidateClassifier.hasObfuscatedStateShape(ObfuscatedStateHolder.class));
        assertFalse(MemberCandidateClassifier.hasObfuscatedStateShape(IncompleteStateHolder.class));
    }


    static class FakeLiveData {}
    static class FakeCompletionStage {}
    static class FakeDeferred {}
    static class SampleAsync {
        FakeLiveData getLiveData() { return null; }
        FakeCompletionStage getCompletionStage() { return null; }
        FakeDeferred getDeferred() { return null; }
    }

    @Test public void recognizesCommonAsyncContainerSignatures() throws Exception {
        assertEquals(MemberCandidateClassifier.Kind.ASYNC_FLOW,
                inspectAsync("getLiveData").kind);
        assertEquals(MemberCandidateClassifier.Kind.ASYNC_FLOW,
                inspectAsync("getCompletionStage").kind);
        assertEquals(MemberCandidateClassifier.Kind.ASYNC_FLOW,
                inspectAsync("getDeferred").kind);
    }

    private MemberCandidateClassifier.Candidate inspectAsync(String name) throws Exception {
        return MemberCandidateClassifier.inspect(SampleAsync.class.getDeclaredMethod(name));
    }

    static class SampleField {
        boolean vip;
        long expiresAt;
    }

    @Test public void classifiesFieldMetadataWithoutReadingFieldValues() throws Exception {
        assertEquals(MemberCandidateClassifier.Kind.BOOLEAN,
                MemberCandidateClassifier.inspect(SampleField.class.getDeclaredField("vip")).kind);
        assertEquals(MemberCandidateClassifier.Kind.LONG,
                MemberCandidateClassifier.inspect(SampleField.class.getDeclaredField("expiresAt")).kind);
    }

    private MemberCandidateClassifier.Candidate inspect(String name) throws Exception {
        Method method = Sample.class.getDeclaredMethod(name);
        return MemberCandidateClassifier.inspect(method);
    }
}
