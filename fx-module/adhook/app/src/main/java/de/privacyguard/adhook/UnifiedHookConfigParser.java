package de.privacyguard.adhook;

import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicy;
import de.privacyguard.adhook.imported.dia.FxDiaDialogMatchPolicy;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;
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
        public final boolean clipboardIsolate;
        public final boolean sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx;
        /** Additional opt-in Android sensor families assigned by the config parser. */
        public boolean sensorEnvironment, sensorFusion, sensorGesture, sensorBiometric;
        public final boolean sensorRateLimit;
        public final boolean wifiScanBlock;
        public final boolean notificationListenBlock;
        public final boolean notificationPermissionHide;
        public final boolean microphoneSilence;
        public final boolean cameraAccessBlock;
        public final boolean locationAccessBlock;
        public final boolean microphoneAccessBlock;
        public final boolean mediaStoreQueryBlock;
        public final boolean adIdUnify;
        public boolean wifiSimulation;
        public String simulatedWifiSsid;
        public String simulatedWifiBssid;
        public boolean networkTypeSimulation;
        public String simulatedNetworkType;
        public boolean locationSimulation;
        public boolean locationProviderEnabledSimulation;
        public double simulatedLatitude;
        public double simulatedLongitude;
        public float simulatedAccuracy = 5f;
        public boolean dialogMatchEnabled;
        public boolean dialogNotify;
        public boolean toastFilterEnabled;
        public final List<String> toastTextTerms = new ArrayList<>();
        public final List<String> dialogTextTerms = new ArrayList<>();
        public final List<String> dialogIdTerms = new ArrayList<>();
        public int keyFinishTrigger = -1;
        public int keyDialogToggleTrigger = -1;
        public boolean androidIdSimulation;
        public String simulatedAndroidId;
        public boolean timeZoneSimulation;
        public String simulatedTimeZone;
        public boolean appVersionSimulation;
        public String simulatedVersionName;
        public long simulatedVersionCode;
        public String developerVipMethod;
        public String developerLoginMethod;
        public String developerHideUpdateMethod;
        public boolean developerHooksEnabled;
        public final List<DeveloperHookRule> developerRules = new ArrayList<>();

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock,
                    false, false, false, false, false, false, false, false);
        }

        // Source-compatible overload for existing sensor policy tests and callers.
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro,
               boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx,
               boolean sensorRateLimit) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock,
                    sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx,
                    sensorRateLimit, false, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro,
               boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, microphoneSilence, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence, boolean cameraAccessBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, microphoneSilence, cameraAccessBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence, boolean cameraAccessBlock, boolean locationAccessBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, microphoneSilence, cameraAccessBlock, locationAccessBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence, boolean cameraAccessBlock, boolean locationAccessBlock, boolean microphoneAccessBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, microphoneSilence, cameraAccessBlock, locationAccessBlock, microphoneAccessBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence, boolean cameraAccessBlock, boolean locationAccessBlock, boolean microphoneAccessBlock, boolean mediaStoreQueryBlock) {
            this(splash, feed, overlay, memberDiag, privacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, clipboardIsolate, microphoneSilence, cameraAccessBlock, locationAccessBlock, microphoneAccessBlock, mediaStoreQueryBlock, false);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock, boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide, boolean clipboardIsolate, boolean microphoneSilence, boolean cameraAccessBlock, boolean locationAccessBlock, boolean microphoneAccessBlock, boolean mediaStoreQueryBlock, boolean adIdUnify) {
            this.splash = splash;
            this.feed = feed;
            this.overlay = overlay;
            this.memberDiag = memberDiag;
            this.privacy = privacy;
            this.exifStrip = exifStrip;
            this.clipboardReadBlock = clipboardReadBlock;
            this.clipboardIsolate = clipboardIsolate;
            this.sensorAccel = sensorAccel; this.sensorGyro = sensorGyro;
            this.sensorLight = sensorLight; this.sensorMagnet = sensorMagnet;
            this.sensorPressure = sensorPressure; this.sensorProx = sensorProx;
            this.sensorRateLimit = sensorRateLimit;
            this.wifiScanBlock = wifiScanBlock;
            this.notificationListenBlock = notificationListenBlock;
            this.notificationPermissionHide = notificationPermissionHide;
            this.microphoneSilence = microphoneSilence;
            this.cameraAccessBlock = cameraAccessBlock;
            this.locationAccessBlock = locationAccessBlock;
            this.microphoneAccessBlock = microphoneAccessBlock;
            this.mediaStoreQueryBlock = mediaStoreQueryBlock;
            this.adIdUnify = adIdUnify;
        }

        /** Ad-filtering scope only; member diagnostics has its own independent switch. */
        public boolean enabled() {
            return splash || feed || overlay;
        }
    }

    public static final class Result {
        public final boolean adsEnabled;
        public final boolean privacyEnabled;
        public final boolean wifiScanEnabled;
        public final boolean notificationListenEnabled;
        public final boolean notificationPermissionHideEnabled;
        public final boolean clipboardIsolationEnabled;
        public final Map<String, Target> targets;

        private Result(boolean adsEnabled, boolean privacyEnabled, boolean wifiScanEnabled, boolean notificationListenEnabled, boolean notificationPermissionHideEnabled, boolean clipboardIsolationEnabled, Map<String, Target> targets) {
            this.adsEnabled = adsEnabled;
            this.privacyEnabled = privacyEnabled;
            this.wifiScanEnabled = wifiScanEnabled;
            this.notificationListenEnabled = notificationListenEnabled;
            this.notificationPermissionHideEnabled = notificationPermissionHideEnabled;
            this.clipboardIsolationEnabled = clipboardIsolationEnabled;
            this.targets = Collections.unmodifiableMap(new LinkedHashMap<>(targets));
        }

        public boolean isAdsEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return adsEnabled && target != null && target.enabled();
        }

        /** Member diagnostics are independent from the global ad-filtering switch. */
        public boolean isMemberDiagnosticsEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return target != null && target.memberDiag;
        }

        public boolean isPrivacyEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.privacy;
        }

        public boolean isExifStripEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.exifStrip;
        }

        public boolean isClipboardIsolatedFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && clipboardIsolationEnabled && target != null && target.clipboardIsolate;
        }

        public boolean isClipboardReadBlockedFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.clipboardReadBlock;
        }

        public boolean isSensorHiddenFor(String packageName, int sensorType) {
            Target target = targets.get(packageName);
            return privacyEnabled && SensorPrivacyPolicy.isEnabled(target, sensorType);
        }

        public boolean isWifiScanBlockedFor(String packageName) {
            Target target = targets.get(packageName);
            return wifiScanEnabled && target != null && target.wifiScanBlock;
        }

        public boolean isNotificationListenBlockedFor(String packageName) {
            Target target = targets.get(packageName);
            return notificationListenEnabled && target != null && target.notificationListenBlock;
        }

        public boolean isNotificationPermissionHiddenFor(String packageName) {
            Target target = targets.get(packageName);
            return notificationPermissionHideEnabled && target != null && target.notificationPermissionHide;
        }
    }

    public static Result parse(String text) {
        if (text == null) throw new IllegalArgumentException("null config");
        if (hasLegacyMasterKey(text)) return parseLegacyAdsConfig(text);
        String[] lines = text.split("\\R", -1);

        boolean schemaSeen = false, adsSeen = false, privacySeen = false, wifiScanSeen = false, notificationListenSeen = false, notificationPermissionHideSeen = false, clipboardIsolationSeen = false, sectionSeen = false;
        boolean ads = false, privacy = false, wifiScan = false, notificationListen = false, notificationPermissionHide = false, clipboardIsolation = false;
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
                } else if ("wifi_scan_enabled".equals(key)) {
                    if (wifiScanSeen || !bit(value)) throw new IllegalArgumentException("invalid wifi_scan_enabled");
                    wifiScanSeen = true; wifiScan = "1".equals(value);
                } else if ("notification_listen_enabled".equals(key)) {
                    if (notificationListenSeen || !bit(value)) throw new IllegalArgumentException("invalid notification_listen_enabled");
                    notificationListenSeen = true; notificationListen = "1".equals(value);
                } else if ("clipboard_isolate_enabled".equals(key)) {
                    if (clipboardIsolationSeen || !bit(value)) throw new IllegalArgumentException("invalid clipboard_isolate_enabled");
                    clipboardIsolationSeen = true; clipboardIsolation = "1".equals(value);
                } else if ("notification_permission_hide_enabled".equals(key)) {
                    if (notificationPermissionHideSeen || !bit(value)) throw new IllegalArgumentException("invalid notification_permission_hide_enabled");
                    notificationPermissionHideSeen = true; notificationPermissionHide = "1".equals(value);
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
            boolean splash = false, feed = false, overlay = false, member = false, targetPrivacy = false, exifStrip = false, clipboardReadBlock = false, clipboardIsolate = false;
            boolean sensorAccel=false, sensorGyro=false, sensorLight=false, sensorMagnet=false, sensorPressure=false, sensorProx=false, sensorRateLimit=false, sensorEnvironment=false, sensorFusion=false, sensorGesture=false, sensorBiometric=false, wifiScanBlock=false, notificationListenBlock=false, notificationPermissionHideTarget=false, microphoneSilence=false, cameraAccessBlock=false, locationAccessBlock=false, microphoneAccessBlock=false, mediaStoreQueryBlock=false, adIdUnify=false, locationProviderEnabledSimulation=false;
            boolean wifiSimulation=false;
            String simulatedWifiSsid=null, simulatedWifiBssid=null;
            boolean networkTypeSimulation=false;
            String simulatedNetworkType=null;
            boolean locationSimulation=false;
            boolean dialogMatchEnabled=false, dialogNotify=false, toastFilterEnabled=false;
            int keyFinishTrigger=-1, keyDialogToggleTrigger=-1;
            String dialogTextTermsRaw=null, dialogIdTermsRaw=null, toastTextTermsRaw=null;
            Double simulatedLatitude=null, simulatedLongitude=null;
            float simulatedAccuracy=5f;
            boolean simulatedAccuracySpecified=false;
            boolean androidIdSimulation=false;
            String simulatedAndroidId=null;
            boolean timeZoneSimulation=false;
            String simulatedTimeZone=null;
            boolean appVersionSimulation=false;
            String simulatedVersionName=null;
            Long simulatedVersionCode=null;
            String developerVipMethod=null, developerLoginMethod=null, developerHideUpdateMethod=null;
            boolean developerHooksEnabled = false;
            List<DeveloperHookRule> developerRules = new ArrayList<>();
            Set<String> developerRuleIds = new HashSet<>();
            Set<Integer> developerRuleSlots = new HashSet<>();
            Set<String> seen = new HashSet<>();
            for (int i = 1; i < parts.length; i++) {
                int eq = parts[i].indexOf('=');
                if (eq < 1) throw new IllegalArgumentException("malformed feature");
                String key = parts[i].substring(0, eq).trim();
                String value = parts[i].substring(eq + 1).trim();
                if (!seen.add(key)) throw new IllegalArgumentException("duplicate feature");
                if ("wifi_ssid".equals(key)) {
                    if (!validWifiSsid(value)) throw new IllegalArgumentException("invalid simulated Wi-Fi SSID");
                    simulatedWifiSsid=value;
                    continue;
                }
                if ("wifi_bssid".equals(key)) {
                    if (!value.matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}"))
                        throw new IllegalArgumentException("invalid simulated Wi-Fi BSSID");
                    simulatedWifiBssid=value.toLowerCase(java.util.Locale.ROOT);
                    continue;
                }
                if ("network_type".equals(key)) {
                    if (!"wifi".equals(value) && !"cellular".equals(value))
                        throw new IllegalArgumentException("network_type must be wifi or cellular");
                    simulatedNetworkType=value;
                    continue;
                }
                if ("dialog_match".equals(key)) {
                    dialogMatchEnabled = "1".equals(value);
                    if (!bit(value)) throw new IllegalArgumentException("invalid dialog match flag");
                    continue;
                }
                if ("dialog_notify".equals(key)) {
                    dialogNotify = "1".equals(value);
                    if (!bit(value)) throw new IllegalArgumentException("invalid dialog notification flag");
                    continue;
                }
                if ("dialog_text_terms_b64".equals(key)) {
                    dialogTextTermsRaw = decodeDeveloperRuleValue(value);
                    continue;
                }
                if ("dialog_id_terms_b64".equals(key)) {
                    dialogIdTermsRaw = decodeDeveloperRuleValue(value);
                    continue;
                }
                if ("toast_filter".equals(key)) {
                    toastFilterEnabled = "1".equals(value);
                    if (!bit(value)) throw new IllegalArgumentException("invalid toast filter flag");
                    continue;
                }
                if ("toast_text_terms_b64".equals(key)) {
                    toastTextTermsRaw = decodeDeveloperRuleValue(value);
                    continue;
                }
                if ("key_finish_trigger".equals(key) || "key_dialog_toggle_trigger".equals(key)) {
                    int trigger;
                    try { trigger = Integer.parseInt(value); }
                    catch (NumberFormatException invalid) {
                        throw new IllegalArgumentException("invalid Dia key trigger");
                    }
                    if (trigger < -1 || trigger > 6)
                        throw new IllegalArgumentException("Dia key trigger must be -1 or between 0 and 6");
                    if ("key_finish_trigger".equals(key)) keyFinishTrigger = trigger;
                    else keyDialogToggleTrigger = trigger;
                    continue;
                }
                if ("location_lat".equals(key)) {
                    try { simulatedLatitude = Double.valueOf(value); }
                    catch (NumberFormatException invalid) { throw new IllegalArgumentException("invalid simulated latitude"); }
                    if (simulatedLatitude.isNaN() || simulatedLatitude.isInfinite()
                            || simulatedLatitude < -90d || simulatedLatitude > 90d)
                        throw new IllegalArgumentException("simulated latitude out of range");
                    continue;
                }
                if ("location_lon".equals(key)) {
                    try { simulatedLongitude = Double.valueOf(value); }
                    catch (NumberFormatException invalid) { throw new IllegalArgumentException("invalid simulated longitude"); }
                    if (simulatedLongitude.isNaN() || simulatedLongitude.isInfinite()
                            || simulatedLongitude < -180d || simulatedLongitude > 180d)
                        throw new IllegalArgumentException("simulated longitude out of range");
                    continue;
                }
                if ("location_accuracy".equals(key)) {
                    simulatedAccuracySpecified = true;
                    try { simulatedAccuracy = Float.parseFloat(value); }
                    catch (NumberFormatException invalid) { throw new IllegalArgumentException("invalid simulated accuracy"); }
                    if (Float.isNaN(simulatedAccuracy) || Float.isInfinite(simulatedAccuracy)
                            || simulatedAccuracy < 0f || simulatedAccuracy > 1000f)
                        throw new IllegalArgumentException("simulated accuracy out of range");
                    continue;
                }
                if ("android_id".equals(key)) {
                    if (!value.matches("(?i)[0-9a-f]{16}"))
                        throw new IllegalArgumentException("simulated Android ID must be 16 hex characters");
                    simulatedAndroidId = value.toLowerCase(java.util.Locale.ROOT);
                    continue;
                }
                if ("time_zone".equals(key)) {
                    boolean known = false;
                    for (String id : java.util.TimeZone.getAvailableIDs()) {
                        if (id.equals(value)) { known = true; break; }
                    }
                    if (!known) throw new IllegalArgumentException("unknown simulated time zone");
                    simulatedTimeZone = value;
                    continue;
                }
                if ("app_version_name_b64".equals(key)) {
                    simulatedVersionName = decodeDeveloperRuleValue(value);
                    if (simulatedVersionName.isEmpty()
                            || simulatedVersionName.getBytes(StandardCharsets.UTF_8).length > 128)
                        throw new IllegalArgumentException("simulated app version name exceeds 128 bytes");
                    for (int n=0;n<simulatedVersionName.length();n++)
                        if (Character.isISOControl(simulatedVersionName.charAt(n)))
                            throw new IllegalArgumentException("simulated app version name contains control characters");
                    continue;
                }
                if ("app_version_code".equals(key)) {
                    try { simulatedVersionCode = Long.valueOf(value); }
                    catch (NumberFormatException invalid) { throw new IllegalArgumentException("invalid simulated app version code"); }
                    if (simulatedVersionCode < 0L || simulatedVersionCode > 2147483647L)
                        throw new IllegalArgumentException("simulated app version code out of range");
                    continue;
                }
                if ("dev_hook_enabled".equals(key)) {
                    if (!bit(value)) throw new IllegalArgumentException("invalid developer hook opt-in");
                    developerHooksEnabled = "1".equals(value);
                    continue;
                }
                java.util.regex.Matcher rawRuleKey =
                        java.util.regex.Pattern.compile("^dev_rule_([0-9]+)$").matcher(key);
                java.util.regex.Matcher encodedRuleKey =
                        java.util.regex.Pattern.compile("^dev_rule_b64_([0-9]+)$").matcher(key);
                if (rawRuleKey.matches() || encodedRuleKey.matches()) {
                    int slot = Integer.parseInt(rawRuleKey.matches()
                            ? rawRuleKey.group(1) : encodedRuleKey.group(1));
                    if (slot < 1 || !developerRuleSlots.add(slot))
                        throw new IllegalArgumentException("duplicate or invalid developer rule slot");
                    // Legacy dev_rule_N values remain readable. New writes use URL-safe
                    // Base64 so commas inside typed Java/JVM parameter signatures cannot
                    // be mistaken for target-row separators.
                    String ruleValue = encodedRuleKey.matches()
                            ? decodeDeveloperRuleValue(value) : value;
                    DeveloperHookRule rule = DeveloperHookRule.parse(ruleValue, pkg);
                    if (rule == null) {
                        String[] ruleFields = ruleValue.split("\\|", -1);
                        if (ruleFields.length == 4
                                && DeveloperHookRule.isUnsupportedMutationAction(ruleFields[2])) {
                            throw new IllegalArgumentException(DeveloperHookRule.UNSUPPORTED_MUTATION_ACTION_MESSAGE);
                        }
                        throw new IllegalArgumentException("invalid developer rule");
                    }
                    if (!developerRuleIds.add(rule.id))
                        throw new IllegalArgumentException("duplicate developer rule id");
                    developerRules.add(rule);
                    continue;
                }
                if ("dev_test_vip_method".equals(key) || "dev_test_login_method".equals(key) || "dev_test_hide_update_method".equals(key)) {
                    if (!validDeveloperBooleanMethodSpec(value, pkg)) throw new IllegalArgumentException("invalid developer test method descriptor");
                    if ("dev_test_vip_method".equals(key)) developerVipMethod=value;
                    else if ("dev_test_login_method".equals(key)) developerLoginMethod=value;
                    else developerHideUpdateMethod=value;
                    continue;
                }
                if (!bit(value)) throw new IllegalArgumentException("invalid feature value");
                boolean on = "1".equals(value);
                switch (key) {
                    case "ads_splash": splash = on; break;
                    case "ads_feed": feed = on; break;
                    case "ads_overlay": overlay = on; break;
                    case "member_diag": member = on; break;
                    case "privacy": targetPrivacy = on; break;
                    case "exif_strip": exifStrip = on; break;
                    case "clipboard_read_block": clipboardReadBlock = on; break;
                    case "clipboard_isolate": clipboardIsolate = on; break;
                    case "sensor_accel": sensorAccel = on; break;
                    case "sensor_gyro": sensorGyro = on; break;
                    case "sensor_light": sensorLight = on; break;
                    case "sensor_magnet": sensorMagnet = on; break;
                    case "sensor_pressure": sensorPressure = on; break;
                    case "sensor_prox": sensorProx = on; break;
                    case "sensor_environment": sensorEnvironment = on; break;
                    case "sensor_fusion": sensorFusion = on; break;
                    case "sensor_gesture": sensorGesture = on; break;
                    case "sensor_biometric": sensorBiometric = on; break;
                    case "sensor_rate_limit": sensorRateLimit = on; break;
                    case "wifi_scan_block": wifiScanBlock = on; break;
                    case "wifi_simulate": wifiSimulation = on; break;
                    case "network_type_simulate": networkTypeSimulation = on; break;
                    case "location_simulate": locationSimulation = on; break;
                    case "location_provider_enabled_simulate": locationProviderEnabledSimulation = on; break;
                    case "android_id_simulate": androidIdSimulation = on; break;
                    case "time_zone_simulate": timeZoneSimulation = on; break;
                    case "app_version_simulate": appVersionSimulation = on; break;
                    case "notification_listen_block": notificationListenBlock = on; break;
                    case "notification_permission_hide": notificationPermissionHideTarget = on; break;
                    case "mic_silence": microphoneSilence = on; break;
                    case "camera_access_block": cameraAccessBlock = on; break;
                    case "location_access_block": locationAccessBlock = on; break;
                    case "mic_access_block": microphoneAccessBlock = on; break;
                    case "media_store_query_block": mediaStoreQueryBlock = on; break;
                    case "ad_id_unify": adIdUnify = on; break;
                    default: throw new IllegalArgumentException("unknown target feature");
                }
            }
            if (clipboardReadBlock && clipboardIsolate) throw new IllegalArgumentException("clipboard isolation conflicts with read block");
            Target parsedTarget = new Target(splash, feed, overlay, member, targetPrivacy, exifStrip, clipboardReadBlock, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHideTarget, clipboardIsolate, microphoneSilence, cameraAccessBlock, locationAccessBlock, microphoneAccessBlock, mediaStoreQueryBlock, adIdUnify);
            parsedTarget.sensorEnvironment = sensorEnvironment;
            parsedTarget.sensorFusion = sensorFusion;
            parsedTarget.sensorGesture = sensorGesture;
            parsedTarget.sensorBiometric = sensorBiometric;
            parsedTarget.developerVipMethod = developerVipMethod;
            parsedTarget.developerLoginMethod = developerLoginMethod;
            parsedTarget.developerHideUpdateMethod = developerHideUpdateMethod;
            parsedTarget.developerHooksEnabled = developerHooksEnabled;
            parsedTarget.developerRules.addAll(developerRules);
            if (wifiSimulation && simulatedWifiSsid == null && simulatedWifiBssid == null)
                throw new IllegalArgumentException("Wi-Fi simulation requires an SSID or BSSID");
            if (!wifiSimulation && (simulatedWifiSsid != null || simulatedWifiBssid != null))
                throw new IllegalArgumentException("Wi-Fi values require wifi_simulate=1");
            parsedTarget.wifiSimulation = wifiSimulation;
            parsedTarget.simulatedWifiSsid = simulatedWifiSsid;
            parsedTarget.simulatedWifiBssid = simulatedWifiBssid;
            if (networkTypeSimulation && simulatedNetworkType == null)
                throw new IllegalArgumentException("network type simulation requires a selected type");
            if (!networkTypeSimulation && simulatedNetworkType != null)
                throw new IllegalArgumentException("network_type requires network_type_simulate=1");
            parsedTarget.networkTypeSimulation = networkTypeSimulation;
            parsedTarget.simulatedNetworkType = simulatedNetworkType;
            List<String> dialogTextTerms = FxDiaDialogMatchPolicy.parseTerms(dialogTextTermsRaw);
            List<String> dialogIdTerms = FxDiaDialogMatchPolicy.parseTerms(dialogIdTermsRaw);
            boolean hasDialogTerms = !dialogTextTerms.isEmpty() || !dialogIdTerms.isEmpty();
            if (dialogMatchEnabled && !hasDialogTerms)
                throw new IllegalArgumentException("dialog match monitoring requires explicit text or ID rules");
            if (!dialogMatchEnabled && hasDialogTerms)
                throw new IllegalArgumentException("dialog match rules require dialog_match=1");
            if (dialogNotify && !dialogMatchEnabled)
                throw new IllegalArgumentException("dialog notification requires dialog_match=1");
            if (FxDiaKeyGesturePolicy.hasOverlappingTriggers(
                    keyFinishTrigger, keyDialogToggleTrigger)) {
                throw new IllegalArgumentException("Dia key actions have overlapping gesture triggers");
            }
            if (keyDialogToggleTrigger >= 0 && !dialogMatchEnabled)
                throw new IllegalArgumentException("Dialog key toggle requires an enabled per-app Dialog rule set");
            List<String> toastTextTerms = FxDiaDialogMatchPolicy.parseTerms(toastTextTermsRaw);
            if (toastFilterEnabled && toastTextTerms.isEmpty())
                throw new IllegalArgumentException("toast filtering requires explicit text rules");
            if (!toastFilterEnabled && !toastTextTerms.isEmpty())
                throw new IllegalArgumentException("toast text rules require toast_filter=1");
            if (locationSimulation && (simulatedLatitude == null || simulatedLongitude == null))
                throw new IllegalArgumentException("location simulation requires latitude and longitude");
            if (!locationSimulation && (simulatedLatitude != null || simulatedLongitude != null
                    || simulatedAccuracySpecified))
                throw new IllegalArgumentException("location values require location_simulate=1");
            if (locationSimulation && locationAccessBlock)
                throw new IllegalArgumentException("location simulation conflicts with location access blocking");
            if (locationProviderEnabledSimulation && locationAccessBlock)
                throw new IllegalArgumentException("provider-enabled simulation conflicts with location access blocking");
            parsedTarget.dialogMatchEnabled = dialogMatchEnabled;
            parsedTarget.dialogNotify = dialogNotify;
            parsedTarget.dialogTextTerms.addAll(dialogTextTerms);
            parsedTarget.dialogIdTerms.addAll(dialogIdTerms);
            parsedTarget.keyFinishTrigger = keyFinishTrigger;
            parsedTarget.keyDialogToggleTrigger = keyDialogToggleTrigger;
            parsedTarget.toastFilterEnabled = toastFilterEnabled;
            parsedTarget.toastTextTerms.addAll(toastTextTerms);
            parsedTarget.locationSimulation = locationSimulation;
            parsedTarget.locationProviderEnabledSimulation = locationProviderEnabledSimulation;
            if (simulatedLatitude != null) parsedTarget.simulatedLatitude = simulatedLatitude;
            if (simulatedLongitude != null) parsedTarget.simulatedLongitude = simulatedLongitude;
            parsedTarget.simulatedAccuracy = simulatedAccuracy;
            if (androidIdSimulation && simulatedAndroidId == null)
                throw new IllegalArgumentException("Android ID simulation requires a value");
            if (!androidIdSimulation && simulatedAndroidId != null)
                throw new IllegalArgumentException("android_id requires android_id_simulate=1");
            parsedTarget.androidIdSimulation = androidIdSimulation;
            parsedTarget.simulatedAndroidId = simulatedAndroidId;
            if (timeZoneSimulation && simulatedTimeZone == null)
                throw new IllegalArgumentException("time zone simulation requires a zone");
            if (!timeZoneSimulation && simulatedTimeZone != null)
                throw new IllegalArgumentException("time_zone requires time_zone_simulate=1");
            parsedTarget.timeZoneSimulation = timeZoneSimulation;
            parsedTarget.simulatedTimeZone = simulatedTimeZone;
            if (appVersionSimulation && (simulatedVersionName == null || simulatedVersionCode == null))
                throw new IllegalArgumentException("app version simulation requires version name and code");
            if (!appVersionSimulation && (simulatedVersionName != null || simulatedVersionCode != null))
                throw new IllegalArgumentException("app version values require app_version_simulate=1");
            parsedTarget.appVersionSimulation = appVersionSimulation;
            parsedTarget.simulatedVersionName = simulatedVersionName;
            parsedTarget.simulatedVersionCode = simulatedVersionCode == null ? 0L : simulatedVersionCode;
            targets.put(pkg, parsedTarget);
        }

        if (!schemaSeen || !adsSeen || !privacySeen || !sectionSeen)
            throw new IllegalArgumentException("missing required schema fields");
        return new Result(ads, privacy, wifiScan, notificationListen, notificationPermissionHide, clipboardIsolation, targets);
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
        String[] lines = text.split("\\R", -1);
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
        return new Result(ads, false, false, false, false, false, targets);
    }


    private static String decodeDeveloperRuleValue(String value) {
        if (value == null || value.isEmpty() || value.length() > 1400
                || !value.matches("[A-Za-z0-9_-]+"))
            throw new IllegalArgumentException("invalid encoded developer rule");
        final byte[] decoded;
        try {
            decoded = java.util.Base64.getUrlDecoder().decode(value);
        } catch (IllegalArgumentException malformed) {
            throw new IllegalArgumentException("invalid encoded developer rule");
        }
        if (decoded.length == 0 || decoded.length > 1024)
            throw new IllegalArgumentException("encoded developer rule exceeds size limit");
        String rule = new String(decoded, StandardCharsets.UTF_8);
        if (!Arrays.equals(decoded, rule.getBytes(StandardCharsets.UTF_8)))
            throw new IllegalArgumentException("encoded developer rule is not valid UTF-8");
        return rule;
    }

    private static boolean validDeveloperBooleanMethodSpec(String value, String packageName) {
        if (value == null || value.length() > 512) return false;
        java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("^([A-Za-z_$][A-Za-z0-9_$.]*)#([A-Za-z_$][A-Za-z0-9_$]*)\\(\\)Z$").matcher(value);
        if (!matcher.matches()) return false;
        String owner = matcher.group(1);
        return owner.startsWith(packageName + ".") && !owner.startsWith("java.") && !owner.startsWith("android.");
    }

    private static boolean validWifiSsid(String value) {
        if (value == null || value.isEmpty()
                || value.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 32) return false;
        for (int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            if (c<0x20 || c==0x7f || c==',' || c=='|') return false;
        }
        return true;
    }

    private static boolean bit(String value) {
        return "0".equals(value) || "1".equals(value);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+");
    }
}
