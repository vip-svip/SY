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
