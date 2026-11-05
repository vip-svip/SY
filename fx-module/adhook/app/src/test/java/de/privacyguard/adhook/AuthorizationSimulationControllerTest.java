package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AuthorizationSimulationControllerTest {
    private static final String PKG = "com.example.owned";
    private AuthorizationSimulationProfile vipScenario() {
        return new AuthorizationSimulationProfile(
                AuthorizationSimulationProfile.LoginState.LOGGED_IN,
                AuthorizationSimulationProfile.EntitlementState.VIP,
                AuthorizationSimulationProfile.BillingState.PURCHASED,
                AuthorizationSimulationProfile.UpdateState.UP_TO_DATE,
                1900000000000L, "vip_preview");
    }
    @Test public void scenarioRequiresDebugOptInAndExactPackage() {
        AuthorizationSimulationController release = new AuthorizationSimulationController(false,true,PKG,PKG);
        AuthorizationSimulationController noOptIn = new AuthorizationSimulationController(true,false,PKG,PKG);
        AuthorizationSimulationController wrongPackage = new AuthorizationSimulationController(true,true,"com.example.other",PKG);
        assertFalse(release.isEnabled());
        assertFalse(noOptIn.isEnabled());
        assertFalse(wrongPackage.isEnabled());
        assertFalse(release.setScenario(vipScenario()));
        assertFalse(noOptIn.setScenario(vipScenario()));
    }
    @Test public void enabledControllerStoresAllUiScenarioDimensions() {
        AuthorizationSimulationController c = new AuthorizationSimulationController(true,true,PKG,PKG);
        AuthorizationSimulationProfile expected = vipScenario();
        assertTrue(c.setScenario(expected));
        AuthorizationSimulationProfile actual = c.snapshotForTestUi();
        assertEquals(expected.loginState,actual.loginState);
        assertEquals(expected.entitlementState,actual.entitlementState);
        assertEquals(expected.billingState,actual.billingState);
        assertEquals(expected.updateState,actual.updateState);
        assertEquals(expected.memberExpiryEpochMs,actual.memberExpiryEpochMs);
        assertEquals("vip_preview",actual.scenarioId);
    }
    @Test public void simulationIsOnlyASeparateUiProjection() {
        AuthorizationSimulationController c = new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(c.setScenario(vipScenario()));
        assertEquals(MemberUiTestProfile.State.VIP,c.entitlementForTestUi(MemberUiTestProfile.State.FREE));
        assertEquals(MemberUiTestProfile.State.FREE,
                MemberUiTestProfile.resolveEntitlementState(MemberUiTestProfile.State.FREE));
    }
    @Test public void disabledControllerFallsBackToDefaultAndServerUiState() {
        AuthorizationSimulationController c = new AuthorizationSimulationController(false,true,PKG,PKG);
        assertEquals(MemberUiTestProfile.State.FREE,c.entitlementForTestUi(MemberUiTestProfile.State.FREE));
        assertEquals(AuthorizationSimulationProfile.LoginState.LOGGED_OUT,c.snapshotForTestUi().loginState);
    }
    @Test public void resetRestoresDefaultScenario() {
        AuthorizationSimulationController c = new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(c.setScenario(vipScenario()));
        c.reset();
        assertEquals(AuthorizationSimulationProfile.EntitlementState.FREE,c.snapshotForTestUi().entitlementState);
        assertEquals(AuthorizationSimulationProfile.BillingState.IDLE,c.snapshotForTestUi().billingState);
    }
    @Test(expected = IllegalArgumentException.class)
    public void rejectsNegativeExpiry() {
        new AuthorizationSimulationProfile(AuthorizationSimulationProfile.LoginState.LOGGED_IN,
                AuthorizationSimulationProfile.EntitlementState.VIP,
                AuthorizationSimulationProfile.BillingState.PURCHASED,
                AuthorizationSimulationProfile.UpdateState.UP_TO_DATE,-1,"bad");
    }
}
