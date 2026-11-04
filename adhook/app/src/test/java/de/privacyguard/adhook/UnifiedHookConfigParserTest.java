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
        assertTrue(serialized.contains("dev_rule_b64_64="));
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
    public void roundTripsCommaDelimitedTypedMethodParametersThroughEncodedRuleField() {
        String rawRule = "trace|com.example.owned.AuthRepo#dispatch(java.lang.String,int[])java.lang.Object|OBSERVE|25";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                rawRule.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String config = "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                + "com.example.owned,dev_hook_enabled=1,dev_rule_b64_1=" + encoded + "\n";

        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(config);
        UnifiedHookConfigParser.Target target = parsed.targets.get("com.example.owned");
        assertTrue(target.developerHooksEnabled);
        assertEquals(1, target.developerRules.size());
        assertEquals("Lcom/example/owned/AuthRepo;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;",
                target.developerRules.get(0).descriptor);
        assertEquals(DeveloperHookRule.Action.OBSERVE, target.developerRules.get(0).action);

        String serialized = UnifiedHookConfigSerializer.serialize(false, false, parsed.targets);
        assertTrue(serialized.contains(",dev_rule_b64_1="));
        assertFalse(serialized.contains(",dev_rule_1="));
        UnifiedHookConfigParser.Result reparsed = UnifiedHookConfigParser.parse(serialized);
        assertTrue(reparsed.targets.get("com.example.owned").developerHooksEnabled);
        assertEquals(target.developerRules.get(0).descriptor,
                reparsed.targets.get("com.example.owned").developerRules.get(0).descriptor);
    }

    @Test
    public void parsesBase64TypedLiteralAndRetainsValueAtRuntimeConfigBoundary() {
        String raw = "name|Lcom/example/owned/DebugState;->name()Ljava/lang/String;|RETURN_LITERAL|7|local-debug";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                raw.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.owned,dev_hook_enabled=1,dev_rule_b64_1=" + encoded + "\n");
        DeveloperHookRule rule = parsed.targets.get("com.example.owned").developerRules.get(0);
        assertEquals(DeveloperHookRule.Action.RETURN_LITERAL, rule.action);
        assertEquals("local-debug", rule.literalValue);
        String republished = UnifiedHookConfigSerializer.serialize(false, false, parsed.targets);
        DeveloperHookRule roundTrip = UnifiedHookConfigParser.parse(republished)
                .targets.get("com.example.owned").developerRules.get(0);
        assertEquals("local-debug", roundTrip.literalValue);
    }

    @Test
    public void retainsBackwardCompatibilityWithSimpleLegacyCustomRuleFields() {
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                + "com.example.owned,dev_hook_enabled=1,dev_rule_1=observe|com.example.owned.AuthRepo#isVip()Z|OBSERVE|1\n");
        assertTrue(parsed.targets.get("com.example.owned").developerHooksEnabled);
        assertEquals(1, parsed.targets.get("com.example.owned").developerRules.size());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsMalformedEncodedCustomRuleField() {
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                + "com.example.owned,dev_hook_enabled=1,dev_rule_b64_1=not*base64\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsTwoEncodingsForTheSameCustomRuleSlot() {
        String rule = "observe|com.example.owned.AuthRepo#isVip()Z|OBSERVE|1";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                rule.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                + "com.example.owned,dev_hook_enabled=1,dev_rule_1=" + rule
                + ",dev_rule_b64_1=" + encoded + "\n");
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
    public void acceptsEmptyTargetsForAutomaticAdOnlyConfiguration() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=1\nprivacy_enabled=0\n[list:targets]\n");
        assertTrue(result.adsEnabled);
        assertFalse(result.privacyEnabled);
        assertTrue(result.targets.isEmpty());
    }

    @Test
    public void parsesAdvertisingIdUnificationOnlyForExplicitlySelectedTargets() {
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.ads,ad_id_unify=1\n");
        assertTrue(parsed.targets.get("com.example.ads").adIdUnify);
        assertFalse(parsed.targets.get("com.example.other") != null
                && parsed.targets.get("com.example.other").adIdUnify);
        UnifiedHookConfigParser.Result legacy = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.ads,splash=1\n");
        assertFalse(legacy.targets.get("com.example.ads").adIdUnify);
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
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nnotification_listen_enabled=1\nnotification_permission_hide_enabled=1\n[list:targets]\n" +
                "com.example.notify,notification_listen_block=1\n");
        assertTrue(result.isNotificationListenBlockedFor("com.example.notify"));
        assertFalse(result.isNotificationListenBlockedFor("com.example.other"));
        assertFalse(result.isNotificationPermissionHiddenFor("com.example.notify"));
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
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\nnotification_listen_enabled=1\nnotification_permission_hide_enabled=1\n[list:targets]\n" +
                "com.example.notify,notification_permission_hide=1\n");
        assertTrue(result.isNotificationPermissionHiddenFor("com.example.notify"));
        assertFalse(result.isNotificationPermissionHiddenFor("com.example.other"));
        assertFalse(result.isNotificationListenBlockedFor("com.example.notify"));
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

    @Test
    public void parsesAndRoundTripsPerTargetApplicationVersionSimulation() {
        String versionName = "9.9.9-test, Tokyo | debug";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                versionName.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String config = String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.owned,app_version_simulate=1,app_version_name_b64="
                        + encoded + ",app_version_code=2147483647", "");
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(config);
        UnifiedHookConfigParser.Target target = parsed.targets.get("com.example.owned");
        assertTrue(target.appVersionSimulation);
        assertEquals(versionName, target.simulatedVersionName);
        assertEquals(2147483647L, target.simulatedVersionCode);
        String serialized = UnifiedHookConfigSerializer.serialize(false, false, parsed.targets);
        UnifiedHookConfigParser.Target roundTrip =
                UnifiedHookConfigParser.parse(serialized).targets.get("com.example.owned");
        assertTrue(roundTrip.appVersionSimulation);
        assertEquals(versionName, roundTrip.simulatedVersionName);
        assertEquals(2147483647L, roundTrip.simulatedVersionCode);
        assertTrue(serialized.contains("app_version_name_b64="));
    }

    @Test
    public void legacyConfigNeverEnablesApplicationVersionSimulation() {
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(
                String.join("\n", "hook_ads_enabled=1", "[list:hook_targets]",
                        "com.example.app,splash=1", ""));
        assertFalse(parsed.targets.get("com.example.app").appVersionSimulation);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsApplicationVersionValuesWithoutExplicitOptIn() {
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "1.0".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.owned,app_version_name_b64=" + encoded + ",app_version_code=1", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsApplicationVersionCodeOutsideAndroidIntRange() {
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "1.0".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.owned,app_version_simulate=1,app_version_name_b64="
                        + encoded + ",app_version_code=2147483648", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsApplicationVersionSimulationWithoutNameOrCode() {
        UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.owned,app_version_simulate=1", ""));
    }

    @Test
    public void parsesAndRoundTripsCoordinateAndGpsProviderStateSimulation() {
        String config = String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.debug,location_simulate=1,location_lat=31.2304,"
                        + "location_lon=121.4737,location_accuracy=8.5,"
                        + "location_provider_enabled_simulate=1", "");
        UnifiedHookConfigParser.Target target =
                UnifiedHookConfigParser.parse(config).targets.get("com.example.debug");
        assertTrue(target.locationSimulation);
        assertTrue(target.locationProviderEnabledSimulation);
        assertEquals(31.2304d, target.simulatedLatitude, 0.000001d);
        assertEquals(121.4737d, target.simulatedLongitude, 0.000001d);
        assertEquals(8.5f, target.simulatedAccuracy, 0.0001f);

        String serialized = UnifiedHookConfigSerializer.serialize(false, false,
                UnifiedHookConfigParser.parse(config).targets);
        UnifiedHookConfigParser.Target restored =
                UnifiedHookConfigParser.parse(serialized).targets.get("com.example.debug");
        assertTrue(restored.locationSimulation);
        assertTrue(restored.locationProviderEnabledSimulation);
        assertEquals(8.5f, restored.simulatedAccuracy, 0.0001f);
    }

    @Test
    public void acceptsGpsProviderStateSimulationWithoutCoordinateOverride() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.debug,location_provider_enabled_simulate=1", ""))
                .targets.get("com.example.debug");
        assertFalse(target.locationSimulation);
        assertTrue(target.locationProviderEnabledSimulation);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsCoordinateSimulationWhenLocationAccessIsBlocked() {
        UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.debug,location_simulate=1,location_lat=31.2,"
                        + "location_lon=121.4,location_access_block=1", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsGpsProviderEnabledSimulationWhenLocationAccessIsBlocked() {
        UnifiedHookConfigParser.parse(String.join("\n",
                "schema_version=1", "ads_enabled=0", "privacy_enabled=0", "[list:targets]",
                "com.example.debug,location_provider_enabled_simulate=1,location_access_block=1", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsPackageSegmentsBeginningWithDigits() {
        UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.123example.app,splash=1\n");
    }

    @Test
    public void parsesExplicitDialogTextAndResourceRulesWithOptionalFeedback() {
        String text = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "更新失败\nPlease sign in".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String ids = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "com.example:id/alert_close\nbtn_cancel".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String config = String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.dialog,dialog_match=1,dialog_notify=1,dialog_text_terms_b64="
                        + text + ",dialog_id_terms_b64=" + ids, "");
        UnifiedHookConfigParser.Target target =
                UnifiedHookConfigParser.parse(config).targets.get("com.example.dialog");
        assertTrue(target.dialogMatchEnabled);
        assertTrue(target.dialogNotify);
        assertEquals(java.util.Arrays.asList("更新失败", "Please sign in"), target.dialogTextTerms);
        assertEquals(java.util.Arrays.asList("com.example:id/alert_close", "btn_cancel"),
                target.dialogIdTerms);
    }

    @Test
    public void legacyTargetsDoNotEnableDialogHandlingOrFeedback() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.legacy,splash=1\n")
                .targets.get("com.example.legacy");
        assertFalse(target.dialogMatchEnabled);
        assertFalse(target.dialogNotify);
        assertTrue(target.dialogTextTerms.isEmpty());
        assertTrue(target.dialogIdTerms.isEmpty());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDialogMatchWithoutExplicitRules() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.dialog,dialog_match=1", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDialogFeedbackWhenMatchingIsDisabled() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.dialog,dialog_notify=1", ""));
    }


    @Test
    public void parsesPerAppToastFilterRules() {
        String terms = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "签到成功\nPlease update".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String config = String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.toast,toast_filter=1,toast_text_terms_b64=" + terms, "");
        UnifiedHookConfigParser.Target target =
                UnifiedHookConfigParser.parse(config).targets.get("com.example.toast");
        assertTrue(target.toastFilterEnabled);
        assertEquals(java.util.Arrays.asList("签到成功", "Please update"), target.toastTextTerms);
    }

    @Test
    public void legacyTargetsDoNotEnableToastFiltering() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.legacy,splash=1\n")
                .targets.get("com.example.legacy");
        assertFalse(target.toastFilterEnabled);
        assertTrue(target.toastTextTerms.isEmpty());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsToastFilterWithoutExplicitTerms() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]", "com.example.toast,toast_filter=1", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsToastTermsWhenFilteringIsDisabled() {
        String terms = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "promotion".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.toast,toast_text_terms_b64=" + terms, ""));
    }


    @Test
    public void parsesPerAppActivityKeyActions() {
        String terms = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                "更新失败".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String config = String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.debug,key_finish_trigger=5,key_dialog_toggle_trigger=6,"
                        + "dialog_match=1,dialog_text_terms_b64=" + terms, "");
        UnifiedHookConfigParser.Target target =
                UnifiedHookConfigParser.parse(config).targets.get("com.example.debug");
        assertEquals(5, target.keyFinishTrigger);
        assertEquals(6, target.keyDialogToggleTrigger);
        assertTrue(target.dialogMatchEnabled);
    }

    @Test
    public void legacyTargetsKeepActivityKeyActionsDisabled() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.legacy,splash=1\n")
                .targets.get("com.example.legacy");
        assertEquals(-1, target.keyFinishTrigger);
        assertEquals(-1, target.keyDialogToggleTrigger);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsActivityKeyTriggerOutOfRange() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.debug,key_finish_trigger=7", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDialogKeyToggleWithoutDialogRules() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.debug,key_dialog_toggle_trigger=6", ""));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsTwoActivityKeyActionsUsingTheSameTrigger() {
        UnifiedHookConfigParser.parse(String.join("\n", "schema_version=1", "ads_enabled=0",
                "privacy_enabled=0", "[list:targets]",
                "com.example.debug,key_finish_trigger=5,key_dialog_toggle_trigger=5,"
                        + "dialog_match=1,dialog_text_terms_b64="
                        + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                                "blocked".getBytes(java.nio.charset.StandardCharsets.UTF_8)), ""));
    }


}

