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
        if (targets == null) throw new IllegalArgumentException("targets is null");
        Map<String, UnifiedHookConfigParser.Target> sorted = new TreeMap<>(targets);
        StringBuilder out = new StringBuilder(128);
        out.append("schema_version=1\n")
                .append("ads_enabled=").append(adsEnabled ? '1' : '0').append('\n')
                .append("privacy_enabled=").append(privacyEnabled ? '1' : '0').append('\n')
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
                    .append(",sensor_accel=").append(target.sensorAccel ? '1' : '0')
                    .append(",sensor_gyro=").append(target.sensorGyro ? '1' : '0')
                    .append(",sensor_light=").append(target.sensorLight ? '1' : '0')
                    .append(",sensor_magnet=").append(target.sensorMagnet ? '1' : '0')
                    .append(",sensor_pressure=").append(target.sensorPressure ? '1' : '0')
                    .append(",sensor_prox=").append(target.sensorProx ? '1' : '0')
                    .append(",sensor_rate_limit=").append(target.sensorRateLimit ? '1' : '0')
                    .append(",wifi_scan_hide=").append(target.wifiScanHide ? '1' : '0')
                    .append(",cell_info_hide=").append(target.cellInfoHide ? '1' : '0')
                    .append('\n');
        }

        String serialized = out.toString();
        // Reuse the parser as the single schema validator; invalid/protected package
        // names and malformed state must never be emitted as a seemingly valid file.
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(serialized);
        if (parsed.adsEnabled != adsEnabled || parsed.privacyEnabled != privacyEnabled
                || parsed.targets.size() != sorted.size()) {
            throw new IllegalArgumentException("config failed validation");
        }
        return serialized;
    }
}
