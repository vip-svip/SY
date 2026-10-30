package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class ClipboardPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(boolean enabled) {
        return new UnifiedHookConfigParser.Target(false, false, false, false, false, false, enabled);
    }
    @Test public void blocksReadsOnlyForExplicitSinglePackageTarget() {
        assertTrue(ClipboardPrivacyPolicy.shouldBlockRead(true, 1, "com.example.app", target(true)));
    }
    @Test public void sharedPackageProcessFailsOpen() {
        assertFalse(ClipboardPrivacyPolicy.shouldBlockRead(true, 2, "com.example.app", target(true)));
    }
    @Test public void privacyMasterOffFailsOpen() {
        assertFalse(ClipboardPrivacyPolicy.shouldBlockRead(false, 1, "com.example.app", target(true)));
    }
    @Test public void unselectedOrProtectedPackagesFailOpen() {
        assertFalse(ClipboardPrivacyPolicy.shouldBlockRead(true, 1, "com.example.app", target(false)));
        assertFalse(ClipboardPrivacyPolicy.shouldBlockRead(true, 1, "android", target(true)));
        assertFalse(ClipboardPrivacyPolicy.shouldBlockRead(true, 1, "org.lsposed.manager", target(true)));
    }
}
