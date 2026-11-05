package de.privacyguard.adhook;

/**
 * Holds test scenarios for developer-owned app test screens.
 * It deliberately has no network, BillingClient, token-store, update-client or
 * Xposed result-replacement integration. Protected business logic must use
 * server-verified state, never this controller.
 */
public final class AuthorizationSimulationController {
    private final boolean enabled;
    private AuthorizationSimulationProfile profile = AuthorizationSimulationProfile.defaults();

    public AuthorizationSimulationController(boolean debuggableBuild, boolean explicitOptIn,
                                              String processPackage, String configuredTestPackage) {
        enabled = AuthorizationSimulationGate.isEnabled(debuggableBuild, explicitOptIn,
                processPackage, configuredTestPackage);
    }
    public boolean isEnabled() { return enabled; }

    /** Replaces a scenario only when the fail-closed developer gate is enabled. */
    public synchronized boolean setScenario(AuthorizationSimulationProfile scenario) {
        if (!enabled || scenario == null) return false;
        profile = scenario;
        return true;
    }
    /** Scenario data for a dedicated test/preview UI only. */
    public synchronized AuthorizationSimulationProfile snapshotForTestUi() {
        return enabled ? profile : AuthorizationSimulationProfile.defaults();
    }
    /** Presentation helper only; never use its result for API authorization. */
    public synchronized MemberUiTestProfile.State entitlementForTestUi(
            MemberUiTestProfile.State serverVerifiedState) {
        MemberUiTestProfile.State server = MemberUiTestProfile.resolveEntitlementState(serverVerifiedState);
        if (!enabled) return server;
        switch (profile.entitlementState) {
            case VIP: return MemberUiTestProfile.State.VIP;
            case EXPIRED: return MemberUiTestProfile.State.EXPIRED;
            case REVOKED: return MemberUiTestProfile.State.REVOKED;
            case PENDING: return MemberUiTestProfile.State.PENDING;
            case FREE:
            default: return MemberUiTestProfile.State.FREE;
        }
    }
    public synchronized void reset() {
        if (enabled) profile = AuthorizationSimulationProfile.defaults();
    }
}
