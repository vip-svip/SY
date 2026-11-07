package de.privacyguard.adhook;

import org.junit.Test;

import java.nio.charset.StandardCharsets;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract test for the process-map rewrite used against native hook detection.
 *
 * DeviceWarLock's HookDetector flags any `rwxp` mapping and FridaDetector flags any
 * mapping naming an instrumentation payload. The filter must remove exactly those
 * lines while leaving every innocent mapping intact, because a truncated or empty
 * map is itself a detection signal.
 */
public final class ProcessMapFilterTest {

    private static final String SAMPLE = String.join("\n",
            "12c00000-12c40000 rw-p 00000000 00:00 0 [anon:dalvik-main space]",
            "7a1b200000-7a1b201000 r-xp 00000000 103:05 1234 /system/lib64/libc.so",
            "7a2b300000-7a2b301000 rwxp 00000000 00:00 0 [anon:Frida]",
            "7a3b400000-7a3b401000 rw-p 00000000 103:05 5678 /data/local/tmp/frida-agent.so",
            "7a4b500000-7a4b501000 rw-p 00000000 103:05 9012 /system/lib64/liblog.so",
            "7a5b600000-7a5b601000 rwxp 00000000 00:00 0",
            "7a6b700000-7a6b701000 r--p 00000000 103:05 3456 /system/framework/framework.jar") + "\n";

    @Test public void rwxLinesAreDetected() {
        assertTrue(ProcessMapFilter.isRwxLine(
                "7a2b300000-7a2b301000 rwxp 00000000 00:00 0 [anon:Frida]"));
        assertTrue(ProcessMapFilter.isRwxLine(
                "7a5b600000-7a5b601000 rwxp 00000000 00:00 0"));
        assertFalse(ProcessMapFilter.isRwxLine(
                "12c00000-12c40000 rw-p 00000000 00:00 0 [anon:dalvik-main space]"));
        assertFalse(ProcessMapFilter.isRwxLine(
                "7a1b200000-7a1b201000 r-xp 00000000 103:05 1234 /system/lib64/libc.so"));
        assertFalse(ProcessMapFilter.isRwxLine("garbage"));
        assertFalse(ProcessMapFilter.isRwxLine(null));
    }

    @Test public void agentNamesAreDetected() {
        for (String path : new String[]{
                "/data/local/tmp/frida-agent.so", "/data/adb/modules/magisk",
                "/system/framework/XposedBridge.jar", "/data/adb/lspd/lib/liblsposed.so",
                "/data/local/tmp/re.frida.server", "/system/lib64/libriru.so"}) {
            assertTrue(path, ProcessMapFilter.namesAgent("0-0 rw-p 0 0 0 " + path));
        }
        assertFalse(ProcessMapFilter.namesAgent(
                "7a1b200000-7a1b201000 r-xp 00000000 /system/lib64/libc.so"));
        assertFalse(ProcessMapFilter.namesAgent(null));
    }

    @Test public void filterRemovesOnlyTheEvidenceLines() {
        String filtered = ProcessMapFilter.filter(SAMPLE);
        assertNotNull(filtered);
        // The rwx segments are gone.
        assertFalse(filtered.contains("rwxp"));
        // The instrumentation payload is gone.
        assertFalse(filtered.contains("frida"));
        // Every innocent mapping survives verbatim.
        assertTrue(filtered.contains("12c00000-12c40000 rw-p 00000000 00:00 0 [anon:dalvik-main space]"));
        assertTrue(filtered.contains("/system/lib64/libc.so"));
        assertTrue(filtered.contains("/system/lib64/liblog.so"));
        assertTrue(filtered.contains("/system/framework/framework.jar"));
        // The result still has real newlines, not escaped ones.
        assertTrue(filtered.contains("\n"));
        assertEquals(4, filtered.trim().split("\n").length);
    }

    @Test public void emptyResultNeverReturned() {
        // If every line were evidence the filter must not hand back an empty map,
        // because a zero-length map looks like a failed read.
        String allEvidence = "7a2b300000-7a2b301000 rwxp 00000000 00:00 0 [anon:Frida]\n";
        String filtered = ProcessMapFilter.filter(allEvidence);
        assertNotNull(filtered);
        assertTrue("must not become empty", filtered.length() > 0);
        assertEquals(allEvidence, filtered);
    }

    @Test public void filterBytesMatchesStringResult() {
        byte[] filtered = ProcessMapFilter.filterBytes(SAMPLE.getBytes(StandardCharsets.UTF_8));
        assertArrayEquals(ProcessMapFilter.filter(SAMPLE).getBytes(StandardCharsets.UTF_8), filtered);
        assertFalse(new String(filtered, StandardCharsets.UTF_8).contains("frida"));
    }

    @Test public void evidencePathsAreRecognised() {
        assertTrue(ProcessMapFilter.isEvidencePath("/proc/self/maps"));
        assertTrue(ProcessMapFilter.isEvidencePath("/proc/self/smaps"));
        assertTrue(ProcessMapFilter.isEvidencePath("/data/local/tmp/frida-agent.so"));
        assertTrue(ProcessMapFilter.isEvidencePath("/data/adb/modules/magisk"));
        assertFalse(ProcessMapFilter.isEvidencePath("/system/lib64/libc.so"));
        assertFalse(ProcessMapFilter.isEvidencePath("/data/data/com.example.app/db"));
        assertFalse(ProcessMapFilter.isEvidencePath(""));
        assertFalse(ProcessMapFilter.isEvidencePath(null));
    }

    @Test public void untouchedContentPassesThroughUnchanged() {
        String innocent = "7a1b200000-7a1b201000 r-xp 00000000 /system/lib64/libc.so\n";
        assertEquals(innocent, ProcessMapFilter.filter(innocent));
        assertArrayEquals(innocent.getBytes(StandardCharsets.UTF_8),
                ProcessMapFilter.filterBytes(innocent.getBytes(StandardCharsets.UTF_8)));
    }
}
