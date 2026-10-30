package de.privacyguard.adhook;

/**
 * Explicit entitlement decision seam for applications owned by the developer.
 *
 * Integrate this at the application's entitlement repository boundary in a
 * debuggable build. When the fail-closed gate is not satisfied, the authoritative
 * server state is returned unchanged. No billing receipt, token, server response,
 * signature, or production credential is fabricated or modified.
 */
public final class DeveloperEntitlementTestSeam {
    public enum State { FREE, VIP, EXPIRED, REVOKED, PENDING }
    public enum Source { SERVER_VERIFIED, DEVELOPER_TEST_SCENARIO }

    public static final class Decision {
        public final State state;
        public final Source source;
        public final long expiryEpochMs;
        public final String scenarioId;
        Decision(State state, Source source, long expiryEpochMs, String scenarioId) {
            this.state=state; this.source=source; this.expiryEpochMs=expiryEpochMs;
            this.scenarioId=scenarioId;
        }
    }

    private DeveloperEntitlementTestSeam() {}

    public static Decision resolve(State serverVerifiedState,
                                   AuthorizationSimulationController controller,
                                   boolean debuggableBuild,
                                   boolean explicitOptIn,
                                   String processPackage,
                                   String configuredTestPackage) {
        State server = serverVerifiedState == null ? State.FREE : serverVerifiedState;
        boolean allowed = MemberTestGate.isEnabled(debuggableBuild, explicitOptIn,
                processPackage, configuredTestPackage);
        if (!allowed || controller == null || !controller.isEnabled()) {
            return new Decision(server, Source.SERVER_VERIFIED, 0L, "server");
        }

        AuthorizationSimulationProfile profile = controller.snapshotForTestUi();
        if (profile == null) return new Decision(server, Source.SERVER_VERIFIED, 0L, "server");
        State simulated;
        switch (profile.entitlementState) {
            case VIP: simulated=State.VIP; break;
            case EXPIRED: simulated=State.EXPIRED; break;
            case REVOKED: simulated=State.REVOKED; break;
            case PENDING: simulated=State.PENDING; break;
            case FREE:
            default: simulated=State.FREE; break;
        }
        return new Decision(simulated, Source.DEVELOPER_TEST_SCENARIO,
                profile.memberExpiryEpochMs, profile.scenarioId);
    }
}
