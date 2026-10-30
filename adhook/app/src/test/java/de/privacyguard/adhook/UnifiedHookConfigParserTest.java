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
    public void parsesClipboardIsolationAsIndependentPrivacyFeature() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\nclipboard_isolate_enabled=1\n" +
                "[list:targets]\ncom.example.app,clipboard_isolate=1\n");
        assertTrue(result.clipboardIsolationEnabled);
        assertTrue(result.isClipboardIsolatedFor("com.example.app"));
        assertFalse(result.isClipboardReadBlockedFor("com.example.app"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsConflictingClipboardIsolationAndReadBlock() {
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,clipboard_isolate=1,clipboard_read_block=1\n");
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
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1,feed=0,overlay=0,member_diag=0 | legacy metadata\n");
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

    @Test
    public void parsesOptInWifiScanBlockIndependently() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nwifi_scan_enabled=1\n[list:targets]\n" +
                "com.example.wifi,privacy=0,wifi_scan_block=1\n");
        assertTrue(result.isWifiScanBlockedFor("com.example.wifi"));
        assertFalse(result.isWifiScanBlockedFor("com.example.other"));
        assertFalse(result.isPrivacyEnabledFor("com.example.wifi"));
    }

    @Test
    public void wifiScanMasterOffOverridesPerAppFlag() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nwifi_scan_enabled=0\n[list:targets]\n" +
                "com.example.wifi,wifi_scan_block=1\n");
        assertFalse(result.isWifiScanBlockedFor("com.example.wifi"));
    }

    @Test
    public void parsesOptInNotificationListenBlockWithIndependentMaster() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nnotification_listen_enabled=1\n[list:targets]\n" +
                "com.example.notify,notification_listen_block=1\n");
        assertTrue(result.isNotificationListenBlockedFor("com.example.notify"));
        assertFalse(result.isNotificationListenBlockedFor("com.example.other"));
        assertFalse(result.isPrivacyEnabledFor("com.example.notify"));
    }

    @Test
    public void notificationListenMasterDefaultsOffForOlderRemoteFiles() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.notify,notification_listen_block=1\n");
        assertFalse(result.isNotificationListenBlockedFor("com.example.notify"));
    }

    @Test
    public void parsesNotificationPermissionHideWithIndependentMaster() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nnotification_permission_hide_enabled=1\n[list:targets]\n" +
                "com.example.notify,notification_permission_hide=1\n");
        assertTrue(result.isNotificationPermissionHiddenFor("com.example.notify"));
        assertFalse(result.isNotificationPermissionHiddenFor("com.example.other"));
    }

    @Test
    public void notificationPermissionHideMasterDefaultsOff() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.notify,notification_permission_hide=1\n");
        assertFalse(result.isNotificationPermissionHiddenFor("com.example.notify"));
    }

    @Test
    public void parsesMicrophoneSilenceAsOptInPrivacyFeature() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.audio,mic_silence=1\n");
        assertTrue(result.privacyEnabled);
        assertTrue(result.targets.get("com.example.audio").microphoneSilence);
    }

    @Test
    public void parsesExplicitCameraAccessDenialPerTarget() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\\nads_enabled=0\\nprivacy_enabled=1\\n[list:targets]\\n" +
                "com.example.camera,camera_access_block=1\\n");
        assertTrue(result.targets.get("com.example.camera").cameraAccessBlock);
        assertFalse(result.targets.get("com.example.other") != null);
        assertTrue(result.privacyEnabled);
    }

    @Test
    public void legacyConfigNeverEnablesCameraAccessDenial() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\\n[list:hook_targets]\\ncom.example.app,splash=1\\n");
        assertFalse(result.targets.get("com.example.app").cameraAccessBlock);
    }

    @Test
    public void legacyConfigNeverEnablesMicrophoneSilence() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").microphoneSilence);
    }
}

