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
        assertEquals("com.example.vpn.auth.Session#isLoggedIn()Z", rule.descriptor);
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

    @Test public void rejectsOutOfPackageAndUnsupportedSignature() {
        assertNull(DeveloperHookRule.parse("x|com.other.App#isVip()Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip(Ljava/lang/String;)Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|network_bypass|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|true|9999", "com.example.vpn"));
    }
}
