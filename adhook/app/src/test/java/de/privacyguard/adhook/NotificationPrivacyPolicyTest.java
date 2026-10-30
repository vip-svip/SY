package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class NotificationPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(boolean enabled) {
        return new UnifiedHookConfigParser.Target(false, false, false, false, false,
                false, false, false, false, false, false, false, false, false, false, enabled);
    }
    @Test public void blocksOnlyExplicitSinglePackageTarget() {
        assertTrue(NotificationPrivacyPolicy.shouldBlock(true, 1, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldBlock(true, 1, "com.example.app", target(false)));
        assertFalse(NotificationPrivacyPolicy.shouldBlock(true, 1, "com.example.app", null));
    }
    @Test public void failsOpenWhenMasterOffSharedOrProtected() {
        assertFalse(NotificationPrivacyPolicy.shouldBlock(false, 1, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldBlock(true, 2, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldBlock(true, 1, "android", target(true)));
    }
}
