package de.privacyguard.adhook;

/** Immutable scenario data for developer-owned application UI/integration tests.
 * This is presentation/test data, never a credential, receipt, server response or entitlement grant. */
public final class AuthorizationSimulationProfile {
    public enum LoginState { LOGGED_OUT, LOGGED_IN, SESSION_EXPIRED, REFRESH_REQUIRED, ERROR }
    public enum EntitlementState { FREE, VIP, EXPIRED, REVOKED, PENDING }
    public enum BillingState { IDLE, PURCHASED, PENDING, CANCELED, FAILED, REFUNDED, RESTORED }
    public enum UpdateState { NOT_CHECKED, UP_TO_DATE, UPDATE_AVAILABLE, FORCE_UPDATE, CHECK_FAILED }
    public final LoginState loginState;
    public final EntitlementState entitlementState;
    public final BillingState billingState;
    public final UpdateState updateState;
    /** Zero means no expiry is displayed in the test UI. */
    public final long memberExpiryEpochMs;
    /** Sanitized, non-secret scenario label. */
    public final String scenarioId;

    public AuthorizationSimulationProfile(LoginState loginState, EntitlementState entitlementState,
            BillingState billingState, UpdateState updateState, long memberExpiryEpochMs, String scenarioId) {
        if (loginState == null || entitlementState == null || billingState == null || updateState == null)
            throw new IllegalArgumentException("all simulation states are required");
        if (memberExpiryEpochMs < 0) throw new IllegalArgumentException("expiry must be non-negative");
        this.loginState = loginState;
        this.entitlementState = entitlementState;
        this.billingState = billingState;
        this.updateState = updateState;
        this.memberExpiryEpochMs = memberExpiryEpochMs;
        this.scenarioId = sanitize(scenarioId);
    }
    public static AuthorizationSimulationProfile defaults() {
        return new AuthorizationSimulationProfile(LoginState.LOGGED_OUT, EntitlementState.FREE,
                BillingState.IDLE, UpdateState.NOT_CHECKED, 0L, "default");
    }
    private static String sanitize(String value) {
        if (value == null || value.isEmpty()) return "scenario";
        StringBuilder out = new StringBuilder(32);
        for (int i = 0; i < value.length() && out.length() < 32; i++) {
            char c = value.charAt(i);
            out.append((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '_' || c == '-' ? c : '_');
        }
        return out.length() == 0 ? "scenario" : out.toString();
    }
}
