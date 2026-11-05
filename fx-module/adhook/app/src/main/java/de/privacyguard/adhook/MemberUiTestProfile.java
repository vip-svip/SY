package de.privacyguard.adhook;

/**
 * UI-only test states for applications owned by the developer.
 *
 * Production entitlement decisions must continue to use the server-verified state.
 * Callers should use resolveUiState() only for rendering test screens and previews.
 */
public final class MemberUiTestProfile {
    public enum State {
        FREE, VIP, EXPIRED, REVOKED, PENDING
    }

    private MemberUiTestProfile() {}

    public static State resolveUiState(State serverVerifiedState,
                                       State requestedTestState,
                                       boolean gateEnabled) {
        if (serverVerifiedState == null) serverVerifiedState = State.FREE;
        if (!gateEnabled || requestedTestState == null) return serverVerifiedState;
        return requestedTestState;
    }

    /** Always returns the authoritative server state for entitlement checks. */
    public static State resolveEntitlementState(State serverVerifiedState) {
        return serverVerifiedState == null ? State.FREE : serverVerifiedState;
    }
}
