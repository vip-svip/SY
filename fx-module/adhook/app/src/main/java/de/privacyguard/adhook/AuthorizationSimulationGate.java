package de.privacyguard.adhook;

/** Fail-closed gate for developer simulation scenarios. */
public final class AuthorizationSimulationGate {
    private AuthorizationSimulationGate() {}
    public static boolean isEnabled(boolean debuggableBuild, boolean explicitOptIn,
                                    String processPackage, String configuredTestPackage) {
        return MemberTestGate.isEnabled(debuggableBuild, explicitOptIn, processPackage, configuredTestPackage);
    }
}
