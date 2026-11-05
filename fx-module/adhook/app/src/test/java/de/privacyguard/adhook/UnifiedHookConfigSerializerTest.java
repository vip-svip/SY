package de.privacyguard.adhook;

import org.junit.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.*;

public class UnifiedHookConfigSerializerTest {
    private static Map<String, UnifiedHookConfigParser.Target> target(boolean ads, boolean privacy) {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", new UnifiedHookConfigParser.Target(
                ads, false, false, false, privacy, false, false));
        return targets;
    }

    @Test
    public void serializerRoundTripsWifiNetworkLocationIdentityTimezoneAndDeveloperMethods() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false);
        target.wifiSimulation = true;
        target.simulatedWifiSsid = "FX Lab 5G";
        target.simulatedWifiBssid = "02:00:00:00:00:01";
        target.networkTypeSimulation = true;
        target.simulatedNetworkType = "cellular";
        target.locationSimulation = true;
        target.simulatedLatitude = 35.681236d;
        target.simulatedLongitude = 139.767125d;
        target.simulatedAccuracy = 12.5f;
        target.locationProviderEnabledSimulation = true;
        target.androidIdSimulation = true;
        target.simulatedAndroidId = "0123456789ABCDEF";
        target.timeZoneSimulation = true;
        target.simulatedTimeZone = "Asia/Tokyo";
        target.developerVipMethod = "com.example.app.AccountState#isVip()Z";
        target.developerLoginMethod = "com.example.app.AccountState#isLoggedIn()Z";
        target.developerHideUpdateMethod = "com.example.app.UpdatePolicy#shouldShow()Z";
        targets.put("com.example.app", target);

        String encoded = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Target parsed =
                UnifiedHookConfigParser.parse(encoded).targets.get("com.example.app");

        assertTrue(encoded.contains("wifi_simulate=1"));
        assertTrue(encoded.contains("wifi_ssid=FX Lab 5G"));
        assertTrue(encoded.contains("wifi_bssid=02:00:00:00:00:01"));
        assertTrue(parsed.wifiSimulation);
        assertEquals("FX Lab 5G", parsed.simulatedWifiSsid);
        assertEquals("02:00:00:00:00:01", parsed.simulatedWifiBssid);

        assertTrue(parsed.networkTypeSimulation);
        assertEquals("cellular", parsed.simulatedNetworkType);
        assertTrue(parsed.locationSimulation);
        assertEquals(35.681236d, parsed.simulatedLatitude, 0.0000001d);
        assertEquals(139.767125d, parsed.simulatedLongitude, 0.0000001d);
        assertEquals(12.5f, parsed.simulatedAccuracy, 0f);
        assertTrue(parsed.locationProviderEnabledSimulation);
        assertTrue(parsed.androidIdSimulation);
        assertEquals("0123456789abcdef", parsed.simulatedAndroidId);
        assertTrue(parsed.timeZoneSimulation);
        assertEquals("Asia/Tokyo", parsed.simulatedTimeZone);
        assertEquals("com.example.app.AccountState#isVip()Z", parsed.developerVipMethod);
        assertEquals("com.example.app.AccountState#isLoggedIn()Z", parsed.developerLoginMethod);
        assertEquals("com.example.app.UpdatePolicy#shouldShow()Z", parsed.developerHideUpdateMethod);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsEnabledWifiSimulationWithoutValue() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.wifiSimulation = true;
        targets.put("com.example.app", target);
        UnifiedHookConfigSerializer.serialize(false, false, targets);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsEnabledLocationSimulationWithInvalidCoordinates() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false);
        target.locationSimulation = true;
        target.simulatedLatitude = 91d;
        target.simulatedLongitude = 0d;
        targets.put("com.example.app", target);
        UnifiedHookConfigSerializer.serialize(false, true, targets);
    }

    @Test
    public void serializerRoundTripsClipboardIsolationMasterAndTarget() {
        UnifiedHookConfigParser.Result input = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\nclipboard_isolate_enabled=1\n" +
                "[list:targets]\ncom.example.app,clipboard_isolate=1\n");
        String encoded = UnifiedHookConfigSerializer.serialize(false, true, false, false, false, true, input.targets);
        UnifiedHookConfigParser.Result output = UnifiedHookConfigParser.parse(encoded);
        assertTrue(output.clipboardIsolationEnabled);
        assertTrue(output.isClipboardIsolatedFor("com.example.app"));
    }

    @Test
    public void serializerRoundTripsDebugOnlyVoidNoOpAction() {
        String rawRule = "stop|Lcom/example/vpn/Worker;->refresh(Ljava/lang/String;)V|NO_OP_VOID|25";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                rawRule.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.Result input = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.vpn,dev_hook_enabled=1,dev_rule_b64_1=" + encoded + "\n");
        String serialized = UnifiedHookConfigSerializer.serialize(false, false, input.targets);
        UnifiedHookConfigParser.Result output = UnifiedHookConfigParser.parse(serialized);
        assertTrue(output.targets.get("com.example.vpn").developerHooksEnabled);
        assertEquals(DeveloperHookRule.Action.NO_OP_VOID,
                output.targets.get("com.example.vpn").developerRules.get(0).action);
        assertFalse(output.targets.get("com.example.vpn").developerRules.get(0).replacement);
        assertTrue(serialized.contains("dev_rule_b64_1="));
    }

    @Test
    public void serializerRoundTripsTypedLiteralDeveloperRule() {
        String rawRule = "label|Lcom/example/vpn/DebugState;->label()Ljava/lang/String;|RETURN_LITERAL|25|debug-build";
        String encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                rawRule.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        UnifiedHookConfigParser.Result input = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.vpn,dev_hook_enabled=1,dev_rule_b64_1=" + encoded + "\n");
        String serialized = UnifiedHookConfigSerializer.serialize(false, false, input.targets);
        UnifiedHookConfigParser.Result output = UnifiedHookConfigParser.parse(serialized);
        DeveloperHookRule rule = output.targets.get("com.example.vpn").developerRules.get(0);
        assertEquals(DeveloperHookRule.Action.RETURN_LITERAL, rule.action);
        assertEquals("debug-build", rule.literalValue);
        assertTrue(serialized.contains("dev_rule_b64_1="));
    }

    @Test
    public void serializerRoundTripsMultipleDeveloperRules() {
        UnifiedHookConfigParser.Result input = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.vpn,dev_hook_enabled=1,dev_rule_1=vip|com.example.vpn.auth.AuthState#isVip()Z|true|100," +
                "dev_rule_2=update|com.example.vpn.update.Policy.shouldShowUpdate()Z|false|10\n");
        String encoded = UnifiedHookConfigSerializer.serialize(false, false, input.targets);
        UnifiedHookConfigParser.Result output = UnifiedHookConfigParser.parse(encoded);
        assertEquals(2, output.targets.get("com.example.vpn").developerRules.size());
        assertTrue(output.targets.get("com.example.vpn").developerHooksEnabled);
        assertTrue(encoded.contains("dev_hook_enabled=1"));
        assertEquals("vip", output.targets.get("com.example.vpn").developerRules.get(0).id);
        assertTrue(output.targets.get("com.example.vpn").developerRules.get(0).replacement);
        assertFalse(output.targets.get("com.example.vpn").developerRules.get(1).replacement);
        assertTrue(encoded.contains("dev_rule_b64_2="));
        assertFalse(encoded.contains(",dev_rule_2="));
    }

    @Test
    public void parserAndSerializerRoundTripMoreThanSixtyFourDeveloperRules() {
        StringBuilder config = new StringBuilder(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.vpn,dev_hook_enabled=1");
        for (int i = 1; i <= 96; i++) {
            config.append(",dev_rule_").append(i).append("=rule").append(i)
                    .append("|com.example.vpn.Rule").append(i)
                    .append("#isEnabled()Z|OBSERVE|").append(i);
        }
        config.append('\n');

        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(config.toString());
        assertEquals(96, parsed.targets.get("com.example.vpn").developerRules.size());
        String serialized = UnifiedHookConfigSerializer.serialize(false, false, parsed.targets);
        assertTrue(serialized.contains("dev_rule_b64_96="));
        UnifiedHookConfigParser.Result roundTrip = UnifiedHookConfigParser.parse(serialized);
        assertEquals(96, roundTrip.targets.get("com.example.vpn").developerRules.size());
    }

    @Test
    public void roundTripsAllIndependentMasterSwitchCombinations() {
        boolean[][] combinations = {
                {true, false}, {false, true}, {false, false}, {true, true}
        };
        for (boolean[] combination : combinations) {
            String text = UnifiedHookConfigSerializer.serialize(
                    combination[0], combination[1], target(true, true));
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
            assertEquals(combination[0], parsed.adsEnabled);
            assertEquals(combination[1], parsed.privacyEnabled);
            assertEquals(combination[0], parsed.isAdsEnabledFor("com.example.app"));
            assertEquals(combination[1], parsed.isPrivacyEnabledFor("com.example.app"));
            assertFalse(parsed.isAdsEnabledFor("com.notselected.app"));
            assertFalse(parsed.isPrivacyEnabledFor("com.notselected.app"));
        }
    }

    @Test
    public void outputIsDeterministicAndSortsPackageNames() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("org.example.zed", new UnifiedHookConfigParser.Target(false, true, false, false, false, false, false));
        targets.put("com.example.alpha", new UnifiedHookConfigParser.Target(true, false, false, false, true, false, false));
        String first = UnifiedHookConfigSerializer.serialize(true, true, targets);
        String second = UnifiedHookConfigSerializer.serialize(true, true, targets);
        assertEquals(first, second);
        assertTrue(first.indexOf("com.example.alpha") < first.indexOf("org.example.zed"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesProtectedSystemPackages() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("android", new UnifiedHookConfigParser.Target(false, false, false, false, true, false, false));
        UnifiedHookConfigSerializer.serialize(false, true, targets);
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesNullTargetRows() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", null);
        UnifiedHookConfigSerializer.serialize(true, false, targets);
    }

    @Test
    public void privacyOnlyTargetDoesNotEnableAdsButCanEnablePrivacy() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.privacyonly",
                new UnifiedHookConfigParser.Target(false, false, false, false, true, false, false));

        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);

        assertFalse(parsed.isAdsEnabledFor("com.example.privacyonly"));
        assertTrue(parsed.isPrivacyEnabledFor("com.example.privacyonly"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.other"));
    }

    @Test
    public void serializerRoundTripsAdvertisingIdUnification() {
        UnifiedHookConfigParser.Result input = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.ads,ad_id_unify=1\n");
        String encoded = UnifiedHookConfigSerializer.serialize(false, true, input.targets);
        assertTrue(encoded.contains("ad_id_unify=1"));
        assertTrue(UnifiedHookConfigParser.parse(encoded).targets.get("com.example.ads").adIdUnify);
    }

    @Test
    public void serializerRoundTripsExifRedactionIndependently() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.exif", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, true, false));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
        assertTrue(parsed.isExifStripEnabledFor("com.example.exif"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.exif"));
        assertTrue(text.contains("exif_strip=1"));
    }

    @Test
    public void serializerRoundTripsClipboardReadBlockIndependently() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.clip", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
        assertTrue(parsed.isClipboardReadBlockedFor("com.example.clip"));
        assertTrue(text.contains("clipboard_read_block=1"));
        assertFalse(parsed.isClipboardReadBlockedFor("com.example.other"));
    }

    @Test
    public void disabledPrivacyMasterOverridesPerAppPrivacyFlag() {
        String text = UnifiedHookConfigSerializer.serialize(true, false, target(true, true));
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);

        assertTrue(parsed.isAdsEnabledFor("com.example.app"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.app"));
    }

    @Test
    public void legacyAdsConfigNeverEnablesPrivacy() {
        String legacy = "hook_ads_enabled=1\n[list:hook_targets]\n"
                + "com.example.app,splash=1,feed=0,overlay=0,member_diag=0|Example|1\n";
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(legacy);

        assertTrue(parsed.isAdsEnabledFor("com.example.app"));
        assertFalse(parsed.privacyEnabled);
        assertFalse(parsed.isPrivacyEnabledFor("com.example.app"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void parserRejectsDuplicateTargetFeature() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n"
                + "[list:targets]\ncom.example.app,ads_splash=1,ads_splash=0\n");
    }

    @Test
    public void parserAcceptsConfigOver64KiB() {
        StringBuilder large = new StringBuilder("schema_version=1\nads_enabled=1\nprivacy_enabled=0\n");
        while (large.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length <= 65536) {
            large.append("#padding\n");
        }
        large.append("[list:targets]\ncom.example.large,ads_splash=1\n");
        String config = large.toString();
        assertTrue(config.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 65536);

        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(config);
        assertTrue(parsed.isAdsEnabledFor("com.example.large"));
        String serialized = UnifiedHookConfigSerializer.serialize(true, false, parsed.targets);
        assertTrue(UnifiedHookConfigParser.parse(serialized).isAdsEnabledFor("com.example.large"));
    }

    @Test
    public void serializerRoundTripsAllSixSensorFlags() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.sensors", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false, true, true, true, true, true, true, true, false));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Target t = UnifiedHookConfigParser.parse(text).targets.get("com.example.sensors");
        assertTrue(t.sensorAccel && t.sensorGyro && t.sensorLight && t.sensorMagnet && t.sensorPressure && t.sensorProx);
        assertTrue(text.contains("sensor_prox=1"));
        assertTrue(text.contains("sensor_rate_limit=1"));
    }

    @Test
    public void serializerRoundTripsWifiScanMasterAndTarget() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.wifi", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, false, true, targets);
        assertTrue(text.contains("wifi_scan_enabled=1"));
        assertTrue(text.contains("wifi_scan_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).isWifiScanBlockedFor("com.example.wifi"));
    }

    @Test
    public void serializerRoundTripsNotificationListenMasterAndTarget() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.notify", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, false, false, true, targets);
        assertTrue(text.contains("notification_listen_enabled=1"));
        assertTrue(text.contains("notification_listen_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).isNotificationListenBlockedFor("com.example.notify"));
    }

    @Test
    public void serializerRoundTripsNotificationPermissionHideMasterAndTarget() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.notify", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, false, false, false, true, targets);
        assertTrue(text.contains("notification_permission_hide_enabled=1"));
        assertTrue(text.contains("notification_permission_hide=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).isNotificationPermissionHiddenFor("com.example.notify"));
    }

    @Test
    public void serializerRoundTripsExplicitMediaStoreQueryBlock() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.media", new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false,
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        assertTrue(text.contains("media_store_query_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).targets.get("com.example.media").mediaStoreQueryBlock);
    }

    @Test
    public void serializerRoundTripsExplicitMicrophoneAccessDenial() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.audio", new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false,
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        assertTrue(text.contains("mic_access_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).targets.get("com.example.audio").microphoneAccessBlock);
    }

    @Test
    public void serializerRoundTripsExplicitLocationAccessDenial() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.location", new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false,
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        assertTrue(text.contains("location_access_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).targets.get("com.example.location").locationAccessBlock);
    }

    @Test
    public void serializerRoundTripsExplicitCameraAccessDenial() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.camera", new UnifiedHookConfigParser.Target(
                false, false, false, false, true, false, false,
                false, false, false, false, false, false, false,
                false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        assertTrue(text.contains("camera_access_block=1"));
        assertTrue(UnifiedHookConfigParser.parse(text).targets.get("com.example.camera").cameraAccessBlock);
    }

    @Test
    public void serializerRoundTripsMicrophoneSilenceOptIn() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.audio", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false,
                false, false, false, false, false, false, false,
                false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Target parsed = UnifiedHookConfigParser.parse(text).targets.get("com.example.audio");
        assertTrue(parsed.microphoneSilence);
        assertTrue(text.contains("mic_silence=1"));
    }
    @Test
    public void serializerRoundTripsDialogRulesAndFeedbackPerTarget() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.dialogMatchEnabled = true;
        target.dialogNotify = true;
        target.dialogTextTerms.add("更新失败");
        target.dialogTextTerms.add("Please sign in");
        target.dialogIdTerms.add("com.example:id/alert_close");
        target.dialogIdTerms.add("btn_cancel");
        targets.put("com.example.dialog", target);

        String encoded = UnifiedHookConfigSerializer.serialize(false, false, targets);
        assertTrue(encoded.contains("dialog_match=1"));
        assertTrue(encoded.contains("dialog_notify=1"));
        UnifiedHookConfigParser.Target restored =
                UnifiedHookConfigParser.parse(encoded).targets.get("com.example.dialog");
        assertTrue(restored.dialogMatchEnabled);
        assertTrue(restored.dialogNotify);
        assertEquals(target.dialogTextTerms, restored.dialogTextTerms);
        assertEquals(target.dialogIdTerms, restored.dialogIdTerms);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsDialogFeedbackWithoutEnabledMatcher() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.dialogNotify = true;
        targets.put("com.example.dialog", target);
        UnifiedHookConfigSerializer.serialize(false, false, targets);
    }


    @Test
    public void serializerRoundTripsPerAppToastFilterRules() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.toastFilterEnabled = true;
        target.toastTextTerms.add("签到成功");
        target.toastTextTerms.add("Please update");
        targets.put("com.example.toast", target);

        String encoded = UnifiedHookConfigSerializer.serialize(false, false, targets);
        assertTrue(encoded.contains("toast_filter=1"));
        assertTrue(encoded.contains("toast_text_terms_b64="));
        UnifiedHookConfigParser.Target restored =
                UnifiedHookConfigParser.parse(encoded).targets.get("com.example.toast");
        assertTrue(restored.toastFilterEnabled);
        assertEquals(target.toastTextTerms, restored.toastTextTerms);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsToastTermsWhenFilteringIsDisabled() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.toastTextTerms.add("promotion");
        targets.put("com.example.toast", target);
        UnifiedHookConfigSerializer.serialize(false, false, targets);
    }


    @Test
    public void serializerRoundTripsPerAppActivityKeyActions() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.keyFinishTrigger = 5;
        target.keyDialogToggleTrigger = 6;
        target.dialogMatchEnabled = true;
        target.dialogTextTerms.add("更新失败");
        targets.put("com.example.debug", target);

        String encoded = UnifiedHookConfigSerializer.serialize(false, false, targets);
        assertTrue(encoded.contains("key_finish_trigger=5"));
        assertTrue(encoded.contains("key_dialog_toggle_trigger=6"));
        UnifiedHookConfigParser.Target restored =
                UnifiedHookConfigParser.parse(encoded).targets.get("com.example.debug");
        assertEquals(5, restored.keyFinishTrigger);
        assertEquals(6, restored.keyDialogToggleTrigger);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsDialogKeyToggleWithoutDialogRules() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.keyDialogToggleTrigger = 6;
        targets.put("com.example.debug", target);
        UnifiedHookConfigSerializer.serialize(false, false, targets);
    }

    @Test(expected = IllegalArgumentException.class)
    public void serializerRejectsTwoActivityKeyActionsWithOverlappingGestures() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false);
        target.keyFinishTrigger = 0;
        target.keyDialogToggleTrigger = 2;
        target.dialogMatchEnabled = true;
        target.dialogTextTerms.add("blocked");
        targets.put("com.example.debug", target);
        UnifiedHookConfigSerializer.serialize(false, false, targets);
    }


}
