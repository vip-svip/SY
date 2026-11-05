package de.privacyguard.adhook.imported.dia;

import org.junit.Test;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxDiaInstallerRestartPolicyTest {
    @Test public void restartRequiresSuccessfulEmptySessionSnapshot() {
        assertTrue(FxDiaInstallerRestartPolicy.isSafeToRestart(true, 0, 0, 0));
        assertFalse(FxDiaInstallerRestartPolicy.isSafeToRestart(false, 0, 0, 0));
    }

    @Test public void anyActiveOrCommittedSessionBlocksRestart() {
        assertFalse(FxDiaInstallerRestartPolicy.isSafeToRestart(true, 1, 0, 0));
        assertFalse(FxDiaInstallerRestartPolicy.isSafeToRestart(true, 0, 1, 0));
        assertFalse(FxDiaInstallerRestartPolicy.isSafeToRestart(true, 0, 0, 1));
    }

    @Test public void multipleSessionsDoNotChangeTheFailClosedDecision() {
        assertFalse(FxDiaInstallerRestartPolicy.isSafeToRestart(true, 3, 2, 1));
    }
}
