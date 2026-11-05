package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class WifiScanPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(boolean enabled) {
        return new UnifiedHookConfigParser.Target(false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, enabled);
    }

    @Test public void blocksOnlyExplicitSinglePackageTarget() {
        assertTrue(WifiScanPrivacyPolicy.shouldBlock(true, 1, "com.example.app", target(true)));
        assertFalse(WifiScanPrivacyPolicy.shouldBlock(true, 1, "com.example.app", target(false)));
        assertFalse(WifiScanPrivacyPolicy.shouldBlock(true, 1, "com.example.app", null));
    }

    @Test public void failsOpenWhenMasterOffOrProcessIsSharedOrProtected() {
        assertFalse(WifiScanPrivacyPolicy.shouldBlock(false, 1, "com.example.app", target(true)));
        assertFalse(WifiScanPrivacyPolicy.shouldBlock(true, 2, "com.example.app", target(true)));
        assertFalse(WifiScanPrivacyPolicy.shouldBlock(true, 1, "android", target(true)));
    }
}
