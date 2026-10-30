package de.privacyguard.adhook;

/** Typed, read-only adapter for verified auth, entitlement, billing and update outcomes. */
public final class AuthorizationIntegrationAdapter {
 public enum SessionState { RESTORED, REFRESHED, EXPIRED, LOGGED_OUT, UNKNOWN }
 public enum EntitlementState { ACTIVE, INACTIVE, EXPIRED, REVOKED, PENDING, UNKNOWN }
 public enum BillingState { PURCHASED, PENDING, CANCELED, REFUNDED, REVOKED, ERROR, UNKNOWN }
 public enum UpdateState { AVAILABLE, UP_TO_DATE, DISABLED_BY_POLICY, ERROR, UNKNOWN }
 private final AuthorizationTrace trace;
 public AuthorizationIntegrationAdapter(AuthorizationTrace trace) { if(trace==null) throw new IllegalArgumentException("trace required"); this.trace=trace; }
 public void session(SessionState state,String source) { trace.record(AuthorizationTrace.Stage.SESSION_RESTORE,map(state),0,-1,source,"session_state"); }
 public void entitlement(EntitlementState state,String source,int httpStatus,long durationMs) { trace.record(AuthorizationTrace.Stage.ENTITLEMENT_RESULT,map(state),httpStatus,durationMs,source,"verified_entitlement_state"); }
 public void billing(BillingState state,String source) { trace.record(AuthorizationTrace.Stage.BILLING_RESULT,map(state),0,-1,source,"billing_state"); }
 public void update(UpdateState state,String source) { trace.record(AuthorizationTrace.Stage.UPDATE_RESULT,map(state),0,-1,source,"update_policy_state"); }
 private static AuthorizationTrace.Outcome map(SessionState s) { if(s==null)return AuthorizationTrace.Outcome.UNKNOWN; switch(s){case RESTORED:return AuthorizationTrace.Outcome.SUCCESS;case REFRESHED:return AuthorizationTrace.Outcome.SUCCESS;case EXPIRED:return AuthorizationTrace.Outcome.EXPIRED;case LOGGED_OUT:return AuthorizationTrace.Outcome.REVOKED;default:return AuthorizationTrace.Outcome.UNKNOWN;} }
 private static AuthorizationTrace.Outcome map(EntitlementState s) { if(s==null)return AuthorizationTrace.Outcome.UNKNOWN; switch(s){case ACTIVE:return AuthorizationTrace.Outcome.SUCCESS;case INACTIVE:return AuthorizationTrace.Outcome.REJECTED;case EXPIRED:return AuthorizationTrace.Outcome.EXPIRED;case REVOKED:return AuthorizationTrace.Outcome.REVOKED;case PENDING:return AuthorizationTrace.Outcome.PENDING;default:return AuthorizationTrace.Outcome.UNKNOWN;} }
 private static AuthorizationTrace.Outcome map(BillingState s) { if(s==null)return AuthorizationTrace.Outcome.UNKNOWN; switch(s){case PURCHASED:return AuthorizationTrace.Outcome.SUCCESS;case PENDING:return AuthorizationTrace.Outcome.PENDING;case CANCELED:return AuthorizationTrace.Outcome.REJECTED;case REFUNDED:case REVOKED:return AuthorizationTrace.Outcome.REVOKED;case ERROR:return AuthorizationTrace.Outcome.ERROR;default:return AuthorizationTrace.Outcome.UNKNOWN;} }
 private static AuthorizationTrace.Outcome map(UpdateState s) { if(s==null)return AuthorizationTrace.Outcome.UNKNOWN; switch(s){case AVAILABLE:return AuthorizationTrace.Outcome.SUCCESS;case UP_TO_DATE:return AuthorizationTrace.Outcome.SUCCESS;case DISABLED_BY_POLICY:return AuthorizationTrace.Outcome.SKIPPED;case ERROR:return AuthorizationTrace.Outcome.ERROR;default:return AuthorizationTrace.Outcome.UNKNOWN;} }
}
