package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract tests for the consistency-baseline collapse and the emulator/sandbox gate.
 *
 * These two classes implement what s1mb1o/vpn-detector-android ConsistencyChecks and
 * imxiaoc996/DeviceWarLock's Sandbox/Virtual/Native/System detectors actually probe,
 * so the assertions pin the exact behaviour those detectors would observe.
 */
public final class ConsistencyAndEmulatorPolicyTest {

    private static UnifiedHookConfigParser.Target target(String features) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.app,privacy=1," + features + "\n")
                .targets.get("com.example.app");
    }

    // ---------- consistency baseline ----------

    @Test public void collapseIsAllOrNothing() {
        UnifiedHookConfigParser.Target t = target("carrier_collection_block=1");
        for (ConsistencyBaselinePolicy.Field field
                : ConsistencyBaselinePolicy.Field.values()) {
            assertTrue(field.name(), ConsistencyBaselinePolicy.shouldCollapse(
                    true, 1, "com.example.app", t, field));
        }
        // Either hardening switch is enough; both are off means no collapse.
        assertTrue(ConsistencyBaselinePolicy.shouldCollapse(true, 1, "com.example.app",
                target("police_recon_block=1"),
                ConsistencyBaselinePolicy.Field.TIMEZONE_ID));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 1, "com.example.app",
                target("clipboard_read_block=0"),
                ConsistencyBaselinePolicy.Field.SIM_COUNTRY));
    }

    @Test public void collapseIsFailClosed() {
        UnifiedHookConfigParser.Target t = target("carrier_collection_block=1");
        ConsistencyBaselinePolicy.Field field = ConsistencyBaselinePolicy.Field.SIM_COUNTRY;
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(false, 1, "com.example.app", t, field));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 2, "com.example.app", t, field));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 1, "android", t, field));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 1, "de.privacyguard.adhook", t, field));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 1, null, t, field));
        assertFalse(ConsistencyBaselinePolicy.shouldCollapse(true, 1, "com.example.app", null, field));
    }

    @Test public void neutralValuesMatchTheComparisonBaseline() {
        assertTrue(ConsistencyBaselinePolicy.NEUTRAL_TIMEZONE.equals("UTC"));
        assertTrue(ConsistencyBaselinePolicy.NEUTRAL_COUNTRY.isEmpty());
        assertTrue(ConsistencyBaselinePolicy.NEUTRAL_MCC.isEmpty());
        // Collapsed: country/operator/language become empty, timezone becomes UTC.
        assertEquals("", ConsistencyBaselinePolicy.neutralValue(true,
                ConsistencyBaselinePolicy.Field.SIM_COUNTRY, "CN"));
        assertEquals("", ConsistencyBaselinePolicy.neutralValue(true,
                ConsistencyBaselinePolicy.Field.NETWORK_COUNTRY, "CN"));
        assertEquals("", ConsistencyBaselinePolicy.neutralValue(true,
                ConsistencyBaselinePolicy.Field.MCC, "460"));
        assertEquals("UTC", ConsistencyBaselinePolicy.neutralValue(true,
                ConsistencyBaselinePolicy.Field.TIMEZONE_ID, "Asia/Shanghai"));
        assertEquals(0, ConsistencyBaselinePolicy.neutralInt(true,
                ConsistencyBaselinePolicy.Field.TIMEZONE_OFFSET, 28800000));
        assertEquals(0, ConsistencyBaselinePolicy.neutralInt(true,
                ConsistencyBaselinePolicy.Field.SIM_STATE, 5));
        // Not collapsed: the real value passes through untouched.
        assertEquals("CN", ConsistencyBaselinePolicy.neutralValue(false,
                ConsistencyBaselinePolicy.Field.SIM_COUNTRY, "CN"));
    }

    @Test public void regionMarkersAreInvisibleWhenCollapsed() {
        assertFalse(ConsistencyBaselinePolicy.isRegionMarkerPackage(true,
                "ru.example.marker"));
        assertTrue(ConsistencyBaselinePolicy.isRegionMarkerPackage(false,
                "ru.example.marker"));
    }

    // ---------- emulator / sandbox ----------

    @Test public void emulatorGateIsFailClosed() {
        UnifiedHookConfigParser.Target t = target("police_recon_block=1");
        assertTrue(EmulatorSandboxPolicy.shouldBlock(true, 1, "com.example.app", t));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(false, 1, "com.example.app", t));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(true, 2, "com.example.app", t));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(true, 1, "android", t));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(true, 1, "org.lsposed.manager", t));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(true, 1, "com.example.app", null));
        assertFalse(EmulatorSandboxPolicy.shouldBlock(true, 1, "com.example.app",
                target("clipboard_read_block=0")));
    }

    @Test public void everyEmulatorSurfaceIsGatedByTheReconSwitch() {
        UnifiedHookConfigParser.Target t = target("police_recon_block=1");
        for (EmulatorSandboxPolicy.Surface surface : EmulatorSandboxPolicy.Surface.values()) {
            assertTrue(surface.name(), EmulatorSandboxPolicy.shouldBlockSurface(
                    true, 1, "com.example.app", t, surface));
        }
    }

    @Test public void kernelAndSandboxPathsAreRecognised() {
        for (String path : new String[]{
                "/proc/mounts", "/proc/version", "/proc/self/fd/12",
                "/proc/fs/jbd2/...", "/proc/fs/ext4/...",
                "/sys/class/thermal", "/sys/module/dm_verity/parameters/status",
                "/sys/fs/avb", "/sys/module/kernelsu", "/sys/module/zygisk"}) {
            assertTrue(path, EmulatorSandboxPolicy.isEmulatorEvidencePath(path));
        }
        assertFalse(EmulatorSandboxPolicy.isEmulatorEvidencePath("/data/data/com.example.app/db"));
        assertFalse(EmulatorSandboxPolicy.isEmulatorEvidencePath("/system/lib64/libc.so"));
        assertFalse(EmulatorSandboxPolicy.isEmulatorEvidencePath(null));
    }

    @Test public void evidenceCommandsAreRecognised() {
        for (String command : new String[]{"ps", "ps -ef", "ps -A", "getprop",
                "cat /proc/mounts", "cat /sys/module/dm_verity/parameters/status"}) {
            assertTrue(command, EmulatorSandboxPolicy.isEmulatorEvidenceCommand(command));
        }
        assertFalse(EmulatorSandboxPolicy.isEmulatorEvidenceCommand("ls /sdcard"));
        assertFalse(EmulatorSandboxPolicy.isEmulatorEvidenceCommand(null));
    }

    @Test public void processListCollapsesTheSandboxSibling() {
        String ps = String.join("\n",
                "u0_a123 4567 1 com.example.app",
                "u0_a123 4567 1 com.example.app:remote",
                "root 89 1 init",
                "u0_a123 4567 1 com.example.app:sandbox") + "\n";
        String filtered = EmulatorSandboxPolicy.filterProcessList(ps, "com.example.app");
        assertNotNull(filtered);
        // The first copy survives so the app does not look absent.
        assertTrue(filtered.contains("com.example.app\n") || filtered.startsWith("u0_a123 4567 1 com.example.app"));
        // The duplicated copies are gone: the SDK counts "more than one" as sandbox.
        int occurrences = 0;
        int index = 0;
        while ((index = filtered.indexOf("com.example.app", index)) >= 0) {
            occurrences++;
            index += "com.example.app".length();
        }
        assertEquals(1, occurrences);
        // Unrelated processes are untouched.
        assertTrue(filtered.contains("init"));
        // A null package must not rewrite anything.
        assertEquals(ps, EmulatorSandboxPolicy.filterProcessList(ps, null));
        assertEquals(ps, EmulatorSandboxPolicy.filterProcessList(ps, ""));
    }
}
