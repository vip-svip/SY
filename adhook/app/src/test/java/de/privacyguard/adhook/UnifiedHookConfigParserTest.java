package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class UnifiedHookConfigParserTest {
    private static final String VALID =
            "schema_version=1\n" +
            "ads_enabled=1\n" +
            "privacy_enabled=0\n" +
            "[list:targets]\n" +
            "com.example.app,ads_splash=1,ads_feed=0,ads_overlay=1,member_diag=0,privacy=1\n";

    @Test
    public void parsesIndependentMasterSwitchesAndPerPackageFeatures() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(VALID);
        assertTrue(result.adsEnabled);
        assertFalse(result.privacyEnabled);
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.app");
        assertNotNull(target);
        assertTrue(target.splash);
        assertFalse(target.feed);
        assertTrue(target.overlay);
        assertFalse(target.memberDiag);
        assertTrue(target.privacy);
    }


    @Test
    public void legacyAdConfigRemainsCompatibleAndDoesNotEnablePrivacy() {
        String legacy = "hook_ads_enabled=1\n" +
                "[list:hook_targets]\n" +
                "com.example.app,splash=1,feed=0,overlay=1,member_diag=0 | legacy metadata\n";
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(legacy);
        assertTrue(result.adsEnabled);
        assertFalse(result.privacyEnabled);
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.app");
        assertNotNull(target);
        assertTrue(target.splash);
        assertFalse(target.feed);
        assertTrue(target.overlay);
        assertFalse(target.privacy);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnknownLegacyTargetOption() {
        UnifiedHookConfigParser.parse("hook_ads_enabled=1\n[list:hook_targets]\n" +
                "com.example.app,make_vip=1\n");
    }

    @Test
    public void privacyOnlyTargetWorksWhenAdsMasterSwitchIsOff() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=1\n");
        assertFalse(result.isAdsEnabledFor("com.example.app"));
        assertTrue(result.isPrivacyEnabledFor("com.example.app"));
    }

    @Test
    public void privacyMasterSwitchOffOverridesPerPackagePrivacyFlag() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=1\nprivacy_enabled=0\n" +
                "[list:targets]\ncom.example.app,ads_splash=1,ads_feed=0,ads_overlay=0,member_diag=0,privacy=1\n");
        assertTrue(result.isAdsEnabledFor("com.example.app"));
        assertFalse(result.isPrivacyEnabledFor("com.example.app"));
    }

    @Test
    public void commentMentioningLegacyKeyDoesNotSelectLegacyParser() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "# old key hook_ads_enabled=1 is documentation only\n" +
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=1\n");
        assertFalse(result.adsEnabled);
        assertTrue(result.privacyEnabled);
        assertTrue(result.isPrivacyEnabledFor("com.example.app"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsMissingRequiredSwitch() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\n[list:targets]\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDuplicatePackageTransactionally() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=1\ncom.example.app,ads_feed=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsProtectedPackages() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\nandroid,privacy=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnknownFeatures() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,make_vip=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsOversizedConfig() {
        StringBuilder text = new StringBuilder(70000);
        while (text.length() < 66000) text.append('#').append('x').append('\n');
        UnifiedHookConfigParser.parse(text.toString());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsOversizedLegacyConfigBeforeLegacyDispatch() {
        StringBuilder text = new StringBuilder("hook_ads_enabled=1\n[list:hook_targets]\n");
        for (int i = 0; i < 22000; i++) text.append("com.example.app,ads_splash=1\n");
        UnifiedHookConfigParser.parse(text.toString());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsNullConfigWithParserException() {
        UnifiedHookConfigParser.parse(null);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUtf8ConfigOver64KiBEvenWhenCharacterCountIsLower() {
        StringBuilder text = new StringBuilder("#");
        for (int i = 0; i < 22000; i++) text.append('界');
        UnifiedHookConfigParser.parse(text.toString());
    }

    @Test
    public void parsesOptInExifPrivacyFeatureIndependently() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=0,exif_strip=1\n");
        assertTrue(result.isExifStripEnabledFor("com.example.app"));
        assertFalse(result.isPrivacyEnabledFor("com.example.app"));
    }

    @Test
    public void legacyConfigNeverEnablesExifRedaction() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.isExifStripEnabledFor("com.example.app"));
    }

    @Test
    public void parsesOptInClipboardReadBlockIndependently() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.clip,privacy=0,clipboard_read_block=1\n");
        assertTrue(result.isClipboardReadBlockedFor("com.example.clip"));
        assertFalse(result.isPrivacyEnabledFor("com.example.clip"));
    }

    @Test
    public void privacyMasterSwitchOffOverridesClipboardReadBlock() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n" +
                "[list:targets]\ncom.example.clip,clipboard_read_block=1\n");
        assertFalse(result.isClipboardReadBlockedFor("com.example.clip"));
    }

    @Test
    public void parsesWifiScanAndCellInfoPrivacyFlagsIndependently() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.radio,wifi_scan_hide=1,cell_info_hide=0\n");
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.radio");
        assertNotNull(target);
        assertTrue(target.wifiScanHide);
        assertFalse(target.cellInfoHide);
    }

    @Test
    public void parsesRegionDiagnosticFlag() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.region,region_diag=1\n").targets.get("com.example.region");
        assertNotNull(target);
        assertTrue(target.regionDiag);
    }

    @Test
    public void parsesPassiveLocationPrivacyFlag() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.location,disable_passive_loc=1\n").targets.get("com.example.location");
        assertNotNull(target);
        assertTrue(target.disablePassiveLocation);
    }

    @Test
    public void parsesMicrophoneBlockFlag() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.audio,mic_block=1\n").targets.get("com.example.audio");
        assertNotNull(target);
        assertTrue(target.micBlock);
    }

    @Test
    public void parsesCameraIdPrivacyFlag() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.camera,camera_id_hide=1\n").targets.get("com.example.camera");
        assertNotNull(target);
        assertTrue(target.cameraIdHide);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsInvalidWifiScanFlag() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.radio,wifi_scan_hide=2\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDuplicateFeatureKeys() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=1,privacy=0\n");
    }
    @Test
    public void parsesSixSensorPrivacyFlagsIndependently() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.sensors,sensor_accel=1,sensor_gyro=0,sensor_light=1,sensor_magnet=0,sensor_pressure=1,sensor_prox=0,sensor_rate_limit=1\n");
        UnifiedHookConfigParser.Target t = result.targets.get("com.example.sensors");
        assertTrue(t.sensorAccel); assertFalse(t.sensorGyro); assertTrue(t.sensorLight);
        assertFalse(t.sensorMagnet); assertTrue(t.sensorPressure); assertFalse(t.sensorProx); assertTrue(t.sensorRateLimit);
        assertTrue(result.isSensorHiddenFor("com.example.sensors", 1));
        assertFalse(result.isSensorHiddenFor("com.example.sensors", 4));
    }

}
