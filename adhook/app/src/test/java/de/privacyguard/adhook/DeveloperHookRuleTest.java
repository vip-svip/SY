package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperHookRuleTest {
    @Test public void acceptsJavaDescriptorSyntax() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "vip|com.example.vpn.auth.AuthState#isVip()Z|RETURN_TRUE|100",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("com.example.vpn.auth.AuthState#isVip()Z", rule.descriptor);
        assertTrue(rule.replacement);
        assertEquals(100, rule.priority);
    }

    @Test public void acceptsJvmArrowSyntax() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "login|Lcom/example/vpn/auth/Session;->isLoggedIn()Z|true|50",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/auth/Session;->isLoggedIn()Z", rule.descriptor);
    }

    @Test public void acceptsTypedJvmMethodForReadOnlyObservation() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;|OBSERVE|20",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals(DeveloperHookRule.Action.OBSERVE, rule.action);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void acceptsConstructorDescriptorForMetadataResolution() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "construct|Lcom/example/vpn/Trace;-><init>(I)V|OBSERVE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals(DeveloperHookRule.Action.OBSERVE, rule.action);
    }

    @Test public void acceptsJavaSourceSignatureWithTypedArgumentsAndObjectReturn() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(java.lang.String,int[])java.lang.Object|OBSERVE|25",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void acceptsJavaSourceSignatureWithPrimitiveAndArrayReturn() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#copy(byte[],boolean)byte[]|OBSERVE|25",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->copy([BZ)[B", rule.descriptor);
    }

    @Test public void sourceParserDoesNotConfuseJvmBooleanCodeWithClassName() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "legacy|com.example.vpn.AuthState#isVip()Z|RETURN_TRUE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("com.example.vpn.AuthState#isVip()Z", rule.descriptor);
    }

    @Test public void resolvesCommonJavaLangSimpleNames() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(String)Object|OBSERVE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void rejectsGenericJavaSourceSignatureWithoutErasure() {
        assertNull(DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(java.util.List<java.lang.String>)java.lang.Object|OBSERVE|25",
                "com.example.vpn"));
    }

    @Test public void acceptsDottedSyntaxAndFalseAction() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "update|com.example.vpn.update.UpdatePolicy.shouldShowUpdate()Z|false|10",
                "com.example.vpn");
        assertNotNull(rule);
        assertFalse(rule.replacement);
        assertEquals("com.example.vpn.update.UpdatePolicy#shouldShowUpdate()Z", rule.descriptor);
    }

    @Test public void supportsObserveAndDisabledActions() {
        DeveloperHookRule observe = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#isEnabled()Z|OBSERVE_ONLY|0", "com.example.vpn");
        DeveloperHookRule disabled = DeveloperHookRule.parse(
                "off|com.example.vpn.Trace#isEnabled()Z|DISABLED|-1", "com.example.vpn");
        assertNotNull(observe);
        assertEquals(DeveloperHookRule.Action.OBSERVE, observe.action);
        assertNotNull(disabled);
        assertEquals(DeveloperHookRule.Action.DISABLED, disabled.action);
    }

    @Test public void highestPriorityDisabledRuleMasksLowerPriorityRule() {
        DeveloperHookRule low = DeveloperHookRule.parse(
                "observe|com.example.vpn.Trace#isEnabled()Z|OBSERVE|1", "com.example.vpn");
        DeveloperHookRule off = DeveloperHookRule.parse(
                "off|com.example.vpn.Trace#isEnabled()Z|DISABLED|10", "com.example.vpn");
        assertTrue(DeveloperHookRule.selectEffective(java.util.Arrays.asList(low, off)).isEmpty());
    }

    @Test public void lowerPriorityRuleDoesNotOverrideHigherPriorityRule() {
        DeveloperHookRule low = DeveloperHookRule.parse(
                "low|com.example.vpn.Trace#isEnabled()Z|OBSERVE|1", "com.example.vpn");
        DeveloperHookRule high = DeveloperHookRule.parse(
                "high|com.example.vpn.Trace#isEnabled()Z|OBSERVE|10", "com.example.vpn");
        java.util.List<DeveloperHookRule> selected =
                DeveloperHookRule.selectEffective(java.util.Arrays.asList(low, high));
        assertEquals(1, selected.size());
        assertEquals("high", selected.get(0).id);
    }

    @Test public void acceptsDottedJavaSourceSignature() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace.dispatch(String,int[])Object|OBSERVE|5",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void rejectsOutOfPackageAndUnsupportedSignature() {
        assertNull(DeveloperHookRule.parse("x|com.other.App#isVip()Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip(Ljava/lang/String;)Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|network_bypass|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|true|9999", "com.example.vpn"));
    }
}
