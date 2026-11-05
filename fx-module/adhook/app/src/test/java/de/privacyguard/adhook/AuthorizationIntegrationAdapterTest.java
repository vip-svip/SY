package de.privacyguard.adhook;
import org.junit.Test;
import static org.junit.Assert.*;
public class AuthorizationIntegrationAdapterTest {
 @Test public void mapsVerifiedBusinessStatesWithoutChangingThem() {
  AuthorizationTrace trace=new AuthorizationTrace(); AuthorizationIntegrationAdapter a=new AuthorizationIntegrationAdapter(trace);
  a.entitlement(AuthorizationIntegrationAdapter.EntitlementState.EXPIRED,"membership.api",200,18);
  a.billing(AuthorizationIntegrationAdapter.BillingState.PENDING,"billing.client");
  a.session(AuthorizationIntegrationAdapter.SessionState.LOGGED_OUT,"session.store");
  a.update(AuthorizationIntegrationAdapter.UpdateState.DISABLED_BY_POLICY,"update.policy");
  assertEquals(AuthorizationTrace.Outcome.EXPIRED,trace.snapshot().get(0).outcome);
  assertEquals(AuthorizationTrace.Outcome.PENDING,trace.snapshot().get(1).outcome);
  assertEquals(AuthorizationTrace.Outcome.REVOKED,trace.snapshot().get(2).outcome);
  assertEquals(AuthorizationTrace.Outcome.SKIPPED,trace.snapshot().get(3).outcome);
 }
 @Test public void nullStateIsUnknown() { AuthorizationTrace trace=new AuthorizationTrace(); new AuthorizationIntegrationAdapter(trace).entitlement(null,"adapter",200,0); assertEquals(AuthorizationTrace.Outcome.UNKNOWN,trace.snapshot().get(0).outcome); }
}
