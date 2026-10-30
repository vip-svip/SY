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
    public void acceptsSixtyFourCustomRulesPerTarget() {
        StringBuilder config = new StringBuilder(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_hook_enabled=1");
        for (int i = 1; i <= UnifiedHookConfigParser.MAX_DEVELOPER_RULES_PER_TARGET; i++) {
            config.append(",dev_rule_").append(i).append("=r").append(i)
                    .append("|com.example.owned.AuthRepo#isVip()Z|OBSERVE|").append(i);
        }
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(config.toString());
        assertEquals(64, parsed.targets.get("com.example.owned").developerRules.size());
        String serialized = UnifiedHookConfigSerializer.serialize(false, false, parsed.targets);
        UnifiedHookConfigParser.Result roundTrip = UnifiedHookConfigParser.parse(serialized);
        assertEquals(64, roundTrip.targets.get("com.example.owned").developerRules.size());
        assertTrue(serialized.contains("dev_rule_64=r64|"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsSixtyFiveCustomRulesPerTarget() {
        StringBuilder config = new StringBuilder(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_hook_enabled=1");
        for (int i = 1; i <= 65; i++) {
            config.append(",dev_rule_").append(i).append("=r").append(i)
                    .append("|com.example.owned.AuthRepo#isVip()Z|OBSERVE|").append(i);
        }
        UnifiedHookConfigParser.parse(config.toString());
    }

    @Test
    public void parsesExactDeveloperDebugBooleanHookDescriptors() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_hook_enabled=1,dev_test_vip_method=com.example.owned.AuthRepo#isVip()Z," +
                "dev_test_login_method=com.example.owned.SessionRepo#isLoggedIn()Z," +
                "dev_test_hide_update_method=com.example.owned.UpdatePolicy#shouldShowUpdate()Z\n");
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.owned");
        assertEquals("com.example.owned.AuthRepo#isVip()Z", target.developerVipMethod);
        assertEquals("com.example.owned.SessionRepo#isLoggedIn()Z", target.developerLoginMethod);
        assertEquals("com.example.owned.UpdatePolicy#shouldShowUpdate()Z", target.developerHideUpdateMethod);
    }

    @Test
    public void customHookRequiresExplicitOptIn() {
        UnifiedHookConfigParser.Result disabled = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_rule_1=vip|com.example.owned.AuthRepo#isVip()Z|true|1\n");
        assertFalse(disabled.targets.get("com.example.owned").developerHooksEnabled);

        UnifiedHookConfigParser.Result enabled = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_hook_enabled=1,dev_rule_1=vip|com.example.owned.AuthRepo#isVip()Z|true|1\n");
        assertTrue(enabled.targets.get("com.example.owned").developerHooksEnabled);
    }

    @Test
    public void higherPriorityRuleWinsForDuplicateMethod() {
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_hook_enabled=1,dev_rule_1=a|com.example.owned.AuthRepo#isVip()Z|true|1," +
                "dev_rule_2=b|com.example.owned.AuthRepo#isVip()Z|false|2\n");
        java.util.List<DeveloperHookRule> effective =
                DeveloperHookRule.selectEffective(parsed.targets.get("com.example.owned").developerRules);
        assertEquals(1, effective.size());
        assertEquals("b", effective.get(0).id);
        assertEquals(DeveloperHookRule.Action.RETURN_FALSE, effective.get(0).action);
    }

    @Test
    public void disabledHigherPriorityRuleDoesNotShadowEnabledRule() {
        java.util.List<DeveloperHookRule> rules = new java.util.ArrayList<>();
        rules.add(DeveloperHookRule.parse("off|com.example.owned.AuthRepo#isVip()Z|OFF|100", "com.example.owned"));
        rules.add(DeveloperHookRule.parse("active|com.example.owned.AuthRepo#isVip()Z|RETURN_TRUE|10", "com.example.owned"));
        java.util.List<DeveloperHookRule> effective = DeveloperHookRule.selectEffective(rules);
        assertEquals(1, effective.size());
        assertEquals("active", effective.get(0).id);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDeveloperHookOutsideConfiguredPackage() {
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.owned,dev_test_vip_method=com.other.app.AuthRepo#isVip()Z\n");
    }

    @Test
    public void parsesMultipleDeveloperRulesAndOrdersByPriorityAtRuntime() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.vpn,dev_rule_1=vip|com.example.vpn.auth.AuthState#isVip()Z|true|100," +
                "dev_rule_2=login|Lcom/example/vpn/auth/Session;->isLoggedIn()Z|RETURN_TRUE|50," +
                "dev_rule_3=update|com.example.vpn.update.Policy.shouldShowUpdate()Z|false|10\n");
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.vpn");
        assertEquals(3, target.developerRules.size());
        assertEquals("vip", target.developerRules.get(0).id);
        assertEquals(100, target.developerRules.get(0).priority);
        assertEquals("Lcom/example/vpn/auth/Session;->isLoggedIn()Z", target.developerRules.get(1).descriptor);
        assertFalse(target.developerRules.get(2).replacement);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDeveloperRuleOutsideConfiguredVpnPackage() {
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.vpn,dev_rule_1=vip|com.other.Auth#isVip()Z|true|100\n");
    }

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
    public void memberDiagnosticsRemainEnabledWhenAdsMasterSwitchIsOff() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n" +
                "[list:targets]\ncom.example.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=1\n");
        assertFalse(result.isAdsEnabledFor("com.example.app"));
        assertTrue(result.isMemberDiagnosticsEnabledFor("com.example.app"));
    }

    @Test
    public void memberDiagnosticsAreDisabledWhenNotExplicitlyConfigured() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=1\nprivacy_enabled=0\n" +
                "[list:targets]\ncom.example.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0\n");
        assertFalse(result.isMemberDiagnosticsEnabledFor("com.example.app"));
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
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.camera,camera_access_block=1\n");
        assertTrue(result.targets.get("com.example.camera").cameraAccessBlock);
        assertFalse(result.targets.get("com.example.other") != null);
        assertTrue(result.privacyEnabled);
    }

    @Test
    public void parsesExplicitMediaStoreQueryBlockPerTarget() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.media,media_store_query_block=1\n");
        assertTrue(result.targets.get("com.example.media").mediaStoreQueryBlock);
        assertTrue(result.privacyEnabled);
    }

    @Test
    public void legacyConfigNeverEnablesMediaStoreQueryBlock() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").mediaStoreQueryBlock);
    }

    @Test
    public void parsesExplicitMicrophoneAccessDenialPerTarget() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.audio,mic_access_block=1\n");
        assertTrue(result.targets.get("com.example.audio").microphoneAccessBlock);
        assertTrue(result.privacyEnabled);
    }

    @Test
    public void legacyConfigNeverEnablesMicrophoneAccessDenial() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").microphoneAccessBlock);
    }

    @Test
    public void parsesExplicitLocationAccessDenialPerTarget() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.location,location_access_block=1\n");
        assertTrue(result.targets.get("com.example.location").locationAccessBlock);
        assertTrue(result.privacyEnabled);
    }

    @Test
    public void legacyConfigNeverEnablesLocationAccessDenial() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").locationAccessBlock);
    }

    @Test
    public void legacyConfigNeverEnablesCameraAccessDenial() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").cameraAccessBlock);
    }

    @Test
    public void legacyConfigNeverEnablesMicrophoneSilence() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.app,splash=1\n");
        assertFalse(result.targets.get("com.example.app").microphoneSilence);
    }
}

