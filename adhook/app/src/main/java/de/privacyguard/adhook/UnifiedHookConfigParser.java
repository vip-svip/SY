package de.privacyguard.adhook;

import de.privacyguard.adhook.imported.dia.FxDiaDialogMatchPolicy;
import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicy;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.HashSet;
import java.util.Arrays;

/**
 * Versioned, transactional configuration model for the single FX Hook APK.
 * This parser is consumed by the unified runtime for per-app ad, privacy, region,
 * VPN-detection and read-only membership settings. Missing optional flags default off.
 */
public final class UnifiedHookConfigParser {
    private static final Set<String> ENTITLEMENT_STATES = Collections.unmodifiableSet(
            new HashSet<>(Arrays.asList("FREE", "VIP", "EXPIRED", "REVOKED", "PENDING")));

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
        public final boolean regionHidden;
        public final boolean vpnDetectionHidden;
        public final boolean mediaHidden;
        public final boolean usageHidden;
        public final boolean deviceProfile;
        // Migrated per-app privacy controls from the unified SY Hook schema.
        public final boolean exifStrip, clipboardReadBlock, clipboardIsolate;
        public final boolean sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx;
        public final boolean sensorEnvironment, sensorFusion, sensorGesture, sensorBiometric, sensorRateLimit;
        public final boolean wifiScanBlock, notificationListenBlock, notificationPermissionHide;
        public final boolean microphoneSilence, cameraAccessBlock, locationAccessBlock, microphoneAccessBlock;
        public final boolean mediaStoreQueryBlock, adIdUnify;
        // Opt-in legacy privacy switches that the parser already accepts and the
        // policy helpers already read. Defaults stay false so an existing config
        // never enables a hook it did not ask for.
        public boolean regionDiag, usageStatsOff, a11yHide, audioFpBlock, micBlock, cameraIdHide, blockMediaStore, blockImeLogging, micHwHide, disablePassiveLocation, hideFingerprintHw, hideFaceHw, wifiScanHide, cellInfoHide;
        public final boolean dialogMatchEnabled;
        public final boolean dialogNotify;
        public final boolean toastFilterEnabled;
        public final List<String> dialogTextTerms;
        public final List<String> dialogIdTerms;
        public final List<String> toastTextTerms;
        public final int keyFinishTrigger;
        public final int keyDialogToggleTrigger;
        // Generic VIP / paid-entitlement reporting. Presentation-only: the app is told
        // which membership state to display, nothing touches receipts or billing.
        public boolean vipEntitlementSimulation;
        // Real premium unlocking: entitlement getters, billing results and the app's
        // own persisted flags all resolve to "unlocked" for this target.
        public boolean vipUnlock;
        // State anti-fraud, carrier-side collection and public-security reconnaissance
        // blocking. Each drives its own hook installer and defaults to off.
        public boolean antiFraudBlock;
        public boolean carrierCollectionBlock;
        public boolean policeReconBlock;
        public String simulatedEntitlementState;
        // In-app update suppression: report "already current" and/or a chosen version.
        public boolean blockAppUpdate;
        public boolean fakeAppVersion;
        public String simulatedAppVersion;
        // Per-target test location. Off by default; coordinates require the explicit
        // opt-in and never combine with location access blocking.
        public boolean locationSimulation;
        public boolean locationProviderEnabledSimulation;
        public double simulatedLatitude;
        public double simulatedLongitude;
        public float simulatedAccuracy = 5f;
        /** Per-app extra class/resource-name tokens grouped by ad category. */
        public final Map<String, Set<String>> customRules;

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean regionHidden, boolean vpnDetectionHidden, boolean mediaHidden, boolean usageHidden, boolean deviceProfile,
               boolean exifStrip, boolean clipboardReadBlock, boolean clipboardIsolate,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet,
               boolean sensorPressure, boolean sensorProx, boolean sensorEnvironment, boolean sensorFusion,
               boolean sensorGesture, boolean sensorBiometric, boolean sensorRateLimit, boolean wifiScanBlock,
               boolean notificationListenBlock, boolean notificationPermissionHide, boolean microphoneSilence,
               boolean cameraAccessBlock, boolean locationAccessBlock, boolean microphoneAccessBlock,
               boolean mediaStoreQueryBlock, boolean adIdUnify, Map<String, Set<String>> customRules) {
            this(splash, feed, overlay, memberDiag, privacy, regionHidden, vpnDetectionHidden,
                    mediaHidden, usageHidden, deviceProfile, exifStrip, clipboardReadBlock,
                    clipboardIsolate, sensorAccel, sensorGyro, sensorLight, sensorMagnet,
                    sensorPressure, sensorProx, sensorEnvironment, sensorFusion, sensorGesture,
                    sensorBiometric, sensorRateLimit, wifiScanBlock, notificationListenBlock,
                    notificationPermissionHide, microphoneSilence, cameraAccessBlock,
                    locationAccessBlock, microphoneAccessBlock, mediaStoreQueryBlock, adIdUnify,
                    customRules, false, false, false, Collections.<String>emptyList(),
                    Collections.<String>emptyList(), Collections.<String>emptyList(), -1, -1);
        }

        /** Legacy ads/privacy-only shape used by clipboard policy tests. */
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock) {
            this(splash, feed, overlay, memberDiag, privacy, false, false, false, false, false, exifStrip, clipboardReadBlock, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false,
                    Collections.<String, Set<String>>emptyMap());
        }

        /** Sensor policy shape: the seven sensor switches. */
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit) {
            this(splash, feed, overlay, memberDiag, privacy, false, false, false, false, false, exifStrip, clipboardReadBlock, false, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, false, false, false, false, sensorRateLimit, false, false, false, false, false, false, false, false, false,
                    Collections.<String, Set<String>>emptyMap());
        }

        /** Adds the Wi-Fi scan switch. */
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock) {
            this(splash, feed, overlay, memberDiag, privacy, false, false, false, false, false, exifStrip, clipboardReadBlock, false, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, false, false, false, false, sensorRateLimit, wifiScanBlock, false, false, false, false, false, false, false, false,
                    Collections.<String, Set<String>>emptyMap());
        }

        /** Adds the notification-listener switch. */
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock) {
            this(splash, feed, overlay, memberDiag, privacy, false, false, false, false, false, exifStrip, clipboardReadBlock, false, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, false, false, false, false, sensorRateLimit, wifiScanBlock, notificationListenBlock, false, false, false, false, false, false, false,
                    Collections.<String, Set<String>>emptyMap());
        }

        /** Adds the notification permission switch. */
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy, boolean exifStrip, boolean clipboardReadBlock,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet, boolean sensorPressure, boolean sensorProx, boolean sensorRateLimit, boolean wifiScanBlock, boolean notificationListenBlock, boolean notificationPermissionHide) {
            this(splash, feed, overlay, memberDiag, privacy, false, false, false, false, false, exifStrip, clipboardReadBlock, false, sensorAccel, sensorGyro, sensorLight, sensorMagnet, sensorPressure, sensorProx, false, false, false, false, sensorRateLimit, wifiScanBlock, notificationListenBlock, notificationPermissionHide, false, false, false, false, false, false,
                    Collections.<String, Set<String>>emptyMap());
        }

        // Compatibility constructor for the earlier legacy ads-only parser.
        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag,
               boolean privacy, boolean regionHidden, boolean vpnDetectionHidden,
               boolean mediaHidden, boolean usageHidden, boolean deviceProfile,
               Map<String, Set<String>> customRules) {
            this(splash, feed, overlay, memberDiag, privacy, regionHidden, vpnDetectionHidden,
                    mediaHidden, usageHidden, deviceProfile, false, false, false,
                    false, false, false, false, false, false, false, false, false, false,
                    false, false, false, false, false, false, false, false, false,
                    false, customRules, false, false, false, Collections.<String>emptyList(),
                    Collections.<String>emptyList(), Collections.<String>emptyList(), -1, -1);
        }

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag, boolean privacy,
               boolean regionHidden, boolean vpnDetectionHidden, boolean mediaHidden, boolean usageHidden, boolean deviceProfile,
               boolean exifStrip, boolean clipboardReadBlock, boolean clipboardIsolate,
               boolean sensorAccel, boolean sensorGyro, boolean sensorLight, boolean sensorMagnet,
               boolean sensorPressure, boolean sensorProx, boolean sensorEnvironment, boolean sensorFusion,
               boolean sensorGesture, boolean sensorBiometric, boolean sensorRateLimit, boolean wifiScanBlock,
               boolean notificationListenBlock, boolean notificationPermissionHide, boolean microphoneSilence,
               boolean cameraAccessBlock, boolean locationAccessBlock, boolean microphoneAccessBlock,
               boolean mediaStoreQueryBlock, boolean adIdUnify, Map<String, Set<String>> customRules,
               boolean dialogMatchEnabled, boolean dialogNotify, boolean toastFilterEnabled,
               List<String> dialogTextTerms, List<String> dialogIdTerms, List<String> toastTextTerms,
               int keyFinishTrigger, int keyDialogToggleTrigger) {
            this.splash = splash;
            this.feed = feed;
            this.overlay = overlay;
            this.memberDiag = memberDiag;
            this.privacy = privacy;
            this.regionHidden = regionHidden;
            this.vpnDetectionHidden = vpnDetectionHidden;
            this.mediaHidden = mediaHidden;
            this.usageHidden = usageHidden;
            this.deviceProfile = deviceProfile;
            this.exifStrip = exifStrip;
            this.clipboardReadBlock = clipboardReadBlock;
            this.clipboardIsolate = clipboardIsolate;
            this.sensorAccel = sensorAccel; this.sensorGyro = sensorGyro;
            this.sensorLight = sensorLight; this.sensorMagnet = sensorMagnet;
            this.sensorPressure = sensorPressure; this.sensorProx = sensorProx;
            this.sensorEnvironment = sensorEnvironment; this.sensorFusion = sensorFusion;
            this.sensorGesture = sensorGesture; this.sensorBiometric = sensorBiometric;
            this.sensorRateLimit = sensorRateLimit; this.wifiScanBlock = wifiScanBlock;
            this.notificationListenBlock = notificationListenBlock;
            this.notificationPermissionHide = notificationPermissionHide;
            this.microphoneSilence = microphoneSilence; this.cameraAccessBlock = cameraAccessBlock;
            this.locationAccessBlock = locationAccessBlock; this.microphoneAccessBlock = microphoneAccessBlock;
            this.mediaStoreQueryBlock = mediaStoreQueryBlock; this.adIdUnify = adIdUnify;
            this.dialogMatchEnabled = dialogMatchEnabled;
            this.dialogNotify = dialogNotify;
            this.toastFilterEnabled = toastFilterEnabled;
            this.dialogTextTerms = Collections.unmodifiableList(new ArrayList<>(
                    dialogTextTerms == null ? Collections.<String>emptyList() : dialogTextTerms));
            this.dialogIdTerms = Collections.unmodifiableList(new ArrayList<>(
                    dialogIdTerms == null ? Collections.<String>emptyList() : dialogIdTerms));
            this.toastTextTerms = Collections.unmodifiableList(new ArrayList<>(
                    toastTextTerms == null ? Collections.<String>emptyList() : toastTextTerms));
            this.keyFinishTrigger = keyFinishTrigger;
            this.keyDialogToggleTrigger = keyDialogToggleTrigger;
            Map<String, Set<String>> copy = new LinkedHashMap<>();
            for (Map.Entry<String, Set<String>> entry : customRules.entrySet()) {
                copy.put(entry.getKey(), Collections.unmodifiableSet(new HashSet<>(entry.getValue())));
            }
            this.customRules = Collections.unmodifiableMap(copy);
        }

        public boolean enabled() {
            return splash || feed || overlay;
        }
    }

    public static final class Result {
        public final boolean adsEnabled;
        public final boolean privacyEnabled;
        public final boolean systemServicesEnabled;
        public final Set<String> hiddenSystemServices;
        public final boolean pmQueryEnabled;
        public final boolean appListEnabled;
        public final String appListMode;
        public final Set<String> hiddenApps;
        public final Set<String> keptApps;
        public final Map<String, Target> targets;

        private Result(boolean adsEnabled, boolean privacyEnabled, boolean systemServicesEnabled,
                       Set<String> hiddenSystemServices, boolean pmQueryEnabled,
                       boolean appListEnabled, String appListMode, Set<String> hiddenApps,
                       Set<String> keptApps, Map<String, Target> targets) {
            this.adsEnabled = adsEnabled;
            this.privacyEnabled = privacyEnabled;
            this.systemServicesEnabled = systemServicesEnabled;
            this.hiddenSystemServices = Collections.unmodifiableSet(new HashSet<>(hiddenSystemServices));
            this.pmQueryEnabled = pmQueryEnabled;
            this.appListEnabled = appListEnabled;
            this.appListMode = appListMode == null ? "custom" : appListMode;
            this.hiddenApps = Collections.unmodifiableSet(new HashSet<>(hiddenApps));
            this.keptApps = Collections.unmodifiableSet(new HashSet<>(keptApps));
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

        public boolean isRegionHiddenFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.regionHidden;
        }

        public boolean isVpnDetectionHiddenFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.vpnDetectionHidden;
        }

        public boolean isMediaHiddenFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.mediaHidden;
        }

        public boolean isUsageHiddenFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.usageHidden;
        }

        public boolean isDeviceProfileEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && target != null && target.deviceProfile;
        }

        public boolean isSystemServiceHidingEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && systemServicesEnabled && !hiddenSystemServices.isEmpty()
                    && target != null && target.privacy;
        }

        public boolean isAppListHidingEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return privacyEnabled && appListEnabled && target != null && target.privacy;
        }
    }

    public static Result parse(String text) {
        if (text == null) throw new IllegalArgumentException("null config");
        String[] lines = text.split("\\R", -1);
        if (hasLegacyMasterKey(text)) return parseLegacyAdsConfig(text);

        boolean schemaSeen = false, adsSeen = false, privacySeen = false;
        boolean systemServicesEnabledSeen = false, systemServicesSectionSeen = false, targetsSectionSeen = false;
        boolean appListEnabledSeen = false, appListModeSeen = false, pmQueryEnabledSeen = false;
        boolean appListHideSectionSeen = false, appListKeepSectionSeen = false;
        boolean ads = false, privacy = false, systemServicesEnabled = false, pmQueryEnabled = false, appListEnabled = false;
        String appListMode = "custom";
        String section = "";
        Set<String> systemServices = new HashSet<>();
        Set<String> hiddenApps = new HashSet<>(), keptApps = new HashSet<>();
        Map<String, Target> targets = new LinkedHashMap<>();

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            if (line.startsWith("[") || line.endsWith("]")) {
                if (!line.startsWith("[") || !line.endsWith("]") || line.length() < 3)
                    throw new IllegalArgumentException("malformed section");
                String next = line.substring(1, line.length() - 1).trim();
                if ("list:app_list_hide".equals(next) && !appListHideSectionSeen &&
                        !appListKeepSectionSeen && !systemServicesSectionSeen && !targetsSectionSeen) {
                    appListHideSectionSeen = true;
                    section = next;
                } else if ("list:app_list_keep".equals(next) && !appListKeepSectionSeen &&
                        !systemServicesSectionSeen && !targetsSectionSeen) {
                    appListKeepSectionSeen = true;
                    section = next;
                } else if ("list:system_services".equals(next) && !systemServicesSectionSeen && !targetsSectionSeen) {
                    systemServicesSectionSeen = true;
                    section = next;
                } else if ("list:targets".equals(next) && !targetsSectionSeen) {
                    targetsSectionSeen = true;
                    section = next;
                } else {
                    throw new IllegalArgumentException("unsupported, duplicate or out-of-order section");
                }
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
                } else if ("system_services_enabled".equals(key)) {
                    if (systemServicesEnabledSeen || !bit(value))
                        throw new IllegalArgumentException("invalid system_services_enabled");
                    systemServicesEnabledSeen = true;
                    systemServicesEnabled = "1".equals(value);
                } else if ("pm_query_enabled".equals(key)) {
                    if (pmQueryEnabledSeen || !bit(value)) throw new IllegalArgumentException("invalid pm_query_enabled");
                    pmQueryEnabledSeen = true;
                    pmQueryEnabled = "1".equals(value);
                } else if ("app_list_enabled".equals(key)) {
                    if (appListEnabledSeen || !bit(value)) throw new IllegalArgumentException("invalid app_list_enabled");
                    appListEnabledSeen = true;
                    appListEnabled = "1".equals(value);
                } else if ("app_list_mode".equals(key)) {
                    if (appListModeSeen || !("empty".equals(value) || "custom".equals(value) || "allowlist".equals(value)))
                        throw new IllegalArgumentException("invalid app_list_mode");
                    appListModeSeen = true;
                    appListMode = value;
                } else {
                    throw new IllegalArgumentException("unknown top-level key");
                }
                continue;
            }

            if ("list:system_services".equals(section)) {
                if (!line.matches("[A-Za-z][A-Za-z0-9_.-]{0,79}"))
                    throw new IllegalArgumentException("invalid system service name");
                if (!systemServices.add(line))
                    throw new IllegalArgumentException("duplicate system service name");
                continue;
            }
            if ("list:app_list_hide".equals(section) || "list:app_list_keep".equals(section)) {
                if (!validPackage(line) || NEVER.contains(line))
                    throw new IllegalArgumentException("invalid app-list package name");
                Set<String> destination = "list:app_list_hide".equals(section) ? hiddenApps : keptApps;
                if (!destination.add(line))
                    throw new IllegalArgumentException("duplicate app-list package name");
                continue;
            }
            if (!"list:targets".equals(section))
                throw new IllegalArgumentException("missing target section");
            String[] parts = line.split(",", -1);
            if (parts.length < 2) throw new IllegalArgumentException("target requires at least one feature");
            String pkg = parts[0].trim();
            if (!validPackage(pkg) || NEVER.contains(pkg) || targets.containsKey(pkg))
                throw new IllegalArgumentException("invalid, protected or duplicate package");
            boolean splash = false, feed = false, overlay = false, member = false, targetPrivacy = false;
            boolean regionHidden = false, vpnDetectionHidden = false, mediaHidden = false, usageHidden = false, deviceProfile = false;
            boolean exifStrip=false, clipboardReadBlock=false, clipboardIsolate=false;
            boolean regionDiag=false, usageStatsOff=false, a11yHide=false, audioFpBlock=false;
            boolean micBlock=false, cameraIdHide=false, blockMediaStore=false, blockImeLogging=false;
            boolean micHwHide=false, disablePassiveLocation=false, hideFingerprintHw=false, hideFaceHw=false;
            boolean wifiScanHide=false, cellInfoHide=false;
            boolean sensorAccel=false, sensorGyro=false, sensorLight=false, sensorMagnet=false, sensorPressure=false, sensorProx=false;
            boolean sensorEnvironment=false, sensorFusion=false, sensorGesture=false, sensorBiometric=false, sensorRateLimit=false;
            boolean wifiScanBlock=false, notificationListenBlock=false, notificationPermissionHide=false;
            boolean microphoneSilence=false, cameraAccessBlock=false, locationAccessBlock=false, microphoneAccessBlock=false;
            boolean mediaStoreQueryBlock=false, adIdUnify=false;
            boolean vipEntitlementSimulation=false;
            boolean vipUnlock=false;
            boolean antiFraudBlock=false, carrierCollectionBlock=false, policeReconBlock=false;
            String simulatedEntitlementState=null;
            boolean blockAppUpdate=false;
            boolean fakeAppVersion=false;
            String simulatedAppVersion=null;
            boolean locationSimulation=false, locationProviderEnabledSimulation=false;
            Double simulatedLatitude=null, simulatedLongitude=null;
            float simulatedAccuracy=5f;
            boolean simulatedAccuracySpecified=false;
            boolean dialogMatchEnabled=false, dialogNotify=false, toastFilterEnabled=false;
            int keyFinishTrigger=-1, keyDialogToggleTrigger=-1;
            String dialogTextTermsRaw=null, dialogIdTermsRaw=null, toastTextTermsRaw=null;
            Set<String> seen = new HashSet<>();
            Map<String, Set<String>> customRules = new LinkedHashMap<>();
            for (int i = 1; i < parts.length; i++) {
                int eq = parts[i].indexOf('=');
                if (eq < 1) throw new IllegalArgumentException("malformed feature");
                String key = parts[i].substring(0, eq).trim();
                String value = parts[i].substring(eq + 1).trim();
                if (!seen.add(key)) throw new IllegalArgumentException("duplicate feature");
                if ("vip_entitlement_state".equals(key)) {
                    if (!ENTITLEMENT_STATES.contains(value))
                        throw new IllegalArgumentException("unknown simulated entitlement state");
                    simulatedEntitlementState = value;
                    continue;
                }
                if ("app_version_value".equals(key)) {
                    if (!AppUpdatePolicy.isPlausibleVersion(value))
                        throw new IllegalArgumentException("implausible simulated app version");
                    simulatedAppVersion = value;
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
                if ("rules".equals(key)) {
                    customRules = parseCustomRules(value);
                    continue;
                }
                if (!bit(value)) throw new IllegalArgumentException("invalid feature flag");
                boolean on = "1".equals(value);
                switch (key) {
                    case "ads_splash": splash = on; break;
                    case "ads_feed": feed = on; break;
                    case "ads_overlay": overlay = on; break;
                    case "member_diag": member = on; break;
                    case "privacy": targetPrivacy = on; break;
                    case "vip_entitlement_simulate": vipEntitlementSimulation = on; break;
                    case "vip_unlock": vipUnlock = on; break;
                    case "anti_fraud_block": antiFraudBlock = on; break;
                    case "carrier_collection_block": carrierCollectionBlock = on; break;
                    case "police_recon_block": policeReconBlock = on; break;
                    case "block_app_update": blockAppUpdate = on; break;
                    case "fake_app_version": fakeAppVersion = on; break;
                    case "location_simulate": locationSimulation = on; break;
                    case "location_provider_enabled_simulate": locationProviderEnabledSimulation = on; break;
                    case "region_hidden": regionHidden = on; break;
                    case "vpn_hidden": vpnDetectionHidden = on; break;
                    case "media_hidden": mediaHidden = on; break;
                    case "usage_hidden": usageHidden = on; break;
                    case "device_profile": deviceProfile = on; break;
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
                    case "notification_listen_block": notificationListenBlock = on; break;
                    case "notification_permission_hide": notificationPermissionHide = on; break;
                    case "mic_silence": microphoneSilence = on; break;
                    case "camera_access_block": cameraAccessBlock = on; break;
                    case "location_access_block": locationAccessBlock = on; break;
                    case "mic_access_block": microphoneAccessBlock = on; break;
                    case "media_store_query_block": mediaStoreQueryBlock = on; break;
                    case "ad_id_unify": adIdUnify = on; break;
                    case "region_diag": regionDiag = on; break;
                    case "usagestats_off": usageStatsOff = on; break;
                    case "a11y_hide": a11yHide = on; break;
                    case "audio_fp_block": audioFpBlock = on; break;
                    case "mic_block": micBlock = on; break;
                    case "camera_id_hide": cameraIdHide = on; break;
                    case "block_mediastore": blockMediaStore = on; break;
                    case "block_ime_logging": blockImeLogging = on; break;
                    case "mic_hw_hide": micHwHide = on; break;
                    case "disable_passive_loc": disablePassiveLocation = on; break;
                    case "hide_fingerprint_hw": hideFingerprintHw = on; break;
                    case "hide_face_hw": hideFaceHw = on; break;
                    case "wifi_scan_hide": wifiScanHide = on; break;
                    case "cell_info_hide": cellInfoHide = on; break;
                    case "dialog_match": dialogMatchEnabled = on; break;
                    case "dialog_notify": dialogNotify = on; break;
                    case "dialog_text_terms_b64": dialogTextTermsRaw = value; break;
                    case "dialog_id_terms_b64": dialogIdTermsRaw = value; break;
                    case "toast_filter": toastFilterEnabled = on; break;
                    case "toast_text_terms_b64": toastTextTermsRaw = value; break;
                    case "key_finish_trigger":
                    case "key_dialog_toggle_trigger": {
                        final int trigger;
                        try { trigger = Integer.parseInt(value); }
                        catch (NumberFormatException invalid) {
                            throw new IllegalArgumentException("invalid Dia key trigger");
                        }
                        if (trigger < -1 || trigger > 6)
                            throw new IllegalArgumentException("Dia key trigger must be -1 or between 0 and 6");
                        if ("key_finish_trigger".equals(key)) keyFinishTrigger = trigger;
                        else keyDialogToggleTrigger = trigger;
                        break;
                    }
                    default: throw new IllegalArgumentException("unknown target feature");
                }
            }
            for (String category : customRules.keySet()) {
                boolean categoryEnabled = ("splash".equals(category) && splash)
                        || ("feed".equals(category) && feed)
                        || ("overlay".equals(category) && overlay);
                if (!categoryEnabled)
                    throw new IllegalArgumentException("custom rule requires its category to be enabled");
            }
            // Read-block and isolation may coexist in a published row: the isolation
            // policy gives read-block precedence and fails open, and rejecting the row
            // here would drop the entire transactional config instead of one feature.
            List<String> dialogTextTerms = FxDiaDialogMatchPolicy.parseTerms(decodeDiaTerms(dialogTextTermsRaw));
            List<String> dialogIdTerms = FxDiaDialogMatchPolicy.parseTerms(decodeDiaTerms(dialogIdTermsRaw));
            if (locationSimulation && (simulatedLatitude == null || simulatedLongitude == null))
                throw new IllegalArgumentException("location simulation requires latitude and longitude");
            if (!locationSimulation && (simulatedLatitude != null || simulatedLongitude != null
                    || simulatedAccuracySpecified))
                throw new IllegalArgumentException("location values require location_simulate=1");
            if (locationSimulation && locationAccessBlock)
                throw new IllegalArgumentException("location simulation conflicts with location access blocking");
            if (locationProviderEnabledSimulation && locationAccessBlock)
                throw new IllegalArgumentException("provider-enabled simulation conflicts with location access blocking");
            if (vipEntitlementSimulation && simulatedEntitlementState == null)
                throw new IllegalArgumentException("vip entitlement simulation requires an explicit state");
            if (!vipEntitlementSimulation && simulatedEntitlementState != null)
                throw new IllegalArgumentException("vip_entitlement_state requires vip_entitlement_simulate=1");
            if (fakeAppVersion && simulatedAppVersion == null)
                throw new IllegalArgumentException("custom app version requires app_version_value");
            if (!fakeAppVersion && simulatedAppVersion != null)
                throw new IllegalArgumentException("app_version_value requires fake_app_version=1");
            List<String> toastTextTerms = FxDiaDialogMatchPolicy.parseTerms(decodeDiaTerms(toastTextTermsRaw));
            boolean hasDialogTerms = !dialogTextTerms.isEmpty() || !dialogIdTerms.isEmpty();
            if (dialogMatchEnabled && !hasDialogTerms)
                throw new IllegalArgumentException("dialog match requires explicit text or resource ID rules");
            if (!dialogMatchEnabled && (hasDialogTerms || dialogNotify))
                throw new IllegalArgumentException("dialog rules and feedback require dialog_match=1");
            if (toastFilterEnabled && toastTextTerms.isEmpty())
                throw new IllegalArgumentException("toast filtering requires explicit text rules");
            if (!toastFilterEnabled && !toastTextTerms.isEmpty())
                throw new IllegalArgumentException("toast text rules require toast_filter=1");
            if (FxDiaKeyGesturePolicy.hasOverlappingTriggers(keyFinishTrigger, keyDialogToggleTrigger))
                throw new IllegalArgumentException("Dia key actions have overlapping gesture triggers");
            if (keyDialogToggleTrigger >= 0 && !dialogMatchEnabled)
                throw new IllegalArgumentException("dialog key toggle requires dialog_match=1");
            Target parsedTarget = new Target(splash, feed, overlay, member, targetPrivacy,
                    regionHidden, vpnDetectionHidden, mediaHidden, usageHidden, deviceProfile,
                    exifStrip, clipboardReadBlock, clipboardIsolate, sensorAccel, sensorGyro, sensorLight,
                    sensorMagnet, sensorPressure, sensorProx, sensorEnvironment, sensorFusion, sensorGesture,
                    sensorBiometric, sensorRateLimit, wifiScanBlock, notificationListenBlock,
                    notificationPermissionHide, microphoneSilence, cameraAccessBlock, locationAccessBlock,
                    microphoneAccessBlock, mediaStoreQueryBlock, adIdUnify, customRules,
                    dialogMatchEnabled, dialogNotify, toastFilterEnabled, dialogTextTerms,
                    dialogIdTerms, toastTextTerms, keyFinishTrigger, keyDialogToggleTrigger);
            parsedTarget.vipEntitlementSimulation = vipEntitlementSimulation;
            parsedTarget.vipUnlock = vipUnlock;
            parsedTarget.antiFraudBlock = antiFraudBlock;
            parsedTarget.carrierCollectionBlock = carrierCollectionBlock;
            parsedTarget.policeReconBlock = policeReconBlock;
            parsedTarget.simulatedEntitlementState = simulatedEntitlementState;
            parsedTarget.blockAppUpdate = blockAppUpdate;
            parsedTarget.fakeAppVersion = fakeAppVersion;
            parsedTarget.simulatedAppVersion = simulatedAppVersion;
            parsedTarget.locationSimulation = locationSimulation;
            parsedTarget.locationProviderEnabledSimulation = locationProviderEnabledSimulation;
            if (simulatedLatitude != null) parsedTarget.simulatedLatitude = simulatedLatitude;
            if (simulatedLongitude != null) parsedTarget.simulatedLongitude = simulatedLongitude;
            parsedTarget.simulatedAccuracy = simulatedAccuracy;
            parsedTarget.regionDiag = regionDiag;
            parsedTarget.usageStatsOff = usageStatsOff;
            parsedTarget.a11yHide = a11yHide;
            parsedTarget.audioFpBlock = audioFpBlock;
            parsedTarget.micBlock = micBlock;
            parsedTarget.cameraIdHide = cameraIdHide;
            parsedTarget.blockMediaStore = blockMediaStore;
            parsedTarget.blockImeLogging = blockImeLogging;
            parsedTarget.micHwHide = micHwHide;
            parsedTarget.disablePassiveLocation = disablePassiveLocation;
            parsedTarget.hideFingerprintHw = hideFingerprintHw;
            parsedTarget.hideFaceHw = hideFaceHw;
            parsedTarget.wifiScanHide = wifiScanHide;
            parsedTarget.cellInfoHide = cellInfoHide;
            targets.put(pkg, parsedTarget);
        }

        if (!schemaSeen || !adsSeen || !privacySeen || !targetsSectionSeen)
            throw new IllegalArgumentException("missing required schema fields");
        return new Result(ads, privacy, systemServicesEnabled, systemServices,
                pmQueryEnabled, appListEnabled, appListMode, hiddenApps, keptApps, targets);
    }


    private static String decodeDiaTerms(String encoded) {
        if (encoded == null) return null;
        if (encoded.isEmpty()) return "";
        final byte[] decoded;
        try {
            decoded = java.util.Base64.getUrlDecoder().decode(encoded);
        } catch (IllegalArgumentException malformed) {
            throw new IllegalArgumentException("invalid encoded Dia rule text");
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(decoded)).toString();
        } catch (CharacterCodingException malformed) {
            throw new IllegalArgumentException("Dia rules must be valid UTF-8");
        }
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
            targets.put(pkg, new Target(splash, feed, overlay, member, false, false, false, false, false, false, Collections.emptyMap()));
        }
        if (!masterSeen || !sectionSeen) throw new IllegalArgumentException("missing legacy fields");
        return new Result(ads, false, false, Collections.<String>emptySet(),
                false, false, "custom", Collections.<String>emptySet(), Collections.<String>emptySet(), targets);
    }

    /** Rules use category:token;category:token. Tokens match lower-cased class/resource names only. */
    private static Map<String, Set<String>> parseCustomRules(String value) {
        Map<String, Set<String>> rules = new LinkedHashMap<>();
        if (value.isEmpty()) return rules;
        for (String item : value.split(";", -1)) {
            int colon = item.indexOf(':');
            if (colon < 1 || colon == item.length() - 1)
                throw new IllegalArgumentException("malformed custom rule");
            String category = item.substring(0, colon).trim();
            String token = item.substring(colon + 1).trim().toLowerCase(java.util.Locale.ROOT);
            if (!("splash".equals(category) || "feed".equals(category) || "overlay".equals(category)))
                throw new IllegalArgumentException("unsupported custom rule category");
            if (!token.matches("[a-z0-9_.-]{3,100}"))
                throw new IllegalArgumentException("invalid custom rule token");
            Set<String> values = rules.computeIfAbsent(category, k -> new HashSet<>());
            if (!values.add(token)) throw new IllegalArgumentException("duplicate custom rule");
        }
        return rules;
    }

    private static boolean bit(String value) {
        return "0".equals(value) || "1".equals(value);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }
}
