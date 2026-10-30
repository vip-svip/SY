package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperLocalStateTestSeamTest {
    private static final String PKG="com.example.owned";
    private static AuthorizationSimulationProfile localFree() {
        return new AuthorizationSimulationProfile(
                AuthorizationSimulationProfile.LoginState.LOGGED_OUT,
                AuthorizationSimulationProfile.EntitlementState.FREE,
                AuthorizationSimulationProfile.BillingState.IDLE,
                AuthorizationSimulationProfile.UpdateState.UPDATE_AVAILABLE,0,"local_free");
    }
    private static AuthorizationSimulationProfile testVip() {
        return new AuthorizationSimulationProfile(
                AuthorizationSimulationProfile.LoginState.LOGGED_IN,
                AuthorizationSimulationProfile.EntitlementState.VIP,
                AuthorizationSimulationProfile.BillingState.PURCHASED,
                AuthorizationSimulationProfile.UpdateState.UP_TO_DATE,
                1900000000000L,"vip_logged_in_no_update");
    }
    @Test public void explicitDebugScenarioProjectsVipLoginAndNoUpdate() {
        AuthorizationSimulationController c=new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(c.setScenario(testVip()));
        DeveloperLocalStateTestSeam.Decision d=DeveloperLocalStateTestSeam.resolve(
                localFree(),c,true,true,PKG,PKG);
        assertEquals(DeveloperLocalStateTestSeam.Source.DEVELOPER_TEST_SCENARIO,d.source);
        assertEquals(AuthorizationSimulationProfile.EntitlementState.VIP,d.entitlementState);
        assertEquals(AuthorizationSimulationProfile.LoginState.LOGGED_IN,d.loginState);
        assertFalse(d.shouldShowUpdateForTestFlow());
        assertTrue(d.isLoggedInForTestFlow());
        assertEquals(1900000000000L,d.expiryEpochMs);
    }
    @Test public void releaseOrMissingOptInPreservesExactLocalState() {
        AuthorizationSimulationController c=new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(c.setScenario(testVip()));
        DeveloperLocalStateTestSeam.Decision release=DeveloperLocalStateTestSeam.resolve(
                localFree(),c,false,true,PKG,PKG);
        DeveloperLocalStateTestSeam.Decision noOptIn=DeveloperLocalStateTestSeam.resolve(
                localFree(),c,true,false,PKG,PKG);
        assertEquals(DeveloperLocalStateTestSeam.Source.APPLICATION_LOCAL_STATE,release.source);
        assertEquals(AuthorizationSimulationProfile.EntitlementState.FREE,release.entitlementState);
        assertEquals(AuthorizationSimulationProfile.LoginState.LOGGED_OUT,noOptIn.loginState);
        assertTrue(noOptIn.shouldShowUpdateForTestFlow());
    }
    @Test public void packageMismatchPreservesLocalState() {
        AuthorizationSimulationController c=new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(c.setScenario(testVip()));
        DeveloperLocalStateTestSeam.Decision d=DeveloperLocalStateTestSeam.resolve(
                localFree(),c,true,true,"com.other.app",PKG);
        assertEquals(DeveloperLocalStateTestSeam.Source.APPLICATION_LOCAL_STATE,d.source);
        assertEquals(AuthorizationSimulationProfile.UpdateState.UPDATE_AVAILABLE,d.updateState);
    }
    @Test(expected=IllegalArgumentException.class)
    public void nullApplicationStateRejected() {
        DeveloperLocalStateTestSeam.resolve(null,null,false,false,PKG,PKG);
    }
}
