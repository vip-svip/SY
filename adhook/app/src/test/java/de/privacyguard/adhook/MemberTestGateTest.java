package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class MemberTestGateTest {
    @Test public void requiresDebugBuildExplicitOptInAndExactPackage() {
        assertTrue(MemberTestGate.isEnabled(true, true, "com.example.owned",
                "com.example.owned"));
        assertFalse(MemberTestGate.isEnabled(false, true, "com.example.owned",
                "com.example.owned"));
        assertFalse(MemberTestGate.isEnabled(true, false, "com.example.owned",
                "com.example.owned"));
        assertFalse(MemberTestGate.isEnabled(true, true, "com.example.other",
                "com.example.owned"));
    }

    @Test public void failsClosedForNullAndProtectedPackages() {
        assertFalse(MemberTestGate.isEnabled(true, true, null, "com.example.owned"));
        assertFalse(MemberTestGate.isEnabled(true, true, "android", "android"));
        assertFalse(MemberTestGate.isEnabled(true, true, "org.lsposed.manager",
                "org.lsposed.manager"));
    }
}
