package de.privacyguard.adhook;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import java.util.Arrays;
import java.nio.charset.StandardCharsets;

/**
 * Versioned, transactional configuration model for the single FX Hook APK.
 * AdVisibilityHook uses this parser directly for both the versioned unified schema
 * and backward-compatible legacy ad-only payloads. Legacy payloads never enable privacy.
 */
public final class UnifiedHookConfigParser {
    private static final Set<String> NEVER = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager")));

    private UnifiedHookConfigParser() {}

    public static final class Target {
        public final boolean splash;
        public final boolean feed;
        public final boolean overlay;
        public final boolean memberDiag;
        public final boolean privacy;
        public final boolean exifStrip;
        public final boolean clipboardReadBlock;
        public final boolean sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx;
        public final boolean sensorRateLimit;
        public final boolean wifiScanHide;
        public final boolean cellInfoHide;
        public final boolean cameraIdHide;

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock,
                    false, false, false, false, false, false, false, false, false, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro,
               boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock,
                    sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx,
                    sensorRateLimit, false, false, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro,
               boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx,
               boolean sensorRateLimit, boolean wifiScanHide, boolean cellInfoHide) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock,
                    sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx,
                    sensorRateLimit, wifiScanHide, cellInfoHide, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro,
               boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx,
               boolean sensorRateLimit, boolean wifiScanHide, boolean cellInfoHide, boolean cameraIdHide) {
            this.splash = splash;
            this.feed = feed;
            this.overlay = overlay;
            this.memberDiag = memberDiag;
            this.privacy = privacy;
            this.exifStrip = exifStrip;
            this.clipboardReadBlock = clipboardReadBlock;
            this.sensorAccel = sensorAccel; this.sensorGyro = sensorGyro;
            this.sensorLight = sensorLight; this.sensorMagnet = sensorMagnet;
            this.sensorPressure = sensorPressure; this.sensorProx = sensorProx;
            this.sensorRateLimit = sensorRateLimit;
            this.wifiScanHide = wifiScanHide;
            this.cellInfoHide = cellInfoHide;
            this.cameraIdHide = cameraIdHide;
        }

        public boolean enabled() {
            return splash || feed || overlay || memberDiag;
        }
    }

    public static final class Result {
        public final boolean adsEnabled;
        public final boolean privacyEnabled;
        public final Map<String, Target> targets;

        private Result(boolean adsEnabled, boolean privacyEnabled, Map<String, Target> targets) {
            this.adsEnabled = adsEnabled;
            this.privacyEnabled = privacyEnabled;
            this.targets = Collections.unmodifiableMap(new LinkedHashMap<>(targets));
        }

        public boolean isAdsEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return adsEnabled && target != null && target.enabled();
        }

        public boolean isPrivacyEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.privacy;
        }

        public boolean isExifStripEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.exifStrip;
        }

        public boolean isClipboardReadBlockedFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.clipboardReadBlock;
        }

        public boolean isSensorHiddenFor(String packageName, int sensorType) {
            Target target = targets.get(packageName);
            return privacyEnabled && SensorPrivacyPolicy.isEnabled(target, sensorType);
        }
    }

    public static Result parse(String text) {
        if (text == null) throw new IllegalArgumentException("null config");
        // Enforce the same byte and line limits before dispatching to either parser.
        // Legacy configs must not bypass the limits enforced for schema v1.
        if (text.getBytes(StandardCharsets.UTF_8).length > 65536) throw new IllegalArgumentException("config exceeds 64 KiB");
        if (text.split("\\R", -1).length > 1000) throw new IllegalArgumentException("config exceeds 1000 lines");
        if (hasLegacyMasterKey(text)) return parseLegacyAdsConfig(text);
        String[] lines = text.split("\\R", -1);
        if (lines.length > 1000) throw new IllegalArgumentException("config exceeds 1000 lines");

        boolean schemaSeen = false, adsSeen = false, privacySeen = false, sectionSeen = false;
        boolean ads = false, privacy = false;
        String section = "";
        Map<String, Target> targets = new LinkedHashMap<>();

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            if (line.startsWith("[") || line.endsWith("]")) {
                if (!line.startsWith("[") || !line.endsWith("]") || line.length() < 3)
                    throw new IllegalArgumentException("malformed section");
                String next = line.substring(1, line.length() - 1).trim();
                if (!"list:targets".equals(next) || sectionSeen)
                    throw new IllegalArgumentException("unsupported or duplicate section");
                sectionSeen = true;
                section = next;
                continue;
            }
            if (section.isEmpty()) {
                int eq = line.indexOf('=');
                if (eq < 1) throw new IllegalArgumentException("malformed top-level key");
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                if ("schema_version".equals(key)) {
                    if (schemaSeen || !"1".equals(value)) throw new IllegalArgumentException("unsupported schema");
                    schemaSeen = true;
                } else if ("ads_enabled".equals(key)) {
                    if (adsSeen || !bit(value)) throw new IllegalArgumentException("invalid ads_enabled");
                    adsSeen = true; ads = "1".equals(value);
                } else if ("privacy_enabled".equals(key)) {
                    if (privacySeen || !bit(value)) throw new IllegalArgumentException("invalid privacy_enabled");
                    privacySeen = true; privacy = "1".equals(value);
                } else {
                    throw new IllegalArgumentException("unknown top-level key");
                }
                continue;
            }

            String[] parts = line.split(",", -1);
            if (parts.length < 2) throw new IllegalArgumentException("target requires at least one feature");
            String pkg = parts[0].trim();
            if (!validPackage(pkg) || NEVER.contains(pkg) || targets.containsKey(pkg))
                throw new IllegalArgumentException("invalid, protected or duplicate package");
            boolean splash = false, feed = false, overlay = false, member = false, targetPrivacy = false, exifStrip = false, clipboardReadBlock = false;
            boolean sensorAccel=false, sensorGyro=false, sensorLight=false, sensorMagnet=false, sensorPressure=false, sensorProx=false, sensorRateLimit=false;
            boolean wifiScanHide=false, cellInfoHide=false, cameraIdHide=false;
            Set<String> seen = new HashSet<>();
            for (int i = 1; i < parts.length; i++) {
                int eq = parts[i].indexOf('=');
                if (eq < 1) throw new IllegalArgumentException("malformed feature");
                String key = parts[i].substring(0, eq).trim();
                String value = parts[i].substring(eq + 1).trim();
                if (!seen.add(key) || !bit(value)) throw new IllegalArgumentException("duplicate or invalid feature");
                boolean on = "1".equals(value);
                switch (key) {
                    case "ads_splash": splash = on; break;
                    case "ads_feed": feed = on; break;
                    case "ads_overlay": overlay = on; break;
                    case "member_diag": member = on; break;
                    case "privacy": targetPrivacy = on; break;
                    case "exif_strip": exifStrip = on; break;
                    case "clipboard_read_block": clipboardReadBlock = on; break;
                    case "sensor_accel": sensorAccel = on; break;
                    case "sensor_gyro": sensorGyro = on; break;
                    case "sensor_light": sensorLight = on; break;
                    case "sensor_magnet": sensorMagnet = on; break;
                    case "sensor_pressure": sensorPressure = on; break;
                    case "sensor_prox": sensorProx = on; break;
                    case "sensor_rate_limit": sensorRateLimit = on; break;
                    case "wifi_scan_hide": wifiScanHide = on; break;
                    case "cell_info_hide": cellInfoHide = on; break;
                    case "camera_id_hide": cameraIdHide = on; break;
                    default: throw new IllegalArgumentException("unknown target feature");
                }
            }
            targets.put(pkg, new Target(splash, feed, overlay, member, targetPrivacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanHide, cellInfoHide, cameraIdHide));
        }

        if (!schemaSeen || !adsSeen || !privacySeen || !sectionSeen)
            throw new IllegalArgumentException("missing required schema fields");
        return new Result(ads, privacy, targets);
    }


    /** Only an actual top-level legacy key selects the legacy parser; comments must not. */
    private static boolean hasLegacyMasterKey(String text) {
        if (text == null) return false;
        for (String raw : text.split("\\R", -1)) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            if (line.startsWith("[")) return false;
            int eq = line.indexOf('=');
            return eq > 0 && "hook_ads_enabled".equals(line.substring(0, eq).trim());
        }
        return false;
    }

    /** Backward compatibility for existing FX generators; privacy remains disabled. */
    private static Result parseLegacyAdsConfig(String text) {
        if (text.getBytes(StandardCharsets.UTF_8).length > 65536) throw new IllegalArgumentException("config exceeds 64 KiB");
        String[] lines = text.split("\\R", -1);
        if (lines.length > 1000) throw new IllegalArgumentException("config exceeds 1000 lines");
        boolean masterSeen = false, ads = false, sectionSeen = false;
        String section = "";
        Map<String, Target> targets = new LinkedHashMap<>();
        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            if (line.startsWith("[") || line.endsWith("]")) {
                if (!"[list:hook_targets]".equals(line) || sectionSeen)
                    throw new IllegalArgumentException("unsupported or duplicate legacy section");
                sectionSeen = true; section = "targets"; continue;
            }
            if (section.isEmpty()) {
                int eq = line.indexOf('=');
                if (eq < 1 || !"hook_ads_enabled".equals(line.substring(0, eq).trim()) || masterSeen)
                    throw new IllegalArgumentException("invalid legacy top-level option");
                String value = line.substring(eq + 1).trim();
                if (!bit(value)) throw new IllegalArgumentException("invalid legacy master switch");
                masterSeen = true; ads = "1".equals(value); continue;
            }
            int metadata = line.indexOf('|');
            String config = (metadata >= 0 ? line.substring(0, metadata) : line).trim();
            String[] parts = config.split(",", -1);
            if (parts.length < 2) throw new IllegalArgumentException("malformed legacy target");
            String pkg = parts[0].trim();
            if (!validPackage(pkg) || NEVER.contains(pkg) || targets.containsKey(pkg))
                throw new IllegalArgumentException("invalid or duplicate legacy package");
            boolean splash = false, feed = false, overlay = false, member = false;
            Set<String> seen = new HashSet<>();
            for (int i = 1; i < parts.length; i++) {
                int eq = parts[i].indexOf('=');
                if (eq < 1) throw new IllegalArgumentException("malformed legacy feature");
                String key = parts[i].substring(0, eq).trim(), value = parts[i].substring(eq + 1).trim();
                if (!seen.add(key) || !bit(value)) throw new IllegalArgumentException("duplicate or invalid legacy feature");
                boolean on = "1".equals(value);
                switch (key) {
                    case "splash": splash = on; break;
                    case "feed": feed = on; break;
                    case "overlay": overlay = on; break;
                    case "member_diag": member = on; break;
                    default: throw new IllegalArgumentException("unknown legacy feature");
                }
            }
            targets.put(pkg, new Target(splash, feed, overlay, member, false, false, false));
        }
        if (!masterSeen || !sectionSeen) throw new IllegalArgumentException("missing legacy fields");
        return new Result(ads, false, targets);
    }

    private static boolean bit(String value) {
        return "0".equals(value) || "1".equals(value);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }
}
