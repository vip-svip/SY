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

    private UnifiedHookConfigParser.Target permissionTarget(boolean enabled) {
        return new UnifiedHookConfigParser.Target(false, false, false, false, false,
                false, false, false, false, false, false, false, false, false, false, false, enabled);
    }
    @Test public void hidesOnlyExplicitNotificationPermissionQueryTarget() {
        assertTrue(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.app", permissionTarget(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.app", permissionTarget(false)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "com.example.app", null));
    }
    @Test public void notificationPermissionQueryFailsOpenWhenMasterOffSharedOrProtected() {
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(false, 1, "com.example.app", permissionTarget(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 2, "com.example.app", permissionTarget(true)));
        assertFalse(NotificationPrivacyPolicy.shouldHidePermission(true, 1, "android", permissionTarget(true)));
    }
}

