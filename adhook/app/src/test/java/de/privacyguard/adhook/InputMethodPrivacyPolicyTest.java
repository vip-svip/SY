package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class InputMethodPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flag) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.ime," + flag + "\n").targets.get("com.example.ime");
    }

    @Test public void inputMethodHidingIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("block_ime_logging=1");
        assertTrue(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, "com.example.ime", t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(false, 1, "com.example.ime", t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 2, "com.example.ime", t));
    }

    @Test public void protectedAndUnknownTargetsFailOpen() {
        UnifiedHookConfigParser.Target t = target("block_ime_logging=1");
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, "android", t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, "de.privacyguard.adhook", t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, "org.lsposed.manager", t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, null, t));
        assertFalse(InputMethodPrivacyPolicy.shouldHideInputMethods(true, 1, "com.example.ime", target("block_ime_logging=0")));
    }
}
