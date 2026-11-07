package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class ClipboardIsolationPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.clip," + flags + "\n").targets.get("com.example.clip");
    }

    @Test public void isolationRequiresExplicitSinglePackageOptIn() {
        assertTrue(ClipboardIsolationPolicy.shouldIsolate(true, 1, "com.example.clip",
                target("clipboard_isolate=1")));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(false, 1, "com.example.clip",
                target("clipboard_isolate=1")));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 2, "com.example.clip",
                target("clipboard_isolate=1")));
    }

    @Test public void readBlockTakesPrecedenceAndFailsOpenFromIsolationPath() {
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, "com.example.clip",
                target("clipboard_isolate=1,clipboard_read_block=1")));
    }

    @Test public void protectedAndUnknownTargetsFailOpen() {
        UnifiedHookConfigParser.Target t = target("clipboard_isolate=1");
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, "android", t));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, "de.privacyguard.adhook", t));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, "org.lsposed.manager", t));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, null, t));
        assertFalse(ClipboardIsolationPolicy.shouldIsolate(true, 1, "com.example.clip", null));
    }
}
