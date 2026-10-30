package de.privacyguard.adhook;

import java.util.Map;
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
                    .append(",dev_hook_enabled=").append(target.developerHooksEnabled ? '1' : '0');
            int ruleIndex = 1;
            for (DeveloperHookRule rule : target.developerRules) {
                if (rule == null || ruleIndex > 16) throw new IllegalArgumentException("invalid developer rule list");
                out.append(",dev_rule_").append(ruleIndex++).append('=')
                        .append(rule.id).append('|').append(rule.descriptor).append('|')
                        .append(rule.action.name()).append('|').append(rule.priority);
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
