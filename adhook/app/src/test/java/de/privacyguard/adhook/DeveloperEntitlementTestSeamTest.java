package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperEntitlementTestSeamTest {
    private static final String PKG="com.example.owned";
    private static AuthorizationSimulationProfile vipProfile() {
        return new AuthorizationSimulationProfile(AuthorizationSimulationProfile.LoginState.LOGGED_IN,
                AuthorizationSimulationProfile.EntitlementState.VIP,
                AuthorizationSimulationProfile.BillingState.PURCHASED,
                AuthorizationSimulationProfile.UpdateState.UP_TO_DATE, 1900000000000L, "vip_e2e");
    }

    @Test public void debugOptInUsesScenarioAtEntitlementRepositoryBoundary() {
        AuthorizationSimulationController controller=new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(controller.setScenario(vipProfile()));
        DeveloperEntitlementTestSeam.Decision result=DeveloperEntitlementTestSeam.resolve(
                DeveloperEntitlementTestSeam.State.FREE,controller,true,true,PKG,PKG);
        assertEquals(DeveloperEntitlementTestSeam.State.VIP,result.state);
        assertEquals(DeveloperEntitlementTestSeam.Source.DEVELOPER_TEST_SCENARIO,result.source);
        assertEquals(1900000000000L,result.expiryEpochMs);
        assertEquals("vip_e2e",result.scenarioId);
    }

    @Test public void releaseBuildAlwaysUsesServerVerifiedState() {
        AuthorizationSimulationController controller=new AuthorizationSimulationController(false,true,PKG,PKG);
        DeveloperEntitlementTestSeam.Decision result=DeveloperEntitlementTestSeam.resolve(
                DeveloperEntitlementTestSeam.State.FREE,controller,false,true,PKG,PKG);
        assertEquals(DeveloperEntitlementTestSeam.State.FREE,result.state);
        assertEquals(DeveloperEntitlementTestSeam.Source.SERVER_VERIFIED,result.source);
    }

    @Test public void wrongPackageOrMissingOptInFailsClosed() {
        AuthorizationSimulationController controller=new AuthorizationSimulationController(true,true,PKG,PKG);
        assertTrue(controller.setScenario(vipProfile()));
        DeveloperEntitlementTestSeam.Decision wrongPackage=DeveloperEntitlementTestSeam.resolve(
                DeveloperEntitlementTestSeam.State.EXPIRED,controller,true,true,"com.other.app",PKG);
        DeveloperEntitlementTestSeam.Decision noOptIn=DeveloperEntitlementTestSeam.resolve(
                DeveloperEntitlementTestSeam.State.REVOKED,controller,true,false,PKG,PKG);
        assertEquals(DeveloperEntitlementTestSeam.State.EXPIRED,wrongPackage.state);
        assertEquals(DeveloperEntitlementTestSeam.Source.SERVER_VERIFIED,wrongPackage.source);
        assertEquals(DeveloperEntitlementTestSeam.State.REVOKED,noOptIn.state);
        assertEquals(DeveloperEntitlementTestSeam.Source.SERVER_VERIFIED,noOptIn.source);
    }

    @Test public void nullServerStateDefaultsToFreeWhenGateClosed() {
        DeveloperEntitlementTestSeam.Decision result=DeveloperEntitlementTestSeam.resolve(
                null,null,false,false,PKG,PKG);
        assertEquals(DeveloperEntitlementTestSeam.State.FREE,result.state);
        assertEquals(DeveloperEntitlementTestSeam.Source.SERVER_VERIFIED,result.source);
    }
}
