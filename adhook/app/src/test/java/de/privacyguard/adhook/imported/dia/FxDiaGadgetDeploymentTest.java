package de.privacyguard.adhook.imported.dia;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

/** Backend-level port policy tests; the UI must not be the security boundary. */
public final class FxDiaGadgetDeploymentTest {
    @Test public void acceptsOnlyUnreservedUserPorts() {
        assertTrue(FxDiaGadgetDeployment.isValidListenPort(1024));
        assertTrue(FxDiaGadgetDeployment.isValidListenPort(27043));
        assertTrue(FxDiaGadgetDeployment.isValidListenPort(65535));
    }

    @Test public void rejectsPrivilegedDefaultAndOutOfRangePorts() {
        assertFalse(FxDiaGadgetDeployment.isValidListenPort(-1));
        assertFalse(FxDiaGadgetDeployment.isValidListenPort(0));
        assertFalse(FxDiaGadgetDeployment.isValidListenPort(1023));
        assertFalse(FxDiaGadgetDeployment.isValidListenPort(27042));
        assertFalse(FxDiaGadgetDeployment.isValidListenPort(65536));
    }

    @Test public void preflightRejectsInvalidPortsBeforeResolvingTargetPackage() {
        for (int port : new int[] {-1, 0, 1023, 27042, 65536}) {
            String error = FxDiaGadgetDeployment.validateSources(
                    null, null, null, null, port);
            assertTrue("port " + port + " must be rejected by preflight",
                    error != null && error.contains("监听端口"));
        }
    }

    @Test public void rootCommandBuilderRejectsInvalidPortsBeforeGeneratingShell() {
        for (int port : new int[] {-1, 0, 1023, 27042, 65536}) {
            assertThrows(IllegalArgumentException.class, () ->
                    FxDiaGadgetDeployment.buildDeployCommand(
                            "/data/local/tmp/libfrida-gadget.so",
                            "/data/local/tmp/libfrida-gadget.config.so",
                            "/data/app/com.example.debuggable/lib/arm64",
                            "com.example.debuggable",
                            port));
        }
    }

    @Test public void deployBuilderRejectsTargetPathTraversalAndInvalidPackage() {
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildDeployCommand(
                        "/data/local/tmp/libfrida-gadget.so",
                        "/data/local/tmp/libfrida-gadget.config.so",
                        "/data/app/../../data/adb/modules/privacyguard",
                        "com.example.debuggable",
                        27043));
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildDeployCommand(
                        "/data/local/tmp/libfrida-gadget.so",
                        "/data/local/tmp/libfrida-gadget.config.so",
                        "/data/app/com.example.debuggable/lib/arm64",
                        "com.example;touch /data/adb/pwn",
                        27043));
    }

    @Test public void deployBuilderRejectsTraversalAndNonCanonicalSourcePaths() {
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildDeployCommand(
                        "/data/local/tmp/../etc/passwd",
                        "/data/local/tmp/libfrida-gadget.config.so",
                        "/data/app/com.example.debuggable/lib/arm64",
                        "com.example.debuggable",
                        27043));
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildDeployCommand(
                        "/data/local/tmp/libfrida-gadget.so",
                        "/data/local/tmp/./libfrida-gadget.config.so",
                        "/data/app/com.example.debuggable/lib/arm64",
                        "com.example.debuggable",
                        27043));
    }

    @Test public void removeBuilderRejectsTargetPathTraversalAndInvalidPackage() {
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildRemoveCommand(
                        "/data/app/../../data/adb/modules/privacyguard",
                        "com.example.debuggable"));
        assertThrows(IllegalArgumentException.class, () ->
                FxDiaGadgetDeployment.buildRemoveCommand(
                        "/data/app/com.example.debuggable/lib/arm64",
                        "com.example;touch /data/adb/pwn"));
    }

    @Test public void acceptsOnlyTheSelectedAppsMainOrNamedChildProcess() {
        assertTrue(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.example.debuggable") == null);
        assertTrue(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.example.debuggable:remote") == null);
        assertTrue(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.example.debuggable:worker_2") == null);
    }

    @Test public void rejectsWildcardForeignAndMalformedProcessNames() {
        assertFalse(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "*") == null);
        assertFalse(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.other.app") == null);
        assertFalse(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.example.debuggable:remote;id") == null);
        assertFalse(FxDiaGadgetDeployment.validateProcessName(
                "com.example.debuggable", "com.example.debuggable:") == null);
    }

    @Test public void markerBindsTheExactSelectedProcess() {
        String command = FxDiaGadgetDeployment.buildDeployCommand(
                "/data/local/tmp/libfrida-gadget.so",
                "/data/local/tmp/libfrida-gadget.config.so",
                "/data/app/com.example.debuggable/lib/arm64",
                "com.example.debuggable",
                27043,
                "com.example.debuggable:remote");
        assertTrue(command.contains("processes=%s"));
        assertTrue(command.contains("com.example.debuggable:remote"));
        assertFalse(command.contains("processes=*"));
    }

    @Test public void rootCommandBuilderRetainsValidatedPort() {
        String command = FxDiaGadgetDeployment.buildDeployCommand(
                "/data/local/tmp/libfrida-gadget.so",
                "/data/local/tmp/libfrida-gadget.config.so",
                "/data/app/com.example.debuggable/lib/arm64",
                "com.example.debuggable",
                27043);
        assertTrue(command.contains("port=27043"));
    }
}
