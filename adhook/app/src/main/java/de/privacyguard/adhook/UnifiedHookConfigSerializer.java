package de.privacyguard.adhook;

import java.util.Map;
import java.nio.charset.StandardCharsets;
import java.util.TreeMap;

/**
 * Deterministic serializer for the unified FX Hook config schema.
 *
 * This is a format-level building block; the root-side FX module still needs to
 * call it when publishing Remote Files. It deliberately does not read root files
 * or write LSPosed Remote Files itself.
 */
public final class UnifiedHookConfigSerializer {
    private UnifiedHookConfigSerializer() {}

    public static String serialize(boolean adsEnabled, boolean privacyEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, false, false, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled, false, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled, boolean notificationListenEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled, notificationListenEnabled, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled, boolean notificationListenEnabled, boolean notificationPermissionHideEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        return serialize(adsEnabled, privacyEnabled, wifiScanEnabled, notificationListenEnabled, notificationPermissionHideEnabled, false, targets);
    }

    public static String serialize(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled, boolean notificationListenEnabled, boolean notificationPermissionHideEnabled, boolean clipboardIsolationEnabled,
                                   Map<String, UnifiedHookConfigParser.Target> targets) {
        if (targets == null) throw new IllegalArgumentException("targets is null");
        Map<String, UnifiedHookConfigParser.Target> sorted = new TreeMap<>(targets);
        StringBuilder out = new StringBuilder(128);
        out.append("schema_version=1\n")
                .append("ads_enabled=").append(adsEnabled ? '1' : '0').append('\n')
                .append("privacy_enabled=").append(privacyEnabled ? '1' : '0').append('\n')
                .append("wifi_scan_enabled=").append(wifiScanEnabled ? '1' : '0').append('\n')
                .append("notification_listen_enabled=").append(notificationListenEnabled ? '1' : '0').append('\n')
                .append("notification_permission_hide_enabled=").append(notificationPermissionHideEnabled ? '1' : '0').append('\n')
                .append("clipboard_isolate_enabled=").append(clipboardIsolationEnabled ? '1' : '0').append('\n')
                .append("[list:targets]\n");
        for (Map.Entry<String, UnifiedHookConfigParser.Target> entry : sorted.entrySet()) {
            String pkg = entry.getKey();
            UnifiedHookConfigParser.Target target = entry.getValue();
            if (target == null) throw new IllegalArgumentException("null target");
            out.append(pkg)
                    .append(",ads_splash=").append(target.splash ? '1' : '0')
                    .append(",ads_feed=").append(target.feed ? '1' : '0')
                    .append(",ads_overlay=").append(target.overlay ? '1' : '0')
                    .append(",member_diag=").append(target.memberDiag ? '1' : '0')
                    .append(",privacy=").append(target.privacy ? '1' : '0')
                    .append(",exif_strip=").append(target.exifStrip ? '1' : '0')
                    .append(",clipboard_read_block=").append(target.clipboardReadBlock ? '1' : '0')
                    .append(",clipboard_isolate=").append(target.clipboardIsolate ? '1' : '0')
                    .append(",sensor_accel=").append(target.sensorAccel ? '1' : '0')
                    .append(",sensor_gyro=").append(target.sensorGyro ? '1' : '0')
                    .append(",sensor_light=").append(target.sensorLight ? '1' : '0')
                    .append(",sensor_magnet=").append(target.sensorMagnet ? '1' : '0')
                    .append(",sensor_pressure=").append(target.sensorPressure ? '1' : '0')
                    .append(",sensor_prox=").append(target.sensorProx ? '1' : '0')
                    .append(",sensor_rate_limit=").append(target.sensorRateLimit ? '1' : '0')
                    .append(",wifi_scan_block=").append(target.wifiScanBlock ? '1' : '0')
                    .append(",notification_listen_block=").append(target.notificationListenBlock ? '1' : '0')
                    .append(",notification_permission_hide=").append(target.notificationPermissionHide ? '1' : '0')
                    .append(",mic_silence=").append(target.microphoneSilence ? '1' : '0')
                    .append(",camera_access_block=").append(target.cameraAccessBlock ? '1' : '0')
                    .append(",location_access_block=").append(target.locationAccessBlock ? '1' : '0')
                    .append(",mic_access_block=").append(target.microphoneAccessBlock ? '1' : '0')
                    .append(",media_store_query_block=").append(target.mediaStoreQueryBlock ? '1' : '0')
                    .append(",ad_id_unify=").append(target.adIdUnify ? '1' : '0')
                    .append(",app_version_simulate=").append(target.appVersionSimulation ? '1' : '0')
                    .append(",dev_hook_enabled=").append(target.developerHooksEnabled ? '1' : '0');

            if (target.wifiSimulation) {
                if (target.simulatedWifiSsid == null && target.simulatedWifiBssid == null) {
                    throw new IllegalArgumentException("Wi-Fi simulation requires an SSID or BSSID");
                }
                out.append(",wifi_simulate=1");
                if (target.simulatedWifiSsid != null) {
                    out.append(",wifi_ssid=").append(target.simulatedWifiSsid);
                }
                if (target.simulatedWifiBssid != null) {
                    out.append(",wifi_bssid=").append(target.simulatedWifiBssid);
                }
            } else if (target.simulatedWifiSsid != null || target.simulatedWifiBssid != null) {
                throw new IllegalArgumentException("Wi-Fi values require wifi_simulate=1");
            }

            if (target.networkTypeSimulation) {
                if (!"wifi".equals(target.simulatedNetworkType)
                        && !"cellular".equals(target.simulatedNetworkType)) {
                    throw new IllegalArgumentException("network type simulation requires wifi or cellular");
                }
                out.append(",network_type_simulate=1,network_type=")
                        .append(target.simulatedNetworkType);
            } else if (target.simulatedNetworkType != null) {
                throw new IllegalArgumentException("network type requires network_type_simulate=1");
            }

            if (target.locationSimulation) {
                if (Double.isNaN(target.simulatedLatitude) || Double.isInfinite(target.simulatedLatitude)
                        || target.simulatedLatitude < -90d || target.simulatedLatitude > 90d
                        || Double.isNaN(target.simulatedLongitude) || Double.isInfinite(target.simulatedLongitude)
                        || target.simulatedLongitude < -180d || target.simulatedLongitude > 180d
                        || Float.isNaN(target.simulatedAccuracy) || Float.isInfinite(target.simulatedAccuracy)
                        || target.simulatedAccuracy < 0f || target.simulatedAccuracy > 1000f) {
                    throw new IllegalArgumentException("invalid simulated location");
                }
                out.append(",location_simulate=1,location_lat=")
                        .append(Double.toString(target.simulatedLatitude))
                        .append(",location_lon=").append(Double.toString(target.simulatedLongitude))
                        .append(",location_accuracy=").append(Float.toString(target.simulatedAccuracy));
            }
            if (target.locationProviderEnabledSimulation) {
                out.append(",location_provider_enabled_simulate=1");
            }

            if (target.androidIdSimulation) {
                if (target.simulatedAndroidId == null
                        || !target.simulatedAndroidId.matches("(?i)[0-9a-f]{16}")) {
                    throw new IllegalArgumentException("invalid simulated Android ID");
                }
                out.append(",android_id_simulate=1,android_id=")
                        .append(target.simulatedAndroidId.toLowerCase(java.util.Locale.ROOT));
            } else if (target.simulatedAndroidId != null) {
                throw new IllegalArgumentException("Android ID requires android_id_simulate=1");
            }

            if (target.timeZoneSimulation) {
                if (target.simulatedTimeZone == null || target.simulatedTimeZone.isEmpty()) {
                    throw new IllegalArgumentException("time-zone simulation requires a time zone");
                }
                out.append(",time_zone_simulate=1,time_zone=").append(target.simulatedTimeZone);
            } else if (target.simulatedTimeZone != null) {
                throw new IllegalArgumentException("time_zone requires time_zone_simulate=1");
            }

            if (target.developerVipMethod != null) {
                out.append(",dev_test_vip_method=").append(target.developerVipMethod);
            }
            if (target.developerLoginMethod != null) {
                out.append(",dev_test_login_method=").append(target.developerLoginMethod);
            }
            if (target.developerHideUpdateMethod != null) {
                out.append(",dev_test_hide_update_method=").append(target.developerHideUpdateMethod);
            }

            if (target.appVersionSimulation) {
                if (target.simulatedVersionName == null || target.simulatedVersionName.isEmpty()
                        || target.simulatedVersionName.getBytes(StandardCharsets.UTF_8).length > 128
                        || target.simulatedVersionCode < 0L || target.simulatedVersionCode > 2147483647L)
                    throw new IllegalArgumentException("invalid simulated application version");
                String encodedVersionName = java.util.Base64.getUrlEncoder().withoutPadding()
                        .encodeToString(target.simulatedVersionName.getBytes(StandardCharsets.UTF_8));
                out.append(",app_version_name_b64=").append(encodedVersionName)
                        .append(",app_version_code=").append(target.simulatedVersionCode);
            }
            int ruleIndex = 1;
            for (DeveloperHookRule rule : target.developerRules) {
                if (rule == null || ruleIndex > UnifiedHookConfigParser.MAX_DEVELOPER_RULES_PER_TARGET)
                    throw new IllegalArgumentException("invalid developer rule list");
                String ruleValue = rule.toEncodedString();
                String encodedRule = java.util.Base64.getUrlEncoder().withoutPadding()
                        .encodeToString(ruleValue.getBytes(StandardCharsets.UTF_8));
                out.append(",dev_rule_b64_").append(ruleIndex++).append('=').append(encodedRule);
            }
            out.append('\n');
        }

        String serialized = out.toString();
        // Reuse the parser as the single schema validator; invalid/protected package
        // names and malformed state must never be emitted as a seemingly valid file.
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(serialized);
        if (parsed.adsEnabled != adsEnabled || parsed.privacyEnabled != privacyEnabled
                || parsed.wifiScanEnabled != wifiScanEnabled || parsed.notificationListenEnabled != notificationListenEnabled || parsed.notificationPermissionHideEnabled != notificationPermissionHideEnabled || parsed.clipboardIsolationEnabled != clipboardIsolationEnabled || parsed.targets.size() != sorted.size()) {
            throw new IllegalArgumentException("config failed validation");
        }
        return serialized;
    }
}
