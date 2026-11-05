package de.privacyguard.adhook;

/**
 * Test-only replacement seam for a developer-owned app's local repository boundary.
 * The host app explicitly calls this from its own repository adapter in debuggable
 * builds. It does not hook arbitrary third-party packages or alter production builds.
 */
public final class DeveloperLocalStateTestSeam {
    public enum Source { APPLICATION_LOCAL_STATE, DEVELOPER_TEST_SCENARIO }
    public static final class Decision {
        public final AuthorizationSimulationProfile.LoginState loginState;
        public final AuthorizationSimulationProfile.EntitlementState entitlementState;
        public final AuthorizationSimulationProfile.UpdateState updateState;
        public final AuthorizationSimulationProfile.BillingState billingState;
        public final long expiryEpochMs;
        public final String scenarioId;
        public final Source source;
        private Decision(AuthorizationSimulationProfile p, Source source) {
            this.loginState=p.loginState;
            this.entitlementState=p.entitlementState;
            this.updateState=p.updateState;
            this.billingState=p.billingState;
            this.expiryEpochMs=p.memberExpiryEpochMs;
            this.scenarioId=p.scenarioId;
            this.source=source;
        }
        public boolean isLoggedInForTestFlow() {
            return loginState == AuthorizationSimulationProfile.LoginState.LOGGED_IN;
        }
        public boolean shouldShowUpdateForTestFlow() {
            return updateState == AuthorizationSimulationProfile.UpdateState.UPDATE_AVAILABLE
                    || updateState == AuthorizationSimulationProfile.UpdateState.FORCE_UPDATE;
        }
    }
    private DeveloperLocalStateTestSeam() {}

    /**
     * Resolve one complete local-state snapshot. When the gate is closed, the exact
     * application-provided snapshot is returned. When open, the explicit test
     * scenario is returned for UI/integration tests only.
     */
    public static Decision resolve(AuthorizationSimulationProfile applicationLocalState,
            AuthorizationSimulationController controller, boolean debuggableBuild,
            boolean explicitOptIn, String processPackage, String configuredTestPackage) {
        if (applicationLocalState == null) throw new IllegalArgumentException("application local state is required");
        boolean allowed=MemberTestGate.isEnabled(debuggableBuild,explicitOptIn,
                processPackage,configuredTestPackage);
        if (!allowed || controller == null || !controller.isEnabled()) {
            return new Decision(applicationLocalState,Source.APPLICATION_LOCAL_STATE);
        }
        AuthorizationSimulationProfile scenario=controller.snapshotForTestUi();
        if (scenario == null) return new Decision(applicationLocalState,Source.APPLICATION_LOCAL_STATE);
        return new Decision(scenario,Source.DEVELOPER_TEST_SCENARIO);
    }
}
