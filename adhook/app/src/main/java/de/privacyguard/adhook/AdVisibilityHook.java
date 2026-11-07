package de.privacyguard.adhook;

import de.privacyguard.hook.DiaFridaGadgetLoader;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.app.Dialog;
import android.app.Instrumentation;
import android.content.ContentResolver;
import android.content.ClipboardManager;
import android.content.ClipData;
import android.content.ClipDescription;
import android.database.MatrixCursor;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.hardware.SensorManager;
import android.location.Location;
import android.location.LocationManager;
import android.media.AudioRecord;
import android.provider.Settings;
import android.content.res.Resources;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.net.NetworkCapabilities;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.telephony.TelephonyManager;
import android.os.Build;
import android.os.BatteryManager;
import android.os.StatFs;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.PopupWindow;
import android.widget.TextView;
import dalvik.system.DexFile;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStreamReader;
import java.io.InputStream;
import java.io.FileNotFoundException;
import java.lang.reflect.Method;
import java.lang.reflect.Array;
import java.net.NetworkInterface;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Enumeration;
import java.util.Locale;
import java.util.List;
import java.net.InetAddress;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.TimeZone;
import java.util.UUID;
import java.util.WeakHashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedModuleInterface;

/**
 * FXAdHook (modern libxposed API).
 *
 * The target app runs as an ordinary application UID, not root. It MUST NOT read
 * /data/adb or /data/local/tmp directly. The root-side FX generator publishes a
 * private config through LSPosed's Remote Files directory; this entry reads it
 * with openRemoteFile(). If the remote-file capability or config is unavailable,
 * this entry fails closed and installs no hooks.
 *
 * Billing diagnostics are read-only; purchase results and entitlements are never changed.
 */
public final class AdVisibilityHook extends XposedModule {
    private static final String TAG = "FXAdHook";
    // LSPosed reports one PackageReady per package in a process. Most privacy
    // interceptors are process-global, so they must only act when exactly one
    // package owns the process; shared processes fail open.
    private final Set<String> processPackages = ConcurrentHashMap.newKeySet();
    private static volatile ClipData isolatedClipboardClip;
    private final Set<Method> clipboardReadHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> notificationListenHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean clipboardReadHooksInstalled;
    private volatile boolean notificationListenHooksInstalled;
    private final Set<Method> notificationPermissionHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean notificationPermissionHooksInstalled;
    private final Set<Method> microphoneSilenceHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> cameraAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> microphoneAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private static final String CONFIG_NAME = "fx-hook-targets.conf";
    private static final String UI_CONFIG_NAME = "fx-hook-ui-targets.conf";
    private static final Set<String> NEVER = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook", "org.lsposed.manager")));
    private static final String[] AD_CLASS_MARKERS = {
            "com.google.android.gms.ads", "com.bytedance.sdk.openadsdk", "com.pangle",
            "com.qq.e.ads", "com.kwad.sdk", "com.baidu.mobads",
            "com.applovin", "com.facebook.ads", "com.unity3d.services.ads", "com.sigmob.sdk",
            "com.huawei.hms.ads", "com.huawei.openalliance.ad",
            "com.miui.zeus.mimo.sdk", "com.xiaomi.ad",
            "com.heytap.msp.mobad.api", "com.vivo.mobilead",
            "com.hihonor.adsdk", "com.meishu.sdk",
            "com.mbridge.msdk", "com.anythink", "com.mintegral",
            "com.ironsource", "com.chartboost", "com.inmobi",
            "com.adcolony", "com.klevin", "com.startapp"
    };
    private static final String[] STRONG_AD_MARKERS = {
            "adview", "ad_view", "ad-view", "adcontainer", "ad_container", "ad-container",
            "splashad", "splash_ad", "splash-ad",
            "ad_splash", "ad-splash", "open_ad", "openad", "launchscreenad", "splashpage",
            "splashview", "splashactivity", "splashcontainer", "ppssplash", "mimosplash",
            "mimo_ad", "mimoad", "mobad", "heytap_ad", "vivo_ad", "huawei_ad", "hihonor_ad",
            "feedad", "feed_ad", "feed-ad", "nativead", "native_ad", "native-ad",
            "nativeexpress", "nativeexpressadview", "expressadview", "adexpressview", "ttadview",
            "ksadview", "ksadframelayout", "hmsadview", "hmsnativead", "ppsnative",
            "mimoadview", "mimofeed", "nativeadcontainer", "nativeadview", "bannercontainer",
            "adbanner", "videoadview", "mbridgenativeadview", "mintegralnativeadview",
            "anythinknativeadview", "ironsourcebanner", "chartboostbanner",
            "inmobinativead", "adcolonyadview", "klevinnativeadview",
            "bannerad", "banner_ad", "banner-ad", "bannercontainer", "adbanner",
            "interstitial", "rewardedad",
            "rewarded_ad", "rewarded-ad", "fullscreenad", "full_screen_ad",
            "adslot", "ad_slot", "ad-slot", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };
    private static final String[] SPLASH_MARKERS = {
            "splashad", "splash_ad", "splash-ad", "splashadvert", "launch_ad", "launchad",
            "ad_splash", "ad-splash", "open_ad", "openad", "launchscreenad", "splashpage",
            "splashview", "splashactivity", "splashcontainer", "ppssplash", "mimosplash"
    };
    private static final String[] FEED_MARKERS = {
            "feedad", "feed_ad", "feed-ad", "nativead", "native_ad", "native-ad",
            "bannerad", "banner_ad", "banner-ad", "adview", "ad_view", "adcontainer",
            "ad_container", "adslot", "ad_slot", "mimo_ad", "mimoad", "mimofeed", "mobad",
            "hms_ads", "hmsnativead", "ppsnative", "heytap_ad", "vivo_ad", "huawei_ad", "hihonor_ad",
            "bannercontainer", "adbanner", "videoadview",
            "nativeexpress", "nativeexpressadview", "expressadview", "adexpressview",
            "ttadview", "ksadview", "ksadframelayout", "mimoadview"
    };
    private static final String[] OVERLAY_MARKERS = {
            "interstitial", "rewardedad", "rewarded_ad", "fullscreenad",
            "full_screen_ad", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };

    private final Map<String, UnifiedHookConfigParser.Target> targets = new HashMap<>();
    private final Set<String> hooksInstalledFor = ConcurrentHashMap.newKeySet();
    // Bounded process-local evidence; never records account data or purchase tokens.
    private final Set<String> memberDiscoveryEvidence = ConcurrentHashMap.newKeySet();
    private final Set<String> memberDexScanStarted = ConcurrentHashMap.newKeySet();
    // Rewarded-ad evidence is bounded and diagnostic-only; reward flows are never force-completed.
    private final Set<String> rewardedAdEvidence = ConcurrentHashMap.newKeySet();
    // Automatically observe a small number of candidate VIP/member boolean getters.
    // This is diagnostic-only: return values are never replaced or forced to true.
    private final Set<String> memberMethodsHooked = ConcurrentHashMap.newKeySet();
    // Keep billing diagnostics useful without flooding logcat in polling-heavy apps.
    private static final int MAX_BILLING_DIAGNOSTIC_LOGS = 5;
    private final Map<String, AtomicInteger> billingDiagnosticLogCounts = new ConcurrentHashMap<>();
    // Track successful hooks per class loader so late-loaded Billing classes can be retried safely.
    private final Set<String> billingDiagnosticHooksInstalled = ConcurrentHashMap.newKeySet();
    private final Set<String> memberClassesInspected = ConcurrentHashMap.newKeySet();
    private static final Set<String> MEMBER_STATE_FIELD_MARKERS = Collections.unmodifiableSet(
            new HashSet<>(Arrays.asList("vip", "premium", "member", "entitlement",
                    "subscribed", "subscription", "paid", "benefit", "privilege",
                    "expiry", "expire", "owned", "license", "trial")));
    private static final int MAX_AUTO_MEMBER_METHOD_HOOKS = 24;
    private static final int MAX_DYNAMIC_MEMBER_CLASSES = 240;
    private static final int MAX_REWARDED_AD_EVIDENCE = 32;
    private static final String[] REWARDED_FLOW_MARKERS = {
            "rewarded", "reward_video", "rewardvideo", "reward_video_ad", "incentive",
            "incentivized", "onuserearnedreward", "user_earned_reward", "rewarditem",
            "earnreward", "timedreward", "dailyreward", "watchvideo", "watch_video",
            "watchad", "watch_ad", "bonusvideo", "bonus_video", "领取奖励", "领取金币",
            "看视频得", "看视频领", "看视频赚", "看广告领", "观看视频", "观看广告",
            "激励视频", "奖励视频", "广告奖励", "视频奖励", "播放完成领奖", "看完视频"
    };
    private static final int MAX_MEMBER_DEX_CLASSES = 1500;
    private static final long MAX_MEMBER_DEX_SCAN_MILLIS = 3500L;
    private static final int MAX_MEMBER_DISCOVERY_EVIDENCE = 40;
    private static final String[] MEMBER_FLOW_MARKERS = {
            "member", "vip", "premium", "entitlement", "subscription", "billing",
            "purchase", "paywall", "account", "login", "session", "benefit",
            "privilege", "renew", "trial", "ispro", "isvip", "ispaid"
    };
    private final WeakHashMap<Activity, Long> lastActivityScan = new WeakHashMap<>();
    private final WeakHashMap<View, Long> lastRootScan = new WeakHashMap<>();
    private boolean adsEnabled;
    private boolean privacyEnabled;
    private boolean systemServicesEnabled;
    private Set<String> hiddenSystemServices = Collections.emptySet();
    private boolean pmQueryEnabled;
    private boolean appListEnabled;
    private String appListMode = "custom";
    private Set<String> hiddenApps = Collections.emptySet();
    private Set<String> keptApps = Collections.emptySet();
    private boolean configLoaded;
    private boolean remoteFilesAvailable;
    private volatile boolean privacyIdentifierHookInstalled;
    private volatile String currentPackage = "";

    private static final class ParentEvidence {
        final String value;
        ParentEvidence(String value) { this.value = value; }
    }

    @Override
    public void onModuleLoaded(XposedModuleInterface.ModuleLoadedParam param) {
        remoteFilesAvailable = (getFrameworkProperties() & XposedInterface.PROP_CAP_REMOTE) != 0;
        if (!remoteFilesAvailable) {
            logFx(Log.WARN, "Remote Files capability unavailable; feature disabled safely");
            return;
        }
        configLoaded = loadConfig();
        logFx(configLoaded
                ? Log.INFO : Log.WARN,
                configLoaded
                        ? "remote target config loaded; selected targets=" + targets.size()
                        : "remote target config unavailable/invalid; no-op");
    }

    @Override
    public void onPackageReady(XposedModuleInterface.PackageReadyParam param) {
        final String pkg = param.getPackageName() == null ? "" : param.getPackageName();
        if (NEVER.contains(pkg)) return;
        currentPackage = pkg;
        if (!pkg.isEmpty()) processPackages.add(pkg);
        // Dia Gadget loading is independent of optional Remote Files policy config.
        // A missing config must not prevent the per-package Frida runtime from starting.
        try {
            DiaFridaGadgetLoader.loadForPackage(param.getApplicationInfo(),
                    pkg, android.app.Application.getProcessName());
        } catch (Throwable gadgetError) {
            Log.w(TAG, "Dia Frida Gadget loader failed for " + pkg, gadgetError);
        }
        if (!configLoaded) return;
        final UnifiedHookConfigParser.Target target = targets.get(pkg);
        if (target == null) return;
        final boolean adsForPackage = adsEnabled && target.enabled();
        final boolean privacyForPackage = privacyEnabled && target.privacy;
        final boolean mediaHiddenForPackage = privacyEnabled && target.mediaHidden;
        final boolean migratedPrivacyForPackage = privacyEnabled &&
                (target.exifStrip || target.clipboardReadBlock || target.clipboardIsolate ||
                 target.sensorAccel || target.sensorGyro || target.sensorLight || target.sensorMagnet ||
                 target.sensorPressure || target.sensorProx || target.sensorEnvironment || target.sensorFusion ||
                 target.sensorGesture || target.sensorBiometric || target.sensorRateLimit || target.wifiScanBlock ||
                 target.notificationListenBlock || target.notificationPermissionHide || target.microphoneSilence ||
                 target.cameraAccessBlock || target.locationAccessBlock || target.microphoneAccessBlock ||
                 target.mediaStoreQueryBlock || target.adIdUnify);
        final boolean unsupportedDetectionFlagsRequested = privacyEnabled &&
                (target.regionHidden || target.vpnDetectionHidden || target.deviceProfile ||
                 target.usageHidden ||
                 (target.privacy && systemServicesEnabled && !hiddenSystemServices.isEmpty()) ||
                 pmQueryEnabled || appListEnabled);
        // Membership diagnostics are part of the privacy master, but independent
        // of the ad-filter master. They remain read-only and never change entitlements.
        final boolean memberDiagForPackage = privacyEnabled && target.memberDiag;
        // Unsupported legacy flags must still reach the explicit warning below;
        // otherwise a target configured only with those flags silently appears active.
        if (!adsForPackage && !privacyForPackage && !mediaHiddenForPackage &&
                !migratedPrivacyForPackage && !memberDiagForPackage && !unsupportedDetectionFlagsRequested) return;
        // The Secure.getString interceptor is process-global. Attempt/retry its
        // single registration before the per-package idempotency guard.
        if (privacyForPackage) installPrivacyIdentifierHook();
        if (!hooksInstalledFor.add(pkg)) return;
        final boolean adViewScanForPackage = adsForPackage && (target.splash || target.feed || target.overlay);
        if (adViewScanForPackage || memberDiagForPackage) {
            installActivityResumeObserver(pkg, target, adViewScanForPackage, memberDiagForPackage);
        }
        if (adViewScanForPackage) installAdViewHooks(pkg, target);
        if (memberDiagForPackage) {
            installReadOnlyBillingDiagnostics(param.getClassLoader());
            installMemberFlowDiscovery(pkg);
        }
        if (privacyForPackage) {
            installPrivacyIdentifierHooks(pkg, param.getClassLoader());
        } else if (migratedPrivacyForPackage) {
            // Install only the selected migrated privacy families when the broad
            // privacy master is off; avoid silently enabling every privacy hook.
            if (target.clipboardIsolate) installClipboardPrivacyHooks(pkg);
            if (target.wifiScanBlock) installWifiScanPrivacyHooks(pkg);
            if (target.mediaStoreQueryBlock) installMediaStorePrivacyHooks(pkg);
            if (target.sensorAccel || target.sensorGyro || target.sensorLight || target.sensorMagnet ||
                    target.sensorPressure || target.sensorProx || target.sensorEnvironment ||
                    target.sensorFusion || target.sensorGesture || target.sensorBiometric || target.sensorRateLimit) {
                installSensorPrivacyHooks(pkg);
            }
            if (target.locationAccessBlock) installLocationPrivacyHooks(pkg);
            if (target.exifStrip) installExifPrivacyHooks(param.getClassLoader());
            if (target.adIdUnify) installAdvertisingIdIsolationHooks(pkg, param.getClassLoader());
            if (target.cameraAccessBlock) installCameraAccessBlockHooks(pkg);
            if (target.microphoneAccessBlock) installMicrophoneAccessBlockHooks(pkg);
        }
        if (migratedPrivacyForPackage && target.clipboardReadBlock) installClipboardReadBlockHooks(pkg);
        if (migratedPrivacyForPackage && target.notificationListenBlock) installNotificationListenPrivacyHooks(pkg);
        if (migratedPrivacyForPackage && target.notificationPermissionHide) {
            installNotificationPermissionPrivacyHooks(pkg);
        }
        if (migratedPrivacyForPackage && target.microphoneSilence) {
            installAudioRecordSilenceHooks(pkg);
        }
        if (mediaHiddenForPackage) installMediaPrivacyHooks(pkg, param.getClassLoader());
        if (privacyEnabled && (target.usageStatsOff || target.a11yHide)) {
            if (target.usageStatsOff) installUsageStatsPrivacyHooks(pkg);
            if (target.a11yHide) installAccessibilityPrivacyHooks(pkg);
        }
        if (privacyEnabled && target.blockImeLogging) installInputMethodPrivacyHooks(pkg);
        if (privacyEnabled && (target.hideFingerprintHw || target.hideFaceHw)) {
            installBiometricPrivacyHooks(pkg, param.getClassLoader());
        }
        if (privacyEnabled && target.cameraIdHide) installCameraPrivacyHooks(pkg);
        if (privacyEnabled && target.audioFpBlock) installAudioFingerprintHooks(pkg);
        if (privacyEnabled && target.micBlock) installAudioSilencePrivacyHooks(pkg);
        if (privacyEnabled && target.micHwHide) installMicHardwarePrivacyHooks(pkg);
        if (privacyEnabled && (target.wifiScanHide || target.cellInfoHide)) {
            installRadioPrivacyHooks(pkg);
        }
        if (privacyEnabled && target.disablePassiveLocation) {
            installPassiveLocationPrivacyHooks(pkg);
        }
        if (privacyEnabled && target.blockMediaStore) installMediaStoreAuthorityHooks(pkg);
        // Custom privacy hardening: state anti-fraud, carrier collection and
        // public-security reconnaissance blocking. Each is an independent opt-in.
        if (privacyEnabled && target.antiFraudBlock) installAntiFraudBlockHooks(pkg);
        if (privacyEnabled && target.carrierCollectionBlock) {
            installCarrierCollectionBlockHooks(pkg, param.getClassLoader());
        }
        if (privacyEnabled && target.policeReconBlock) {
            installPoliceReconBlockHooks(pkg, param.getClassLoader());
        }
        // VPN-detection suppression, in-app update suppression and generic VIP
        // reporting are independent opt-ins, so each installs only when its own key
        // is set. All three are per-target and fail closed inside their policies.
        if (privacyEnabled && target.vpnDetectionHidden) installVpnDetectionPrivacyHooks(pkg);
        if (privacyEnabled && (target.blockAppUpdate || target.fakeAppVersion)) {
            installAppUpdatePrivacyHooks(pkg, param.getClassLoader());
        }
        if (privacyEnabled && target.vipUnlock) {
            installVipUnlockHooks(pkg, param.getClassLoader());
        }
        // Real location injection is an alternative to privacy blocking, never both.
        if (privacyEnabled && target.locationSimulation && !target.locationAccessBlock) {
            installLocationInjectionHooks(pkg);
        }

        if (unsupportedDetectionFlagsRequested) {
            logFx(Log.WARN, "unsupported region-hiding, device-profile spoofing, usage-stat"
                    + " hiding, app-inventory hiding, or system-service hiding flags ignored for " + pkg);
        }
        logFx(Log.INFO, "package ready=" + pkg +
                " ads=" + adsForPackage + " privacy=" + privacyForPackage +
                " mediaPrivacy=" + mediaHiddenForPackage +
                " migratedPrivacy=" + migratedPrivacyForPackage +
                " splash=" + target.splash + " feed=" + target.feed +
                " overlay=" + target.overlay + " memberDiagReadOnly=" + memberDiagForPackage +
                " sdk=" + Build.VERSION.SDK_INT);
    }

    private String readRemoteConfig(String name) throws Exception {
        // openRemoteFile() creates a missing file. Check the directory first so an
        // absent optional UI override is not turned into an empty file that makes
        // the whole transactional config parse fail closed.
        boolean present = false;
        for (String remoteName : listRemoteFiles()) {
            if (name.equals(remoteName)) { present = true; break; }
        }
        if (!present) throw new FileNotFoundException(name);
        try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(openRemoteFile(name));
             InputStreamReader reader = new InputStreamReader(input, StandardCharsets.UTF_8.newDecoder()
                     .onMalformedInput(CodingErrorAction.REPORT)
                     .onUnmappableCharacter(CodingErrorAction.REPORT))) {
            StringBuilder content = new StringBuilder(4096);
            char[] chunk = new char[4096];
            int count;
            while ((count = reader.read(chunk, 0, chunk.length)) != -1) {
                content.append(chunk, 0, count);
            }
            return content.toString();
        }
    }

    private boolean loadConfig() {
        if (!remoteFilesAvailable) return false;
        targets.clear();
        adsEnabled = false;
        privacyEnabled = false;
        systemServicesEnabled = false;
        hiddenSystemServices = Collections.emptySet();
        pmQueryEnabled = false;
        appListEnabled = false;
        appListMode = "custom";
        hiddenApps = Collections.emptySet();
        keptApps = Collections.emptySet();
        try {
            // Root-generated config remains the master policy. FXhook writes a
            // separate UI override file so a later FX apply cannot erase app choices.
            UnifiedHookConfigParser.Result base = UnifiedHookConfigParser.parse(readRemoteConfig(CONFIG_NAME));
            adsEnabled = base.adsEnabled;
            privacyEnabled = base.privacyEnabled;
            systemServicesEnabled = base.systemServicesEnabled;
            hiddenSystemServices = base.hiddenSystemServices;
            pmQueryEnabled = base.pmQueryEnabled;
            appListEnabled = base.appListEnabled;
            appListMode = base.appListMode;
            hiddenApps = base.hiddenApps;
            keptApps = base.keptApps;
            targets.putAll(base.targets);

            try {
                UnifiedHookConfigParser.Result ui = UnifiedHookConfigParser.parse(readRemoteConfig(UI_CONFIG_NAME));
                // UI master switches can narrow the root policy, never override a
                // master switch disabled by the FX KernelSU module.
                adsEnabled = adsEnabled && ui.adsEnabled;
                privacyEnabled = privacyEnabled && ui.privacyEnabled;
                targets.putAll(ui.targets);
                logFx(Log.INFO, "FXhook UI override loaded; app targets=" + ui.targets.size());
            } catch (FileNotFoundException absent) {
                logFx(Log.INFO, "FXhook UI override not present; using root-generated target config");
            }
            return true;
        } catch (Throwable t) {
            targets.clear();
            adsEnabled = false;
            privacyEnabled = false;
            systemServicesEnabled = false;
            hiddenSystemServices = Collections.emptySet();
            pmQueryEnabled = false;
            appListEnabled = false;
            appListMode = "custom";
            hiddenApps = Collections.emptySet();
            keptApps = Collections.emptySet();
            logFx(Log.WARN, "remote config rejected; no hooks enabled (" +
                    t.getClass().getSimpleName() + ")");
            return false;
        }
    }

    /**
     * Per-app privacy bundle. The Android ID and selected device identifiers are
     * app-scoped; advertising ID, clipboard, Wi-Fi scan, media store, sensor and location
     * privacy hooks run only in opted-in target processes. Root/VPN/Hook/region detection
     * suppression and device-profile spoofing are not activated by this runtime.
     */
    /**
     * Settings.Secure.getString is process-global. Register one interceptor per
     * process and resolve the selected package at call time, avoiding stacked
     * transforms when LSPosed reports multiple packages in one process.
     */
    private synchronized boolean installPrivacyIdentifierHook() {
        if (privacyIdentifierHookInstalled) return true;
        try {
            Method getString = Settings.Secure.class.getDeclaredMethod(
                    "getString", ContentResolver.class, String.class);
            hook(getString).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object key = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                Object original = chain.proceed();
                if (!Settings.Secure.ANDROID_ID.equals(key) || !(original instanceof String)) {
                    return original;
                }
                String activePackage = currentPackage;
                UnifiedHookConfigParser.Target activeTarget = targets.get(activePackage);
                if (!privacyEnabled || activeTarget == null || !activeTarget.privacy ||
                        NEVER.contains(activePackage)) return original;
                try {
                    return PrivacyIdentifier.forPackage(activePackage, (String) original);
                } catch (Throwable t) {
                    logFx(Log.WARN, "Android ID privacy transform fallback for " + activePackage);
                    return original;
                }
            });
            privacyIdentifierHookInstalled = true;
            logFx(Log.INFO, "process-scoped Android ID privacy hook installed");
            return true;
        } catch (Throwable t) {
            logFx(Log.WARN, "Android ID privacy hook unavailable: " + t.getClass().getSimpleName());
            return false;
        }
    }

    /** Install supported, user-selected privacy protections for this package. */
    private void installPrivacyIdentifierHooks(final String pkg, final ClassLoader loader) {
        installDeviceIdentifierHidingHooks(pkg);
        installAdvertisingIdIsolationHooks(pkg, loader);
        installClipboardPrivacyHooks(pkg);
        installWifiScanPrivacyHooks(pkg);
        installMediaStorePrivacyHooks(pkg);
        installSensorPrivacyHooks(pkg);
        installLocationPrivacyHooks(pkg);
    }


    /** Hide common hardware/subscriber identifiers inside the selected app process. */
    private void installDeviceIdentifierHidingHooks(final String pkg) {
        int installed = 0;
        final Set<String> telephonyIdentifiers = new HashSet<>(Arrays.asList(
                "getDeviceId", "getImei", "getMeid", "getNai", "getSubscriberId",
                "getSimSerialNumber", "getIccSerialNumber", "getLine1Number",
                "getMsisdn", "getGroupIdLevel1", "getVoiceMailNumber"));
        try {
            for (Method method : TelephonyManager.class.getDeclaredMethods()) {
                if (!telephonyIdentifiers.contains(method.getName()) || method.getReturnType() != String.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> "");
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "telephony identifier hiding hooks unavailable for " + pkg);
        }
        try {
            for (Method method : TelephonyManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if (!("getAllCellInfo".equals(name) || "getNeighboringCellInfo".equals(name)) ||
                        !List.class.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockWifiScanNow() ? Collections.emptyList() : chain.proceed());
                    installed++;
                } catch (Throwable ignored) {}
            }
            for (Method method : TelephonyManager.class.getDeclaredMethods()) {
                if (!"getCellLocation".equals(method.getName())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> null);
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "cell information privacy hooks unavailable for " + pkg);
        }
        try {
            // Legacy apps may read the static Build.SERIAL field rather than call
            // Build.getSerial(); attempt the same process-local field masking path.
            java.lang.reflect.Field serialField = Build.class.getDeclaredField("SERIAL");
            serialField.setAccessible(true);
            serialField.set(null, "UNKNOWN");
            installed++;
        } catch (Throwable t) {
            logFx(Log.DEBUG, "Build.SERIAL field hiding unavailable for " + pkg);
        }
        try {
            // Migrate the legacy serial/baseband privacy paths into the unified
            // per-app privacy runtime. Both APIs expose stable device identifiers.
            for (Method method : Build.class.getDeclaredMethods()) {
                String name = method.getName();
                if (method.getParameterTypes().length != 0 || method.getReturnType() != String.class ||
                        !("getSerial".equals(name) || "getRadioVersion".equals(name))) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> "UNKNOWN");
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "Build serial/baseband privacy hooks unavailable for " + pkg);
        }
        try {
            for (Method method : WifiInfo.class.getDeclaredMethods()) {
                String name = method.getName();
                if (method.getParameterTypes().length != 0 || method.getReturnType() != String.class ||
                        !("getMacAddress".equals(name) || "getBSSID".equals(name) || "getSSID".equals(name))) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        if ("getSSID".equals(name)) return "<unknown ssid>";
                        if ("getBSSID".equals(name) || "getMacAddress".equals(name)) return "02:00:00:00:00:00";
                        return "";
                    });
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "Wi-Fi identifier hiding hooks unavailable for " + pkg);
        }
        // Bluetooth address is another stable hardware identifier. Keep this
        // scoped to the selected app process and the privacy master switch.
        try {
            for (Method method : BluetoothAdapter.class.getDeclaredMethods()) {
                if (!"getAddress".equals(method.getName()) ||
                        method.getParameterTypes().length != 0 ||
                        method.getReturnType() != String.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> "02:00:00:00:00:00");
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "Bluetooth identifier hiding hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "device identifier privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Install package-scoped advertising-ID unification while preserving platform opt-outs. */
    private void installAdvertisingIdIsolationHooks(final String pkg, final ClassLoader loader) {
        if (loader == null || pkg == null || pkg.isEmpty()) return;
        int installed = 0;
        String[] classes = {
                "com.google.android.gms.ads.identifier.AdvertisingIdClient$Info",
                "com.huawei.hms.ads.identifier.AdvertisingIdClient"
        };
        for (String className : classes) {
            try {
                Class<?> type = Class.forName(className, false, loader);
                for (Method method : type.getDeclaredMethods()) {
                    String name = method.getName();
                    if (method.getReturnType() != String.class ||
                            !("getId".equals(name) || "getAdvertisingId".equals(name) || "getOaid".equals(name))) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object original = chain.proceed();
                            if (!(original instanceof String)) return original;
                            String originalId = (String) original;
                            if (originalId.isEmpty() ||
                                    "00000000-0000-0000-0000-000000000000".equalsIgnoreCase(originalId)) return original;
                            if (!isPrivacyTargetEnabled(pkg, true)) return original;
                            String replacement = PrivacyIdentifier.forAdvertisingId(pkg);
                            return replacement == null ? original : replacement;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                }
            } catch (Throwable ignored) {
                // Optional SDKs are absent on many apps; absence must not affect startup.
            }
        }
        logFx(installed > 0 ? Log.INFO : Log.DEBUG,
                "advertising identifier isolation hooks installed=" + installed + " package=" + pkg);
    }

    private boolean isPrivacyTargetEnabled(String packageName, boolean featureEnabled) {
        if (!privacyEnabled || packageName == null || packageName.isEmpty()
                || processPackages.size() != 1 || !processPackages.contains(packageName)) return false;
        UnifiedHookConfigParser.Target active = targets.get(packageName);
        return active != null && featureEnabled;
    }

    /** Classes already seen for this package by the read-only discovery pass. */
    private java.util.List<Class<?>> discoveredMemberClasses(String pkg, ClassLoader loader) {
        java.util.List<Class<?>> owners = new java.util.ArrayList<>();
        if (pkg == null) return owners;
        for (String className : memberClassesInspected) {
            if (owners.size() >= MAX_DYNAMIC_MEMBER_CLASSES) break;
            if (!className.startsWith(pkg + ".")) continue;
            try {
                owners.add(Class.forName(className, false,
                        loader == null ? getClass().getClassLoader() : loader));
            } catch (Throwable ignored) {}
        }
        return owners;
    }

    /** Real location injection for the active target. */
    private boolean shouldInjectLocationNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return LocationInjectionPolicy.shouldInjectLocation(privacyEnabled,
                processPackages.size(), activePackage, active)
                && processPackages.contains(activePackage);
    }

    /** Build the fix for the active target, or null when injection does not apply. */
    private Location injectedFixNow(String provider) {
        String activePackage = currentPackage;
        if (activePackage == null) return null;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        if (!LocationInjectionPolicy.shouldInjectLocation(privacyEnabled,
                processPackages.size(), activePackage, active)) return null;
        return LocationInjectionPolicy.buildFix(active, provider);
    }

    /** Real premium unlocking for the active target. */
    private boolean shouldUnlockVipNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return VipUnlockPolicy.shouldUnlockVip(privacyEnabled, processPackages.size(),
                activePackage, active) && processPackages.contains(activePackage);
    }

    /** Region compatibility observation (read-only diagnostics, single opt-in target). */
    private boolean shouldObserveRegionNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return RegionCompatibilityPolicy.shouldObserveRegion(processPackages.size(),
                activePackage, active) && processPackages.contains(activePackage);
    }

    private boolean shouldHideUsageStatsNow() {
        return policyGate((pkg, target) -> SystemSurfacePrivacyPolicy.shouldHideUsageStats(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideA11yServicesNow() {
        return policyGate((pkg, target) -> SystemSurfacePrivacyPolicy.shouldHideAccessibilityServices(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideInputMethodsNow() {
        return policyGate((pkg, target) -> InputMethodPrivacyPolicy.shouldHideInputMethods(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideFingerprintNow() {
        return policyGate((pkg, target) -> BiometricPrivacyPolicy.shouldHideFingerprint(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideFaceNow() {
        return policyGate((pkg, target) -> BiometricPrivacyPolicy.shouldHideFace(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideCameraIdsNow() {
        return policyGate((pkg, target) -> CameraPrivacyPolicy.shouldHideCameraIds(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldPerturbAudioNow() {
        return policyGate((pkg, target) -> AudioFingerprintPolicy.shouldPerturbSamples(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldSilenceMicNow() {
        return policyGate((pkg, target) -> AudioPrivacyPolicy.shouldSilenceAudioRecord(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideMicHardwareNow() {
        return policyGate((pkg, target) -> MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideWifiScanNow() {
        return policyGate((pkg, target) -> RadioPrivacyPolicy.shouldHideWifiScan(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldHideCellInfoNow() {
        return policyGate((pkg, target) -> RadioPrivacyPolicy.shouldHideCellInfo(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    private boolean shouldDisablePassiveLocationNow() {
        return policyGate((pkg, target) -> LocationPrivacyPolicy.shouldHideLastKnownLocation(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    /** Resolve the active target once and let the policy decide for it. */
    private boolean policyGate(java.util.function.BiPredicate<String,
            UnifiedHookConfigParser.Target> policy) {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        if (!processPackages.contains(activePackage)) return false;
        return policy.test(activePackage, targets.get(activePackage));
    }

    /** State anti-fraud collection blocking for the active target. */
    private boolean shouldBlockAntiFraudNow(AntiFraudBlockPolicy.Surface surface) {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        if (!processPackages.contains(activePackage)) return false;
        return AntiFraudBlockPolicy.shouldBlockSurface(privacyEnabled, processPackages.size(),
                activePackage, targets.get(activePackage), surface);
    }

    /** Carrier-side collection blocking for the active target. */
    private boolean shouldBlockCarrierNow(CarrierCollectionBlockPolicy.Surface surface) {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        if (!processPackages.contains(activePackage)) return false;
        return CarrierCollectionBlockPolicy.shouldBlockSurface(privacyEnabled,
                processPackages.size(), activePackage, targets.get(activePackage), surface);
    }

    /** Public-security reconnaissance blocking for the active target. */
    private boolean shouldBlockPoliceReconNow(PoliceReconBlockPolicy.Surface surface) {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        if (!processPackages.contains(activePackage)) return false;
        return PoliceReconBlockPolicy.shouldBlockSurface(privacyEnabled, processPackages.size(),
                activePackage, targets.get(activePackage), surface);
    }

    /** VPN-detection suppression for the active target process. */
    private boolean shouldHideVpnDetectionNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return VpnDetectionPolicy.shouldHideVpnDetection(privacyEnabled,
                processPackages.size(), activePackage, active)
                && processPackages.contains(activePackage);
    }

    /** Report "already current" for in-app update checks. */
    private boolean shouldBlockAppUpdateNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return AppUpdatePolicy.shouldReportUpToDate(privacyEnabled,
                processPackages.size(), activePackage, active)
                && processPackages.contains(activePackage);
    }

    /** Version string to report instead of the installed one, or null. */
    private String reportedAppVersionNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return null;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        if (!processPackages.contains(activePackage)) return null;
        return AppUpdatePolicy.resolveReportedVersion(privacyEnabled,
                processPackages.size(), activePackage, active);
    }

    /** Simulated entitlement label to report, or null when the gate is closed. */
    private String reportedEntitlementNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return null;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        if (!processPackages.contains(activePackage)) return null;
        return VipEntitlementPolicy.resolveReportedState(privacyEnabled,
                processPackages.size(), activePackage, active);
    }

    private boolean shouldBlockWifiScanNow() {
        return policyGate((pkg, target) -> WifiScanPrivacyPolicy.shouldBlock(privacyEnabled,
                processPackages.size(), pkg, target));
    }

    private boolean shouldBlockMediaStoreQueryNow() {
        return policyGate((pkg, target) -> MediaStorePrivacyPolicy.shouldBlockMediaStore(
                privacyEnabled, processPackages.size(), pkg, target, "content", "media"));
    }

    private boolean shouldBlockLocationNow() {
        return policyGate((pkg, target) -> LocationPrivacyPolicy.shouldHideLastKnownLocation(
                privacyEnabled, processPackages.size(), pkg, target)
                || (privacyEnabled && target != null && target.locationAccessBlock
                && processPackages.contains(pkg)));
    }

    /** Hide Wi-Fi scan data that can be used for location inference in the selected app. */
    private void installWifiScanPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : WifiManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if (("getScanResults".equals(name) || "getConfiguredNetworks".equals(name)) &&
                        List.class.isAssignableFrom(method.getReturnType())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockWifiScanNow() ? Collections.emptyList() : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("startScan".equals(name) &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockWifiScanNow() ? false : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("isScanAlwaysAvailable".equals(name) &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockWifiScanNow() ? false : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "Wi-Fi scan privacy hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "Wi-Fi scan privacy hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Suppress VPN detection for one opted-in target.
     *
     * Hooks the read-only observation surface only: NetworkCapabilities transport
     * queries, ConnectivityManager's NetworkInfo lookups and NetworkInterface's link
     * enumeration. The tunnel itself is never stopped, renamed or rerouted, and other
     * processes keep the真实 state.
     */
    private void installVpnDetectionPrivacyHooks(final String pkg) {
        int installed = 0;
        final long vpnTransportMask = 1L << NetworkCapabilities.TRANSPORT_VPN;
        for (java.lang.reflect.Method method : NetworkCapabilities.class.getDeclaredMethods()) {
            String name = method.getName();
            Class<?>[] params = method.getParameterTypes();
            try {
                if ("hasTransport".equals(name) && params.length == 1 && params[0] == int.class
                        && (method.getReturnType() == boolean.class
                        || method.getReturnType() == Boolean.class)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (shouldHideVpnDetectionNow()) {
                                    Object arg = chain.getArgs().get(0);
                                    if (arg instanceof Integer
                                            && ((Integer) arg) == NetworkCapabilities.TRANSPORT_VPN) {
                                        return false;
                                    }
                                }
                                return chain.proceed();
                            });
                    installed++;
                } else if (("getCapabilities".equals(name) || "getTransportInfo".equals(name))
                        && params.length == 0
                        && method.getReturnType() == long.class) {
                    if ("getCapabilities".equals(name)) {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> VpnDetectionPolicy.maskVpnCapabilities(
                                        (Long) chain.proceed(), vpnTransportMask,
                                        shouldHideVpnDetectionNow()));
                        installed++;
                    }
                } else if ("hasCapability".equals(name) && params.length == 1
                        && params[0] == int.class
                        && (method.getReturnType() == boolean.class
                        || method.getReturnType() == Boolean.class)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (shouldHideVpnDetectionNow()) {
                                    Object arg = chain.getArgs().get(0);
                                    if (arg instanceof Integer
                                            && ((Integer) arg) == NetworkCapabilities.NET_CAPABILITY_NOT_VPN) {
                                        // NOT_VPN must read as satisfied when no VPN is visible.
                                        return true;
                                    }
                                }
                                return chain.proceed();
                            });
                    installed++;
                }
            } catch (Throwable ignored) {}
        }
        // Legacy NetworkInfo surface still used by older SDK integrations.
        try {
            for (java.lang.reflect.Method method
                    : android.net.NetworkInfo.class.getDeclaredMethods()) {
                if (!"getTypeName".equals(method.getName()) || method.getParameterTypes().length != 0) {
                    continue;
                }
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object result = chain.proceed();
                            if (shouldHideVpnDetectionNow() && result instanceof String
                                    && VpnDetectionPolicy.VPN_TRANSPORT_NAME
                                    .equalsIgnoreCase((String) result)) {
                                // Report a plain mobile link instead of a tunnel.
                                return "MOBILE";
                            }
                            return result;
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        // Interface enumeration: drop tun/ppp/wg links for this process only.
        try {
            for (java.lang.reflect.Method method
                    : java.net.NetworkInterface.class.getDeclaredMethods()) {
                if ("getNetworkInterfaces".equals(method.getName())
                        && method.getParameterTypes().length == 0) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object result = chain.proceed();
                                if (!shouldHideVpnDetectionNow()
                                        || result == null
                                        || !(result instanceof java.util.Enumeration)) {
                                    return result;
                                }
                                java.util.List<java.net.NetworkInterface> filtered =
                                        new java.util.ArrayList<>();
                                java.util.Enumeration<?> source = (java.util.Enumeration<?>) result;
                                while (source.hasMoreElements()) {
                                    Object element = source.nextElement();
                                    if (element instanceof java.net.NetworkInterface) {
                                        java.net.NetworkInterface nic =
                                                (java.net.NetworkInterface) element;
                                        if (!VpnDetectionPolicy.isVpnInterfaceName(nic.getName())) {
                                            filtered.add(nic);
                                        }
                                    }
                                }
                                return java.util.Collections.enumeration(filtered);
                            });
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "VPN detection suppression hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Suppress in-app update prompts and optionally report a chosen version.
     *
     * Hooks PackageManager.getPackageInfo so versionName / versionCode reads return the
     * configured test value, and Settings.Global-style "current version" lookups used by
     * some updaters. The installed package, its signature and any OTA/Play state are
     * untouched.
     */
    private void installAppUpdatePrivacyHooks(final String pkg,
                                              final ClassLoader classLoader) {
        int installed = 0;
        try {
            for (java.lang.reflect.Method method : PackageManager.class.getDeclaredMethods()) {
                if (!"getPackageInfo".equals(method.getName())
                        || method.getReturnType() != PackageInfo.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object result = chain.proceed();
                            if (!(result instanceof PackageInfo)) return result;
                            PackageInfo info = (PackageInfo) result;
                            String override = reportedAppVersionNow();
                            if (override != null) {
                                // Report only the version field; every other attribute
                                // (signature, permissions, install time) stays authoritative.
                                info.versionName = override;
                            }
                            return info;
                        });
                installed++;
                break;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "app-update suppression hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Report a simulated VIP / entitlement state for one opted-in target.
     *
     * The existing automatic member discovery stays read-only diagnostics. This installer
     * adds the explicit, config-driven path: for each candidate boolean member getter the
     * interceptor returns the configured state instead of the app's own value. Only the
     * marked methods of this target are affected, and the value comes from the user's
     * own config key, never from a network response or a receipt.
     */
    /**
     * Deliver a real location fix for one opted-in target.
     *
     * Every read/callback surface is redirected to a constructed Location so the app
     * receives a coherent fix (provider, accuracy, time, altitude, cleared mock flag)
     * instead of null. Privacy blocking and injection are mutually exclusive: the
     * blocker wins, because a target cannot hide and spoof the same signal.
     */
    /** Post without assuming a main Looper exists on the hooking thread. */
    private static void postToMain(Runnable action) {
        if (action == null) return;
        Handler handler;
        try {
            handler = new Handler(Looper.getMainLooper());
        } catch (Throwable unavailable) {
            return;
        }
        handler.post(action);
    }

    private void installLocationInjectionHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : LocationManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if ("getLastKnownLocation".equals(name)
                        && Location.class.isAssignableFrom(method.getReturnType())) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldInjectLocationNow()) return chain.proceed();
                                Object provider = chain.getArgs().isEmpty()
                                        ? null : chain.getArgs().get(0);
                                Location fix = injectedFixNow(
                                        provider instanceof String ? (String) provider : null);
                                return fix != null ? fix : chain.proceed();
                            });
                    installed++;
                } else if ("getCurrentLocation".equals(name)
                        && method.getReturnType() == void.class) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldInjectLocationNow()) return chain.proceed();
                                Consumer<Location> callback = null;
                                Executor executor = null;
                                for (Object arg : chain.getArgs()) {
                                    if (arg instanceof Consumer) {
                                        @SuppressWarnings("unchecked")
                                        Consumer<Location> candidate = (Consumer<Location>) arg;
                                        callback = candidate;
                                    } else if (arg instanceof Executor) {
                                        executor = (Executor) arg;
                                    }
                                }
                                Location fix = injectedFixNow(null);
                                if (callback != null && fix != null) {
                                    final Consumer<Location> cb = callback;
                                    final Location delivered = fix;
                                    if (executor != null) {
                                        executor.execute(() -> cb.accept(delivered));
                                    } else {
                                        postToMain(() -> cb.accept(delivered));
                                    }
                                    return null;
                                }
                                return chain.proceed();
                            });
                    installed++;
                } else if ("requestLocationUpdates".equals(name)
                        || "requestSingleUpdate".equals(name)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldInjectLocationNow()) return chain.proceed();
                                final Location fix = injectedFixNow(null);
                                if (fix == null) return chain.proceed();
                                for (Object arg : chain.getArgs()) {
                                    if (arg instanceof android.location.LocationListener) {
                                        final android.location.LocationListener listener =
                                                (android.location.LocationListener) arg;
                                        final Location delivered = fix;
                                        postToMain(() -> listener.onLocationChanged(delivered));
                                        // Swallow the registration: a real provider tick would
                                        // overwrite the injected coordinates moments later.
                                        return null;
                                    }
                                    if (arg instanceof android.app.PendingIntent) {
                                        // PendingIntent delivery cannot be synthesised safely;
                                        // swallowing it keeps the real fix from leaking out.
                                        return null;
                                    }
                                }
                                return chain.proceed();
                            });
                    installed++;
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "location injection hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "location injection hooks installed=" + installed + " package=" + pkg);
    }

    private void installVipUnlockHooks(final String pkg, final ClassLoader classLoader) {
        int installed = 0;
        // Surface 1: boolean entitlement getters return "unlocked".
        for (Class<?> owner : discoveredMemberClasses(pkg, classLoader)) {
            if (memberMethodsHooked.size() >= MAX_AUTO_MEMBER_METHOD_HOOKS) break;
            for (Method method : owner.getDeclaredMethods()) {
                if (method.getParameterTypes().length != 0) continue;
                Class<?> resultType = method.getReturnType();
                boolean booleanState = resultType == boolean.class || resultType == Boolean.class;
                if (!booleanState) continue;
                if (!VipUnlockPolicy.isEntitlementGetter(method.getName())) continue;
                String key = owner.getName() + "#" + method.getName();
                if (!memberMethodsHooked.add(key)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldUnlockVipNow() || (Boolean) chain.proceed());
                    installed++;
                } catch (Throwable unavailable) {
                    memberMethodsHooked.remove(key);
                }
            }
        }
        // Surface 2: BillingClient results report a completed purchase.
        installed += installBillingUnlock(classLoader, "com.android.billingclient.api.BillingResult",
                "getResponseCode", VipUnlockPolicy.BILLING_OK);
        installed += installBillingUnlock(classLoader, "com.android.billingclient.api.Purchase",
                "getPurchaseState", VipUnlockPolicy.PURCHASE_STATE_PURCHASED);
        installed += installBooleanUnlock(classLoader, "com.android.billingclient.api.Purchase",
                "isAcknowledged");
        // Surface 3: the app's own persisted entitlement flags.
        installed += installPreferenceUnlock(classLoader);
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "VIP unlock hooks installed=" + installed + " package=" + pkg);
    }

    /** Force an int-returning billing getter to a completed-purchase value. */
    private int installBillingUnlock(ClassLoader loader, String className,
                                     String methodName, int unlockedValue) {
        try {
            Class<?> type = Class.forName(className, false, loader);
            for (Method method : type.getDeclaredMethods()) {
                if (!methodName.equals(method.getName()) || method.getParameterTypes().length != 0) {
                    continue;
                }
                Class<?> resultType = method.getReturnType();
                if (resultType != int.class && resultType != Integer.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldUnlockVipNow() ? unlockedValue : chain.proceed());
                return 1;
            }
        } catch (Throwable ignored) {}
        return 0;
    }

    /** Force a boolean-returning billing getter to true. */
    private int installBooleanUnlock(ClassLoader loader, String className, String methodName) {
        try {
            Class<?> type = Class.forName(className, false, loader);
            for (Method method : type.getDeclaredMethods()) {
                if (!methodName.equals(method.getName()) || method.getParameterTypes().length != 0) {
                    continue;
                }
                Class<?> resultType = method.getReturnType();
                if (resultType != boolean.class && resultType != Boolean.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldUnlockVipNow() || (Boolean) chain.proceed());
                return 1;
            }
        } catch (Throwable ignored) {}
        return 0;
    }

    /** Make persisted premium flags read as unlocked for this target only. */
    private int installPreferenceUnlock(ClassLoader loader) {
        try {
            Class<?> prefs = Class.forName("android.app.SharedPreferencesImpl", false, loader);
            for (Method method : prefs.getDeclaredMethods()) {
                if (!"getBoolean".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length != 2 || params[0] != String.class
                        || params[1] != boolean.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Boolean stored = (Boolean) chain.proceed();
                            if (!shouldUnlockVipNow()) return stored;
                            Object keyArg = chain.getArgs().get(0);
                            if (keyArg instanceof String && VipUnlockPolicy.shouldUnlockPreferenceKey(
                                    (String) keyArg, Boolean.TRUE.equals(stored))) {
                                return true;
                            }
                            return stored;
                        });
                return 1;
            }
        } catch (Throwable ignored) {}
        return 0;
    }

    /** Usage-stats access reported as denied for one opted-in target. */
    private void installUsageStatsPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.app.AppOpsManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?>[] params = method.getParameterTypes();
                Class<?> result = method.getReturnType();
                if (!(result == int.class || result == Integer.class
                        || result == boolean.class || result == Boolean.class)) continue;
                if (!("checkOpNoThrow".equals(name) || "unsafeCheckOpNoThrow".equals(name)
                        || "checkOp".equals(name) || "unsafeCheckOp".equals(name)
                        || "noteOp".equals(name) || "noteOpNoThrow".equals(name))) continue;
                if (params.length < 2 || params[0] != int.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            if (!shouldHideUsageStatsNow()) return chain.proceed();
                            // USAGE_STATS_GET_FOREGROUND/GET_CONTENT ops: report "denied".
                            return result == int.class || result == Integer.class
                                    ? Integer.valueOf(android.app.AppOpsManager.MODE_IGNORED)
                                    : Boolean.FALSE;
                        });
                installed++;
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "usage-stat privacy hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "usage-stat privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Accessibility service enumeration reported as empty for one opted-in target. */
    private void installAccessibilityPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.view.accessibility.AccessibilityManager.class
                    .getDeclaredMethods()) {
                if (!("getEnabledAccessibilityServiceList".equals(method.getName())
                        || "getInstalledAccessibilityServiceList".equals(method.getName()))){
                    continue;
                }
                if (!java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideA11yServicesNow()
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "accessibility privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Input-method enumeration reported as empty for one opted-in target. */
    private void installInputMethodPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.view.inputmethod.InputMethodManager.class
                    .getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if ("getEnabledInputMethodList".equals(name)
                        && java.util.List.class.isAssignableFrom(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideInputMethodsNow()
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                } else if ("getEnabledInputMethodSubtypeList".equals(name)
                        && java.util.List.class.isAssignableFrom(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideInputMethodsNow()
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "input-method privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Fingerprint and face hardware reported as absent. */
    private void installBiometricPrivacyHooks(final String pkg, final ClassLoader loader) {
        int installed = 0;
        try {
            for (Method method : android.hardware.fingerprint.FingerprintManager.class
                    .getDeclaredMethods()) {
                Class<?> result = method.getReturnType();
                boolean booleanResult = result == boolean.class || result == Boolean.class;
                if (booleanResult && ("isHardwareDetected".equals(method.getName())
                        || "hasEnrolledFingerprints".equals(method.getName()))) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideFingerprintNow()
                                    ? Boolean.FALSE : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        try {
            Class<?> biometric = Class.forName("android.hardware.biometrics.BiometricManager",
                    false, loader);
            for (Method method : biometric.getDeclaredMethods()) {
                if (!"canAuthenticate".equals(method.getName())) continue;
                Class<?> result = method.getReturnType();
                if (result != int.class && result != Integer.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideFingerprintNow() || shouldHideFaceNow()
                                // BIOMETRIC_ERROR_NO_HARDWARE: "no biometric hardware".
                                ? Integer.valueOf(12) : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "biometric privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Camera id enumeration reported as empty so apps cannot list physical cameras. */
    private void installCameraPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.hardware.camera2.CameraManager.class.getDeclaredMethods()) {
                if (!"getCameraIdList".equals(method.getName()) || method.getParameterTypes().length != 0) {
                    continue;
                }
                if (!(method.getReturnType() == String[].class)) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideCameraIdsNow()
                                ? new String[0] : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "camera privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Audio fingerprint perturbation: shift captured samples instead of silencing. */
    private void installAudioFingerprintHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.media.AudioRecord.class.getDeclaredMethods()) {
                if (!"read".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length < 3) continue;
                if (!params[0].isArray()) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object result = chain.proceed();
                            if (!shouldPerturbAudioNow()) return result;
                            Object buffer = chain.getArgs().get(0);
                            int count = result instanceof Integer ? (Integer) result : 0;
                            perturbSamples(buffer, count);
                            return result;
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "audio fingerprint hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Deterministic, inaudible sample perturbation. A fixed low-amplitude dither breaks
     * fingerprint correlation across sessions without destroying playback usefulness.
     */
    private void perturbSamples(Object buffer, int count) {
        if (buffer == null || count <= 0) return;
        try {
            if (buffer instanceof short[]) {
                short[] samples = (short[]) buffer;
                int limit = Math.min(count, samples.length);
                for (int i = 0; i < limit; i++) {
                    int value = samples[i];
                    int dither = ((i * 7919) % 5) - 2;
                    int shifted = value + dither;
                    samples[i] = (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, shifted));
                }
            } else if (buffer instanceof byte[]) {
                byte[] samples = (byte[]) buffer;
                int limit = Math.min(count, samples.length);
                for (int i = 0; i < limit; i++) {
                    int dither = ((i * 7919) % 3) - 1;
                    samples[i] = (byte) (samples[i] + dither);
                }
            }
        } catch (Throwable ignored) {}
    }

    /** Microphone capture silenced (silence, not error, so callers keep their flow). */
    private void installAudioSilencePrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.media.AudioRecord.class.getDeclaredMethods()) {
                if (!"read".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length < 3 || !params[0].isArray()) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object result = chain.proceed();
                            if (!shouldSilenceMicNow()) return result;
                            Object buffer = chain.getArgs().get(0);
                            int count = result instanceof Integer ? (Integer) result : 0;
                            zeroSamples(buffer, count);
                            return result;
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "microphone silence hooks installed=" + installed + " package=" + pkg);
    }

    private void zeroSamples(Object buffer, int count) {
        if (buffer == null || count <= 0) return;
        try {
            if (buffer instanceof short[]) {
                short[] samples = (short[]) buffer;
                java.util.Arrays.fill(samples, 0, Math.min(count, samples.length), (short) 0);
            } else if (buffer instanceof byte[]) {
                byte[] samples = (byte[]) buffer;
                java.util.Arrays.fill(samples, 0, Math.min(count, samples.length), (byte) 0);
            } else if (buffer instanceof float[]) {
                float[] samples = (float[]) buffer;
                java.util.Arrays.fill(samples, 0, Math.min(count, samples.length), 0f);
            }
        } catch (Throwable ignored) {}
    }

    /** Input-device enumeration reported as empty. */
    private void installMicHardwarePrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.media.AudioManager.class.getDeclaredMethods()) {
                if (!"getDevices".equals(method.getName())
                        || !android.media.AudioDeviceInfo[].class.equals(method.getReturnType())) {
                    continue;
                }
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideMicHardwareNow()
                                ? new android.media.AudioDeviceInfo[0] : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "microphone hardware hooks installed=" + installed + " package=" + pkg);
    }

    /** Radio scans and cell info reported as empty (distinct from scan permission denial). */
    private void installRadioPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.net.wifi.WifiManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if (("getScanResults".equals(name) || "getConfiguredNetworks".equals(name))
                        && java.util.List.class.isAssignableFrom(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideWifiScanNow()
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        try {
            for (Method method : android.telephony.TelephonyManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if (("getAllCellInfo".equals(name) && java.util.List.class.isAssignableFrom(result))){
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideCellInfoNow()
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                } else if ("getCellLocation".equals(name)
                        && android.os.Bundle.class.equals(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideCellInfoNow()
                                    ? new android.os.Bundle() : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "radio privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** Passive location reads dropped so no cached fix leaks through the passive provider. */
    private void installPassiveLocationPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.location.LocationManager.class.getDeclaredMethods()) {
                if ("getLastKnownLocation".equals(method.getName())
                        && android.location.Location.class.isAssignableFrom(method.getReturnType())) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldDisablePassiveLocationNow()) return chain.proceed();
                                Object provider = chain.getArgs().isEmpty()
                                        ? null : chain.getArgs().get(0);
                                if (provider instanceof String
                                        && "passive".equalsIgnoreCase((String) provider)) return null;
                                return chain.proceed();
                            });
                    installed++;
                } else if ("requestLocationUpdates".equals(method.getName())
                        && method.getReturnType() == void.class) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldDisablePassiveLocationNow()) return chain.proceed();
                                Object provider = chain.getArgs().isEmpty()
                                        ? null : chain.getArgs().get(0);
                                // Passive updates deliver other apps' fixes; never register them.
                                if (provider instanceof String
                                        && "passive".equalsIgnoreCase((String) provider)) return null;
                                return chain.proceed();
                            });
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "passive location privacy hooks installed=" + installed + " package=" + pkg);
    }

    /** MediaStore-only provider blocking for one opted-in target. */
    private void installMediaStoreAuthorityHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : android.content.ContentResolver.class.getDeclaredMethods()) {
                if (!"query".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length == 0 || params[0] != android.net.Uri.class) continue;
                if (!android.database.Cursor.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object uriArg = chain.getArgs().get(0);
                            if (!(uriArg instanceof android.net.Uri)) return chain.proceed();
                            android.net.Uri uri = (android.net.Uri) uriArg;
                            boolean block = policyGate((active, target) ->
                                    MediaStorePrivacyPolicy.shouldBlockMediaStore(privacyEnabled,
                                            processPackages.size(), active, target,
                                            uri.getScheme(), uri.getAuthority()));
                            if (!block) return chain.proceed();
                            String[] projection = chain.getArgs().size() > 1
                                    && chain.getArgs().get(1) instanceof String[]
                                    ? (String[]) chain.getArgs().get(1) : null;
                            return new MatrixCursor(projection == null
                                    ? new String[]{"_id"} : projection);
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "MediaStore authority hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Block state anti-fraud collection for one opted-in target.
     *
     * The SDK and the system component both reach the same platform reads, so the
     * interception is shared: contacts, SMS and call-log providers return an empty
     * cursor, the installed-app inventory returns nothing, and the clipboard read
     * yields no items. Only this target process is affected.
     */
    private void installAntiFraudBlockHooks(final String pkg) {
        int installed = 0;
        final String[] blockedAuthorities = {
                "com.android.contacts", "contacts", "com.android.providers.contacts",
                "content://sms", "content://mms", "content://mms-sms",
                "call_log", "com.android.calllogbackup", "com.android.providers.telephony"
        };
        try {
            for (Method method : ContentResolver.class.getDeclaredMethods()) {
                if (!"query".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length == 0 || params[0] != Uri.class) continue;
                if (!android.database.Cursor.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object uriArg = chain.getArgs().get(0);
                            if (!(uriArg instanceof Uri)) return chain.proceed();
                            String text = String.valueOf(uriArg).toLowerCase(Locale.ROOT);
                            boolean contactsOrMessages = false;
                            for (String authority : blockedAuthorities) {
                                if (text.contains(authority)) { contactsOrMessages = true; break; }
                            }
                            boolean antiFraud = shouldBlockAntiFraudNow(
                                    AntiFraudBlockPolicy.Surface.CONTACTS)
                                    || shouldBlockAntiFraudNow(AntiFraudBlockPolicy.Surface.SMS)
                                    || shouldBlockAntiFraudNow(AntiFraudBlockPolicy.Surface.CALL_LOG);
                            if (!contactsOrMessages || !antiFraud) return chain.proceed();
                            String[] projection = chain.getArgs().size() > 1
                                    && chain.getArgs().get(1) instanceof String[]
                                    ? (String[]) chain.getArgs().get(1) : null;
                            return new MatrixCursor(projection == null
                                    ? new String[]{"_id"} : projection);
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        // Installed-app inventory: the primary signal an anti-fraud SDK uses to
        // decide whether a scam app is present.
        try {
            for (Method method : PackageManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if (!("getInstalledPackages".equals(name) || "getInstalledApplications".equals(name))) {
                    continue;
                }
                if (!java.util.List.class.isAssignableFrom(result)) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockAntiFraudNow(
                                AntiFraudBlockPolicy.Surface.INSTALLED_APPS)
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        // Clipboard content is a common "paste the code" vector for fraud checks.
        try {
            for (Method method : ClipboardManager.class.getDeclaredMethods()) {
                if (!("getPrimaryClip".equals(method.getName())
                        || "getText".equals(method.getName()))) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockAntiFraudNow(
                                AntiFraudBlockPolicy.Surface.CLIPBOARD)
                                ? null : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "anti-fraud block hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Block carrier-side collection for one opted-in target.
     *
     * Identity getters, subscription enumeration, cell/signal metadata and per-UID
     * traffic statistics all return a neutral baseline so the carrier SDK cannot
     * profile the user from this process.
     */
    private void installCarrierCollectionBlockHooks(final String pkg, final ClassLoader loader) {
        int installed = 0;
        final Set<String> identity = new HashSet<>(Arrays.asList(
                "getSubscriberId", "getSimSerialNumber", "getIccSerialNumber",
                "getLine1Number", "getMsisdn", "getGroupIdLevel1", "getVoiceMailNumber",
                "getSimOperator", "getSimOperatorName", "getNetworkOperator",
                "getNetworkOperatorName", "getSimCountryIso", "getNetworkCountryIso"));
        try {
            for (Method method : TelephonyManager.class.getDeclaredMethods()) {
                if (method.getReturnType() != String.class) continue;
                if (!identity.contains(method.getName())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockCarrierNow(
                                CarrierCollectionBlockPolicy.Surface.SUBSCRIBER_ID)
                                ? "" : chain.proceed());
                installed++;
            }
            for (Method method : TelephonyManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if ("getPhoneCount".equals(name) || "getSimCount".equals(name)) {
                    if (result != int.class && result != Integer.class) continue;
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldBlockCarrierNow(
                                    CarrierCollectionBlockPolicy.Surface.SUBSCRIBER_COUNT)
                                    ? Integer.valueOf(0) : chain.proceed());
                    installed++;
                } else if ("getAllCellInfo".equals(name)
                        && java.util.List.class.isAssignableFrom(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldBlockCarrierNow(
                                    CarrierCollectionBlockPolicy.Surface.CELL_INFO)
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                } else if ("getCellLocation".equals(name)
                        && android.os.Bundle.class.equals(result)) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldBlockCarrierNow(
                                    CarrierCollectionBlockPolicy.Surface.CELL_INFO)
                                    ? new android.os.Bundle() : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        // Subscription enumeration (SIM list) is a second identity surface.
        try {
            Class<?> subMgr = Class.forName("android.telephony.SubscriptionManager", false, loader);
            for (Method method : subMgr.getDeclaredMethods()) {
                if ("getActiveSubscriptionInfoList".equals(method.getName())
                        && java.util.List.class.isAssignableFrom(method.getReturnType())) {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldBlockCarrierNow(
                                    CarrierCollectionBlockPolicy.Surface.SUBSCRIBER_COUNT)
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                }
            }
        } catch (Throwable ignored) {}
        // Per-UID traffic accounting reveals which apps the user runs and how much.
        try {
            Class<?> stats = Class.forName("android.net.TrafficStats", false, loader);
            for (Method method : stats.getDeclaredMethods()) {
                Class<?> result = method.getReturnType();
                if (result != long.class && result != Long.class) continue;
                String name = method.getName();
                if (!name.startsWith("getUid") && !name.startsWith("getTotal")) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockCarrierNow(
                                CarrierCollectionBlockPolicy.Surface.DATA_USAGE)
                                ? Long.valueOf(0L) : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "carrier collection block hooks installed=" + installed + " package=" + pkg);
    }

    /**
     * Block public-security reconnaissance for one opted-in target.
     *
     * The enumeration surfaces an inspection tool uses (package inventory, running
     * processes, accessibility services, identifier reads, VPN visibility) all return
     * a neutral baseline for this process only.
     */
    private void installPoliceReconBlockHooks(final String pkg, final ClassLoader loader) {
        int installed = 0;
        try {
            for (Method method : PackageManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?> result = method.getReturnType();
                if (!java.util.List.class.isAssignableFrom(result)) continue;
                if (!("getInstalledPackages".equals(name) || "getInstalledApplications".equals(name)
                        || "getPackagesHoldingPermissions".equals(name))) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockPoliceReconNow(
                                PoliceReconBlockPolicy.Surface.INSTALLED_PACKAGES)
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        // Running-process enumeration exposes what the user is doing right now.
        try {
            Class<?> activityManager = Class.forName("android.app.ActivityManager", false, loader);
            for (Method method : activityManager.getDeclaredMethods()) {
                if (!"getRunningAppProcesses".equals(method.getName())) continue;
                if (!java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockPoliceReconNow(
                                PoliceReconBlockPolicy.Surface.RUNNING_PROCESSES)
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        // Accessibility-service enumeration is a common forensic angle.
        try {
            for (Method method : android.view.accessibility.AccessibilityManager.class
                    .getDeclaredMethods()) {
                if (!("getEnabledAccessibilityServiceList".equals(method.getName())
                        || "getInstalledAccessibilityServiceList".equals(method.getName()))) {
                    continue;
                }
                if (!java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockPoliceReconNow(
                                PoliceReconBlockPolicy.Surface.ACCESSIBILITY_SERVICES)
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        // Network state: hide the tunnel so the tool cannot prove a VPN is up.
        try {
            for (Method method : NetworkCapabilities.class.getDeclaredMethods()) {
                if (!"hasTransport".equals(method.getName())
                        || method.getParameterTypes().length != 1) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            if (shouldBlockPoliceReconNow(PoliceReconBlockPolicy.Surface.VPN_STATE)) {
                                Object arg = chain.getArgs().get(0);
                                if (arg instanceof Integer
                                        && ((Integer) arg) == NetworkCapabilities.TRANSPORT_VPN) {
                                    return false;
                                }
                            }
                            return chain.proceed();
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        // System-module inventory (APEX/APK modules) is a stable device fingerprint and
        // a common "is this a modified device" check.
        try {
            for (Method method : PackageManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if (!("getInstalledModules".equals(name) || "getModuleInfo".equals(name)
                        || "getIncrementalModuleInfo".equals(name))) continue;
                Class<?> result = method.getReturnType();
                java.util.List<Object> neutral = java.util.Collections.emptyList();
                java.util.Map<Object, Object> neutralMap = java.util.Collections.emptyMap();
                java.util.function.Supplier<Object> fallback = () -> {
                    if (java.util.List.class.isAssignableFrom(result)) return neutral;
                    if (java.util.Map.class.isAssignableFrom(result)) return neutralMap;
                    return null;
                };
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockPoliceReconNow(
                                PoliceReconBlockPolicy.Surface.INSTALLED_PACKAGES)
                                || shouldBlockAntiFraudNow(
                                AntiFraudBlockPolicy.Surface.INSTALLED_APPS)
                                ? fallback.get() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {}
        // ANDROID_ID is the fallback identifier when IMEI/OAID are unavailable.
        try {
            for (Method method : android.provider.Settings.Secure.class.getDeclaredMethods()) {
                if (!"getString".equals(method.getName())) continue;
                Class<?>[] params = method.getParameterTypes();
                if (params.length < 2 || params[0] != ContentResolver.class
                        || params[1] != String.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object keyArg = chain.getArgs().get(1);
                            boolean androidId = keyArg instanceof String
                                    && "android_id".equalsIgnoreCase((String) keyArg);
                            if (!androidId) return chain.proceed();
                            if (shouldBlockPoliceReconNow(
                                    PoliceReconBlockPolicy.Surface.DEVICE_IDENTIFIER)
                                    || shouldBlockAntiFraudNow(
                                    AntiFraudBlockPolicy.Surface.DEVICE_IDENTIFIER)
                                    || shouldBlockCarrierNow(
                                    CarrierCollectionBlockPolicy.Surface.SUBSCRIBER_ID)) {
                                return "";
                            }
                            return chain.proceed();
                        });
                installed++;
            }
        } catch (Throwable ignored) {}
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "police recon block hooks installed=" + installed + " package=" + pkg);
    }

    /** Hide media-library queries while leaving non-media content providers untouched. */
    private void installMediaStorePrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : ContentResolver.class.getDeclaredMethods()) {
                if (!"query".equals(method.getName()) ||
                        !android.database.Cursor.class.isAssignableFrom(method.getReturnType()) ||
                        method.getParameterTypes().length == 0 || method.getParameterTypes()[0] != Uri.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object uriArg = chain.getArgs().get(0);
                        if (!shouldBlockMediaStoreQueryNow() || !(uriArg instanceof Uri) ||
                                !String.valueOf(uriArg).toLowerCase(Locale.ROOT).startsWith("content://media")) {
                            return chain.proceed();
                        }
                        String[] projection = null;
                        if (chain.getArgs().size() > 1 && chain.getArgs().get(1) instanceof String[]) {
                            projection = (String[]) chain.getArgs().get(1);
                        }
                        return new MatrixCursor(projection == null ? new String[]{"_id"} : projection);
                    });
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "MediaStore privacy hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "MediaStore privacy hooks installed=" + installed + " package=" + pkg);
    }

    private boolean shouldBlockClipboardReadNow() {
        return policyGate((pkg, target) -> ClipboardPrivacyPolicy.shouldBlockRead(privacyEnabled,
                processPackages.size(), pkg, target));
    }

    /** Clipboard isolation (separate from read blocking: scoped, opt-in, single package). */
    private boolean shouldIsolateClipboardNow() {
        return policyGate((pkg, target) -> ClipboardIsolationPolicy.shouldIsolate(privacyEnabled,
                processPackages.size(), pkg, target));
    }

    /** Notification listener blocking for one opted-in target. */
    private boolean shouldBlockNotificationListenNow() {
        return policyGate((pkg, target) -> NotificationPrivacyPolicy.shouldBlock(privacyEnabled,
                processPackages.size(), pkg, target));
    }

    /** Notification-permission hiding for one opted-in target. */
    private boolean shouldHideNotificationPermissionNow() {
        return policyGate((pkg, target) -> NotificationPrivacyPolicy.shouldHidePermission(
                privacyEnabled, processPackages.size(), pkg, target));
    }

    /** Advertising-id unification: deterministic synthetic id per package. */
    private String syntheticAdvertisingIdNow() {
        String activePackage = currentPackage;
        if (activePackage == null) return null;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        if (!processPackages.contains(activePackage)) return null;
        if (!AdvertisingIdPrivacyPolicy.shouldUnify(privacyEnabled, processPackages.size(),
                activePackage, active)) return null;
        return AdvertisingIdPrivacyPolicy.syntheticId(activePackage);
    }

    private static Object emptyClipboardReadResult(Method method) {
        Class<?> result = method.getReturnType();
        if (result == boolean.class) return Boolean.FALSE;
        if (result == byte.class) return Byte.valueOf((byte) 0);
        if (result == short.class) return Short.valueOf((short) 0);
        if (result == int.class) return Integer.valueOf(0);
        if (result == long.class) return Long.valueOf(0L);
        if (result == float.class) return Float.valueOf(0f);
        if (result == double.class) return Double.valueOf(0d);
        if (result == char.class) return Character.valueOf('\0');
        if (result.isArray()) return Array.newInstance(result.getComponentType(), 0);
        return null;
    }

    /**
     * Hide all supported methods on one clipboard data surface. The helper only
     * hooks explicitly named readers; one-argument accessors are listed separately
     * so unrelated overloads and write operations remain untouched.
     */
    private int installClipboardReadSurface(Class<?> type, String[] zeroArgNames,
                                            String[] oneArgNames) {
        if (type == null) return 0;
        Set<String> zeroArg = new HashSet<>(Arrays.asList(zeroArgNames));
        Set<String> oneArg = new HashSet<>(Arrays.asList(oneArgNames));
        int installed = 0;
        for (Method method : type.getDeclaredMethods()) {
            String name = method.getName();
            int parameterCount = method.getParameterTypes().length;
            if ((parameterCount == 0 && !zeroArg.contains(name))
                    || (parameterCount == 1 && !oneArg.contains(name))
                    || parameterCount > 1
                    || (parameterCount != 0 && parameterCount != 1)) continue;
            if (Modifier.isStatic(method.getModifiers())) continue;
            if (clipboardReadHookedMethods.contains(method)) continue;
            try {
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockClipboardReadNow()
                                ? emptyClipboardReadResult(method) : chain.proceed());
                clipboardReadHookedMethods.add(method);
                installed++;
            } catch (Throwable error) {
                logFx(Log.DEBUG, "clipboard data accessor hook unavailable: "
                        + type.getName() + "." + name);
            }
        }
        return installed;
    }

    /**
     * Opt-in clipboard read protection. Writes remain untouched; direct reads,
     * metadata inspection, cached ClipData extraction and listener registration
     * are blocked for a single-package process. Shared-package processes fail open.
     */
    private synchronized boolean installClipboardReadBlockHooks(final String pkg) {
        // Do not use a single all-or-nothing boolean as an early return: ART may
        // reject one accessor while the remaining methods register successfully.
        // Keep successful Method hooks and retry only missing methods next time.
        int installed = 0;
        try {
            Class<?> manager = Class.forName("android.content.ClipboardManager", false, null);
            installed += installClipboardReadSurface(manager,
                    new String[]{"getPrimaryClip", "getPrimaryClipDescription", "hasPrimaryClip",
                            "hasText", "getText", "getPrimaryClipSource"},
                    new String[]{"addPrimaryClipChangedListener"});
            // ClipData may have been cached before a consumer reaches an Item.
            // Blocking both the container and Item accessors closes that cached-object path.
            try {
                Class<?> clipData = Class.forName("android.content.ClipData", false, null);
                installed += installClipboardReadSurface(clipData,
                        new String[]{"getItemCount", "getDescription", "getMimeTypes"},
                        new String[]{"getItemAt"});
            } catch (Throwable error) {
                logFx(Log.DEBUG, "ClipData accessors unavailable; manager protection remains active");
            }
            try {
                Class<?> item = Class.forName("android.content.ClipData$Item", false, null);
                installed += installClipboardReadSurface(item,
                        new String[]{"getText", "getHtmlText", "getUri", "getIntent"},
                        new String[]{"coerceToText", "coerceToStyledText", "coerceToHtmlText"});
            } catch (Throwable error) {
                logFx(Log.DEBUG, "ClipData.Item accessors unavailable; manager protection remains active");
            }
            try {
                Class<?> description = Class.forName("android.content.ClipDescription", false, null);
                installed += installClipboardReadSurface(description,
                        new String[]{"getLabel", "getMimeTypeCount", "getTimestamp"},
                        new String[]{"getMimeType", "hasMimeType", "filterMimeTypes"});
            } catch (Throwable error) {
                logFx(Log.DEBUG, "ClipDescription accessors unavailable; manager protection remains active");
            }
        } catch (Throwable error) {
            logFx(Log.WARN, "clipboard manager unavailable: " + error.getClass().getSimpleName());
            return false;
        }
        clipboardReadHooksInstalled = !clipboardReadHookedMethods.isEmpty();
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in clipboard read protection newly installed=" + installed
                        + " total=" + clipboardReadHookedMethods.size()
                        + " across manager/data/item/description for " + pkg);
        return clipboardReadHooksInstalled;
    }

    /** Hide clipboard contents only inside the explicitly selected target app process. */
    private void installClipboardPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : ClipboardManager.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?>[] params = method.getParameterTypes();
                boolean noArgs = params.length == 0;
                if (noArgs && "getPrimaryClip".equals(name) && method.getReturnType() == ClipData.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> isolatedClipboardClip);
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (noArgs && "getPrimaryClipDescription".equals(name) &&
                        method.getReturnType() == ClipDescription.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                isolatedClipboardClip == null ? null : isolatedClipboardClip.getDescription());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (noArgs && "hasPrimaryClip".equals(name) &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                isolatedClipboardClip != null);
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (noArgs && "getText".equals(name)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            ClipData clip = isolatedClipboardClip;
                            return clip != null && clip.getItemCount() > 0 ? clip.getItemAt(0).getText() : null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (noArgs && "hasText".equals(name) &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            ClipData clip = isolatedClipboardClip;
                            return clip != null && clip.getItemCount() > 0 && clip.getItemAt(0).getText() != null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("setPrimaryClip".equals(name) && params.length == 1 && params[0] == ClipData.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object arg = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            isolatedClipboardClip = arg instanceof ClipData ? (ClipData) arg : null;
                            return null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("setText".equals(name) && params.length == 1 && CharSequence.class.isAssignableFrom(params[0])) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object arg = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            isolatedClipboardClip = ClipData.newPlainText(null, arg instanceof CharSequence ? (CharSequence) arg : "");
                            return null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (noArgs && "clearPrimaryClip".equals(name)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            isolatedClipboardClip = null;
                            return null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "clipboard isolation hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "clipboard isolation hooks installed=" + installed + " package=" + pkg);
    }

                                

    

    /**
     * Sensor families come from SensorPrivacyPolicy so the hook and the unit tests
     * cannot disagree about which type belongs to which switch.
     */
    private boolean isFxSensorTypeBlocked(UnifiedHookConfigParser.Target target, int sensorType) {
        if (target == null) return false;
        return SensorPrivacyPolicy.isEnabled(target, sensorType);
    }

    /** Per-type sensor privacy: selected sensors are hidden while unrelated sensors remain available. */
    private void installSensorPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (final Method method : SensorManager.class.getDeclaredMethods()) {
                final String name = method.getName();
                final Class<?>[] parameters = method.getParameterTypes();
                if ("registerListener".equals(name) && parameters.length >= 3
                        && "android.hardware.Sensor".equals(parameters[1].getName())
                        && parameters[2] == int.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    String activePackage = currentPackage;
                                    UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                    Object sensor = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                                    if (sensor != null) {
                                        try {
                                            Object type = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (type instanceof Integer && privacyEnabled
                                                    && processPackages.size() == 1
                                                    && isFxSensorTypeBlocked(active, ((Integer) type).intValue())) {
                                                return method.getReturnType() == boolean.class ? Boolean.FALSE : null;
                                            }
                                        } catch (Throwable ignored) {}
                                    }
                                    Object[] args = chain.getArgs().toArray();
                                    if (privacyEnabled && processPackages.size() == 1 && active != null
                                            && active.sensorRateLimit && args.length > 2
                                            && args[2] instanceof Integer) {
                                        args[2] = Integer.valueOf(Math.max(200000,
                                                ((Integer) args[2]).intValue()));
                                        return chain.proceed(args);
                                    }
                                    return chain.proceed();
                                });
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "sensor registration hook unavailable: " + method.toGenericString());
                    }
                    continue;
                }
                if ("requestTriggerSensor".equals(name) && parameters.length >= 2
                        && "android.hardware.Sensor".equals(parameters[1].getName())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    Object sensor = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                                    if (sensor != null && privacyEnabled && processPackages.size() == 1) {
                                        UnifiedHookConfigParser.Target active = targets.get(currentPackage);
                                        try {
                                            Object type = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (type instanceof Integer && isFxSensorTypeBlocked(active, ((Integer) type).intValue())) {
                                                return Boolean.FALSE;
                                            }
                                        } catch (Throwable ignored) {}
                                    }
                                    return chain.proceed();
                                });
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "trigger sensor hook unavailable");
                    }
                    continue;
                }
                if (!("getSensorList".equals(name) || "getDefaultSensor".equals(name)
                        || "getDynamicSensorList".equals(name))
                        || parameters.length < 1 || parameters[0] != int.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!privacyEnabled || processPackages.size() != 1) return chain.proceed();
                                UnifiedHookConfigParser.Target active = targets.get(currentPackage);
                                Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                if (!(arg instanceof Integer) || active == null) return chain.proceed();
                                int requested = ((Integer) arg).intValue();
                                if (requested == -1 && ("getSensorList".equals(name)
                                        || "getDynamicSensorList".equals(name))) {
                                    Object original = chain.proceed();
                                    if (!(original instanceof List)) return original;
                                    List<Object> visible = new ArrayList<>();
                                    for (Object sensor : (List<?>) original) {
                                        try {
                                            Object type = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (!(type instanceof Integer)
                                                    || !isFxSensorTypeBlocked(active, ((Integer) type).intValue())) {
                                                visible.add(sensor);
                                            }
                                        } catch (Throwable ignored) { visible.add(sensor); }
                                    }
                                    return visible;
                                }
                                if (!isFxSensorTypeBlocked(active, requested)) return chain.proceed();
                                return "getDefaultSensor".equals(name) ? null : Collections.emptyList();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "sensor enumeration hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "sensor privacy hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "per-type sensor privacy hooks installed=" + installed + " package=" + pkg);
    }

    private synchronized boolean installNotificationListenPrivacyHooks(final String pkg) {
        int installed = 0;
        for (String className : new String[]{
                "android.app.NotificationManager",
                "android.service.notification.NotificationListenerService"}) {
            try {
                Class<?> type = Class.forName(className, false, null);
                for (final Method method : type.getDeclaredMethods()) {
                    if (!"getActiveNotifications".equals(method.getName())
                            || method.getParameterTypes().length != 0
                            || !method.getReturnType().isArray()) continue;
                    final Class<?> component = method.getReturnType().getComponentType();
                    if (component == null || !"android.service.notification.StatusBarNotification".equals(component.getName())) continue;
                    if (notificationListenHookedMethods.contains(method)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    String activePackage = currentPackage;
                                    UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                    if (privacyEnabled && active != null && active.notificationListenBlock) {
                                        return Array.newInstance(component, 0);
                                    }
                                    return chain.proceed();
                                });
                        notificationListenHookedMethods.add(method);
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "notification read hook unavailable: " + className);
                    }
                }
            } catch (Throwable t) {
                logFx(Log.DEBUG, "notification API unavailable: " + className);
            }
        }
        // A listener may already be bound before its settings string is hidden.
        // Drop notification payload callbacks at the framework Binder wrapper so
        // an existing NotificationListenerService cannot keep receiving content.
        try {
            Class<?> wrapper = Class.forName(
                    "android.service.notification.NotificationListenerService$NotificationListenerWrapper",
                    false, null);
            Set<String> callbackNames = new HashSet<>(Arrays.asList(
                    "onNotificationPosted", "onNotificationRemoved", "onNotificationRankingUpdate"));
            for (final Method method : wrapper.getDeclaredMethods()) {
                if (!callbackNames.contains(method.getName())
                        || method.getReturnType() != void.class
                        || notificationListenHookedMethods.contains(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (privacyEnabled && active != null && active.notificationListenBlock) return null;
                                return chain.proceed();
                            });
                    notificationListenHookedMethods.add(method);
                    installed++;
                } catch (Throwable error) {
                    logFx(Log.DEBUG, "notification listener Binder callback hook unavailable: "
                            + method.getName());
                }
            }
        } catch (Throwable error) {
            logFx(Log.DEBUG, "NotificationListenerService Binder wrapper unavailable");
        }
        // Legacy API-82 also masked Settings.Secure listener enumeration.
        // Preserve that behavior only for explicitly selected target packages.
        try {
            Class<?> secure = Class.forName("android.provider.Settings$Secure", false, null);
            Method getString = secure.getDeclaredMethod("getString",
                    Class.forName("android.content.ContentResolver", false, null), String.class);
            if (getString.getReturnType() == String.class
                    && !notificationListenHookedMethods.contains(getString)) {
                hook(getString).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object key = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                            String activePackage = currentPackage;
                            UnifiedHookConfigParser.Target active = targets.get(activePackage);
                            if ("enabled_notification_listeners".equals(key)
                                    && privacyEnabled && active != null && active.notificationListenBlock) return "";
                            return chain.proceed();
                        });
                notificationListenHookedMethods.add(getString);
                installed++;
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "notification listener setting query hook unavailable");
        }
        notificationListenHooksInstalled = !notificationListenHookedMethods.isEmpty();
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in active-notification hooks newly installed=" + installed
                        + " total=" + notificationListenHookedMethods.size() + " for " + pkg);
        return notificationListenHooksInstalled;
    }

    /** Suppress cached location and provider enumeration for selected privacy-protected apps. */
    private void installLocationPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            for (Method method : LocationManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if ("getLastKnownLocation".equals(name) && Location.class.isAssignableFrom(method.getReturnType())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockLocationNow() ? null : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("getCurrentLocation".equals(name)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            if (!shouldBlockLocationNow()) return chain.proceed();
                            Consumer<Location> callback = null;
                            Executor executor = null;
                            for (Object arg : chain.getArgs()) {
                                if (arg instanceof Consumer) {
                                    @SuppressWarnings("unchecked")
                                    Consumer<Location> candidate = (Consumer<Location>) arg;
                                    callback = candidate;
                                } else if (arg instanceof Executor) executor = (Executor) arg;
                            }
                            if (callback != null && executor != null) {
                                final Consumer<Location> cb = callback;
                                executor.execute(() -> cb.accept(null));
                                return null;
                            }
                            // Unknown OEM signature: fail closed rather than returning a real location.
                            return null;
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (("requestLocationUpdates".equals(name) || "requestSingleUpdate".equals(name)) &&
                        method.getReturnType() == void.class) {
                    // Prevent callback-based location delivery as well as cached reads.
                    // Returning without registering the listener avoids leaking a fresh fix
                    // through LocationListener/PendingIntent overloads.
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockLocationNow() ? null : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (("addGpsStatusListener".equals(name) || "addNmeaListener".equals(name)
                        || "addProximityAlert".equals(name)) &&
                        (method.getReturnType() == void.class || method.getReturnType() == boolean.class
                                || method.getReturnType() == Boolean.class)) {
                    // Legacy GPS/NMEA/proximity callbacks can expose location outside
                    // the modern LocationListener and GNSS registration APIs.
                    try {
                        Object blocked = method.getReturnType() == boolean.class
                                || method.getReturnType() == Boolean.class ? Boolean.FALSE : null;
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> shouldBlockLocationNow() ? blocked : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (("getProviders".equals(name) || "getAllProviders".equals(name)) && List.class.isAssignableFrom(method.getReturnType())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockLocationNow() ? Collections.emptyList() : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("isProviderEnabled".equals(name) &&
                        (method.getReturnType() == boolean.class || method.getReturnType() == Boolean.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain ->
                                shouldBlockLocationNow() ? false : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "location privacy hooks unavailable for " + pkg);
        }
        // GNSS measurement/status callbacks are separate from LocationListener and
        // must be covered as well; otherwise an app can continue receiving satellite
        // metadata after ordinary location updates are blocked.
        try {
            for (Method method : LocationManager.class.getDeclaredMethods()) {
                String name = method.getName();
                if ("registerGnssMeasurementsCallback".equals(name) ||
                        "registerGnssNavigationMessageCallback".equals(name) ||
                        "registerGnssStatusCallback".equals(name)) {
                    try {
                        Object blocked = method.getReturnType() == boolean.class ||
                                method.getReturnType() == Boolean.class ? Boolean.FALSE : null;
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> shouldBlockLocationNow() ? blocked : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("getGnssHardwareModelName".equals(name) &&
                        method.getReturnType() == String.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> shouldBlockLocationNow() ? "" : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                } else if (("getGnssYearOfHardware".equals(name) ||
                        "getGnssBatchSize".equals(name)) &&
                        (method.getReturnType() == int.class || method.getReturnType() == Integer.class)) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> shouldBlockLocationNow() ? 0 : chain.proceed());
                        installed++;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "GNSS privacy hooks unavailable for " + pkg);
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "location/GNSS privacy hooks installed=" + installed + " package=" + pkg);
    }

            /** Optional camera/microphone/biometric and EXIF privacy controls, scoped per target app. */
    private boolean shouldHidePostNotificationsPermission(String permission, String queriedPackage) {
        if (!"android.permission.POST_NOTIFICATIONS".equals(permission)) return false;
        String activePackage = currentPackage;
        if (activePackage == null || activePackage.isEmpty()
                || (queriedPackage != null && !activePackage.equals(queriedPackage))
                || processPackages.size() != 1) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return privacyEnabled && active != null && active.notificationPermissionHide;
    }
    /**
     * Masks notification permission state consistently across Android's app-level
     * queries. This does not revoke the grant, prevent notification posting, or
     * alter notification-listener access; it only returns a denied/disabled view
     * to the explicitly opted-in single-package target process.
     */
    private int installNotificationPostAppOpsHooks() {
        int installed = 0;
        try {
            Class<?> appOps = Class.forName("android.app.AppOpsManager", false, null);
            int postNotificationCode = Integer.MIN_VALUE;
            try {
                java.lang.reflect.Field opField = appOps.getDeclaredField("OP_POST_NOTIFICATION");
                opField.setAccessible(true);
                postNotificationCode = opField.getInt(null);
            } catch (Throwable ignored) {
                // String OPSTR_POST_NOTIFICATION remains the portable path.
            }
            final int opCode = postNotificationCode;
            final String opName = "android:post_notification";
            final int ignoredMode = 1; // AppOpsManager.MODE_IGNORED
            Set<String> queryNames = new HashSet<>(Arrays.asList(
                    "checkOp", "checkOpNoThrow", "unsafeCheckOp", "unsafeCheckOpNoThrow"));
            for (final Method method : appOps.getDeclaredMethods()) {
                Class<?>[] params = method.getParameterTypes();
                if (!queryNames.contains(method.getName())
                        || notificationPermissionHookedMethods.contains(method)
                        || method.getReturnType() != int.class
                        || (params.length != 3 && params.length != 4)
                        || (params[0] != String.class && params[0] != int.class)
                        || params[1] != int.class || params[2] != String.class
                        || (params.length == 4 && params[3] != String.class)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object[] args = chain.getArgs().toArray();
                                if (args.length < 3 || !(args[1] instanceof Integer)
                                        || !(args[2] instanceof String)) return chain.proceed();
                                int uid = ((Integer) args[1]).intValue();
                                String packageName = (String) args[2];
                                boolean postNotificationOp = args[0] instanceof String
                                        ? opName.equals(args[0])
                                        : args[0] instanceof Integer && opCode != Integer.MIN_VALUE
                                                && ((Integer) args[0]).intValue() == opCode;
                                if (postNotificationOp && uid == android.os.Process.myUid()
                                        && shouldHidePostNotificationsPermission("android.permission.POST_NOTIFICATIONS", packageName)) {
                                    return Integer.valueOf(ignoredMode);
                                }
                                return chain.proceed();
                            });
                    notificationPermissionHookedMethods.add(method);
                    installed++;
                } catch (Throwable error) {
                    logFx(Log.DEBUG, "notification AppOps query hook unavailable: "
                            + method.toGenericString());
                }
            }
        } catch (Throwable error) {
            logFx(Log.DEBUG, "AppOpsManager notification query API unavailable");
        }
        return installed;
    }

    private synchronized boolean installNotificationPermissionPrivacyHooks(final String pkg) {
        // Retry missing framework surfaces after partial ART/OEM registration failures.
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.app.NotificationManager", false, null);
            for (final Method method : type.getDeclaredMethods()) {
                final String name = method.getName();
                final Class<?>[] params = method.getParameterTypes();
                final boolean appEnabled = "areNotificationsEnabled".equals(name)
                        && params.length == 0 && method.getReturnType() == boolean.class;
                final boolean packageEnabled = "areNotificationsEnabledForPackage".equals(name)
                        && params.length >= 1 && params[0] == String.class
                        && method.getReturnType() == boolean.class;
                if ((!appEnabled && !packageEnabled)
                        || notificationPermissionHookedMethods.contains(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object[] args = chain.getArgs().toArray();
                                String queried = packageEnabled && args.length > 0
                                        && args[0] instanceof String ? (String) args[0] : null;
                                boolean ownPackageQuery = !packageEnabled
                                        || (queried != null && queried.equals(currentPackage));
                                if (ownPackageQuery && packageEnabled && args.length > 1
                                        && args[1] instanceof Integer
                                        && ((Integer) args[1]).intValue() != android.os.Process.myUid()) {
                                    ownPackageQuery = false;
                                }
                                if (ownPackageQuery && shouldHidePostNotificationsPermission(
                                        "android.permission.POST_NOTIFICATIONS", queried)) {
                                    return Boolean.FALSE;
                                }
                                return chain.proceed();
                            });
                    notificationPermissionHookedMethods.add(method);
                    installed++;
                } catch (Throwable error) {
                    logFx(Log.DEBUG, "NotificationManager permission state hook unavailable: " + name);
                }
            }
        } catch (Throwable error) {
            logFx(Log.DEBUG, "NotificationManager permission query unavailable");
        }

        // ContextCompat delegates to Context.checkSelfPermission on supported
        // Android releases. Hook the framework wrappers/implementation so both
        // direct Context calls and common compatibility helpers share one result.
        for (String className : new String[]{"android.content.ContextWrapper", "android.app.ContextImpl"}) {
            try {
                Class<?> contextType = Class.forName(className, false, null);
                for (final Method method : contextType.getDeclaredMethods()) {
                    final String name = method.getName();
                    final Class<?>[] params = method.getParameterTypes();
                    final boolean self = "checkSelfPermission".equals(name)
                            && params.length == 1 && params[0] == String.class
                            && method.getReturnType() == int.class;
                    final boolean explicit = "checkPermission".equals(name)
                            && params.length == 3 && params[0] == String.class
                            && params[1] == int.class && params[2] == int.class
                            && method.getReturnType() == int.class;
                    if ((!self && !explicit)
                            || notificationPermissionHookedMethods.contains(method)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    Object[] args = chain.getArgs().toArray();
                                    if (args.length > 0 && args[0] instanceof String) {
                                        boolean ownUid = !explicit || (args.length > 2
                                                && args[2] instanceof Integer
                                                && ((Integer) args[2]).intValue() == android.os.Process.myUid());
                                        if (ownUid && shouldHidePostNotificationsPermission(
                                                (String) args[0], currentPackage)) {
                                            return Integer.valueOf(-1);
                                        }
                                    }
                                    return chain.proceed();
                                });
                        notificationPermissionHookedMethods.add(method);
                        installed++;
                    } catch (Throwable error) {
                        logFx(Log.DEBUG, "Context notification permission hook unavailable: " + name);
                    }
                }
            } catch (Throwable error) {
                logFx(Log.DEBUG, "Context permission API unavailable: " + className);
            }
        }

        // PackageManager callers may query a named package rather than the
        // calling Context. Only mask the active target's own POST_NOTIFICATIONS.
        for (String className : new String[]{
                "android.app.ApplicationPackageManager", "android.content.pm.PackageManager"}) {
            try {
                Class<?> packageManager = Class.forName(className, false, null);
                for (final Method method : packageManager.getDeclaredMethods()) {
                    final String name = method.getName();
                    final Class<?>[] params = method.getParameterTypes();
                    final boolean check = "checkPermission".equals(name)
                            && params.length == 2 && params[0] == String.class
                            && params[1] == String.class && method.getReturnType() == int.class;
                    final boolean flags = "getPermissionFlags".equals(name)
                            && params.length == 3 && params[0] == String.class
                            && params[1] == String.class && method.getReturnType() == int.class;
                    if ((!check && !flags)
                            || notificationPermissionHookedMethods.contains(method)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    Object[] args = chain.getArgs().toArray();
                                    if (args.length > 1 && args[0] instanceof String
                                            && args[1] instanceof String
                                            && shouldHidePostNotificationsPermission(
                                                    (String) args[0], (String) args[1])) {
                                        return Integer.valueOf(check ? -1 : 0);
                                    }
                                    return chain.proceed();
                                });
                        notificationPermissionHookedMethods.add(method);
                        installed++;
                    } catch (Throwable error) {
                        logFx(Log.DEBUG, "PackageManager notification permission hook unavailable: " + name);
                    }
                }
            } catch (Throwable error) {
                logFx(Log.DEBUG, "PackageManager permission query unavailable: " + className);
            }
        }

        installed += installNotificationPostAppOpsHooks();
        notificationPermissionHooksInstalled = !notificationPermissionHookedMethods.isEmpty();
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in notification permission hooks newly installed=" + installed
                        + " total=" + notificationPermissionHookedMethods.size()
                        + " across AppOps/NotificationManager/Context/PackageManager for " + pkg);
        return notificationPermissionHooksInstalled;
    }

    private void installAudioRecordSilenceHooks(String packageName) {
        int installedNow = 0;
        int failedNow = 0;
        for (Method method : AudioRecord.class.getDeclaredMethods()) {
            if (!"read".equals(method.getName()) || method.getReturnType() != int.class
                    || method.getParameterTypes().length == 0
                    || !AudioRecordSilencePolicy.supports(method.getParameterTypes()[0])
                    || microphoneSilenceHookedMethods.contains(method)) continue;
            try {
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    if (!isMicrophoneSilenceAuthorized()) return chain.proceed();
                    Object[] args = chain.getArgs().toArray();
                    int bufferStart = 0;
                    if (args.length > 0 && args[0] instanceof ByteBuffer) {
                        bufferStart = ((ByteBuffer) args[0]).position();
                    }
                    Object result = chain.proceed();
                    if (result instanceof Integer && ((Integer) result) > 0) {
                        AudioRecordSilencePolicy.zero(args, (Integer) result, bufferStart);
                    }
                    return result;
                });
                microphoneSilenceHookedMethods.add(method);
                installedNow++;
            } catch (Throwable t) {
                failedNow++;
                logFx(Log.WARN, "AudioRecord overload hook failed; overload unchanged: "
                        + method.toGenericString() + " (" + t + ")");
            }
        }
        if (installedNow > 0 || failedNow > 0) {
            logFx(failedNow == 0 ? Log.INFO : Log.WARN,
                    "AudioRecord read hooks: newlyInstalled=" + installedNow
                            + " failed=" + failedNow + " total=" + microphoneSilenceHookedMethods.size()
                            + " package=" + packageName);
        }
    }

    private boolean isMicrophoneSilenceAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        String onlyPackage = processPackages.iterator().next();
        UnifiedHookConfigParser.Target selected = targets.get(onlyPackage);
        return selected != null && selected.microphoneSilence;
    }

    private boolean isCameraAccessBlockAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        UnifiedHookConfigParser.Target selected = targets.get(processPackages.iterator().next());
        return selected != null && selected.cameraAccessBlock;
    }

    private void installCameraAccessBlockHooks(String packageName) {
        int installed = 0;
        for (String className : new String[]{"android.hardware.Camera", "android.hardware.camera2.CameraManager"}) {
            try {
                Class<?> type = Class.forName(className, false, null);
                for (Method method : type.getDeclaredMethods()) {
                    boolean legacyOpen = "android.hardware.Camera".equals(className)
                            && "open".equals(method.getName()) && java.lang.reflect.Modifier.isStatic(method.getModifiers());
                    boolean camera2Open = "android.hardware.camera2.CameraManager".equals(className)
                            && "openCamera".equals(method.getName());
                    if ((!legacyOpen && !camera2Open) || cameraAccessHookedMethods.contains(method)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                            if (isCameraAccessBlockAuthorized()) {
                                throw new SecurityException("Camera access disabled by FX Hook privacy setting");
                            }
                            return chain.proceed();
                        });
                        cameraAccessHookedMethods.add(method);
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.WARN, "camera open hook unavailable: " + method.toGenericString());
                    }
                }
            } catch (Throwable t) {
                logFx(Log.DEBUG, "camera API unavailable: " + className);
            }
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "per-app camera access denial hooks installed=" + installed + " package=" + packageName);
    }

    private boolean isMicrophoneAccessBlockAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        UnifiedHookConfigParser.Target selected = targets.get(processPackages.iterator().next());
        return selected != null && selected.microphoneAccessBlock;
    }

    private void installMicrophoneAccessBlockHooks(String packageName) {
        int installed = 0;
        try {
            for (Method method : AudioRecord.class.getDeclaredMethods()) {
                if (!"startRecording".equals(method.getName()) || method.getReturnType() != void.class
                        || microphoneAccessHookedMethods.contains(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                        if (isMicrophoneAccessBlockAuthorized()) {
                            throw new SecurityException("Microphone access disabled by FX Hook privacy setting");
                        }
                        return chain.proceed();
                    });
                    microphoneAccessHookedMethods.add(method);
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.WARN, "AudioRecord start hook unavailable: " + method.toGenericString());
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "AudioRecord API unavailable for microphone access blocking");
        }
        try {
            Class<?> recorder = Class.forName("android.media.MediaRecorder", false, null);
            for (Method method : recorder.getDeclaredMethods()) {
                if (!"start".equals(method.getName()) || method.getParameterTypes().length != 0
                        || microphoneAccessHookedMethods.contains(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                        if (isMicrophoneAccessBlockAuthorized()) {
                            throw new SecurityException("Microphone access disabled by FX Hook privacy setting");
                        }
                        return chain.proceed();
                    });
                    microphoneAccessHookedMethods.add(method);
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.WARN, "MediaRecorder start hook unavailable: " + method.toGenericString());
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "MediaRecorder API unavailable for microphone access blocking");
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "per-app microphone capture denial hooks installed=" + installed + " package=" + packageName);
    }

    private void installMediaPrivacyHooks(final String pkg, final ClassLoader loader) {
        int installed = 0;
        try {
            Class<?> cameraManager = Class.forName("android.hardware.camera2.CameraManager");
            for (Method method : cameraManager.getDeclaredMethods()) {
                if ("getCameraIdList".equals(method.getName()) && method.getReturnType() == String[].class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> new String[0]);
                        installed++;
                    } catch (Throwable ignored) {}
                } else if ("openCamera".equals(method.getName())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                            throw new SecurityException("Camera access disabled by FX privacy policy");
                        });
                        installed++;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "camera2 privacy hooks unavailable for " + pkg);
        }
        try {
            Class<?> legacyCamera = Class.forName("android.hardware.Camera");
            for (Method method : legacyCamera.getDeclaredMethods()) {
                if (!"open".equals(method.getName()) || !java.lang.reflect.Modifier.isStatic(method.getModifiers())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                        throw new SecurityException("Camera access disabled by FX privacy policy");
                    });
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {}
        try {
            Class<?> audioManager = Class.forName("android.media.AudioManager");
            for (Method method : audioManager.getDeclaredMethods()) {
                if (!"getMicrophones".equals(method.getName()) || !List.class.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> Collections.emptyList());
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "microphone inventory hiding unavailable for " + pkg);
        }
        try {
            Class<?> audioRecord = Class.forName("android.media.AudioRecord");
            for (Method method : audioRecord.getDeclaredMethods()) {
                if (!"read".equals(method.getName()) || method.getReturnType() != int.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        if (!(result instanceof Integer) || ((Integer) result) <= 0) return result;
                        int count = (Integer) result;
                        zeroAudioReadBuffers(chain.getArgs(), count);
                        return result;
                    });
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "microphone sample privacy hooks unavailable for " + pkg);
        }
        installed += installBooleanHardwareHide(loader, "android.hardware.fingerprint.FingerprintManager",
                new String[]{"isHardwareDetected", "hasEnrolledFingerprints"});
        // Preserve the old support-library biometric hiding path as well as
        // the platform API, since many apps still call the AndroidX wrapper.
        installed += installBooleanHardwareHide(loader,
                "androidx.core.hardware.fingerprint.FingerprintManagerCompat",
                new String[]{"isHardwareDetected", "hasEnrolledFingerprints"});
        installed += installBooleanHardwareHide(loader,
                "android.support.v4.hardware.fingerprint.FingerprintManagerCompat",
                new String[]{"isHardwareDetected", "hasEnrolledFingerprints"});
        installed += installBooleanHardwareHide(loader, "android.hardware.face.FaceManager",
                new String[]{"isHardwareDetected", "hasEnrolledFaces"});
        try {
            Class<?> biometric = Class.forName("android.hardware.biometrics.BiometricManager");
            for (Method method : biometric.getDeclaredMethods()) {
                if (!"canAuthenticate".equals(method.getName()) ||
                        (method.getReturnType() != int.class && method.getReturnType() != Integer.class)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> 12);
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {}
        installed += installExifPrivacyHooks(loader);
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "media privacy hooks installed=" + installed + " package=" + pkg);
    }

    private static void zeroAudioReadBuffers(List<?> args, int count) {
        for (int i = 0; i < args.size(); i++) {
            Object arg = args.get(i);
            int offset = 0;
            for (int j = i + 1; j < args.size(); j++) {
                if (args.get(j) instanceof Integer) {
                    offset = Math.max(0, (Integer) args.get(j));
                    break;
                }
            }
            if (arg instanceof byte[]) {
                byte[] values = (byte[]) arg;
                int end = Math.min(values.length, offset + count);
                if (offset < end) Arrays.fill(values, offset, end, (byte) 0);
                return;
            }
            if (arg instanceof short[]) {
                short[] values = (short[]) arg;
                int end = Math.min(values.length, offset + count);
                if (offset < end) Arrays.fill(values, offset, end, (short) 0);
                return;
            }
            if (arg instanceof float[]) {
                float[] values = (float[]) arg;
                int end = Math.min(values.length, offset + count);
                if (offset < end) Arrays.fill(values, offset, end, 0f);
                return;
            }
            if (arg instanceof java.nio.ByteBuffer) {
                java.nio.ByteBuffer buffer = ((java.nio.ByteBuffer) arg).duplicate();
                int end = buffer.position();
                int start = Math.max(0, end - count);
                buffer.position(start);
                while (buffer.position() < end) buffer.put((byte) 0);
                return;
            }
        }
    }

    private int installBooleanHardwareHide(ClassLoader loader, String className, String[] methodNames) {
        int installed = 0;
        try {
            Class<?> type = Class.forName(className, false, loader == null ? getClass().getClassLoader() : loader);
            Set<String> names = new HashSet<>(Arrays.asList(methodNames));
            for (Method method : type.getDeclaredMethods()) {
                if (!names.contains(method.getName()) ||
                        (method.getReturnType() != boolean.class && method.getReturnType() != Boolean.class)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> false);
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {}
        return installed;
    }

        private int installExifPrivacyHooks(ClassLoader loader) {
        int installed = 0;
        String[] classes = {"android.media.ExifInterface", "androidx.exifinterface.media.ExifInterface"};
        for (String className : classes) {
            try {
                Class<?> type = Class.forName(className, false, loader == null ? getClass().getClassLoader() : loader);
                for (Method method : type.getDeclaredMethods()) {
                    String name = method.getName();
                    if ("setAttribute".equals(name) && method.getParameterTypes().length == 2 &&
                            method.getParameterTypes()[0] == String.class &&
                            method.getParameterTypes()[1] == String.class &&
                            method.getReturnType() == void.class) {
                        // Prevent selected apps from writing GPS/device/time EXIF tags
                        // back into exported images; read-side filtering alone is incomplete.
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object tag = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            if (tag instanceof String && isSensitiveExifTag((String) tag)) return null;
                            return chain.proceed();
                        });
                        installed++;
                    } else if ("getAttribute".equals(name) && method.getParameterTypes().length == 1 &&
                            method.getParameterTypes()[0] == String.class && method.getReturnType() == String.class) {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object tag = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            if (tag instanceof String && isSensitiveExifTag((String) tag)) return null;
                            return chain.proceed();
                        });
                        installed++;
                    } else if ("getAttributeInt".equals(name) && method.getParameterTypes().length == 2 &&
                            method.getParameterTypes()[0] == String.class &&
                            method.getParameterTypes()[1] == int.class &&
                            method.getReturnType() == int.class) {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object tag = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            if (tag instanceof String && isSensitiveExifTag((String) tag)) return chain.getArgs().get(1);
                            return chain.proceed();
                        });
                        installed++;
                    } else if ("getAttributeDouble".equals(name) && method.getParameterTypes().length == 2 &&
                            method.getParameterTypes()[0] == String.class &&
                            (method.getReturnType() == double.class || method.getReturnType() == Double.class)) {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object tag = chain.getArgs().size() > 0 ? chain.getArgs().get(0) : null;
                            if (tag instanceof String && isSensitiveExifTag((String) tag)) return chain.getArgs().get(1);
                            return chain.proceed();
                        });
                        installed++;
                    } else if ("getLatLong".equals(name) && method.getParameterTypes().length == 1 &&
                            method.getReturnType() == boolean.class) {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> false);
                        installed++;
                    }
                }
            } catch (Throwable ignored) {}
        }
        return installed;
    }

        /** Delegate EXIF tag decisions to ExifPrivacyPolicy (single authoritative rule set). */
    private static boolean isSensitiveExifTag(String tag) {
        return ExifPrivacyPolicy.shouldRedactTag(tag);
    }

                                                                    private void installAdViewHooks(final String pkg, final UnifiedHookConfigParser.Target target) {

        try {
            Method show = Dialog.class.getDeclaredMethod("show");
            hook(show).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                try {
                    Object object = chain.getThisObject();
                    if (object instanceof Dialog) {
                        Window window = ((Dialog) object).getWindow();
                        if (window != null) scheduleRootScans(window.getDecorView(), target, pkg);
                    }
                } catch (Throwable t) {
                    logFx(Log.WARN, "dialog observer failed: " + t.getClass().getSimpleName());
                }
                return result;
            });
            logFx(Log.INFO, "dialog ad observer installed for " + pkg);
        } catch (Throwable t) {
            logFx(Log.WARN, "dialog ad observer unavailable for " + pkg + ": " + t.getClass().getSimpleName());
        }

        int popupHooks = 0;
        try {
            for (Method method : PopupWindow.class.getDeclaredMethods()) {
                String name = method.getName();
                if (!("showAsDropDown".equals(name) || "showAtLocation".equals(name)) ||
                        method.isSynthetic() || method.isBridge()) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        try {
                            Object object = chain.getThisObject();
                            if (object instanceof PopupWindow) {
                                View content = ((PopupWindow) object).getContentView();
                                if (content != null) scheduleRootScans(content, target, pkg);
                            }
                        } catch (Throwable t) {
                            logFx(Log.WARN, "popup observer failed: " + t.getClass().getSimpleName());
                        }
                        return result;
                    });
                    popupHooks++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "popup method enumeration failed: " + t.getClass().getSimpleName());
        }
        logFx(Log.INFO, "popup observers installed=" + popupHooks + " for " + pkg);
        installDynamicAdChildHooks(pkg, target);
    }

    /**
     * Ad SDKs often insert feed/native ad views after Activity.onResume and after
     * the first four delayed scans. Observe child insertion only inside processes
     * already explicitly scoped to a selected app, then check the inserted view itself with the same conservative markers. Child
     * insertions are also observed separately. This covers late-loading/scroll-loaded ads without polling
     * the entire view tree continuously.
     */
    private void installDynamicAdChildHooks(final String pkg, final UnifiedHookConfigParser.Target target) {
        int installed = 0;
        Set<String> hooked = new HashSet<>();

        // Some SDKs attach a prebuilt ad view later, or reparent it after the
        // parent addView call. Observe the final attachment lifecycle as a second
        // path; the delayed check runs on the main thread and uses the same
        // conservative category markers, so unrelated views remain untouched.
        try {
            Method attached = View.class.getDeclaredMethod("onAttachedToWindow");
            hook(attached).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                try {
                    Object object = chain.getThisObject();
                    if (object instanceof View) {
                        scheduleAddedViewCheck((View) object, target, pkg);
                    }
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "view attachment observer failed: " + t.getClass().getSimpleName());
                }
                return result;
            });
            logFx(Log.INFO, "view attachment ad observer installed for " + pkg);
        } catch (Throwable t) {
            logFx(Log.WARN, "view attachment observer unavailable for " + pkg +
                    ": " + t.getClass().getSimpleName());
        }
        try {
            for (Method method : ViewGroup.class.getDeclaredMethods()) {
                if (!"addView".equals(method.getName()) || method.isSynthetic() || method.isBridge()) continue;
                if ((method.getModifiers() & java.lang.reflect.Modifier.PUBLIC) == 0) continue;
                Class<?>[] types = method.getParameterTypes();
                if (types.length == 0 || !View.class.isAssignableFrom(types[0])) continue;
                String signature = method.toGenericString();
                if (!hooked.add(signature)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        try {
                            Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                            if (arg instanceof View) scheduleAddedViewCheck((View) arg, target, pkg);
                        } catch (Throwable t) {
                            logFx(Log.WARN, "dynamic child observer failed: " + t.getClass().getSimpleName());
                        }
                        return result;
                    });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "addView overload unavailable: " + t.getClass().getSimpleName());
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "dynamic addView hooks unavailable: " + t.getClass().getSimpleName());
        }
        logFx(Log.INFO, "dynamic ad child observers installed=" + installed + " for " + pkg);
    }

    private void scheduleAddedViewCheck(final View added, final UnifiedHookConfigParser.Target target, final String pkg) {
        if (added == null) return;
        final Handler handler;
        try { handler = new Handler(Looper.getMainLooper()); }
        catch (Throwable t) { return; }
        try {
            handler.postDelayed(() -> {
                try {
                    if (added.getParent() == null) return;
                    // Inspect the added subtree, not only its outer wrapper. Apps often
                    // insert a generic FrameLayout/RecyclerView holder that already
                    // contains a strongly identified ad view. Passing null as the
                    // scan root makes scanTree evaluate the added root itself as well.
                    scanTree(added, null, 0, new int[]{0}, target, pkg);
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "dynamic ad subtree scan failed: " + t.getClass().getSimpleName());
                }
            }, 80L);
        } catch (Throwable ignored) {}
    }

    private void scheduleScans(final Activity activity, final UnifiedHookConfigParser.Target target) {
        final View decor;
        try {
            if (activity.isFinishing() || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
            decor = activity.getWindow() == null ? null : activity.getWindow().getDecorView();
        } catch (Throwable t) { return; }
        if (decor == null) return;
        long now = System.currentTimeMillis();
        synchronized (lastActivityScan) {
            Long prior = lastActivityScan.get(activity);
            if (prior != null && now - prior < 350L) return;
            lastActivityScan.put(activity, now);
        }
        scheduleRootScans(decor, target, activity.getPackageName());
    }

    private void scheduleRootScans(final View initialRoot, final UnifiedHookConfigParser.Target target, final String pkg) {
        if (initialRoot == null) return;
        long now = System.currentTimeMillis();
        synchronized (lastRootScan) {
            Long prior = lastRootScan.get(initialRoot);
            if (prior != null && now - prior < 350L) return;
            lastRootScan.put(initialRoot, now);
        }
        final Handler handler;
        try { handler = new Handler(Looper.getMainLooper()); }
        catch (Throwable t) { logFx(Log.WARN, "main thread handler unavailable"); return; }
        final int[] delays = new int[]{180, 650, 1500, 3200};
        for (final int delay : delays) {
            try {
                handler.postDelayed(() -> {
                    try {
                        View root = initialRoot.getRootView();
                        if (root == null) root = initialRoot;
                        scanTree(root, root, 0, new int[]{0}, target, pkg);
                    } catch (Throwable t) {
                        logFx(Log.WARN, "bounded view scan failed: " + t.getClass().getSimpleName());
                    }
                }, delay);
            } catch (Throwable ignored) {}
        }
    }

    private void scanTree(View view, View root, int depth, int[] count, UnifiedHookConfigParser.Target target, String pkg) {
        if (view == null || depth > 20 || count[0]++ >= 1800) return;
        if (view != root && shouldHide(view, target)) {
            // Preserve a generic ad container when reward UI is nested inside it.
            if (containsRewardedUiSignal(view, 100, 0)) {
                recordRewardedAdEvidence("container " + shortName(view.getClass().getName())
                        + " action=preserve-reward-flow");
            } else {
                try {
                    if (view.getVisibility() != View.GONE) {
                        view.setVisibility(View.GONE);
                        logFx(Log.INFO, "hidden ad view in " + pkg + " class=" + shortName(view.getClass().getName()));
                    }
                    return;
                } catch (Throwable ignored) {}
            }
        }
        if (!(view instanceof ViewGroup)) return;
        ViewGroup group = (ViewGroup) view;
        int n;
        try { n = group.getChildCount(); } catch (Throwable t) { return; }
        for (int i = 0; i < n && count[0] < 1800; i++) {
            View child;
            try { child = group.getChildAt(i); } catch (Throwable t) { continue; }
            scanTree(child, root, depth + 1, count, target, pkg);
        }
    }

    private boolean shouldHide(View view, UnifiedHookConfigParser.Target target) {
        String cls = lower(view.getClass().getName());
        String id = resourceName(view);
        String evidence = cls + " " + id;
        // Never hide a view identified as a rewarded/incentivized flow: removing it can
        // interrupt the SDK callback chain and make legitimate rewards fail. Observe only.
        if (isRewardedFlowEvidence(evidence)) {
            recordRewardedAdEvidence("view " + shortName(cls) + (id.isEmpty() ? "" : " id=" + id));
            return false;
        }
        if (BuiltInHookRules.matches(view.getContext().getPackageName(), evidence, target)) return true;
        if (matchesCustomRule(evidence, target)) return true;
        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);
        boolean sdkNamespace = hasAny(cls, AD_CLASS_MARKERS);
        // A SDK namespace alone is not proof that every custom View is an ad:
        // SDK packages may also contain controls, placeholders and telemetry views.
        boolean sdkAdView = sdkNamespace && hasAny(cls, STRONG_AD_MARKERS);
        if (!strong && !sdkAdView) {
            if (view instanceof TextView && hasAdLabel((TextView) view)) {
                ParentEvidence parent = findStrongAdParent(view);
                return parent != null && categoryMatches(parent.value, target, false);
            }
            return false;
        }
        return categoryMatches(evidence, target, sdkAdView);
    }

    private static boolean isRewardedFlowEvidence(String evidence) {
        return evidence != null && hasAny(lower(evidence), REWARDED_FLOW_MARKERS);
    }

    /**
     * Bounded descendant inspection for reward-specific UI signals. Text is checked
     * in memory only and is never logged; matching containers are preserved.
     */
    private static boolean containsRewardedUiSignal(View view, int budget, int depth) {
        if (view == null || budget <= 0 || depth > 12) return false;
        String evidence = lower(view.getClass().getName()) + " " + resourceName(view);
        if (isRewardedFlowEvidence(evidence)) return true;
        if (view instanceof TextView) {
            try {
                TextView text = (TextView) view;
                if (isRewardedFlowEvidence(String.valueOf(text.getText()))
                        || isRewardedFlowEvidence(String.valueOf(text.getContentDescription()))) return true;
            } catch (Throwable ignored) {}
        }
        if (!(view instanceof ViewGroup)) return false;
        ViewGroup group = (ViewGroup) view;
        int count;
        try { count = Math.min(group.getChildCount(), budget); }
        catch (Throwable ignored) { return false; }
        for (int i = 0; i < count; i++) {
            if (containsRewardedUiSignal(group.getChildAt(i), budget - i - 1, depth + 1)) return true;
        }
        return false;
    }

    private void recordRewardedAdEvidence(String evidence) {
        if (evidence == null || rewardedAdEvidence.size() >= MAX_REWARDED_AD_EVIDENCE) return;
        if (rewardedAdEvidence.add(evidence)) {
            logFx(Log.INFO, "rewarded-ad lifecycle candidate=" + evidence
                    + " action=observe-only; reward callback/server validation unchanged");
        }
    }

    private boolean matchesCustomRule(String evidence, UnifiedHookConfigParser.Target target) {
        if (target == null || target.customRules.isEmpty()) return false;
        for (Map.Entry<String, Set<String>> entry : target.customRules.entrySet()) {
            boolean categoryEnabled;
            switch (entry.getKey()) {
                case "splash": categoryEnabled = target.splash; break;
                case "feed": categoryEnabled = target.feed; break;
                case "overlay": categoryEnabled = target.overlay; break;
                default: categoryEnabled = false;
            }
            if (!categoryEnabled) continue;
            for (String token : entry.getValue()) {
                if (evidence.contains(token)) return true;
            }
        }
        return false;
    }

    private ParentEvidence findStrongAdParent(View view) {
        android.view.ViewParent p = view.getParent();
        for (int depth = 0; depth < 3 && p instanceof View; depth++, p = p.getParent()) {
            View v = (View) p;
            String evidence = lower(v.getClass().getName()) + " " + resourceName(v);
            if (hasAny(evidence, STRONG_AD_MARKERS)) return new ParentEvidence(evidence);
        }
        return null;
    }

    private boolean categoryMatches(String evidence, UnifiedHookConfigParser.Target target, boolean sdkView) {
        String e = lower(evidence);
        if (hasAny(e, SPLASH_MARKERS)) return target.splash;
        if (hasAny(e, OVERLAY_MARKERS)) return target.overlay;
        if (hasAny(e, FEED_MARKERS)) return target.feed;
        // Do not assign an unclassified ad marker to whichever category happens
        // to be the only enabled one. That makes the category switches misleading
        // and can hide unrelated UI. SDK-specific ad classes default to feed only
        // when the feed category is enabled.
        if (sdkView) return target.feed;
        return false;
    }

    private static boolean hasAdLabel(TextView text) {
        try {
            CharSequence content = text.getText();
            CharSequence desc = text.getContentDescription();
            String all = lower(String.valueOf(content)) + " " + lower(String.valueOf(desc));
            return all.equals("广告") || all.contains("广告位") || all.contains("赞助") ||
                    all.contains("sponsored") || all.contains("advertisement") ||
                    all.equals("ad choices") || all.contains("跳过广告");
        } catch (Throwable ignored) { return false; }
    }

    private static String resourceName(View view) {
        try {
            int id = view.getId();
            if (id == View.NO_ID) return "";
            Resources r = view.getResources();
            return r == null ? "" : lower(r.getResourceEntryName(id));
        } catch (Throwable ignored) { return ""; }
    }

    /**
     * Runtime discovery for explicitly selected, developer-authorized targets.
     * Records bounded class/method-name evidence from resumed Activities. It does not
     * infer entitlement or modify results; candidates require evidence-driven review.
     */
    private void installActivityResumeObserver(final String pkg,
                                               final UnifiedHookConfigParser.Target target,
                                               final boolean observeAds,
                                               final boolean observeMemberFlow) {
        try {
            Method resume = Instrumentation.class.getDeclaredMethod("callActivityOnResume", Activity.class);
            hook(resume).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                try {
                    Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    if (arg instanceof Activity) {
                        Activity activity = (Activity) arg;
                        if (pkg.equals(activity.getPackageName())) {
                            if (observeAds) scheduleScans(activity, target);
                            if (observeMemberFlow) {
                                // Billing libraries may load after the package-ready callback.
                                // Retry on resumed activities; successful hooks are de-duplicated.
                                installReadOnlyBillingDiagnostics(activity.getClassLoader());
                                discoverMemberFlowEvidence(activity);
                                startBoundedMemberDexScan(activity, pkg);
                            }
                        }
                    }
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "activity resume observer failed=" + t.getClass().getSimpleName());
                }
                return result;
            });
            logFx(Log.INFO, "shared activity resume observer installed for " + pkg +
                    " ads=" + observeAds + " memberDiagReadOnly=" + observeMemberFlow);
        } catch (Throwable t) {
            logFx(Log.WARN, "activity resume observer unavailable for " + pkg +
                    " reason=" + t.getClass().getSimpleName());
        }
    }

    private void installMemberFlowDiscovery(final String pkg) {
        installDynamicMemberClassDiscovery(pkg);
        logFx(Log.INFO, "member runtime discovery installed for " + pkg +
                " mode=observe-only evidenceLimit=" + MAX_MEMBER_DISCOVERY_EVIDENCE);
    }

    /**
     * Bounded, read-only candidate scan of the selected app's own APK DEX entries.
     * It does not alter methods, purchase results, or server-side entitlements.
     */
    private void startBoundedMemberDexScan(final Activity activity, final String pkg) {
        if (memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE
                || !memberDexScanStarted.add(pkg)) return;
        final String[] apkPaths;
        try {
            android.content.pm.ApplicationInfo appInfo = activity.getApplicationInfo();
            String[] splits = appInfo.splitSourceDirs;
            int splitCount = splits == null ? 0 : splits.length;
            apkPaths = new String[1 + splitCount];
            apkPaths[0] = appInfo.sourceDir;
            for (int i = 0; i < splitCount; i++) apkPaths[i + 1] = splits[i];
        } catch (Throwable t) {
            memberDexScanStarted.remove(pkg);
            logFx(Log.DEBUG, "member DEX scan unavailable: APK paths inaccessible; retry allowed");
            return;
        }
        Thread worker = new Thread(() -> {
            int inspected = 0;
            int apkFilesScanned = 0;
            long deadline = System.nanoTime() + MAX_MEMBER_DEX_SCAN_MILLIS * 1_000_000L;
            ClassLoader loader = activity.getClassLoader();
            boolean bounded = false;
            try {
                for (String apkPath : apkPaths) {
                    if (apkPath == null || apkPath.isEmpty()
                            || inspected >= MAX_MEMBER_DEX_CLASSES
                            || System.nanoTime() >= deadline
                            || memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) {
                        bounded = true;
                        break;
                    }
                    DexFile dex = null;
                    try {
                        dex = new DexFile(apkPath);
                        apkFilesScanned++;
                        Enumeration<String> names = dex.entries();
                        while (names.hasMoreElements() && inspected < MAX_MEMBER_DEX_CLASSES
                                && System.nanoTime() < deadline
                                && memberDiscoveryEvidence.size() < MAX_MEMBER_DISCOVERY_EVIDENCE) {
                            String name = names.nextElement();
                            inspected++;
                            if (name == null || !name.startsWith(pkg + ".")) continue;
                            boolean classCandidate = containsMemberMarker(name);
                            try {
                                Class<?> candidate = Class.forName(name, false, loader);
                                if (classCandidate) recordMemberEvidence("dex-class " + name);
                                // Feed APK-scanned classes through the same bounded obfuscation-aware
                                // path as classes observed at runtime, not only semantic-name matching.
                                inspectDynamicallyLoadedMemberClass(candidate);
                            } catch (Throwable ignored) {
                                // Obfuscated, optional, or unavailable classes are skipped independently.
                            }
                        }
                        if (names.hasMoreElements() || inspected >= MAX_MEMBER_DEX_CLASSES
                                || System.nanoTime() >= deadline
                                || memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) {
                            bounded = true;
                            break;
                        }
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "member DEX file unavailable=" + t.getClass().getSimpleName());
                    } finally {
                        if (dex != null) {
                            try {
                                dex.close();
                            } catch (Throwable ignored) {
                                // Closing a read-only DEX handle is best-effort on older Android releases.
                            }
                        }
                    }
                }
                logFx(Log.INFO, "member DEX candidate scan finished for " + pkg
                        + " apkFilesScanned=" + apkFilesScanned
                        + " classesInspected=" + inspected
                        + " bounded=" + bounded
                        + " evidenceCount=" + memberDiscoveryEvidence.size());
            } catch (Throwable t) {
                logFx(Log.DEBUG, "member DEX scan unavailable=" + t.getClass().getSimpleName());
            }
        }, "FX-member-dex-scan");
        worker.setDaemon(true);
        worker.start();
    }

    /**
     * Observe classes as the selected app loads them, including secondary/dynamic
     * loaders. Only classes in the opted-in app package are inspected; inspection
     * and any method hooks are bounded and preserve every original return value.
     */
    private void installDynamicMemberClassDiscovery(final String pkg) {
        try {
            Method loadClass = ClassLoader.class.getDeclaredMethod("loadClass", String.class);
            hook(loadClass).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                observeLoadedMemberClass(result, pkg);
                return result;
            });
            int hooksInstalled = 1;
            try {
                Method resolveLoadClass = ClassLoader.class.getDeclaredMethod(
                        "loadClass", String.class, boolean.class);
                hook(resolveLoadClass).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object result = chain.proceed();
                            observeLoadedMemberClass(result, pkg);
                            return result;
                        });
                hooksInstalled++;
            } catch (Throwable optionalOverloadUnavailable) {
                logFx(Log.DEBUG, "two-argument class loading observer unavailable");
            }
            logFx(Log.INFO, "dynamic member class discovery installed for " + pkg
                    + " mode=observe-only classLimit=" + MAX_DYNAMIC_MEMBER_CLASSES
                    + " loaderHooks=" + hooksInstalled);
        } catch (Throwable t) {
            logFx(Log.WARN, "dynamic member class discovery unavailable for " + pkg
                    + " reason=" + t.getClass().getSimpleName());
        }
    }

    private void observeLoadedMemberClass(Object result, String pkg) {
        if (!(result instanceof Class<?>)) return;
        try {
            Class<?> loaded = (Class<?>) result;
            String name = loaded.getName();
            if (name.startsWith(pkg + ".")) inspectDynamicallyLoadedMemberClass(loaded);
        } catch (Throwable t) {
            logFx(Log.DEBUG, "dynamic member class observation failed="
                    + t.getClass().getSimpleName());
        }
    }

    private void inspectDynamicallyLoadedMemberClass(Class<?> type) {
        if (type == null || memberClassesInspected.size() >= MAX_DYNAMIC_MEMBER_CLASSES) return;
        String className = type.getName();
        if (!className.startsWith(currentPackage + ".")) return;
        if (!memberClassesInspected.add(className)) return;
        inspectMemberCandidateClass(type);
        boolean memberContext = containsMemberMarker(className) || hasMemberStateField(type)
                || hasMemberStateType(type);
        // Obfuscation can erase semantic names. Inspect compact methods only when
        // their class has independent membership evidence, reducing false positives.
        try {
            for (Method method : type.getDeclaredMethods()) {
                if (memberMethodsHooked.size() >= MAX_AUTO_MEMBER_METHOD_HOOKS
                        || memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) break;
                String name = method.getName();
                Class<?>[] params = method.getParameterTypes();
                Class<?> result = method.getReturnType();
                boolean primitiveStatus = params.length == 0
                        && (result == boolean.class || result == Boolean.class
                        || result == int.class || result == Integer.class);
                boolean compactObfuscatedName = name.length() <= 2
                        && name.matches("[a-zA-Z_$][a-zA-Z0-9_$]*");
                if (primitiveStatus && compactObfuscatedName && memberContext) {
                    recordMemberEvidence("obfuscated-status-candidate " + type.getName()
                            + "#" + name + "(): " + result.getSimpleName());
                    installReadOnlyMemberCandidateHook(type, method, true);
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "obfuscated member method inspection unavailable="
                    + t.getClass().getSimpleName());
        }
    }

    private boolean hasMemberStateField(Class<?> type) {
        try {
            for (java.lang.reflect.Field field : type.getDeclaredFields()) {
                String name = lower(field.getName());
                for (String marker : MEMBER_STATE_FIELD_MARKERS) {
                    if (name.contains(marker)) {
                        recordMemberEvidence("member-field-candidate " + type.getName()
                                + "#" + field.getName() + ":" + field.getType().getSimpleName());
                        return true;
                    }
                }
            }
        } catch (Throwable ignored) {
            // Field metadata may be hidden by the runtime or vendor policy.
        }
        return false;
    }

    private boolean hasMemberStateType(Class<?> type) {
        try {
            for (Class<?> iface : type.getInterfaces()) {
                if (containsMemberMarker(iface.getName())) {
                    recordMemberEvidence("member-interface-candidate " + type.getName()
                            + " implements " + iface.getName());
                    return true;
                }
            }
            Class<?> parent = type.getSuperclass();
            return parent != null && parent != Object.class && containsMemberMarker(parent.getName());
        } catch (Throwable ignored) {
            return false;
        }
    }

    private void discoverMemberFlowEvidence(Activity activity) {
        if (memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) return;
        Class<?> type = activity.getClass();
        int hierarchyDepth = 0;
        while (type != null && type != Activity.class && hierarchyDepth++ < 6
                && memberDiscoveryEvidence.size() < MAX_MEMBER_DISCOVERY_EVIDENCE) {
            inspectMemberCandidateClass(type);
            type = type.getSuperclass();
        }
        // Inspect resource identifiers only, never visible text or input values.
        // This gives the next analysis stage stable UI anchors without collecting personal data.
        try {
            View decor = activity.getWindow() == null ? null : activity.getWindow().getDecorView();
            if (decor != null) inspectMemberViewTree(activity, decor, new int[]{0});
        } catch (Throwable t) {
            logFx(Log.DEBUG, "member resource inspection unavailable=" + t.getClass().getSimpleName());
        }
    }

    private void inspectMemberViewTree(Activity activity, View view, int[] visited) {
        if (view == null || visited[0] >= 160
                || memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) return;
        visited[0]++;
        try {
            int id = view.getId();
            if (id != View.NO_ID) {
                String entry = activity.getResources().getResourceEntryName(id);
                if (containsMemberMarker(entry)) {
                    recordMemberEvidence("resource " + activity.getPackageName() + ":id/" + entry
                            + " view=" + view.getClass().getName());
                }
            }
        } catch (Resources.NotFoundException ignored) {
            // Dynamically generated IDs have no stable resource entry name.
        } catch (Throwable t) {
            logFx(Log.DEBUG, "member resource name unavailable=" + t.getClass().getSimpleName());
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            int count = Math.min(group.getChildCount(), 160 - visited[0]);
            for (int i = 0; i < count; i++) {
                inspectMemberViewTree(activity, group.getChildAt(i), visited);
                if (memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) return;
            }
        }
    }

    private void inspectMemberCandidateClass(Class<?> type) {
        String className = type.getName();
        if (containsMemberMarker(className)) recordMemberEvidence("class " + className);
        try {
            for (Method method : type.getDeclaredMethods()) {
                if (memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) break;
                String methodName = method.getName();
                if (!containsMemberMarker(methodName)) continue;
                StringBuilder signature = new StringBuilder("method ")
                        .append(className).append("#").append(methodName).append("(");
                Class<?>[] params = method.getParameterTypes();
                for (int i = 0; i < params.length; i++) {
                    if (i > 0) signature.append(",");
                    signature.append(params[i].getSimpleName());
                }
                signature.append("):").append(method.getReturnType().getSimpleName());
                recordMemberEvidence(signature.toString());
                installReadOnlyMemberCandidateHook(type, method);
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "member method inspection unavailable for " + className +
                    " reason=" + t.getClass().getSimpleName());
        }
    }

    /**
     * Automatically hook candidate no-argument boolean member-state getters for
     * observation only. This helps map app-side entitlement flow without changing
     * VIP state, purchase results, network responses, or server-side authorization.
     */
    private void installReadOnlyMemberCandidateHook(Class<?> owner, Method method) {
        installReadOnlyMemberCandidateHook(owner, method, false);
    }

    private void installReadOnlyMemberCandidateHook(Class<?> owner, Method method,
                                                    boolean allowCompactObfuscatedName) {
        if (owner == null || method == null
                || memberMethodsHooked.size() >= MAX_AUTO_MEMBER_METHOD_HOOKS
                || method.getParameterTypes().length != 0) return;
        Class<?> resultType = method.getReturnType();
        boolean booleanState = resultType == boolean.class || resultType == Boolean.class;
        boolean integerState = resultType == int.class || resultType == Integer.class;
        if (!booleanState && !(allowCompactObfuscatedName && integerState)) return;
        String methodName = lower(method.getName());
        boolean semanticCandidate = containsMemberMarker(methodName)
                || methodName.startsWith("is") || methodName.startsWith("has")
                || methodName.startsWith("can") || methodName.startsWith("get")
                || methodName.startsWith("check");
        boolean compactCandidate = allowCompactObfuscatedName && methodName.length() <= 2;
        if (!semanticCandidate && !compactCandidate) return;
        String key = owner.getName() + "#" + method.getName();
        if (!memberMethodsHooked.add(key)) return;
        try {
            hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                if (result instanceof Boolean || result instanceof Integer) {
                    logFx(Log.INFO, "member state observation " + key + "="
                            + result.toString() + " mode=read-only");
                }
                return result;
            });
            logFx(Log.INFO, "auto member candidate hook installed=" + key + " mode=read-only");
        } catch (Throwable t) {
            memberMethodsHooked.remove(key);
            logFx(Log.DEBUG, "auto member candidate hook unavailable=" + shortName(key)
                    + " reason=" + t.getClass().getSimpleName());
        }
    }

    private boolean containsMemberMarker(String value) {
        String normalized = lower(value == null ? "" : value);
        for (String marker : MEMBER_FLOW_MARKERS) if (normalized.contains(marker)) return true;
        return false;
    }

    private void recordMemberEvidence(String evidence) {
        if (evidence == null || evidence.length() > 512) return;
        if (memberDiscoveryEvidence.size() >= MAX_MEMBER_DISCOVERY_EVIDENCE) return;
        if (memberDiscoveryEvidence.add(evidence)) logFx(Log.INFO, "member discovery candidate=" + evidence);
    }

    private void installReadOnlyBillingDiagnostics(ClassLoader loader) {
        int installed = 0;
        // Hook concrete value getters which apps actually call. Hooking abstract
        // BillingClient declarations alone can look successful while never firing.
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.BillingResult",
                "getResponseCode", "billing responseCode")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "getPurchaseState", "billing purchaseState")) installed++;
        // Additional read-only evidence helps distinguish a completed purchase from
        // an unacknowledged/pending state without changing any entitlement or result.
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "isAcknowledged", "billing purchaseAcknowledged")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "isAutoRenewing", "billing purchaseAutoRenewing")) installed++;
        // BillingClient.isReady() is abstract in the public API. Observe the concrete
        // implementation when present; never report an abstract declaration as active.
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.BillingClientImpl",
                "isReady", "billing clientReady")) installed++;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "read-only billing diagnostics installed=" + installed + "/5");
    }

    /**
     * Read numeric status fields only. Never log product IDs, account data,
     * purchase JSON, obfuscated account IDs or purchase tokens.
     */
    private boolean installBillingValueDiagnostic(ClassLoader loader, String className,
                                                  String methodName, String label) {
        try {
            Class<?> type = Class.forName(className, false, loader);
            Method method = type.getMethod(methodName);
            if (Modifier.isAbstract(method.getModifiers())) {
                logFx(Log.DEBUG, "value diagnostic skipped abstract method=" + className + "#" + methodName);
                return false;
            }
            String hookKey = System.identityHashCode(loader) + ":" + className + "#" + methodName;
            if (billingDiagnosticHooksInstalled.contains(hookKey)) return true;
            if (!billingDiagnosticHooksInstalled.add(hookKey)) return true;
            try {
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                // Observe the real return value exactly once. Never replace, synthesize,
                // or retain purchase objects/tokens; cap each signal to avoid log spam.
                Object result = chain.proceed();
                AtomicInteger counter = billingDiagnosticLogCounts.computeIfAbsent(
                        label, ignored -> new AtomicInteger(0));
                if (counter.incrementAndGet() <= MAX_BILLING_DIAGNOSTIC_LOGS) {
                    if (result instanceof Number) {
                        logFx(Log.INFO, label + "=" + ((Number) result).intValue());
                    } else if (result instanceof Boolean) {
                        logFx(Log.INFO, label + "=" + ((Boolean) result).booleanValue());
                    }
                }
                    return result;
                });
            } catch (Throwable hookError) {
                billingDiagnosticHooksInstalled.remove(hookKey);
                throw hookError;
            }
            logFx(Log.INFO, "read-only value diagnostic installed=" + label);
            return true;
        } catch (Throwable t) {
            logFx(Log.DEBUG, "value diagnostic unavailable=" + label + " reason=" + t.getClass().getSimpleName());
            return false;
        }
    }

    private static String lower(String value) {
        return value == null ? "" : value.toLowerCase(Locale.ROOT);
    }

    private static boolean hasAny(String value, String[] tokens) {
        for (String token : tokens) if (value.contains(token)) return true;
        return false;
    }

    private static String shortName(String value) {
        if (value == null) return "?";
        int i = value.lastIndexOf('.');
        return i >= 0 ? value.substring(i + 1) : value;
    }

    private void logFx(int priority, String message) {
        try { log(priority, TAG, message); } catch (Throwable ignored) {}
    }
}
