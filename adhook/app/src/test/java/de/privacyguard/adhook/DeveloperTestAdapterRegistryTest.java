package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperTestAdapterRegistryTest {
    private static AuthorizationSimulationProfile vipPreview() {
        return new AuthorizationSimulationProfile(AuthorizationSimulationProfile.LoginState.LOGGED_IN,
                AuthorizationSimulationProfile.EntitlementState.VIP,
                AuthorizationSimulationProfile.BillingState.PURCHASED,
                AuthorizationSimulationProfile.UpdateState.UP_TO_DATE,0L,"preview");
    }
    @Test public void requiresDebugOptInAndExactPackage() {
        DeveloperTestAdapterRegistry disabled=new DeveloperTestAdapterRegistry(false,true,"com.example.app","com.example.app");
        assertFalse(disabled.register("com.example.app","preview",DeveloperTestAdapterRegistryTest::vipPreview));
        DeveloperTestAdapterRegistry enabled=new DeveloperTestAdapterRegistry(true,true,"com.example.app","com.example.app");
        assertFalse(enabled.register("com.other.app","preview",DeveloperTestAdapterRegistryTest::vipPreview));
        assertTrue(enabled.register("com.example.app","preview",DeveloperTestAdapterRegistryTest::vipPreview));
    }
    @Test public void returnsOnlyRegisteredTestUiScenario() {
        DeveloperTestAdapterRegistry registry=new DeveloperTestAdapterRegistry(true,true,"com.example.app","com.example.app");
        assertEquals(AuthorizationSimulationProfile.EntitlementState.FREE,
                registry.scenarioForTestUi("missing").entitlementState);
        registry.register("com.example.app","preview",DeveloperTestAdapterRegistryTest::vipPreview);
        assertEquals(AuthorizationSimulationProfile.EntitlementState.VIP,
                registry.scenarioForTestUi("preview").entitlementState);
    }
    @Test public void clearRemovesRegistration() {
        DeveloperTestAdapterRegistry registry=new DeveloperTestAdapterRegistry(true,true,"com.example.app","com.example.app");
        registry.register("com.example.app","preview",DeveloperTestAdapterRegistryTest::vipPreview);
        registry.clear();
        assertTrue(registry.registrations().isEmpty());
    }
}
