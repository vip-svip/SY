package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class NotificationPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.notify," + flags + "\n").targets.get("com.example.notify");
    }

    @Test public void notificationHistoryAndPermissionFlagsAreIndependent() {
        UnifiedHookConfigParser.Target t = target("block_notif_listen=1,hide_notif_perm=0");
        assertTrue(NotificationPrivacyPolicy.shouldHideActiveNotifications(true, 1, "com.example.notify", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideNotificationPermission(true, 1, "com.example.notify", t));
    }

    @Test public void notificationPrivacyRequiresMasterAndSinglePackage() {
        UnifiedHookConfigParser.Target t = target("block_notif_listen=1,hide_notif_perm=1");
        assertFalse(NotificationPrivacyPolicy.shouldHideActiveNotifications(false, 1, "com.example.notify", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideActiveNotifications(true, 2, "com.example.notify", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideNotificationPermission(true, 2, "com.example.notify", t));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target("block_notif_listen=1,hide_notif_perm=1");
        assertFalse(NotificationPrivacyPolicy.shouldHideActiveNotifications(true, 1, "android", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideActiveNotifications(true, 1, "de.privacyguard.adhook", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideNotificationPermission(true, 1, "org.lsposed.manager", t));
        assertFalse(NotificationPrivacyPolicy.shouldHideActiveNotifications(true, 1, null, t));
    }
}
