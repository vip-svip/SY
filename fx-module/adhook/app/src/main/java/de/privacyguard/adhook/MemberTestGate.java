package de.privacyguard.adhook;

/**
 * Fail-closed gate for the opt-in member UI test profile.
 *
 * This gate is intentionally independent of server authorization. It must never be
 * used to grant API access, unlock paid resources, or construct purchase credentials.
 */
public final class MemberTestGate {
    private MemberTestGate() {}

    public static boolean isEnabled(boolean debuggableBuild,
                                    boolean userEnabled,
                                    String processPackage,
                                    String configuredTestPackage) {
        if (!debuggableBuild || !userEnabled) return false;
        if (processPackage == null || configuredTestPackage == null) return false;
        String process = processPackage.trim();
        String configured = configuredTestPackage.trim();
        if (process.isEmpty() || configured.isEmpty()) return false;
        if (!process.equals(configured)) return false;
        return !("android".equals(process)
                || "system".equals(process)
                || "de.privacyguard.adhook".equals(process)
                || "org.lsposed.manager".equals(process));
    }
}
