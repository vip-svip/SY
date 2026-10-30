package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class SensorPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(boolean a, boolean g, boolean l, boolean m, boolean p, boolean x) {
        return new UnifiedHookConfigParser.Target(false,false,false,false,false,false,false,a,g,l,m,p,x);
    }
    @Test public void mapsOnlySixSensorTypes() {
        UnifiedHookConfigParser.Target t=target(true,true,true,true,true,true);
        for(int type:new int[]{1,2,4,5,6,8}) assertTrue(SensorPrivacyPolicy.isEnabled(t,type));
        assertFalse(SensorPrivacyPolicy.isEnabled(t,3)); assertFalse(SensorPrivacyPolicy.isEnabled(t,9));
    }
    @Test public void masterOffSharedProcessAndProtectedPackagesFailOpen() {
        UnifiedHookConfigParser.Target t=target(true,true,true,true,true,true);
        assertFalse(SensorPrivacyPolicy.shouldHide(false,1,"com.example.app",t,1));
        assertFalse(SensorPrivacyPolicy.shouldHide(true,2,"com.example.app",t,1));
        assertFalse(SensorPrivacyPolicy.shouldHide(true,1,"android",t,1));
        assertFalse(SensorPrivacyPolicy.shouldHide(true,1,"org.lsposed.manager",t,1));
        assertFalse(SensorPrivacyPolicy.shouldHide(true,1,"com.example.app",null,1));
    }
    @Test public void selectedPackageAndSensorAreRequired() {
        UnifiedHookConfigParser.Target t=target(false,true,false,false,false,false);
        assertTrue(SensorPrivacyPolicy.shouldHide(true,1,"com.example.app",t,4));
        assertFalse(SensorPrivacyPolicy.shouldHide(true,1,"com.example.app",t,1));
    }
}
