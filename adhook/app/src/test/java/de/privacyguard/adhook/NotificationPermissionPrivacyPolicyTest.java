package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class NotificationPermissionPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(boolean enabled) {
        return new UnifiedHookConfigParser.Target(false, false, false, false, false,
                false, false, false, false, false, false, false, false, false, false, false, enabled);
    }

    @Test public void masksOnlyExplicitSinglePackageQuery() {
        assertTrue(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.app", target(false)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.other", null));
    }

    @Test public void failsOpenWhenMasterOffSharedOrProtected() {
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(false, 1, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 2, "com.example.app", target(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "android", target(true)));
    }
}
