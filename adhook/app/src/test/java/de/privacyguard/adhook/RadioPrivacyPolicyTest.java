package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class RadioPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\ncom.example.radio," + flags + "\n")
                .targets.get("com.example.radio");
    }

    @Test public void wifiScanRedactionIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("wifi_scan_hide=1");
        assertTrue(RadioPrivacyPolicy.shouldHideWifiScan(true, 1, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideWifiScan(false, 1, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideWifiScan(true, 2, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideWifiScan(true, 1, "android", t));
    }

    @Test public void cellInfoRedactionIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("cell_info_hide=1");
        assertTrue(RadioPrivacyPolicy.shouldHideCellInfo(true, 1, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideCellInfo(false, 1, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideCellInfo(true, 2, "com.example.radio", t));
        assertFalse(RadioPrivacyPolicy.shouldHideCellInfo(true, 1, "org.lsposed.manager", t));
    }
}
