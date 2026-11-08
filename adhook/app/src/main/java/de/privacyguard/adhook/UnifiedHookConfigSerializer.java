package de.privacyguard.adhook;
import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicy;

import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.nio.charset.StandardCharsets;

/**
 * Deterministic serializer for the root FX Hook configuration schema.
 *
 * The root APK and the KernelSU module currently use different parser models.
 * This class deliberately serializes only fields accepted by the root parser;
 * module-only simulation, dialog and developer-hook fields stay in the module
 * source set and are not copied into the APK model.
 */
public final class UnifiedHookConfigSerializer {
    private UnifiedHookConfigSerializer() {}

    /** Serialize a parsed root-schema result, including its global lists. */
    public static String serialize(UnifiedHookConfigParser.Result config) {
        if (config == null) throw new IllegalArgumentException("config is null");
        return serializeInternal(config.adsEnabled, config.privacyEnabled,
                config.systemServicesEnabled, config.hiddenSystemServices,
                config.pmQueryEnabled, config.appListEnabled, config.appListMode,
                config.hiddenApps, config.keptApps, config.targets, true);
    }

    /** Serialize only the required master switches and per-target settings. */
    public static String serialize(boolean adsEnabled, boolean privacyEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serializeInternal(adsEnabled, privacyEnabled, false,
                java.util.Collections.<String>emptySet(), false, false, "custom",
                java.util.Collections.<String>emptySet(),
                java.util.Collections.<String>emptySet(), targets, true);
    }

    // Keep the former overloads source-compatible, but reject module-only global
    // switches instead of silently emitting keys rejected by the root parser.
    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled, false, false, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled,
                                   boolean notificationListenEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled,
                notificationListenEnabled, false, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled,
                                   boolean notificationListenEnabled, boolean notificationPermissionHideEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled,
                notificationListenEnabled, notificationPermissionHideEnabled, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled,
                                   boolean notificationListenEnabled, boolean notificationPermissionHideEnabled,
                                   boolean clipboardIsolationEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        if (wifiScanEnabled || notificationListenEnabled
                || notificationPermissionHideEnabled || clipboardIsolationEnabled) {
            throw new IllegalArgumentException(
                    "root FX schema uses per-target privacy flags; module-only global switches are unsupported");
        }
        return serialize(adsEnabled, privacyEnabled, targets);
    }

    private static String serializeInternal(
            boolean adsEnabled,
            boolean privacyEnabled,
            boolean systemServicesEnabled,
            Set<String> hiddenSystemServices,
            boolean pmQueryEnabled,
            boolean appListEnabled,
            String appListMode,
            Set<String> hiddenApps,
            Set<String> keptApps,
            Map<String, UnifiedHookConfigParser.Target> targets,
            boolean verifyRoundTrip) {
        if (targets == null) throw new IllegalArgumentException("targets is null");
        if (hiddenSystemServices == null || hiddenApps == null || keptApps == null) {
            throw new IllegalArgumentException("configuration lists must not be null");
        }
        if (!("empty".equals(appListMode) || "custom".equals(appListMode)
                || "allowlist".equals(appListMode))) {
            throw new IllegalArgumentException("invalid app_list_mode");
        }

        Map<String, UnifiedHookConfigParser.Target> sortedTargets = new TreeMap<>(targets);
        StringBuilder out = new StringBuilder(256);
        out.append("schema_version=1\n")
                .append("ads_enabled=").append(bit(adsEnabled)).append('\n')
                .append("privacy_enabled=").append(bit(privacyEnabled)).append('\n')
                .append("system_services_enabled=").append(bit(systemServicesEnabled)).append('\n')
                .append("pm_query_enabled=").append(bit(pmQueryEnabled)).append('\n')
                .append("app_list_enabled=").append(bit(appListEnabled)).append('\n')
                .append("app_list_mode=").append(appListMode).append('\n');

        appendSortedSection(out, "list:app_list_hide", hiddenApps);
        appendSortedSection(out, "list:app_list_keep", keptApps);
        appendSortedSection(out, "list:system_services", hiddenSystemServices);
        out.append("[list:targets]\n");

        for (Map.Entry<String, UnifiedHookConfigParser.Target> entry : sortedTargets.entrySet()) {
            String packageName = entry.getKey();
            UnifiedHookConfigParser.Target target = entry.getValue();
            if (packageName == null || target == null) {
                throw new IllegalArgumentException("target package/name must not be null");
            }
            out.append(packageName)
                    .append(",ads_splash=").append(bit(target.splash))
                    .append(",ads_feed=").append(bit(target.feed))
                    .append(",ads_overlay=").append(bit(target.overlay))
                    .append(",member_diag=").append(bit(target.memberDiag))
                    .append(",privacy=").append(bit(target.privacy))
                    .append(",media_hidden=").append(bit(target.mediaHidden))
                    .append(",usage_hidden=").append(bit(target.usageHidden))
                    .append(",device_profile=").append(bit(target.deviceProfile))
                    // Region and VPN-detection hiding now have real hook implementations,
                    // so a configured value must survive a publish/read round-trip.
                    .append(",region_hidden=").append(bit(target.regionHidden))
                    .append(",vpn_hidden=").append(bit(target.vpnDetectionHidden))
                    .append(",exif_strip=").append(bit(target.exifStrip))
                    .append(",clipboard_read_block=").append(bit(target.clipboardReadBlock))
                    .append(",clipboard_isolate=").append(bit(target.clipboardIsolate))
                    .append(",sensor_accel=").append(bit(target.sensorAccel))
                    .append(",sensor_gyro=").append(bit(target.sensorGyro))
                    .append(",sensor_light=").append(bit(target.sensorLight))
                    .append(",sensor_magnet=").append(bit(target.sensorMagnet))
                    .append(",sensor_pressure=").append(bit(target.sensorPressure))
                    .append(",sensor_prox=").append(bit(target.sensorProx))
                    .append(",sensor_environment=").append(bit(target.sensorEnvironment))
                    .append(",sensor_fusion=").append(bit(target.sensorFusion))
                    .append(",sensor_gesture=").append(bit(target.sensorGesture))
                    .append(",sensor_biometric=").append(bit(target.sensorBiometric))
                    .append(",sensor_rate_limit=").append(bit(target.sensorRateLimit))
                    .append(",wifi_scan_block=").append(bit(target.wifiScanBlock))
                    .append(",notification_listen_block=").append(bit(target.notificationListenBlock))
                    .append(",notification_permission_hide=").append(bit(target.notificationPermissionHide))
                    .append(",mic_silence=").append(bit(target.microphoneSilence))
                    .append(",camera_access_block=").append(bit(target.cameraAccessBlock))
                    .append(",location_access_block=").append(bit(target.locationAccessBlock))
                    .append(",mic_access_block=").append(bit(target.microphoneAccessBlock))
                    .append(",media_store_query_block=").append(bit(target.mediaStoreQueryBlock))
                    .append(",ad_id_unify=").append(bit(target.adIdUnify));
            if (target.locationSimulation) {
                out.append(",location_simulate=1")
                        .append(",location_lat=").append(target.simulatedLatitude)
                        .append(",location_lon=").append(target.simulatedLongitude);
                if (Math.abs(target.simulatedAccuracy - 5f) > 0.0001f)
                    out.append(",location_accuracy=").append(target.simulatedAccuracy);
            }
            if (target.locationProviderEnabledSimulation)
                out.append(",location_provider_enabled_simulate=1");
            if (target.regionDiag) out.append(",region_diag=1");
            if (target.usageStatsOff) out.append(",usagestats_off=1");
            if (target.a11yHide) out.append(",a11y_hide=1");
            if (target.audioFpBlock) out.append(",audio_fp_block=1");
            if (target.micBlock) out.append(",mic_block=1");
            if (target.cameraIdHide) out.append(",camera_id_hide=1");
            if (target.blockMediaStore) out.append(",block_mediastore=1");
            if (target.blockImeLogging) out.append(",block_ime_logging=1");
            if (target.micHwHide) out.append(",mic_hw_hide=1");
            if (target.disablePassiveLocation) out.append(",disable_passive_loc=1");
            if (target.hideFingerprintHw) out.append(",hide_fingerprint_hw=1");
            if (target.hideFaceHw) out.append(",hide_face_hw=1");
            if (target.wifiScanHide) out.append(",wifi_scan_hide=1");
            if (target.cellInfoHide) out.append(",cell_info_hide=1");
            // Premium unlocking, update suppression and a version override are
            // per-target features with real hook implementations, so they must
            // round-trip like every other switch.
            if (target.vipUnlock) out.append(",vip_unlock=1");
            // Developer rules must round-trip: the parser reads dev_rule_N and
            // dev_rule_b64_N, so a save that omits them silently drops every custom rule
            // the user configured.
            for (int slot = 0; slot < target.developerRules.size(); slot++) {
                DeveloperHookRule rule = target.developerRules.get(slot);
                if (rule == null) continue;
                String body = rule.toEncodedString();
                int index = slot + 1;
                // The row is comma-separated, and a typed JVM signature contains commas,
                // so any body with a comma must go through the encoded slot.
                if (body.indexOf(',') < 0) {
                    out.append(",dev_rule_").append(index).append('=').append(body);
                } else {
                    out.append(",dev_rule_b64_").append(index).append('=')
                            .append(java.util.Base64.getUrlEncoder().withoutPadding()
                                    .encodeToString(body.getBytes(
                                            java.nio.charset.StandardCharsets.UTF_8)));
                }
            }

            if (target.antiFraudBlock) out.append(",anti_fraud_block=1");
            if (target.carrierCollectionBlock) out.append(",carrier_collection_block=1");
            if (target.policeReconBlock) out.append(",police_recon_block=1");
            if (target.blockAppUpdate) out.append(",block_app_update=1");
            if (target.fakeAppVersion && target.simulatedAppVersion != null) {
                out.append(",fake_app_version=1")
                        .append(",app_version_value=").append(target.simulatedAppVersion);
            } else if (target.fakeAppVersion) {
                throw new IllegalArgumentException("fake_app_version requires app_version_value");
            }
            if (target.vipEntitlementSimulation) {
                if (target.simulatedEntitlementState == null)
                    throw new IllegalArgumentException(
                            "vip_entitlement_simulate requires vip_entitlement_state");
                out.append(",vip_entitlement_simulate=1")
                        .append(",vip_entitlement_state=").append(target.simulatedEntitlementState);
            }

            if (target.dialogMatchEnabled) {
                if (target.dialogTextTerms.isEmpty() && target.dialogIdTerms.isEmpty())
                    throw new IllegalArgumentException("dialog monitoring requires explicit rules");
                out.append(",dialog_match=1")
                        .append(",dialog_notify=").append(bit(target.dialogNotify));
                if (!target.dialogTextTerms.isEmpty()) {
                    String encoded = java.util.Base64.getUrlEncoder().withoutPadding()
                            .encodeToString(String.join("\n", target.dialogTextTerms)
                                    .getBytes(StandardCharsets.UTF_8));
                    out.append(",dialog_text_terms_b64=").append(encoded);
                }
                if (!target.dialogIdTerms.isEmpty()) {
                    String encoded = java.util.Base64.getUrlEncoder().withoutPadding()
                            .encodeToString(String.join("\n", target.dialogIdTerms)
                                    .getBytes(StandardCharsets.UTF_8));
                    out.append(",dialog_id_terms_b64=").append(encoded);
                }
            } else if (!target.dialogTextTerms.isEmpty() || !target.dialogIdTerms.isEmpty()
                    || target.dialogNotify) {
                throw new IllegalArgumentException("dialog rules/feedback require dialogMatchEnabled");
            }

            if (target.toastFilterEnabled) {
                if (target.toastTextTerms.isEmpty())
                    throw new IllegalArgumentException("toast filtering requires explicit text rules");
                String encodedToastTerms = java.util.Base64.getUrlEncoder().withoutPadding()
                        .encodeToString(String.join("\n", target.toastTextTerms)
                                .getBytes(StandardCharsets.UTF_8));
                out.append(",toast_filter=1,toast_text_terms_b64=").append(encodedToastTerms);
            } else if (!target.toastTextTerms.isEmpty()) {
                throw new IllegalArgumentException("toast text rules require toastFilterEnabled");
            }

            if (target.keyFinishTrigger < -1 || target.keyFinishTrigger > 6
                    || target.keyDialogToggleTrigger < -1 || target.keyDialogToggleTrigger > 6) {
                throw new IllegalArgumentException("invalid Dia key trigger");
            }
            if (FxDiaKeyGesturePolicy.hasOverlappingTriggers(
                    target.keyFinishTrigger, target.keyDialogToggleTrigger)) {
                throw new IllegalArgumentException("Dia key actions have overlapping gesture triggers");
            }
            if (target.keyFinishTrigger >= 0) {
                out.append(",key_finish_trigger=").append(target.keyFinishTrigger);
            }
            if (target.keyDialogToggleTrigger >= 0) {
                if (!target.dialogMatchEnabled || (target.dialogTextTerms.isEmpty()
                        && target.dialogIdTerms.isEmpty())) {
                    throw new IllegalArgumentException("Dialog key toggle requires enabled Dialog rules");
                }
                out.append(",key_dialog_toggle_trigger=").append(target.keyDialogToggleTrigger);
            }

            // Append the optional Dia fields after the stable legacy Hook/privacy fields.
            // The parser treats these as ordinary per-target settings and validates the full row.
            appendCustomRules(out, target.customRules);
            out.append('\n');
        }

        String serialized = out.toString();
        if (verifyRoundTrip) {
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(serialized);
            String canonical = serializeInternal(parsed.adsEnabled, parsed.privacyEnabled,
                    parsed.systemServicesEnabled, parsed.hiddenSystemServices,
                    parsed.pmQueryEnabled, parsed.appListEnabled, parsed.appListMode,
                    parsed.hiddenApps, parsed.keptApps, parsed.targets, false);
            if (!serialized.equals(canonical)) {
                throw new IllegalArgumentException("config lost fields during root-schema round-trip");
            }
        }
        return serialized;
    }

    private static void appendSortedSection(StringBuilder out, String section, Set<String> values) {
        for (String value : values) {
            if (value == null) throw new IllegalArgumentException("null value in " + section);
        }
        out.append('[').append(section).append("]\n");
        for (String value : new TreeSet<>(values)) out.append(value).append('\n');
    }

    private static void appendCustomRules(StringBuilder out, Map<String, Set<String>> rules) {
        if (rules == null || rules.isEmpty()) return;
        TreeMap<String, Set<String>> sorted = new TreeMap<>(rules);
        StringBuilder encoded = new StringBuilder();
        for (Map.Entry<String, Set<String>> entry : sorted.entrySet()) {
            String category = entry.getKey();
            Set<String> tokens = entry.getValue();
            if (!("splash".equals(category) || "feed".equals(category) || "overlay".equals(category))
                    || tokens == null) {
                throw new IllegalArgumentException("invalid custom ad rule category");
            }
            for (String token : tokens) {
                if (token == null || !token.matches("[a-z0-9_.-]{3,100}")) {
                    throw new IllegalArgumentException("invalid custom ad rule token");
                }
            }
            for (String token : new TreeSet<>(tokens)) {
                if (encoded.length() > 0) encoded.append(';');
                encoded.append(category).append(':').append(token);
            }
        }
        if (encoded.length() > 0) out.append(",rules=").append(encoded);
    }

    private static char bit(boolean value) {
        return value ? '1' : '0';
    }
}
