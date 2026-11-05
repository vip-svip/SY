package de.privacyguard.adhook.imported.dia;

/** Fail-closed guard for the Dia Package Installer restart action. */
public final class FxDiaInstallerRestartPolicy {
    private FxDiaInstallerRestartPolicy() { }

    public static boolean isSafeToRestart(boolean sessionReadSucceeded,
                                          int activeSessions,
                                          int committedSessions,
                                          int activeStagedSessions) {
        return sessionReadSucceeded
                && activeSessions == 0
                && committedSessions == 0
                && activeStagedSessions == 0;
    }
}
