package de.privacyguard.adhook;

import android.app.Activity;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.hardware.Camera;
import android.hardware.camera2.CameraManager;
import android.location.LocationManager;
import android.app.Dialog;
import android.app.Instrumentation;
import android.app.Application;
import de.privacyguard.hook.DiaFridaGadgetLoader;
import de.privacyguard.adhook.imported.dia.FxDiaDialogMatchPolicy;
import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicy;
import de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicyRegistry;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import dalvik.system.DexFile;
import android.content.ContentResolver;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.provider.Settings;
import android.content.res.Resources;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.view.View;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Toast;
import android.widget.PopupWindow;
import android.widget.TextView;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.ConcurrentHashMap;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedModuleInterface;

/**
 * FX Hook (unified modern libxposed runtime).
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
    private static final String TAG = "FX Hook";
    private static final String CONFIG_NAME = "fx-hook-targets.conf";
    private static final int MAX_DYNAMIC_MEMBER_CLASSES = 32;
    // addView can fire repeatedly during scrolling; cap each dynamic subtree walk.
    private static final int MAX_DYNAMIC_AD_SCAN_NODES = 400;
    private static final int MAX_DYNAMIC_AD_SCAN_DEPTH = 12;
    private static final int MAX_MEMBER_METADATA_PROBES = 512;
    private static final int MAX_AUTO_MEMBER_METHOD_HOOKS = 8;
    private static final int MAX_REWARDED_AD_EVIDENCE = 96;
    private static final int MAX_MEMBER_STATE_OBSERVATIONS = 64;
    private static final String[] MEMBER_STATE_FIELD_MARKERS = {
            "vip", "premium", "member", "entitle", "subscription", "purchase",
            "license", "expire", "active", "paid", "tier", "level", "valid", "benefit"
    };
    private static final String[] REWARDED_FLOW_MARKERS = {
            "领取金币", "看视频领", "看广告领", "激励视频", "广告奖励",
            "rewarded", "watch video", "watch ad", "claim reward", "earn coins"
    };
    private static final Set<String> NEVER = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook", "org.lsposed.manager",
            // Never install automatic View interception into Android's core UI,
            // permission, telephony, package, storage, network or input services.
            "com.android.systemui", "com.android.settings", "com.android.providers.settings",
            "com.android.providers.media", "com.android.providers.downloads",
            "com.android.providers.downloads.ui", "com.android.documentsui",
            "com.android.permissioncontroller", "com.google.android.permissioncontroller",
            "com.android.packageinstaller", "com.android.shell", "com.android.phone",
            "com.android.server.telecom", "com.android.networkstack",
            "com.android.networkstack.tethering", "com.android.bluetooth", "com.android.nfc",
            "com.android.inputmethod.latin", "com.google.android.inputmethod.latin",
            "com.google.android.gms", "com.google.android.gsf", "com.android.vending")));
    private static final String[] AD_CLASS_MARKERS = {
            "com.google.android.gms.ads", "com.bytedance.sdk.openadsdk", "com.pangle",
            "com.qq.e.ads", "com.kwad.sdk", "com.baidu.mobads",
            "com.applovin", "com.facebook.ads", "com.unity3d.services.ads", "com.sigmob.sdk",
            "com.huawei.hms.ads", "com.huawei.openalliance.ad",
            "com.miui.zeus.mimo.sdk", "com.xiaomi.ad",
            "com.heytap.msp.mobad.api", "com.vivo.mobilead",
            "com.hihonor.adsdk", "com.meishu.sdk"
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
            "adbanner", "videoadview",
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
            "bannercontainer", "adbanner", "videoadview"
    };
    private static final String[] OVERLAY_MARKERS = {
            "interstitial", "rewardedad", "rewarded_ad", "fullscreenad",
            "full_screen_ad", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };

    // Ad category selection is automatic for every eligible app.
    // Privacy and read-only diagnostics remain explicitly scoped per package.
    private static final UnifiedHookConfigParser.Target AUTO_AD_TARGET =
            new UnifiedHookConfigParser.Target(true, true, true, false, false, false, false);

    private final Map<String, UnifiedHookConfigParser.Target> targets = new HashMap<>();
    private final Set<String> hooksInstalledFor = ConcurrentHashMap.newKeySet();
    private final Set<String> processPackages = ConcurrentHashMap.newKeySet();
    private final Set<String> debuggablePackages = ConcurrentHashMap.newKeySet();
    private final Set<String> diaKeyGesturePackages = ConcurrentHashMap.newKeySet();
    private final Map<String, Boolean> diaKeyDialogActive = new ConcurrentHashMap<>();
    private final FxDiaKeyGesturePolicyRegistry diaKeyGesturePolicies =
            new FxDiaKeyGesturePolicyRegistry();
    private volatile boolean diaKeyGestureDispatchHookInstalled;
    private volatile boolean diaKeyGestureLongPressHookInstalled;
    // Settings.Secure.getString is process-global. Register one interceptor per process;
    // adding one per package would stack transforms when a process exposes multiple packages.
    private volatile boolean privacyIdentifierHookInstalled;
    private volatile boolean telephonyIdentifierHooksInstalled;
    private volatile boolean clipboardReadHooksInstalled;
    // Track each successful accessor independently so partial ART hook failures
    // can be retried on a later eligible package load without stacking hooks.
    private final Set<Method> clipboardReadHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean clipboardIsolationHooksInstalled;
    private final Set<Method> clipboardIsolationHookedMethods = ConcurrentHashMap.newKeySet();
    private static volatile Object processClipboardShadow;
    private volatile boolean sensorHooksInstalled;
    private volatile boolean wifiScanHooksInstalled;
    private final Set<Method> wifiScanHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> notificationListenHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean wifiInfoSimulationHooksInstalled;
    private volatile boolean networkTypeSimulationHooksInstalled;
    private volatile boolean locationSimulationHooksInstalled;
    private volatile boolean locationProviderEnabledHooksInstalled;
    private volatile boolean timeZoneSimulationHooksInstalled;
    private volatile boolean appVersionSimulationHooksInstalled;
    private volatile boolean notificationListenHooksInstalled;
    private volatile boolean notificationPermissionHooksInstalled;
    private final Set<Method> notificationPermissionHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean diaToastHooksInstalled;
    private final Set<Method> diaToastHookedMethods = ConcurrentHashMap.newKeySet();
    private final Map<Toast, DiaToastPayload> diaToastPayloads =
            Collections.synchronizedMap(new WeakHashMap<>());
    private final Set<Method> microphoneSilenceHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> cameraAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> microphoneAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> locationAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> mediaStoreQueryHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> advertisingIdHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> developerTestHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<java.lang.reflect.Executable> developerTypedReturnHookedExecutables = ConcurrentHashMap.newKeySet();
    private final Set<java.lang.reflect.Executable> developerVoidNoOpHookedExecutables = ConcurrentHashMap.newKeySet();
    private final Set<java.lang.reflect.Executable> developerPassthroughHookedExecutables = ConcurrentHashMap.newKeySet();
    private final Set<java.lang.reflect.Executable> developerObservedExecutables = ConcurrentHashMap.newKeySet();
    private volatile boolean activityObserverInstalled;
    private volatile boolean dialogObserverInstalled;
    private volatile boolean dialogWindowAddViewHooksInstalled;
    private final Set<String> dialogWindowAddViewMethods = ConcurrentHashMap.newKeySet();
    private final Map<String, Long> dialogNotifyLastShown = new ConcurrentHashMap<>();
    private volatile boolean popupObserversInstalled;
    private volatile boolean dynamicChildObserversInstalled;
    private volatile boolean dynamicMemberDiscoveryInstalled;
    private final Set<String> memberCandidateClasses = ConcurrentHashMap.newKeySet();
    private final Set<String> memberMetadataInspectedClasses = ConcurrentHashMap.newKeySet();
    private final Set<String> memberHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<String> rewardedEvidenceSeen = ConcurrentHashMap.newKeySet();
    private final AtomicInteger memberClassesInspected = new AtomicInteger();
    private final AtomicInteger memberMetadataProbes = new AtomicInteger();
    private final AtomicInteger memberMethodsHooked = new AtomicInteger();
    private final AtomicInteger rewardedEvidenceCount = new AtomicInteger();
    private final AtomicInteger memberStateObservationCount = new AtomicInteger();
    private final Set<String> popupObserverMethods = ConcurrentHashMap.newKeySet();
    private final Set<String> dynamicChildObserverMethods = ConcurrentHashMap.newKeySet();
    private final WeakHashMap<Activity, Long> lastActivityScan = new WeakHashMap<>();
    private final WeakHashMap<View, Long> lastRootScan = new WeakHashMap<>();
    private final WeakHashMap<View, Long> lastAddedViewScan = new WeakHashMap<>();
    // Restore the exact pre-hook visibility when an ad view is reused or detached.
    private final WeakHashMap<View, Integer> hiddenAdViews = new WeakHashMap<>();
    private final WeakHashMap<View, Boolean> externallyChangedAdViews = new WeakHashMap<>();
    private final ThreadLocal<Boolean> fxVisibilityMutation = ThreadLocal.withInitial(() -> false);
    private volatile boolean visibilityMutationObserverInstalled;
    private final WeakHashMap<View, View.OnAttachStateChangeListener> hiddenAdViewListeners = new WeakHashMap<>();
    private boolean adsEnabled;
    private boolean privacyEnabled;
    private boolean wifiScanEnabled;
    private boolean notificationListenEnabled;
    private boolean notificationPermissionHideEnabled;
    private boolean clipboardIsolationEnabled;
    private boolean configLoaded;
    private boolean remoteFilesAvailable;
    private volatile String currentPackage = "";

    private static final class ParentEvidence {
        final String value;
        ParentEvidence(String value) { this.value = value; }
    }

    @Override
    public void onModuleLoaded(XposedModuleInterface.ModuleLoadedParam param) {
        // Ad recognition is built in and does not depend on Remote Files.
        // Remote Files is needed only for optional per-app privacy/diagnostic policy.
        adsEnabled = true;
        remoteFilesAvailable = (getFrameworkProperties() & XposedInterface.PROP_CAP_REMOTE) != 0;
        if (remoteFilesAvailable) {
            configLoaded = loadConfig();
        } else {
            configLoaded = false;
            targets.clear();
            privacyEnabled = false;
            logFx(Log.WARN, "Remote Files capability unavailable; optional per-app policies remain disabled");
        }
        // A missing/invalid optional config must never disable automatic Ad detection.
        adsEnabled = true;
        logFx(configLoaded
                ? Log.INFO : Log.WARN,
                configLoaded
                        ? "automatic Ad detection enabled; remote per-app policies loaded=" + targets.size()
                        : "automatic Ad detection enabled; optional remote per-app policies unavailable");
    }

    @Override
    public void onPackageReady(XposedModuleInterface.PackageReadyParam param) {
        final String pkg = param.getPackageName() == null ? "" : param.getPackageName();
        currentPackage = pkg;
        processPackages.add(pkg);
        if (NEVER.contains(pkg)) return;
        // Dia Gadget loading is independent of optional remote privacy/ad config.
        // The registered modern libXposed entrypoint reaches the package/process-
        // scoped loader directly; the legacy adapter delegates to the same utility.
        try {
            DiaFridaGadgetLoader.loadForPackage(param.getApplicationInfo(),
                    pkg, Application.getProcessName());
        } catch (Throwable gadgetError) {
            Log.w(TAG, "Dia Frida Gadget loader failed for " + pkg, gadgetError);
        }
        // Continue with automatic Ad recognition even when Remote Files are absent.
        // All optional per-app policy flags below remain false unless a valid config loaded.
        final UnifiedHookConfigParser.Target target = configLoaded ? targets.get(pkg) : null;
        final int applicationFlags = param.getApplicationInfo().flags;
        final boolean debuggableTarget = (applicationFlags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        final boolean systemTarget = (applicationFlags & (ApplicationInfo.FLAG_SYSTEM
                | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0;
        if (debuggableTarget) debuggablePackages.add(pkg);
        else debuggablePackages.remove(pkg);
        final boolean keyGestureForPackage = target != null && !systemTarget
                && (target.keyFinishTrigger >= 0 || target.keyDialogToggleTrigger >= 0);
        if (keyGestureForPackage) {
            diaKeyGesturePackages.add(pkg);
            diaKeyGesturePolicies.forPackage(pkg);
            if (target.keyDialogToggleTrigger >= 0) {
                diaKeyDialogActive.putIfAbsent(pkg, target.dialogMatchEnabled);
            } else {
                diaKeyDialogActive.remove(pkg);
            }
        } else {
            diaKeyGesturePackages.remove(pkg);
            diaKeyGesturePolicies.remove(pkg);
            diaKeyDialogActive.remove(pkg);
        }
        // Custom Hook is explicitly enabled per app and restricted to debuggable builds.
        // OBSERVE records metadata; RETURN_* actions are local Debug fixtures only.
        // They never grant production authorization or modify server-side entitlements.
        boolean developerRuleForPackage = false;
        boolean developerObserveForPackage = false;
        List<DeveloperHookRule> effectiveDeveloperRules = Collections.emptyList();
        if (target != null && target.developerHooksEnabled && debuggableTarget) {
            // Resolve once so package eligibility and installed interceptors use identical priority decisions.
            effectiveDeveloperRules = DeveloperHookRule.selectEffective(target.developerRules);
            for (DeveloperHookRule rule : effectiveDeveloperRules) {
                if (rule.action == DeveloperHookRule.Action.DISABLED) continue;
                developerRuleForPackage = true; // Keeps every active custom action in the package install path.
                if (rule.action == DeveloperHookRule.Action.OBSERVE) {
                    developerObserveForPackage = true;
                }
            }
        }
        // Ad detection is automatic for every non-protected app; the target map
        // remains exclusively for opt-in privacy and read-only diagnostics.
        final boolean adsForPackage = adsEnabled;
        final boolean memberDiagForPackage = target != null && target.memberDiag;
        final boolean privacyForPackage = privacyEnabled && target != null && target.privacy;
        final boolean exifForPackage = privacyEnabled && target != null && target.exifStrip;
        final boolean clipboardBlockForPackage = privacyEnabled && target != null && target.clipboardReadBlock;
        final boolean clipboardIsolateForPackage = privacyEnabled && clipboardIsolationEnabled && target != null && target.clipboardIsolate;
        final boolean sensorForPackage = privacyEnabled && target != null && (target.sensorAccel || target.sensorGyro
                || target.sensorLight || target.sensorMagnet || target.sensorPressure || target.sensorProx
                || target.sensorEnvironment || target.sensorFusion || target.sensorGesture || target.sensorBiometric
                || target.sensorRateLimit);
        final boolean wifiScanForPackage = wifiScanEnabled && target != null && target.wifiScanBlock;
        final boolean wifiSimulationForPackage = target != null && target.wifiSimulation && debuggableTarget;
        final boolean networkTypeSimulationForPackage = target != null && target.networkTypeSimulation && debuggableTarget;
        final boolean locationSimulationForPackage = target != null && target.locationSimulation && debuggableTarget;
        final boolean locationProviderEnabledSimulationForPackage = target != null && target.locationProviderEnabledSimulation && debuggableTarget;
        final boolean androidIdSimulationForPackage = target != null && target.androidIdSimulation && debuggableTarget;
        final boolean timeZoneSimulationForPackage = target != null && target.timeZoneSimulation && debuggableTarget;
        final boolean appVersionSimulationForPackage = target != null && target.appVersionSimulation && debuggableTarget;
        final boolean notificationListenForPackage = notificationListenEnabled && target != null && target.notificationListenBlock;
        final boolean notificationPermissionHideForPackage = notificationPermissionHideEnabled && target != null && target.notificationPermissionHide;
        final boolean microphoneSilenceForPackage = privacyEnabled && target != null && target.microphoneSilence;
        final boolean cameraAccessBlockForPackage = privacyEnabled && target != null && target.cameraAccessBlock;
        final boolean locationAccessBlockForPackage = privacyEnabled && target != null && target.locationAccessBlock;
        final boolean microphoneAccessBlockForPackage = privacyEnabled && target != null && target.microphoneAccessBlock;
        final boolean mediaStoreQueryBlockForPackage = privacyEnabled && target != null && target.mediaStoreQueryBlock;
        final boolean advertisingIdUnifyForPackage = privacyEnabled && target != null && target.adIdUnify;
        final boolean dialogMatchForPackage = target != null
                && target.dialogMatchEnabled && debuggableTarget;
        // Never filter system or updated-system applications, even if a stale or
        // manually crafted Remote Files entry contains a Toast opt-in.
        final boolean toastFilterForPackage = !systemTarget && target != null
                && target.toastFilterEnabled && !target.toastTextTerms.isEmpty();
        if (!adsForPackage && !dialogMatchForPackage && !toastFilterForPackage && !keyGestureForPackage && !memberDiagForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !wifiSimulationForPackage && !networkTypeSimulationForPackage && !locationSimulationForPackage && !locationProviderEnabledSimulationForPackage && !androidIdSimulationForPackage && !timeZoneSimulationForPackage && !appVersionSimulationForPackage && !notificationListenForPackage && !notificationPermissionHideForPackage && !microphoneSilenceForPackage && !cameraAccessBlockForPackage && !locationAccessBlockForPackage && !microphoneAccessBlockForPackage && !mediaStoreQueryBlockForPackage && !advertisingIdUnifyForPackage && !developerRuleForPackage) return;
        // Global observers must get another chance on each eligible package load;
        // a failed registration must not be hidden by the per-package idempotency guard.
        if (adsForPackage || dialogMatchForPackage) installAdViewHooks();
        if (dialogMatchForPackage) installDiaDialogWindowHooks();
        if (toastFilterForPackage) installDiaToastHooks();
        if (keyGestureForPackage) installDiaKeyGestureHooks();
        // Retry privacy registration independently from the one-shot package guard.
        if (privacyForPackage || androidIdSimulationForPackage) installPrivacyIdentifierHooks(pkg);
        if (timeZoneSimulationForPackage) installTimeZoneSimulationHooks(pkg);
        if (appVersionSimulationForPackage) installAppVersionSimulationHooks(pkg);
        if (exifForPackage) installExifStripHooks(param.getClassLoader(), pkg);
        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);
        if (clipboardIsolateForPackage) installClipboardIsolationHooks(pkg);
        if (sensorForPackage) installSensorEnumerationHooks(pkg);
        if (wifiScanForPackage) installWifiScanPrivacyHooks(pkg);
        if (wifiSimulationForPackage) installWifiInfoSimulationHooks(pkg);
        if (networkTypeSimulationForPackage) installNetworkTypeSimulationHooks(pkg);
        if (locationSimulationForPackage || locationProviderEnabledSimulationForPackage) installLocationSimulationHooks(pkg);
        if (notificationListenForPackage) installNotificationListenPrivacyHooks(pkg);
        if (notificationPermissionHideForPackage) installNotificationPermissionPrivacyHooks(pkg);
        if (microphoneSilenceForPackage) installAudioRecordSilenceHooks(pkg);
        if (cameraAccessBlockForPackage) installCameraAccessBlockHooks(pkg);
        if (locationAccessBlockForPackage) installLocationAccessBlockHooks(pkg);
        if (microphoneAccessBlockForPackage) installMicrophoneAccessBlockHooks(pkg);
        if (mediaStoreQueryBlockForPackage) installMediaStoreQueryBlockHooks(pkg);
        if (advertisingIdUnifyForPackage) installAdvertisingIdHooks(param.getClassLoader(), pkg);
        // Member diagnostics are independent of ads/privacy and must run before
        // the unrelated per-package one-shot guard.
        if (memberDiagForPackage) {
            installReadOnlyBillingDiagnostics(param.getClassLoader());
            installDynamicMemberClassDiscovery(param.getClassLoader(), pkg);
        }
        if (target != null && target.developerHooksEnabled && debuggableTarget) {
            // Every action is scoped to a debuggable target and explicit per-app opt-in.
            // Boolean replacement is restricted by DeveloperHookRule.parse to zero-arg boolean methods.
            for (DeveloperHookRule rule : effectiveDeveloperRules) {
                if (developerObserveForPackage && rule.action == DeveloperHookRule.Action.OBSERVE) {
                    installDeveloperObservationHook(param.getClassLoader(), pkg,
                            debuggableTarget, rule.descriptor, rule.id);
                } else if (rule.action == DeveloperHookRule.Action.RETURN_TRUE
                        || rule.action == DeveloperHookRule.Action.RETURN_FALSE) {
                    installDeveloperBooleanTestHook(param.getClassLoader(), pkg,
                            debuggableTarget, rule.descriptor, rule.action, rule.id);
                } else if (rule.action == DeveloperHookRule.Action.RETURN_NULL
                        || rule.action == DeveloperHookRule.Action.RETURN_ZERO
                        || rule.action == DeveloperHookRule.Action.RETURN_EMPTY_STRING) {
                    installDeveloperTypedReturnHook(param.getClassLoader(), pkg,
                            debuggableTarget, rule.descriptor, rule.action, rule.id);
                } else if (rule.action == DeveloperHookRule.Action.RETURN_LITERAL) {
                    installDeveloperLiteralReturnHook(param.getClassLoader(), pkg,
                            debuggableTarget, rule.descriptor, rule.literalValue, rule.id);
                } else if (rule.action == DeveloperHookRule.Action.NO_OP_VOID) {
                    installDeveloperVoidNoOpHook(param.getClassLoader(), pkg, debuggableTarget,
                            rule.descriptor, rule.id);
                } else if (rule.action == DeveloperHookRule.Action.RETURN_ARGUMENT_0
                        || rule.action == DeveloperHookRule.Action.RETURN_THIS) {
                    installDeveloperPassthroughHook(param.getClassLoader(), pkg, debuggableTarget,
                            rule.descriptor, rule.action, rule.id);
                }
            }
        }
        if (!hooksInstalledFor.add(pkg)) return;
        logFx(Log.INFO, "package ready=" + pkg +
                " ads=" + adsForPackage + " privacy=" + privacyForPackage + " exifStrip=" + exifForPackage + " clipboardReadBlock=" + clipboardBlockForPackage + " clipboardIsolate=" + clipboardIsolateForPackage + " sensors=" + sensorForPackage + " wifiScanEnabled=" + wifiScanEnabled + " wifiScanBlock=" + wifiScanForPackage + " notificationListenBlock=" + notificationListenForPackage + " notificationPermissionHide=" + notificationPermissionHideForPackage + " micSilence=" + microphoneSilenceForPackage + " cameraBlock=" + cameraAccessBlockForPackage + " locationBlock=" + locationAccessBlockForPackage + " micAccessBlock=" + microphoneAccessBlockForPackage + " mediaStoreQueryBlock=" + mediaStoreQueryBlockForPackage +
                " adDetection=automatic(splash/feed/overlay)" + " dialogMatchBlock=" + dialogMatchForPackage + " memberDiagReadOnly=" + memberDiagForPackage +
                " sdk=" + Build.VERSION.SDK_INT);
    }

    private String legacyBooleanDescriptor(String descriptor, String packageName) {
        if (descriptor == null || !descriptor.startsWith("L")) return descriptor;
        DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
        if (parsed == null || !parsed.parameterDescriptors.isEmpty()
                || !"Z".equals(parsed.returnDescriptor) || "<init>".equals(parsed.name)) return descriptor;
        return parsed.owner + "#" + parsed.name + "()Z";
    }

    /**
     * Read-only method observer for explicitly opted-in debuggable packages.
     * Logs signature, argument types, result type, duration and exception class only;
     * argument values, tokens, credentials and returned data are never serialized.
     */
    private void installDeveloperObservationHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, String label) {
        if (descriptor == null || !MemberTestGate.isEnabled(debuggableBuild,
                targetDeveloperOptIn(packageName), packageName, packageName)) return;
        DeveloperExecutableDescriptor parsed;
        try {
            String jvmDescriptor = descriptor;
            if (!jvmDescriptor.startsWith("L")) {
                int split = jvmDescriptor.indexOf('#');
                if (split <= 0 || !jvmDescriptor.endsWith("()Z")) return;
                jvmDescriptor = "L" + jvmDescriptor.substring(0, split).replace('.', '/')
                        + ";->" + jvmDescriptor.substring(split + 1, jvmDescriptor.length() - 3) + "()Z";
            }
            parsed = DeveloperExecutableDescriptor.parse(jvmDescriptor, packageName);
            if (parsed == null) return;
            java.lang.reflect.Executable executable = parsed.resolve(loader);
            if (executable == null || developerObservedExecutables.contains(executable)) return;
            final String executableName = "<init>".equals(parsed.name) ? "<init>" : parsed.name;
            final java.util.concurrent.atomic.AtomicLong hitCounter = new java.util.concurrent.atomic.AtomicLong();
            hook(executable).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept(chain -> {
                        long started = System.nanoTime();
                        long hits = hitCounter.incrementAndGet();
                        StringBuilder argTypes = new StringBuilder();
                        for (Object arg : chain.getArgs()) {
                            if (argTypes.length() > 0) argTypes.append(',');
                            argTypes.append(arg == null ? "null" : arg.getClass().getName());
                        }
                        try {
                            Object result = chain.proceed();
                            long elapsedMicros = (System.nanoTime() - started) / 1000L;
                            if (hits <= 20L || hits % 100L == 0L) {
                                logDeveloperObservation(Log.INFO, "dev-observe rule=" + label + " package=" + packageName
                                        + " executable=" + executableName + " args=[" + argTypes
                                        + "] resultType=" + (result == null ? "null" : result.getClass().getName())
                                        + " instanceType=" + (chain.getThisObject() == null ? "null" : chain.getThisObject().getClass().getName())
                                        + " durationUs=" + elapsedMicros + " hit=" + hits);
                            }
                            return result;
                        } catch (Throwable failure) {
                            long elapsedMicros = (System.nanoTime() - started) / 1000L;
                            logDeveloperObservation(Log.WARN, "dev-observe exception rule=" + label + " package="
                                    + packageName + " executable=" + executableName + " exception="
                                    + failure.getClass().getName() + " durationUs=" + elapsedMicros);
                            throw failure;
                        }
                    });
            developerObservedExecutables.add(executable);
            logFx(Log.INFO, "developer observer installed=" + label + " package=" + packageName
                    + " descriptor=" + descriptor);
        } catch (Throwable failure) {
            logFx(Log.WARN, "developer observer failed open=" + label + " package=" + packageName
                    + " reason=" + failure.getClass().getSimpleName());
        }
    }

    /**
     * Debug-only local UI test fixtures for an explicitly configured developer-owned package.
     * The exact package must be debuggable; descriptors are exact zero-arg boolean methods.
     * These fixtures are never enabled in release builds and are not an authorization credential.
     */
        private void logDeveloperObservation(int priority, String message) {
        // Keep the framework module log and expose the same metadata-only event
        // through logcat so the selected target's native monitor page can read it.
        try { Log.println(priority, TAG, message); } catch (Throwable ignored) { }
        logFx(priority, message);
    }

private boolean targetDeveloperOptIn(String packageName) {
        UnifiedHookConfigParser.Target target = targets.get(packageName);
        return target != null && target.developerHooksEnabled;
    }

    private void installDeveloperTypedReturnHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, DeveloperHookRule.Action action, String label) {
        if (descriptor == null || !MemberTestGate.isEnabled(
                debuggableBuild, targetDeveloperOptIn(packageName), packageName, packageName)) return;
        try {
            DeveloperExecutableDescriptor parsed =
                    DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name)) return;
            java.lang.reflect.Executable executable = parsed.resolve(loader);
            if (!(executable instanceof Method)
                    || developerTypedReturnHookedExecutables.contains(executable)) return;
            final Object fixed;
            switch (action) {
                case RETURN_NULL:
                    if (!(parsed.returnDescriptor.startsWith("L")
                            || parsed.returnDescriptor.startsWith("["))) return;
                    fixed = null;
                    break;
                case RETURN_ZERO:
                    switch (parsed.returnDescriptor) {
                        case "B": fixed = Byte.valueOf((byte) 0); break;
                        case "C": fixed = Character.valueOf((char) 0); break;
                        case "S": fixed = Short.valueOf((short) 0); break;
                        case "I": fixed = Integer.valueOf(0); break;
                        case "J": fixed = Long.valueOf(0L); break;
                        case "F": fixed = Float.valueOf(0F); break;
                        case "D": fixed = Double.valueOf(0D); break;
                        default: return;
                    }
                    break;
                case RETURN_EMPTY_STRING:
                    if (!"Ljava/lang/String;".equals(parsed.returnDescriptor)) return;
                    fixed = "";
                    break;
                default:
                    return;
            }
            final java.util.concurrent.atomic.AtomicLong hits = new java.util.concurrent.atomic.AtomicLong();
            hook(executable).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept(chain -> {
                        long count = hits.incrementAndGet();
                        if (count == 1L || count % 100L == 0L) {
                            logFx(Log.INFO, "developer typed fixture hit=" + label
                                    + " package=" + packageName + " count=" + count);
                        }
                        return fixed;
                    });
            developerTypedReturnHookedExecutables.add(executable);
            logFx(Log.INFO, "developer typed fixture installed=" + label
                    + " package=" + packageName + " method=" + parsed.name);
        } catch (Throwable failure) {
            logFx(Log.WARN, "developer typed fixture failed open=" + label
                    + " package=" + packageName + " error=" + failure.getClass().getSimpleName());
        }
    }

    /** Dia MethodActivity replacement, restricted to exact non-native void methods. */
    private void installDeveloperVoidNoOpHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, String label) {
        if (descriptor == null || !MemberTestGate.isEnabled(
                debuggableBuild, targetDeveloperOptIn(packageName), packageName, packageName)) return;
        try {
            DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name) || !"V".equals(parsed.returnDescriptor)) return;
            java.lang.reflect.Executable executable = parsed.resolve(loader);
            if (!(executable instanceof Method)) return;
            Method method = (Method) executable;
            if (method.getReturnType() != void.class || Modifier.isAbstract(method.getModifiers())
                    || Modifier.isNative(method.getModifiers())
                    || !developerVoidNoOpHookedExecutables.add(executable)) return;
            try {
                final java.util.concurrent.atomic.AtomicLong hits = new java.util.concurrent.atomic.AtomicLong();
                hook(executable).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            long count = hits.incrementAndGet();
                            if (count == 1L || count % 100L == 0L)
                                logFx(Log.INFO, "developer void no-op hit=" + label + " package=" + packageName + " count=" + count);
                            return null;
                        });
            } catch (Throwable hookFailure) {
                developerVoidNoOpHookedExecutables.remove(executable);
                throw hookFailure;
            }
            logFx(Log.INFO, "developer void no-op installed=" + label + " package=" + packageName + " method=" + method.getName());
        } catch (Throwable failure) {
            logFx(Log.WARN, "developer void no-op failed open=" + label + " package=" + packageName + " error=" + failure.getClass().getSimpleName());
        }
    }
    /** Exact immutable constant return for opted-in debuggable target methods. */
    private void installDeveloperLiteralReturnHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, String literalValue, String label) {
        if (descriptor == null || literalValue == null || !MemberTestGate.isEnabled(
                debuggableBuild, targetDeveloperOptIn(packageName), packageName, packageName)) return;
        try {
            DeveloperExecutableDescriptor parsed =
                    DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name)) return;
            java.lang.reflect.Executable executable = parsed.resolve(loader);
            if (!(executable instanceof Method)
                    || developerTypedReturnHookedExecutables.contains(executable)) return;
            Object fixed = DeveloperHookRule.parseLiteralValue(parsed.returnDescriptor, literalValue);
            if (fixed == null) return;
            hook(executable).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept(chain -> fixed);
            developerTypedReturnHookedExecutables.add(executable);
            logFx(Log.INFO, "developer literal fixture installed=" + label
                    + " package=" + packageName + " method=" + parsed.name);
        } catch (Throwable failure) {
            logFx(Log.WARN, "developer literal fixture failed open=" + label
                    + " package=" + packageName + " error=" + failure.getClass().getSimpleName());
        }
    }

    /**
     * Debug-only, type-exact passthrough hooks for developer-owned test builds.
     * RETURN_ARGUMENT_0 returns the first argument only when its JVM descriptor
     * exactly equals the method return descriptor. RETURN_THIS requires a
     * non-static method whose declared return type accepts the receiver class.
     */
    private void installDeveloperPassthroughHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, DeveloperHookRule.Action action, String label) {
        if (descriptor == null || (action != DeveloperHookRule.Action.RETURN_ARGUMENT_0
                && action != DeveloperHookRule.Action.RETURN_THIS)
                || !MemberTestGate.isEnabled(debuggableBuild,
                        targetDeveloperOptIn(packageName), packageName, packageName)) return;
        try {
            DeveloperExecutableDescriptor parsed =
                    DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name)) return;
            java.lang.reflect.Executable executable = parsed.resolve(loader);
            if (!(executable instanceof Method)) return;
            Method method = (Method) executable;
            if (Modifier.isAbstract(method.getModifiers()) || Modifier.isNative(method.getModifiers())) return;
            Class<?>[] parameterTypes = method.getParameterTypes();
            if (action == DeveloperHookRule.Action.RETURN_ARGUMENT_0) {
                if (parameterTypes.length == 0 || method.getReturnType() == void.class
                        || method.getReturnType() != parameterTypes[0]) return;
            } else if (Modifier.isStatic(method.getModifiers())
                    || !method.getReturnType().isAssignableFrom(method.getDeclaringClass())) {
                return;
            }
            if (!developerPassthroughHookedExecutables.add(executable)) return;
            try {
                final java.util.concurrent.atomic.AtomicLong hits = new java.util.concurrent.atomic.AtomicLong();
                hook(executable).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            long count = hits.incrementAndGet();
                            if (count == 1L || count % 100L == 0L) {
                                logFx(Log.INFO, "developer passthrough hit=" + label + " package="
                                        + packageName + " action=" + action + " count=" + count);
                            }
                            if (action == DeveloperHookRule.Action.RETURN_ARGUMENT_0) {
                                java.util.List<Object> args = chain.getArgs();
                                if (args == null || args.isEmpty()) {
                                    throw new IllegalStateException("validated passthrough argument missing");
                                }
                                return args.get(0);
                            }
                            Object receiver = chain.getThisObject();
                            if (receiver == null || !method.getReturnType().isInstance(receiver)) {
                                throw new IllegalStateException("validated receiver is unavailable");
                            }
                            return receiver;
                        });
            } catch (Throwable hookFailure) {
                developerPassthroughHookedExecutables.remove(executable);
                throw hookFailure;
            }
            logFx(Log.INFO, "developer passthrough installed=" + label + " package="
                    + packageName + " action=" + action + " method=" + method.getName());
        } catch (Throwable failure) {
            logFx(Log.WARN, "developer passthrough failed open=" + label + " package="
                    + packageName + " error=" + failure.getClass().getSimpleName());
        }
    }

    private void installDeveloperBooleanTestHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, boolean replacement, String label) {
        installDeveloperBooleanTestHook(loader, packageName, debuggableBuild, descriptor,
                replacement ? DeveloperHookRule.Action.RETURN_TRUE : DeveloperHookRule.Action.RETURN_FALSE, label);
    }

    private void installDeveloperBooleanTestHook(ClassLoader loader, String packageName,
            boolean debuggableBuild, String descriptor, DeveloperHookRule.Action action, String label) {
        if (descriptor == null || !MemberTestGate.isEnabled(debuggableBuild, targetDeveloperOptIn(packageName), packageName, packageName)) return;
        Method method = DeveloperOwnedBooleanHook.resolve(loader, packageName, packageName,
                debuggableBuild, true, descriptor);
        if (method == null || developerTestHookedMethods.contains(method)) return;
        try {
            final java.util.concurrent.atomic.AtomicLong hitCounter = new java.util.concurrent.atomic.AtomicLong();
            hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept(chain -> {
                        long hits = hitCounter.incrementAndGet();
                        if (hits == 1L || hits % 100L == 0L) {
                            logFx(Log.INFO, "developer Debug fixture hit=" + label
                                    + " package=" + packageName + " count=" + hits);
                        }
                        if (action == DeveloperHookRule.Action.OBSERVE) return chain.proceed();
                        return action == DeveloperHookRule.Action.RETURN_TRUE;
                    });
            developerTestHookedMethods.add(method);
            logFx(Log.INFO, "developer Debug UI fixture installed=" + label
                    + " package=" + packageName + " method=" + method.getName());
        } catch (Throwable t) {
            logFx(Log.WARN, "developer Debug UI fixture failed open=" + label
                    + " package=" + packageName + " method=" + method.getName());
        }
    }

    /**
     * Opt-in MediaStore query privacy. It returns an empty cursor only for
     * content://media queries made by the selected single-package process.
     * It does not alter file access, writes, downloads, or other content providers.
     */
    private synchronized boolean installMediaStoreQueryBlockHooks(final String packageName) {
        if (!mediaStoreQueryHookedMethods.isEmpty()) return true;
        int installed = 0;
        for (Method method : ContentResolver.class.getDeclaredMethods()) {
            if (!"query".equals(method.getName()) || method.getReturnType() != Cursor.class) continue;
            Class<?>[] params = method.getParameterTypes();
            if (params.length == 0 || !Uri.class.isAssignableFrom(params[0])) continue;
            try {
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    if (processPackages.size() != 1 || !privacyEnabled) return chain.proceed();
                    String activePackage = currentPackage;
                    UnifiedHookConfigParser.Target active = targets.get(activePackage);
                    if (active == null || !active.mediaStoreQueryBlock) return chain.proceed();
                    Object first = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    if (!(first instanceof Uri) || !"media".equals(((Uri) first).getAuthority())) {
                        return chain.proceed();
                    }
                    Object projection = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                    String[] columns = projection instanceof String[] ? (String[]) projection : new String[0];
                    return new MatrixCursor(columns);
                });
                mediaStoreQueryHookedMethods.add(method);
                installed++;
            } catch (Throwable t) {
                logFx(Log.WARN, "MediaStore query hook failed open: " + method.toGenericString());
            }
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "MediaStore query privacy hooks installed=" + installed + " package=" + packageName);
        return installed > 0;
    }

    /**
     * Explicitly deny location reads/updates for the selected app. This replaces
     * legacy fake-coordinate/location spoofing with a permission-style denial.
     * Shared processes and unknown targets fail open.
     */
    private void installLocationAccessBlockHooks(String packageName) {
        synchronized (locationAccessHookedMethods) {
            int installed = 0;
            Set<String> blockedNames = new HashSet<>(Arrays.asList(
                    // Direct position reads and active/single-shot location requests.
                    "getLastKnownLocation", "getCurrentLocation",
                    "requestLocationUpdates", "requestSingleUpdate",
                    // GNSS and legacy GPS/NMEA callbacks expose position-derived data
                    // even when an app never calls getLastKnownLocation().
                    "registerGnssStatusCallback", "registerGnssMeasurementsCallback",
                    "registerGnssNavigationMessageCallback", "addGpsStatusListener",
                    "addNmeaListener", "addProximityAlert"));
            for (Method method : LocationManager.class.getDeclaredMethods()) {
                if (!blockedNames.contains(method.getName()) || locationAccessHookedMethods.contains(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PASSTHROUGH).intercept(chain -> {
                        if (isLocationAccessBlockAuthorized()) {
                            throw new SecurityException("Location access disabled by FX Hook privacy setting");
                        }
                        return chain.proceed();
                    });
                    locationAccessHookedMethods.add(method);
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.WARN, "location API hook failed; method remains unchanged: " + method.toGenericString());
                }
            }
            logFx(installed > 0 ? Log.INFO : Log.WARN,
                    "location access denial hooks installed=" + installed + " package=" + packageName);
        }
    }

    private boolean isLocationAccessBlockAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        String onlyPackage = processPackages.iterator().next();
        UnifiedHookConfigParser.Target selected = targets.get(onlyPackage);
        return selected != null && selected.locationAccessBlock;
    }

    /**
     * Explicit per-app camera denial. Unlike the legacy cameraNull() spoof, this
     * does not pretend camera hardware is absent: it rejects camera-open requests
     * with a permission-style exception. Shared processes and unknown targets fail open.
     */
    private void installCameraAccessBlockHooks(String packageName) {
        synchronized (cameraAccessHookedMethods) {
            int installed = 0;
            for (Method method : Camera.class.getDeclaredMethods()) {
                if (!"open".equals(method.getName()) || !java.lang.reflect.Modifier.isStatic(method.getModifiers())
                        || cameraAccessHookedMethods.contains(method)) continue;
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
                    logFx(Log.WARN, "legacy camera open hook failed; request remains unchanged: " + method.toGenericString());
                }
            }
            try {
                for (Method method : CameraManager.class.getDeclaredMethods()) {
                    if (!"openCamera".equals(method.getName()) || cameraAccessHookedMethods.contains(method)) continue;
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
                        logFx(Log.WARN, "camera2 open hook failed; request remains unchanged: " + method.toGenericString());
                    }
                }
            } catch (Throwable t) {
                logFx(Log.DEBUG, "camera2 API unavailable on this Android version");
            }
            logFx(installed > 0 ? Log.INFO : Log.WARN,
                    "camera access denial hooks installed=" + installed + " package=" + packageName);
        }
    }

    private boolean isCameraAccessBlockAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        String onlyPackage = processPackages.iterator().next();
        UnifiedHookConfigParser.Target selected = targets.get(onlyPackage);
        return selected != null && selected.cameraAccessBlock;
    }

    /**
     * Explicit per-app microphone recording denial. This blocks capture start
     * rather than fabricating audio samples or spoofing microphone hardware state.
     * Existing microphoneSilence remains a separate post-read buffer policy.
     */
    private void installMicrophoneAccessBlockHooks(String packageName) {
        synchronized (microphoneAccessHookedMethods) {
            int installed = 0;
            for (Method method : AudioRecord.class.getDeclaredMethods()) {
                if (!"startRecording".equals(method.getName())
                        || method.getReturnType() != void.class
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
                    logFx(Log.WARN, "AudioRecord start hook failed; method remains unchanged: " + method.toGenericString());
                }
            }
            for (Method method : MediaRecorder.class.getDeclaredMethods()) {
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
                    logFx(Log.WARN, "MediaRecorder start hook failed; method remains unchanged: " + method.toGenericString());
                }
            }
            logFx(installed > 0 ? Log.INFO : Log.WARN,
                    "microphone start denial hooks installed=" + installed + " package=" + packageName);
        }
    }

    private boolean isMicrophoneAccessBlockAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        String onlyPackage = processPackages.iterator().next();
        UnifiedHookConfigParser.Target selected = targets.get(onlyPackage);
        return selected != null && selected.microphoneAccessBlock;
    }

    private void installAudioRecordSilenceHooks(String packageName) {
        synchronized (microphoneSilenceHookedMethods) {
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
                        if (args.length > 0 && args[0] instanceof java.nio.ByteBuffer) {
                            bufferStart = ((java.nio.ByteBuffer) args[0]).position();
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
                    logFx(Log.WARN, "AudioRecord overload hook failed; this overload remains unchanged: "
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
    }

    private boolean isMicrophoneSilenceAuthorized() {
        if (!privacyEnabled || processPackages.size() != 1) return false;
        String onlyPackage = processPackages.iterator().next();
        UnifiedHookConfigParser.Target selected = targets.get(onlyPackage);
        return selected != null && selected.microphoneSilence;
    }

    private boolean loadConfig() {
        if (!remoteFilesAvailable) return false;
        targets.clear();
        adsEnabled = false;
        privacyEnabled = false;
        wifiScanEnabled = false;
        notificationListenEnabled = false;
        notificationPermissionHideEnabled = false;
        clipboardIsolationEnabled = false;
        try {
            // LSPosed's openRemoteFile may create a missing file; check first.
            if (!Arrays.asList(listRemoteFiles()).contains(CONFIG_NAME)) {
                logFx(Log.WARN, "Remote Files config is missing: " + CONFIG_NAME);
                return false;
            }
        } catch (Throwable listingFailure) {
            logFx(Log.WARN, "Remote Files listing failed; optional per-app policies remain disabled (" +
                    listingFailure.getClass().getSimpleName() + ")");
            return false;
        }
        try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(openRemoteFile(CONFIG_NAME));
             InputStreamReader reader = new InputStreamReader(input,
                     StandardCharsets.UTF_8.newDecoder()
                             .onMalformedInput(CodingErrorAction.REPORT)
                             .onUnmappableCharacter(CodingErrorAction.REPORT))) {
            StringBuilder content = new StringBuilder(4096);
            char[] chunk = new char[8192];
            int count;
            while ((count = reader.read(chunk, 0, chunk.length)) != -1) {
                content.append(chunk, 0, count);
            }
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(content.toString());
            // The legacy Ad master/category switches were removed from the UI.
            // A valid published FX config now enables the built-in classifier; the
            // parsed legacy bit is retained only for schema compatibility.
            adsEnabled = true;
            privacyEnabled = parsed.privacyEnabled;
            wifiScanEnabled = parsed.wifiScanEnabled;
            notificationListenEnabled = parsed.notificationListenEnabled;
            notificationPermissionHideEnabled = parsed.notificationPermissionHideEnabled;
            clipboardIsolationEnabled = parsed.clipboardIsolationEnabled;
            targets.putAll(parsed.targets);
            return true;
        } catch (Throwable t) {
            targets.clear();
            adsEnabled = false;
            privacyEnabled = false;
            logFx(Log.WARN, "remote config rejected; no hooks enabled (" +
                    t.getClass().getSimpleName() + ")");
            return false;
        }
    }

    /**
     * First migrated privacy hook: provide a stable, app-specific Android ID.
     * It is opt-in per package and only intercepts Settings.Secure.ANDROID_ID.
     * All other secure settings and all other identifier APIs remain untouched.
     */
    /**
     * Opt-in read-time EXIF redaction. This does not rewrite image files or mutate
     * exports; it only redacts selected metadata returned by ExifInterface getters.
     */
    private void installExifStripHooks(ClassLoader loader, String pkg) {
        int installed = 0;
        for (String className : new String[]{
                "android.media.ExifInterface",
                "androidx.exifinterface.media.ExifInterface"}) {
            try {
                Class<?> type = Class.forName(className, false, loader);
                Method attribute = type.getMethod("getAttribute", String.class);
                hook(attribute).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> {
                            Object key = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                            Object original = chain.proceed();
                            return key instanceof String && ExifPrivacyPolicy.shouldRedactTag((String) key)
                                    ? null : original;
                        });
                installed++;
                try {
                    Method attributeDouble = type.getMethod("getAttributeDouble", String.class, double.class);
                    hook(attributeDouble).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object key = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                Object fallback = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                                Object original = chain.proceed();
                                if (key instanceof String && ExifPrivacyPolicy.isGpsTag((String) key)
                                        && fallback instanceof Number) {
                                    return ((Number) fallback).doubleValue();
                                }
                                return original;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "EXIF double getter unavailable for " + className);
                }
                try {
                    Method latLong = type.getMethod("getLatLong", float[].class);
                    hook(latLong).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> Boolean.FALSE);
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "EXIF getLatLong unavailable for " + className);
                }
                try {
                    Method altitude = type.getMethod("getAltitude", double.class);
                    hook(altitude).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object fallback = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                return fallback instanceof Number ? ((Number) fallback).doubleValue() : 0.0d;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "EXIF getAltitude unavailable for " + className);
                }
            } catch (Throwable t) {
                logFx(Log.DEBUG, "EXIF API unavailable for " + className);
            }
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "read-time EXIF privacy redaction installed=" + installed + " for " + pkg);
    }

    /**
     * Opt-in per-app sensor enumeration redaction. The framework class is resolved
     * from the boot class loader; unknown APIs and hook failures leave original results
     * untouched. Shared-package processes fail open.
     */
    private synchronized boolean installSensorEnumerationHooks(final String pkg) {
        if (sensorHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.hardware.SensorManager", false, null);
            for (final Method method : type.getDeclaredMethods()) {
                final String name = method.getName();
                Class<?>[] parameters = method.getParameterTypes();
                if ("registerListener".equals(name) && parameters.length >= 3
                        && "android.hardware.Sensor".equals(parameters[1].getName())
                        && parameters[2] == int.class) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    String activePackage = currentPackage;
                                    UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                    java.util.List<Object> args = new java.util.ArrayList<>(chain.getArgs());
                                    Object sensor = args.size() > 1 ? args.get(1) : null;
                                    if (sensor != null) {
                                        try {
                                            Object sensorType = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (sensorType instanceof Integer && SensorPrivacyPolicy.shouldHide(
                                                    privacyEnabled, processPackages.size(), activePackage, active,
                                                    ((Integer) sensorType).intValue())) {
                                                return method.getReturnType() == boolean.class
                                                        ? Boolean.FALSE : null;
                                            }
                                        } catch (Throwable ignored) {
                                            // Unrecognized OEM sensor handles remain usable.
                                        }
                                    }
                                    if (!SensorPrivacyPolicy.shouldClampRate(privacyEnabled, processPackages.size(),
                                            activePackage, active)) return chain.proceed();
                                    Object period = args.size() > 2 ? args.get(2) : null;
                                    if (!(period instanceof Integer)) return chain.proceed();
                                    int originalPeriod = ((Integer) period).intValue();
                                    int clamped = SensorPrivacyPolicy.clampSamplingPeriodUs(originalPeriod);
                                    if (clamped == originalPeriod) return chain.proceed();
                                    args.set(2, Integer.valueOf(clamped));
                                    return chain.proceed(args.toArray());
                                });
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "sensor rate hook unavailable: " + method.toGenericString());
                    }
                    continue;
                }
                if ("requestTriggerSensor".equals(name) && parameters.length >= 2
                        && "android.hardware.Sensor".equals(parameters[1].getName())) {
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    Object sensor = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                                    if (sensor != null) {
                                        try {
                                            Object sensorType = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (sensorType instanceof Integer && SensorPrivacyPolicy.shouldHide(
                                                    privacyEnabled, processPackages.size(), currentPackage,
                                                    targets.get(currentPackage), ((Integer) sensorType).intValue())) {
                                                return Boolean.FALSE;
                                            }
                                        } catch (Throwable ignored) {
                                            // Unknown / OEM sensor handles remain available.
                                        }
                                    }
                                    return chain.proceed();
                                });
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "trigger sensor hook unavailable: " + method.toGenericString());
                    }
                    continue;
                }
                if (!("getSensorList".equals(name) || "getDefaultSensor".equals(name)
                        || "getDynamicSensorList".equals(name))
                        || parameters.length < 1 || parameters[0] != int.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                if (!(arg instanceof Integer)) return chain.proceed();
                                int requestedType = ((Integer) arg).intValue();
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (!SensorPrivacyPolicy.hasAnyEnumerationRule(active)
                                        || !privacyEnabled || processPackages.size() != 1
                                        || activePackage == null || activePackage.isEmpty()) {
                                    return chain.proceed();
                                }
                                if (("getSensorList".equals(name) || "getDynamicSensorList".equals(name))
                                        && requestedType == -1) {
                                    Object original = chain.proceed();
                                    if (!(original instanceof List)) return original;
                                    List<Object> visible = new ArrayList<>();
                                    for (Object sensor : (List<?>) original) {
                                        if (sensor == null) continue;
                                        try {
                                            Object sensorType = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (!(sensorType instanceof Integer)
                                                    || !SensorPrivacyPolicy.shouldHide(true, processPackages.size(),
                                                            activePackage, active, ((Integer) sensorType).intValue())) {
                                                visible.add(sensor);
                                            }
                                        } catch (Throwable ignored) {
                                            // Keep inaccessible OEM sensors visible.
                                            visible.add(sensor);
                                        }
                                    }
                                    return visible;
                                }
                                if (!SensorPrivacyPolicy.shouldHide(true, processPackages.size(),
                                        activePackage, active, requestedType)) return chain.proceed();
                                if ("getDefaultSensor".equals(name)) return null;
                                return Collections.emptyList();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "sensor hook unavailable: " + name + "(" + parameters.length + ")");
                }
            }
            try {
                Class<?> callbackType = Class.forName(
                        "android.hardware.SensorManager$DynamicSensorCallback", false, null);
                for (final Method callbackMethod : callbackType.getDeclaredMethods()) {
                    Class<?>[] callbackParameters = callbackMethod.getParameterTypes();
                    if (!"onDynamicSensorConnected".equals(callbackMethod.getName())
                            || callbackParameters.length != 1
                            || !"android.hardware.Sensor".equals(callbackParameters[0].getName())) continue;
                    try {
                        hook(callbackMethod).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    Object sensor = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                    if (sensor != null) {
                                        try {
                                            Object sensorType = sensor.getClass().getMethod("getType").invoke(sensor);
                                            if (sensorType instanceof Integer && SensorPrivacyPolicy.shouldHide(
                                                    privacyEnabled, processPackages.size(), currentPackage,
                                                    targets.get(currentPackage), ((Integer) sensorType).intValue())) {
                                                return null;
                                            }
                                        } catch (Throwable ignored) {
                                            // Unknown / OEM sensor handles remain visible.
                                        }
                                    }
                                    return chain.proceed();
                                });
                        installed++;
                    } catch (Throwable t) {
                        logFx(Log.DEBUG, "dynamic sensor callback hook unavailable");
                    }
                }
            } catch (Throwable ignored) {
                // Dynamic sensors are API-level and vendor dependent; enumeration
                // and direct registration filters remain active when absent.
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "SensorManager unavailable; sensor privacy fails open (" + t.getClass().getSimpleName() + ")");
            return false;
        }
        sensorHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in sensor enumeration hooks installed=" + installed + " for " + pkg);
        return sensorHooksInstalled;
    }

    private boolean shouldBlockClipboardReadNow() {
        String activePackage = currentPackage;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return ClipboardPrivacyPolicy.shouldBlockRead(privacyEnabled, processPackages.size(),
                activePackage, active);
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

    /**
     * Process-local clipboard shadowing migrated from API-82. This is NOT OS-wide isolation.
     * Only single-package processes are hooked; shared processes fail open.
     */
    private synchronized boolean installClipboardIsolationHooks(final String pkg) {
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.content.ClipboardManager", false, null);
            try {
                Method set = type.getDeclaredMethod("setPrimaryClip", Class.forName("android.content.ClipData", false, null));
                if (!clipboardIsolationHookedMethods.contains(set)) {
                hook(set).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    Object clip = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    Object result = chain.proceed();
                    if (processPackages.size() <= 1 && clip != null) processClipboardShadow = clip;
                    return result;
                });
                clipboardIsolationHookedMethods.add(set);
                installed++;
                }
            } catch (Throwable t) { logFx(Log.DEBUG, "clipboard isolate write hook unavailable"); }
            for (String name : new String[]{"getPrimaryClip", "hasPrimaryClip"}) {
                try {
                    Method read = type.getDeclaredMethod(name);
                    final boolean bool = "hasPrimaryClip".equals(name);
                    if (clipboardIsolationHookedMethods.contains(read)) continue;
                    hook(read).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        if (processPackages.size() > 1) return chain.proceed();
                        return bool ? Boolean.valueOf(processClipboardShadow != null) : processClipboardShadow;
                    });
                    clipboardIsolationHookedMethods.add(read);
                    installed++;
                } catch (Throwable t) { logFx(Log.DEBUG, "clipboard isolate read hook unavailable: " + name); }
            }
        } catch (Throwable t) { logFx(Log.WARN, "clipboard isolate manager unavailable"); return false; }
        clipboardIsolationHooksInstalled = clipboardIsolationHookedMethods.size() == 3;
        logFx(clipboardIsolationHooksInstalled ? Log.INFO : Log.WARN,
                "process-local clipboard isolation hooks newly installed=" + installed
                        + " total=" + clipboardIsolationHookedMethods.size() + " for " + pkg);
        return clipboardIsolationHooksInstalled;
    }

    private boolean shouldBlockWifiScanNow() {
        String activePackage = currentPackage;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return WifiScanPrivacyPolicy.shouldBlock(wifiScanEnabled, processPackages.size(),
                activePackage, active);
    }

    private static Object emptyWifiScanResult(Method method) {
        Class<?> result = method.getReturnType();
        if (java.util.List.class.isAssignableFrom(result)) return Collections.emptyList();
        if (result.isArray()) return Array.newInstance(result.getComponentType(), 0);
        if (result == boolean.class) return Boolean.FALSE;
        if (result == byte.class) return Byte.valueOf((byte) 0);
        if (result == short.class) return Short.valueOf((short) 0);
        if (result == int.class) return Integer.valueOf(0);
        if (result == long.class) return Long.valueOf(0L);
        if (result == float.class) return Float.valueOf(0f);
        if (result == double.class) return Double.valueOf(0d);
        return null;
    }

    /**
     * Cover both the public WifiManager facade and the lower-level WifiScanner
     * service. A blocked app receives no scan results and cannot enqueue a new
     * scan or register a scan callback. Unregister/cleanup methods are untouched.
     */
    private int installWifiScanSurface(Class<?> type) {
        if (type == null) return 0;
        int installed = 0;
        for (final Method method : type.getDeclaredMethods()) {
            final String name = method.getName();
            final Class<?> result = method.getReturnType();
            final boolean listResult = java.util.List.class.isAssignableFrom(result)
                    && ("getScanResults".equals(name)
                    || "getSingleScanResults".equals(name)
                    || "getPnoScanResults".equals(name));
            final boolean startOperation = "startScan".equals(name)
                    || "startPnoScan".equals(name);
            final boolean booleanCapability = "isScanAlwaysAvailable".equals(name)
                    && result == boolean.class;
            final boolean registerListener = "registerScanListener".equals(name)
                    || "registerScanResultsCallback".equals(name);
            if (!listResult && !startOperation && !booleanCapability && !registerListener) continue;
            if (wifiScanHookedMethods.contains(method)) continue;
            try {
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldBlockWifiScanNow()
                                ? emptyWifiScanResult(method) : chain.proceed());
                wifiScanHookedMethods.add(method);
                installed++;
            } catch (Throwable error) {
                logFx(Log.DEBUG, "Wi-Fi scan API hook unavailable: "
                        + type.getName() + "." + name);
            }
        }
        return installed;
    }

    private synchronized boolean installWifiScanPrivacyHooks(final String pkg) {
        int installed = 0;
        try {
            Class<?> manager = Class.forName("android.net.wifi.WifiManager", false, null);
            installed += installWifiScanSurface(manager);
        } catch (Throwable error) {
            logFx(Log.WARN, "WifiManager unavailable: " + error.getClass().getSimpleName());
        }
        // WifiScanner is hidden/system-facing on several Android releases. It is
        // optional; public WifiManager hooks remain available when absent.
        try {
            Class<?> scanner = Class.forName("android.net.wifi.WifiScanner", false, null);
            installed += installWifiScanSurface(scanner);
        } catch (Throwable error) {
            logFx(Log.DEBUG, "WifiScanner API unavailable; WifiManager hooks remain active");
        }
        wifiScanHooksInstalled = !wifiScanHookedMethods.isEmpty();
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in Wi-Fi scan hooks newly installed=" + installed
                        + " total=" + wifiScanHookedMethods.size()
                        + " across WifiManager/WifiScanner for " + pkg);
        return wifiScanHooksInstalled;
    }

    /**
     * Opt-in per-app suppression of active-notification reads. Only the two
     * read APIs returning StatusBarNotification[] are intercepted. Posting,
     * notification shade rendering, listener registration and system services
     * are untouched. Shared-package processes fail open.
     */
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
                                    if (NotificationPrivacyPolicy.shouldBlock(notificationListenEnabled,
                                            processPackages.size(), activePackage, active)) {
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
                                    && NotificationPrivacyPolicy.shouldBlock(notificationListenEnabled,
                                    processPackages.size(), activePackage, active)) return "";
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


    private boolean shouldHidePostNotificationsPermission(String permission, String queriedPackage) {
        if (!"android.permission.POST_NOTIFICATIONS".equals(permission)) return false;
        String activePackage = currentPackage;
        if (activePackage == null || activePackage.isEmpty()
                || (queriedPackage != null && !activePackage.equals(queriedPackage))) return false;
        UnifiedHookConfigParser.Target active = targets.get(activePackage);
        return NotificationPrivacyPolicy.shouldHidePermission(notificationPermissionHideEnabled,
                processPackages.size(), activePackage, active);
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
                                String queried = packageEnabled && !chain.getArgs().isEmpty()
                                        && chain.getArgs().get(0) instanceof String
                                        ? (String) chain.getArgs().get(0) : null;
                                if (NotificationPrivacyPolicy.shouldHidePermission(
                                        notificationPermissionHideEnabled, processPackages.size(),
                                        currentPackage, targets.get(currentPackage))
                                        && (queried == null || queried.equals(currentPackage))) {
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

    /**
     * Unifies String-returning Google Ads ID and Huawei OAID accessors for an
     * explicitly selected single-package process. Shared-process and protected
     * package conditions fail open; platform opt-out/empty IDs are preserved.
     */
    private synchronized boolean installAdvertisingIdHooks(ClassLoader loader, final String pkg) {
        if (loader == null || processPackages.size() != 1 || NEVER.contains(pkg)) return false;
        int installed = 0;
        installed += installAdvertisingIdClassHooks(loader,
                "com.google.android.gms.ads.identifier.AdvertisingIdClient$Info",
                new String[]{"getId"}, true);
        installed += installAdvertisingIdClassHooks(loader,
                "com.huawei.hms.ads.identifier.AdvertisingIdClient",
                new String[]{"getAdvertisingId", "getOaid"}, false);
        if (installed > 0) {
            logFx(Log.INFO, "opt-in advertising ID unification hooks=" + installed + " for " + pkg);
            return true;
        }
        logFx(Log.DEBUG, "no supported advertising ID String accessors found for " + pkg);
        return false;
    }

    private int installAdvertisingIdClassHooks(ClassLoader loader, String className,
                                                String[] methodNames, boolean noArgsOnly) {
        int installed = 0;
        try {
            Class<?> owner = Class.forName(className, false, loader);
            for (Method method : owner.getDeclaredMethods()) {
                boolean named = false;
                for (String methodName : methodNames) {
                    if (methodName.equals(method.getName())) { named = true; break; }
                }
                if (!named || method.getReturnType() != String.class ||
                        (noArgsOnly && method.getParameterTypes().length != 0) ||
                        !advertisingIdHookedMethods.add(method)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object original = chain.proceed();
                        if (!(original instanceof String)) return original;
                        String originalId = (String) original;
                        if (originalId.isEmpty() ||
                                "00000000-0000-0000-0000-000000000000".equalsIgnoreCase(originalId)) return original;
                        String activePackage = currentPackage;
                        UnifiedHookConfigParser.Target activeTarget = targets.get(activePackage);
                        if (processPackages.size() != 1 || !privacyEnabled || activeTarget == null ||
                                !activeTarget.adIdUnify || NEVER.contains(activePackage)) return original;
                        String replacement = PrivacyIdentifier.forAdvertisingId(activePackage);
                        return replacement == null ? original : replacement;
                    });
                    installed++;
                } catch (Throwable hookError) {
                    advertisingIdHookedMethods.remove(method);
                    logFx(Log.WARN, "advertising ID hook unavailable for " + className + "#" +
                            method.getName() + ": " + hookError.getClass().getSimpleName());
                }
            }
        } catch (Throwable ignored) {
            // Optional vendor libraries are absent on most apps; absence is normal.
        }
        return installed;
    }

    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {
        if (privacyIdentifierHookInstalled) return true;
        try {
            Method getString = Settings.Secure.class.getDeclaredMethod(
                    "getString", ContentResolver.class, String.class);
            hook(getString).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object key = chain.getArgs().size() > 1 ? chain.getArgs().get(1) : null;
                // Proceed exactly once. Calling proceed again after a thrown exception can
                // re-enter the original method twice and violate interceptor chain semantics.
                Object original = chain.proceed();
                if (!Settings.Secure.ANDROID_ID.equals(key) || !(original instanceof String)) {
                    return original;
                }
                // This interceptor is installed once in this target process. Resolve the
                // active package at call time instead of stacking one captured-package
                // interceptor for every PackageReady callback.
                String activePackage = currentPackage;
                UnifiedHookConfigParser.Target activeTarget = targets.get(activePackage);
                if (activeTarget == null || NEVER.contains(activePackage)
                        || !isAuthorizedDeviceSimulationTarget(activePackage)) return original;
                if (activeTarget.androidIdSimulation && activeTarget.simulatedAndroidId != null) {
                    return activeTarget.simulatedAndroidId;
                }
                if (!privacyEnabled || !activeTarget.privacy) return original;
                try {
                    return PrivacyIdentifier.forPackage(activePackage, (String) original);
                } catch (Throwable t) {
                    logFx(Log.WARN, "Android ID privacy transform fallback for " + activePackage);
                    return original;
                }
            });
            installTelephonyIdentifierPrivacyHooks(pkg);
            privacyIdentifierHookInstalled = true;
            logFx(Log.INFO, "process-scoped Android ID and telephony identifier privacy hooks installed for " + pkg);
            return true;
        } catch (Throwable t) {
            logFx(Log.WARN, "Android ID privacy hook unavailable for " + pkg +
                    ": " + t.getClass().getSimpleName());
            return false;
        }
    }


    /**
     * Mask carrier/SIM subscriber identifiers for an opted-in target app.
     * Null mirrors Android's ordinary unavailable/permission-denied result.
     */
    private synchronized boolean installTelephonyIdentifierPrivacyHooks(final String pkg) {
        if (telephonyIdentifierHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.telephony.TelephonyManager", false, null);
            final Set<String> identifierMethods = new HashSet<>(Arrays.asList(
                    "getDeviceId", "getImei", "getMeid", "getSubscriberId",
                    "getSimSerialNumber", "getLine1Number", "getNai", "getGroupIdLevel1"));
            for (final Method method : type.getDeclaredMethods()) {
                if (!identifierMethods.contains(method.getName())
                        || method.getReturnType() != String.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object original = chain.proceed();
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (active == null || NEVER.contains(activePackage)
                                        || !privacyEnabled || !active.privacy) return original;
                                return null;
                            });
                    installed++;
                } catch (Throwable failure) {
                    logFx(Log.DEBUG, "telephony identifier privacy hook unavailable: "
                            + method.toGenericString());
                }
            }
            telephonyIdentifierHooksInstalled = installed > 0;
            logFx(installed > 0 ? Log.INFO : Log.WARN,
                    "telephony subscriber/device identifier privacy hooks installed="
                            + installed + " for " + pkg);
            return telephonyIdentifierHooksInstalled;
        } catch (Throwable failure) {
            logFx(Log.WARN, "TelephonyManager identifier privacy hooks unavailable for " + pkg
                    + ": " + failure.getClass().getSimpleName());
            return false;
        }
    }

    /** Install process-global framework observers once; resolve app scope per callback. */
    private static final class DiaToastPayload {
        final String packageName;
        final CharSequence text;
        final View view;
        DiaToastPayload(String packageName, CharSequence text, View view) {
            this.packageName = packageName;
            this.text = text;
            this.view = view;
        }
    }

    private UnifiedHookConfigParser.Target toastRulesFor(String packageName) {
        if (packageName == null || packageName.isEmpty() || NEVER.contains(packageName)
                || packageName.startsWith("com.android.")) return null;
        UnifiedHookConfigParser.Target target = targets.get(packageName);
        return target == null || !target.toastFilterEnabled || target.toastTextTerms.isEmpty()
                ? null : target;
    }

    private void rememberDiaToast(Toast toast, String packageName,
                                  CharSequence text, View view) {
        if (toast == null) return;
        DiaToastPayload previous = diaToastPayloads.get(toast);
        if ((packageName == null || packageName.isEmpty()) && previous != null) {
            packageName = previous.packageName;
        }
        if ((packageName == null || packageName.isEmpty()) && processPackages.size() == 1) {
            packageName = processPackages.iterator().next();
        }
        if (text == null && previous != null) text = previous.text;
        if (view == null && previous != null) view = previous.view;
        if (text != null) {
            int count = Math.min(text.length(), FxDiaDialogMatchPolicy.MAX_TEXT_CHARS);
            text = text.subSequence(0, count).toString();
        }
        diaToastPayloads.put(toast, new DiaToastPayload(packageName, text, view));
    }

    private String findToastTextMatch(View view, List<String> terms, int[] budget, int depth) {
        if (view == null || terms == null || terms.isEmpty()
                || budget[0]-- <= 0 || depth > 16) return null;
        if (view instanceof TextView
                && FxDiaDialogMatchPolicy.matchesText(((TextView) view).getText(), terms)) {
            return "view";
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            int children = Math.min(group.getChildCount(), Math.max(0, budget[0]));
            for (int i = 0; i < children && budget[0] > 0; i++) {
                String match = findToastTextMatch(group.getChildAt(i), terms, budget, depth + 1);
                if (match != null) return match;
            }
        }
        return null;
    }

    private android.content.Context resolveToastContext(Toast toast) {
        if (toast == null) return null;
        try {
            Field contextField = Toast.class.getDeclaredField("mContext");
            contextField.setAccessible(true);
            Object context = contextField.get(toast);
            if (context instanceof android.content.Context) return (android.content.Context) context;
        } catch (Throwable ignored) {
            // Newer Android releases may move or remove Toast's internal Context field.
        }
        return null;
    }

    private synchronized void installDiaToastHooks() {
        if (diaToastHooksInstalled) return;
        boolean showInstalled = false;
        int captureHooksInstalled = 0;
        try {
            Method show = Toast.class.getDeclaredMethod("show");
            if (!diaToastHookedMethods.contains(show)) {
                hook(show).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    Object instance = chain.getThisObject();
                    if (instance instanceof Toast) {
                        Toast toast = (Toast) instance;
                        try {
                            DiaToastPayload payload = diaToastPayloads.get(toast);
                            View view = toast.getView();
                            if (view == null && payload != null) view = payload.view;
                            String packageName = payload == null ? null : payload.packageName;
                            if ((packageName == null || packageName.isEmpty()) && view != null) {
                                packageName = view.getContext().getPackageName();
                            }
                            if (packageName == null || packageName.isEmpty()) {
                                android.content.Context context = resolveToastContext(toast);
                                if (context != null) packageName = context.getPackageName();
                            }
                            if ((packageName == null || packageName.isEmpty())
                                    && processPackages.size() == 1) {
                                packageName = processPackages.iterator().next();
                            }
                            UnifiedHookConfigParser.Target rules = toastRulesFor(packageName);
                            if (rules != null) {
                                String matched = findToastTextMatch(view, rules.toastTextTerms,
                                        new int[]{512}, 0);
                                if (matched == null && payload != null
                                        && FxDiaDialogMatchPolicy.matchesText(
                                                payload.text, rules.toastTextTerms)) {
                                    matched = "text";
                                }
                                if (matched != null) {
                                    // Never log Toast text or matched rule contents.
                                    logFx(Log.INFO, "dia-toast-block package=" + packageName
                                            + " source=" + matched);
                                    return null;
                                }
                            }
                        } catch (Throwable failure) {
                            // A failed or inaccessible Toast must never break its caller.
                            logFx(Log.DEBUG, "Toast text filter failed open: "
                                    + failure.getClass().getSimpleName());
                        }
                    }
                    return chain.proceed();
                });
                diaToastHookedMethods.add(show);
            }
            showInstalled = diaToastHookedMethods.contains(show);

            for (Method method : Toast.class.getDeclaredMethods()) {
                String name = method.getName();
                Class<?>[] types = method.getParameterTypes();
                boolean isMakeText = "makeText".equals(name)
                        && Modifier.isStatic(method.getModifiers())
                        && Toast.class.isAssignableFrom(method.getReturnType())
                        && types.length == 3
                        && android.content.Context.class.isAssignableFrom(types[0])
                        && (CharSequence.class.isAssignableFrom(types[1]) || types[1] == int.class)
                        && types[2] == int.class;
                boolean isSetText = "setText".equals(name) && types.length == 1
                        && (CharSequence.class.isAssignableFrom(types[0]) || types[0] == int.class);
                boolean isSetView = "setView".equals(name) && types.length == 1
                        && View.class.isAssignableFrom(types[0]);
                if (!isMakeText && !isSetText && !isSetView) continue;
                if (diaToastHookedMethods.contains(method)) {
                    captureHooksInstalled++;
                    continue;
                }
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        try {
                            List<Object> args = chain.getArgs();
                            if (isMakeText && result instanceof Toast && args.size() >= 3) {
                                android.content.Context context =
                                        args.get(0) instanceof android.content.Context
                                                ? (android.content.Context) args.get(0) : null;
                                CharSequence text = null;
                                Object value = args.get(1);
                                if (value instanceof CharSequence) text = (CharSequence) value;
                                else if (value instanceof Integer && context != null) {
                                    try { text = context.getText((Integer) value); }
                                    catch (Throwable ignored) { }
                                }
                                rememberDiaToast((Toast) result,
                                        context == null ? null : context.getPackageName(), text, null);
                            } else if (chain.getThisObject() instanceof Toast && isSetText
                                    && !args.isEmpty()) {
                                Toast toast = (Toast) chain.getThisObject();
                                CharSequence text = args.get(0) instanceof CharSequence
                                        ? (CharSequence) args.get(0) : null;
                                if (args.get(0) instanceof Integer) {
                                    android.content.Context context = resolveToastContext(toast);
                                    if (context != null) {
                                        try { text = context.getText((Integer) args.get(0)); }
                                        catch (Throwable ignored) { }
                                    }
                                }
                                // A failed resource lookup must not retain text from a previous Toast.
                                rememberDiaToast(toast, null, text == null ? "" : text, null);
                            } else if (chain.getThisObject() instanceof Toast && isSetView
                                    && !args.isEmpty() && args.get(0) instanceof View) {
                                // Replacing the view invalidates any text captured from an earlier
                                // makeText call on the same Toast instance.
                                View view = (View) args.get(0);
                                diaToastPayloads.put((Toast) chain.getThisObject(),
                                        new DiaToastPayload(view.getContext().getPackageName(), null, view));
                            }
                        } catch (Throwable failure) {
                            logFx(Log.DEBUG, "Toast text capture unavailable: "
                                    + failure.getClass().getSimpleName());
                        }
                        return result;
                    });
                    diaToastHookedMethods.add(method);
                    captureHooksInstalled++;
                } catch (Throwable failure) {
                    logFx(Log.DEBUG, "Toast capture method unavailable: "
                            + failure.getClass().getSimpleName());
                }
            }
            diaToastHooksInstalled = showInstalled && captureHooksInstalled > 0;
            logFx(Log.INFO, "Dia Toast hooks installed capture=" + captureHooksInstalled
                    + ", show=" + showInstalled);
        } catch (Throwable failure) {
            diaToastHooksInstalled = false;
            logFx(Log.WARN, "Dia Toast hooks unavailable: "
                    + failure.getClass().getSimpleName());
        }
    }

    private UnifiedHookConfigParser.Target diaKeyGestureRulesFor(String packageName) {
        if (packageName == null || packageName.isEmpty() || NEVER.contains(packageName)
                || !diaKeyGesturePackages.contains(packageName)) return null;
        UnifiedHookConfigParser.Target target = targets.get(packageName);
        return target == null || (target.keyFinishTrigger < 0 && target.keyDialogToggleTrigger < 0)
                ? null : target;
    }

    private void handleDiaKeyGesture(Activity activity, String packageName, int trigger) {
        UnifiedHookConfigParser.Target target = diaKeyGestureRulesFor(packageName);
        if (target == null) return;
        if (target.keyFinishTrigger == trigger) {
            logFx(Log.INFO, "dia-key-action package=" + packageName
                    + " action=finish-activity trigger=" + trigger);
            activity.finish();
        }
        if (target.keyDialogToggleTrigger == trigger) {
            boolean current = Boolean.TRUE.equals(diaKeyDialogActive.get(packageName));
            boolean next = !current;
            diaKeyDialogActive.put(packageName, next);
            logFx(Log.INFO, "dia-key-action package=" + packageName
                    + " action=dialog-rule-toggle enabled=" + next + " trigger=" + trigger);
            try {
                Toast.makeText(activity, next ? "FX Dialog 规则已恢复" : "FX Dialog 规则已暂停",
                        Toast.LENGTH_SHORT).show();
            } catch (Throwable failure) {
                logFx(Log.DEBUG, "Dia key action feedback unavailable: "
                        + failure.getClass().getSimpleName());
            }
        }
    }

    private synchronized void installDiaKeyGestureHooks() {
        if (!diaKeyGestureDispatchHookInstalled) {
            try {
                Method dispatch = Activity.class.getDeclaredMethod("dispatchKeyEvent", KeyEvent.class);
                hook(dispatch).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    try {
                        Object receiver = chain.getThisObject();
                        Object argument = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                        if (receiver instanceof Activity && argument instanceof KeyEvent) {
                            Activity activity = (Activity) receiver;
                            KeyEvent event = (KeyEvent) argument;
                            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                                String packageName = activity.getPackageName();
                                UnifiedHookConfigParser.Target target = diaKeyGestureRulesFor(packageName);
                                if (target != null) {
                                    FxDiaKeyGesturePolicy gesturePolicy =
                                            diaKeyGesturePolicies.forPackage(packageName);
                                    if (gesturePolicy == null) return chain.proceed();
                                    List<Integer> triggers = gesturePolicy.onKeyDown(
                                            event.getKeyCode(), event.getEventTime(), event.getRepeatCount());
                                    for (Integer trigger : triggers) {
                                        handleDiaKeyGesture(activity, packageName, trigger);
                                    }
                                }
                            }
                        }
                    } catch (Throwable failure) {
                        // Key remapping is opt-in and must never prevent native key dispatch.
                        logFx(Log.DEBUG, "Activity.dispatchKeyEvent gesture failed open: "
                                + failure.getClass().getSimpleName());
                    }
                    return chain.proceed();
                });
                diaKeyGestureDispatchHookInstalled = true;
            } catch (Throwable failure) {
                logFx(Log.WARN, "Activity.dispatchKeyEvent key hook unavailable: "
                        + failure.getClass().getSimpleName());
            }
        }
        if (!diaKeyGestureLongPressHookInstalled) {
            try {
                Method longPress = Activity.class.getDeclaredMethod("onKeyLongPress",
                        int.class, KeyEvent.class);
                hook(longPress).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    try {
                        Object receiver = chain.getThisObject();
                        List<Object> args = chain.getArgs();
                        if (receiver instanceof Activity && args.size() >= 1
                                && args.get(0) instanceof Integer
                                && ((Integer) args.get(0)) == KeyEvent.KEYCODE_BACK) {
                            Activity activity = (Activity) receiver;
                            String packageName = activity.getPackageName();
                            UnifiedHookConfigParser.Target target = diaKeyGestureRulesFor(packageName);
                            if (target != null) {
                                FxDiaKeyGesturePolicy gesturePolicy =
                                        diaKeyGesturePolicies.forPackage(packageName);
                                if (gesturePolicy != null) {
                                    for (Integer trigger : gesturePolicy.onLongPress(
                                            (Integer) args.get(0))) {
                                        handleDiaKeyGesture(activity, packageName, trigger);
                                    }
                                }
                            }
                        }
                    } catch (Throwable failure) {
                        logFx(Log.DEBUG, "Activity.onKeyLongPress gesture failed open: "
                                + failure.getClass().getSimpleName());
                    }
                    return chain.proceed();
                });
                diaKeyGestureLongPressHookInstalled = true;
            } catch (Throwable failure) {
                logFx(Log.WARN, "Activity.onKeyLongPress key hook unavailable: "
                        + failure.getClass().getSimpleName());
            }
        }
        if (diaKeyGestureDispatchHookInstalled || diaKeyGestureLongPressHookInstalled) {
            logFx(Log.INFO, "Dia ActivityKey hooks installed dispatch="
                    + diaKeyGestureDispatchHookInstalled + ", longPress="
                    + diaKeyGestureLongPressHookInstalled);
        }
    }

    private UnifiedHookConfigParser.Target dialogRulesFor(String packageName) {
        if (packageName == null || packageName.isEmpty() || NEVER.contains(packageName)
                || !debuggablePackages.contains(packageName)) return null;
        UnifiedHookConfigParser.Target target = targets.get(packageName);
        if (Boolean.FALSE.equals(diaKeyDialogActive.get(packageName))) return null;
        if (target == null || !target.dialogMatchEnabled
                || (target.dialogTextTerms.isEmpty() && target.dialogIdTerms.isEmpty())) return null;
        return target;
    }

    /** Install bounded pre-addView checks for every WindowManagerImpl overload that accepts a View and LayoutParams. */
    private synchronized void installDiaDialogWindowHooks() {
        if (dialogWindowAddViewHooksInstalled) return;
        try {
            Class<?> windowManagerImpl = Class.forName("android.view.WindowManagerImpl",
                    false, View.class.getClassLoader());
            int eligible = 0;
            int installed = 0;
            for (Method method : windowManagerImpl.getDeclaredMethods()) {
                if (!"addView".equals(method.getName()) || method.isSynthetic() || method.isBridge()) continue;
                Class<?>[] types = method.getParameterTypes();
                if (types.length < 2 || !View.class.isAssignableFrom(types[0])
                        || !types[1].isAssignableFrom(WindowManager.LayoutParams.class)) continue;
                eligible++;
                String key = method.toGenericString();
                if (dialogWindowAddViewMethods.contains(key)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        try {
                            if (chain.getArgs().size() >= 2
                                    && chain.getArgs().get(0) instanceof View
                                    && chain.getArgs().get(1) instanceof ViewGroup.LayoutParams) {
                                View root = (View) chain.getArgs().get(0);
                                ViewGroup.LayoutParams params =
                                        (ViewGroup.LayoutParams) chain.getArgs().get(1);
                                // Never remove an Activity-sized root. This guard also avoids
                                // mistaking a full-screen app window for a transient Dialog.
                                if (!(params.width == ViewGroup.LayoutParams.MATCH_PARENT
                                        && params.height == ViewGroup.LayoutParams.MATCH_PARENT)) {
                                    String pkg = root.getContext().getPackageName();
                                    UnifiedHookConfigParser.Target target = dialogRulesFor(pkg);
                                    String matched = target == null ? null
                                            : findDialogRuleMatch(root, target, new int[]{512}, 0);
                                    if (matched != null) {
                                        logFx(Log.INFO, "dia-dialog-window-block package=" + pkg
                                                + " kind=" + matched);
                                        if (target.dialogNotify) showDialogSuppressionToast(root.getContext(), pkg);
                                        return null;
                                    }
                                }
                            }
                        } catch (Throwable failure) {
                            // Fail open: framework/layout inspection errors cannot break app windows.
                            logFx(Log.DEBUG, "WindowManager.addView Dialog check failed open: "
                                    + failure.getClass().getSimpleName());
                        }
                        return chain.proceed();
                    });
                    dialogWindowAddViewMethods.add(key);
                    installed++;
                } catch (Throwable failure) {
                    logFx(Log.DEBUG, "WindowManager.addView overload unavailable: "
                            + failure.getClass().getSimpleName());
                }
            }
            dialogWindowAddViewHooksInstalled = eligible > 0
                    && dialogWindowAddViewMethods.size() >= eligible;
            logFx(Log.INFO, "Dia Dialog WindowManager hooks installed=" + installed
                    + ", complete=" + dialogWindowAddViewHooksInstalled);
        } catch (Throwable failure) {
            logFx(Log.WARN, "Dia Dialog WindowManager hook unavailable: "
                    + failure.getClass().getSimpleName());
            dialogWindowAddViewHooksInstalled = false;
        }
    }

    private void showDialogSuppressionToast(final android.content.Context context,
                                            final String packageName) {
        if (context == null || packageName == null) return;
        long now = System.currentTimeMillis();
        Long previous = dialogNotifyLastShown.put(packageName, now);
        if (previous != null && now - previous < 3000L) return;
        Runnable display = () -> {
            try {
                Toast.makeText(context, "FX 已按 Dialog 规则拦截", Toast.LENGTH_SHORT).show();
            } catch (Throwable failure) {
                logFx(Log.DEBUG, "Dialog feedback toast unavailable: "
                        + failure.getClass().getSimpleName());
            }
        };
        try {
            if (Looper.myLooper() == Looper.getMainLooper()) display.run();
            else new Handler(Looper.getMainLooper()).post(display);
        } catch (Throwable failure) {
            logFx(Log.DEBUG, "Dialog feedback dispatch unavailable: "
                    + failure.getClass().getSimpleName());
        }
    }

    private void scheduleDialogMatchScan(final Dialog dialog,
                                         final UnifiedHookConfigParser.Target target,
                                         final String packageName) {
        try {
            final Window window = dialog.getWindow();
            final View decor = window == null ? null : window.getDecorView();
            if (decor == null) return;
            decor.postDelayed(() -> {
                try {
                    if (!dialog.isShowing()) return;
                    String kind = findDialogRuleMatch(decor, target, new int[]{512}, 0);
                    if (kind != null) {
                        // Record only the match type and package. Dialog text may contain
                        // private information, so it is never copied into logcat.
                        logFx(Log.INFO, "dia-dialog-match package=" + packageName
                                + " executable=dialog-match kind=" + kind);
                    }
                } catch (Throwable failure) {
                    logFx(Log.DEBUG, "dialog match inspection failed: "
                            + failure.getClass().getSimpleName());
                }
            }, 120L);
        } catch (Throwable failure) {
            logFx(Log.DEBUG, "dialog match scheduling unavailable: "
                    + failure.getClass().getSimpleName());
        }
    }

    private String findDialogRuleMatch(View view, UnifiedHookConfigParser.Target target,
                                       int[] budget, int depth) {
        if (view == null || target == null || budget[0]-- <= 0 || depth > 16) return null;
        CharSequence text = view instanceof TextView ? ((TextView) view).getText() : null;
        if (FxDiaDialogMatchPolicy.matchesText(text, target.dialogTextTerms)) return "text";
        int id = view.getId();
        if (id != View.NO_ID) {
            String fullName = null;
            String entryName = null;
            try { fullName = view.getResources().getResourceName(id); }
            catch (Resources.NotFoundException ignored) { }
            try { entryName = view.getResources().getResourceEntryName(id); }
            catch (Resources.NotFoundException ignored) { }
            if (FxDiaDialogMatchPolicy.matchesResourceId(
                    id, fullName, entryName, target.dialogIdTerms)) return "id";
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            int childCount = Math.min(group.getChildCount(), Math.max(0, budget[0]));
            for (int i = 0; i < childCount && budget[0] > 0; i++) {
                String match = findDialogRuleMatch(group.getChildAt(i), target, budget, depth + 1);
                if (match != null) return match;
            }
        }
        return null;
    }

    private synchronized void installAdViewHooks() {
        if (!activityObserverInstalled) try {
            Method resume = Instrumentation.class.getDeclaredMethod("callActivityOnResume", Activity.class);
            hook(resume).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                try {
                    Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    if (arg instanceof Activity) {
                        Activity activity = (Activity) arg;
                        UnifiedHookConfigParser.Target target = adTargetFor(activity.getPackageName());
                        if (target != null) scheduleScans(activity, target);
                    }
                } catch (Throwable t) { logFx(Log.WARN, "activity observer failed: " + t.getClass().getSimpleName()); }
                return result;
            });
            activityObserverInstalled = true;
        } catch (Throwable t) { logFx(Log.WARN, "activity observer unavailable: " + t.getClass().getSimpleName()); }
        if (!dialogObserverInstalled) try {
            Method show = Dialog.class.getDeclaredMethod("show");
            hook(show).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object object = chain.getThisObject();
                Dialog dialog = object instanceof Dialog ? (Dialog) object : null;
                String dialogPackage = null;
                Window dialogWindow = null;
                try {
                    if (dialog != null) {
                        dialogPackage = dialog.getContext().getPackageName();
                        UnifiedHookConfigParser.Target dialogRules = dialogRulesFor(dialogPackage);
                        dialogWindow = dialog.getWindow();
                        View decor = dialogWindow == null ? null : dialogWindow.getDecorView();
                        WindowManager.LayoutParams attributes = dialogWindow == null
                                ? null : dialogWindow.getAttributes();
                        boolean fullScreen = attributes != null
                                && attributes.width == WindowManager.LayoutParams.MATCH_PARENT
                                && attributes.height == WindowManager.LayoutParams.MATCH_PARENT;
                        String matched = dialogRules == null || fullScreen ? null
                                : findDialogRuleMatch(decor, dialogRules, new int[]{512}, 0);
                        if (matched != null) {
                            logFx(Log.INFO, "dia-dialog-block package=" + dialogPackage
                                    + " kind=" + matched);
                            if (dialogRules.dialogNotify) showDialogSuppressionToast(
                                    dialog.getContext(), dialogPackage);
                            return null;
                        }
                    }
                } catch (Throwable failure) {
                    // A malformed or inaccessible view tree must never block normal app UI.
                    logFx(Log.DEBUG, "dialog pre-display match failed open: "
                            + failure.getClass().getSimpleName());
                }
                Object result = chain.proceed();
                try {
                    if (dialog != null) {
                        String pkg = dialogPackage == null
                                ? dialog.getContext().getPackageName() : dialogPackage;
                        UnifiedHookConfigParser.Target target = adTargetFor(pkg);
                        Window window = dialogWindow == null ? dialog.getWindow() : dialogWindow;
                        UnifiedHookConfigParser.Target dialogRules = dialogRulesFor(pkg);
                        if (dialogRules != null && window != null) {
                            scheduleDialogMatchScan(dialog, dialogRules, pkg);
                        }
                        if (target != null && window != null) scheduleRootScans(window.getDecorView(), target, pkg);
                    }
                } catch (Throwable t) { logFx(Log.WARN, "dialog observer failed: " + t.getClass().getSimpleName()); }
                return result;
            });
            dialogObserverInstalled = true;
        } catch (Throwable t) { logFx(Log.WARN, "dialog observer unavailable: " + t.getClass().getSimpleName()); }
        if (!popupObserversInstalled) {
            int eligible = 0;
            int installedNow = 0;
            try {
                for (Method method : PopupWindow.class.getDeclaredMethods()) {
                    String name = method.getName();
                    if (!("showAsDropDown".equals(name) || "showAtLocation".equals(name)) || method.isSynthetic() || method.isBridge()) continue;
                    eligible++;
                    String key = method.toGenericString();
                    if (popupObserverMethods.contains(key)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object result = chain.proceed();
                            try {
                                Object object = chain.getThisObject();
                                if (object instanceof PopupWindow) {
                                    View content = ((PopupWindow) object).getContentView();
                                    if (content != null) {
                                        String pkg = content.getContext().getPackageName();
                                        UnifiedHookConfigParser.Target target = adTargetFor(pkg);
                                        if (target != null) scheduleRootScans(content, target, pkg);
                                    }
                                }
                            } catch (Throwable t) { logFx(Log.WARN, "popup observer failed: " + t.getClass().getSimpleName()); }
                            return result;
                        });
                        popupObserverMethods.add(key);
                        installedNow++;
                    } catch (Throwable t) { logFx(Log.DEBUG, "popup overload unavailable: " + t.getClass().getSimpleName()); }
                }
            } catch (Throwable t) { logFx(Log.WARN, "popup observers unavailable: " + t.getClass().getSimpleName()); }
            popupObserversInstalled = eligible > 0 && popupObserverMethods.size() >= eligible;
            logFx(Log.INFO, "global popup observers newly installed=" + installedNow + ", complete=" + popupObserversInstalled);
        }
        if (!dynamicChildObserversInstalled) dynamicChildObserversInstalled = installDynamicAdChildHooks();
    }

    private UnifiedHookConfigParser.Target adTargetFor(String pkg) {
        if (pkg == null || pkg.isEmpty() || !adsEnabled || NEVER.contains(pkg)) return null;
        return AUTO_AD_TARGET;
    }

    /**
     * Ad SDKs often insert feed/native ad views after Activity.onResume and after
     * the first four delayed scans. Observe child insertion only inside processes
     * in eligible app processes and check the inserted view with conservative markers. Child
     * insertions are also observed separately. This covers late-loading/scroll-loaded ads without polling
     * the entire view tree continuously.
     */
    private boolean installDynamicAdChildHooks() {
        int eligible = 0;
        int installedNow = 0;
        try {
            for (Method method : ViewGroup.class.getDeclaredMethods()) {
                if (!"addView".equals(method.getName()) || method.isSynthetic() || method.isBridge()) continue;
                if ((method.getModifiers() & java.lang.reflect.Modifier.PUBLIC) == 0) continue;
                Class<?>[] types = method.getParameterTypes();
                if (types.length == 0 || !View.class.isAssignableFrom(types[0])) continue;
                eligible++;
                String key = method.toGenericString();
                if (dynamicChildObserverMethods.contains(key)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        try {
                            Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                            if (arg instanceof View) {
                                View added = (View) arg;
                                String pkg = added.getContext().getPackageName();
                                UnifiedHookConfigParser.Target target = adTargetFor(pkg);
                                if (target != null) scheduleAddedViewCheck(added, target, pkg);
                            }
                        } catch (Throwable t) { logFx(Log.WARN, "dynamic child observer failed: " + t.getClass().getSimpleName()); }
                        return result;
                    });
                    dynamicChildObserverMethods.add(key);
                    installedNow++;
                } catch (Throwable t) { logFx(Log.DEBUG, "addView overload unavailable: " + t.getClass().getSimpleName()); }
            }
        } catch (Throwable t) { logFx(Log.WARN, "dynamic addView hooks unavailable: " + t.getClass().getSimpleName()); }
        boolean complete = eligible > 0 && dynamicChildObserverMethods.size() >= eligible;
        logFx(Log.INFO, "global dynamic ad child observers installed; newly=" + installedNow + ", complete=" + complete);
        return complete;
    }

    private void scheduleAddedViewCheck(final View added, final UnifiedHookConfigParser.Target target, final String pkg) {
        if (added == null) return;
        // addView overloads can delegate to one another; avoid queuing the same
        // inserted view several times for one logical attachment.
        long now = System.currentTimeMillis();
        synchronized (lastAddedViewScan) {
            Long prior = lastAddedViewScan.get(added);
            if (prior != null && now - prior < 300L) return;
            lastAddedViewScan.put(added, now);
        }
        final Handler handler;
        try { handler = new Handler(Looper.getMainLooper()); }
        catch (Throwable t) { return; }
        try {
            handler.postDelayed(() -> {
                try {
                    if (added.getParent() == null) return;
                    // Inspect the inserted root itself, then recursively inspect its
                    // descendants. SDKs commonly add a neutral container whose nested
                    // child is the actual ad view; checking only the root misses it.
                    scanAddedViewTree(added, target, pkg);
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "dynamic ad subtree scan failed: " + t.getClass().getSimpleName());
                }
            }, 80L);
        } catch (Throwable ignored) {}
    }

    private synchronized void installVisibilityMutationObserver() {
        if (visibilityMutationObserverInstalled) return;
        try {
            Method setter = View.class.getDeclaredMethod("setVisibility", int.class);
            hook(setter).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object receiver = chain.getThisObject();
                if (receiver instanceof View && !fxVisibilityMutation.get()) {
                    View changed = (View) receiver;
                    synchronized (hiddenAdViews) {
                        if (hiddenAdViews.containsKey(changed)) {
                            externallyChangedAdViews.put(changed, Boolean.TRUE);
                        }
                    }
                }
                return chain.proceed();
            });
            visibilityMutationObserverInstalled = true;
            logFx(Log.INFO, "ad visibility mutation observer installed");
        } catch (Throwable failure) {
            logFx(Log.WARN, "ad visibility mutation observer unavailable; automatic View hiding disabled for safety");
        }
    }

    private void hideAdView(final View view, final String pkg, final String failureLabel) {
        if (view == null || view.getVisibility() == View.GONE) return;
        // Install only after a real Ad view is found; avoid intercepting every
        // setVisibility call in apps that never contain a matched Ad view.
        installVisibilityMutationObserver();
        if (!visibilityMutationObserverInstalled) {
            // Without ownership tracking, hiding could overwrite a later app-owned
            // visibility change. Fail open rather than risk a stale recycled View.
            return;
        }
        try {
            synchronized (hiddenAdViews) {
                if (!hiddenAdViews.containsKey(view)) {
                    hiddenAdViews.put(view, view.getVisibility());
                    View.OnAttachStateChangeListener listener = new View.OnAttachStateChangeListener() {
                        @Override public void onViewAttachedToWindow(View attached) { }
                        @Override public void onViewDetachedFromWindow(View detached) {
                            restoreHiddenAdView(detached);
                        }
                    };
                    hiddenAdViewListeners.put(view, listener);
                    view.addOnAttachStateChangeListener(listener);
                }
            }
            if (view.getVisibility() != View.GONE) {
                fxVisibilityMutation.set(true);
                try { view.setVisibility(View.GONE); }
                finally { fxVisibilityMutation.set(false); }
                logFx(Log.INFO, "hidden ad view in " + pkg
                        + " class=" + shortName(view.getClass().getName()));
            }
        } catch (Throwable t) {
            restoreHiddenAdView(view);
            logFx(Log.DEBUG, failureLabel + ": " + t.getClass().getSimpleName());
        }
    }

    private void restoreHiddenAdView(View view) {
        if (view == null) return;
        Integer original;
        View.OnAttachStateChangeListener listener;
        synchronized (hiddenAdViews) {
            original = hiddenAdViews.remove(view);
            listener = hiddenAdViewListeners.remove(view);
        }
        try {
            if (listener != null) view.removeOnAttachStateChangeListener(listener);
            boolean changedByTarget;
            synchronized (hiddenAdViews) {
                changedByTarget = externallyChangedAdViews.remove(view) != null;
            }
            // Restore only when no target-app setVisibility call occurred after FX hid it.
            if (original != null && !changedByTarget && view.getVisibility() == View.GONE) {
                fxVisibilityMutation.set(true);
                try { view.setVisibility(original); }
                finally { fxVisibilityMutation.set(false); }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "ad view visibility restore failed: " + t.getClass().getSimpleName());
        }
    }

    private void scanAddedViewTree(View added, UnifiedHookConfigParser.Target target, String pkg) {
        if (added == null) return;
        if (shouldHide(added, target)) {
            hideAdView(added, pkg, "dynamic ad root hide failed");
            return;
        } else {
            restoreHiddenAdView(added);
        }
        if (!(added instanceof ViewGroup)) return;
        ViewGroup group = (ViewGroup) added;
        int childCount;
        try { childCount = Math.min(group.getChildCount(), MAX_DYNAMIC_AD_SCAN_NODES); }
        catch (Throwable t) { return; }
        int[] visited = new int[]{0};
        for (int i = 0; i < childCount && visited[0] < MAX_DYNAMIC_AD_SCAN_NODES; i++) {
            try {
                View child = group.getChildAt(i);
                if (child != null) scanDynamicTree(child, added, 1, visited, target, pkg);
            } catch (Throwable ignored) { }
        }
    }

    private void scanDynamicTree(View view, View root, int depth, int[] count,
                                 UnifiedHookConfigParser.Target target, String pkg) {
        if (view == null || depth > MAX_DYNAMIC_AD_SCAN_DEPTH
                || count[0]++ >= MAX_DYNAMIC_AD_SCAN_NODES) return;
        if (view != root && shouldHide(view, target)) {
            hideAdView(view, pkg, "dynamic ad child hide failed");
            return;
        } else if (view != root) {
            restoreHiddenAdView(view);
        }
        if (!(view instanceof ViewGroup)) return;
        ViewGroup group = (ViewGroup) view;
        int childCount;
        try { childCount = Math.min(group.getChildCount(), MAX_DYNAMIC_AD_SCAN_NODES); }
        catch (Throwable ignored) { return; }
        for (int i = 0; i < childCount && count[0] < MAX_DYNAMIC_AD_SCAN_NODES; i++) {
            try {
                scanDynamicTree(group.getChildAt(i), root, depth + 1, count, target, pkg);
            } catch (Throwable ignored) { }
        }
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
                        inspectMemberViewTree(root, pkg);
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
            hideAdView(view, pkg, "ad view hide failed");
            return;
        } else if (view != root) {
            restoreHiddenAdView(view);
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
        if (view instanceof TextView && isRewardedFlowEvidence((TextView) view)) {
            recordRewardedAdEvidence(view, "preserve-reward-flow");
            return false; // preserve-reward-flow: keep rewarded video UI and callback path unchanged
        }
        String cls = lower(view.getClass().getName());
        String id = resourceName(view);
        String evidence = cls + " " + id;
        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);
        boolean sdkNamespace = hasAny(cls, AD_CLASS_MARKERS);
        // A SDK namespace alone is not proof that every custom View is an ad:
        // SDK packages may also contain controls, placeholders and telemetry views.
        boolean sdkAdView = sdkNamespace && hasAny(cls, STRONG_AD_MARKERS);
        if ((strong || sdkNamespace) && view instanceof ViewGroup
                && containsRewardedEvidenceInSubtree(view, 0, new int[]{0})) {
            recordRewardedAdEvidence(view, "container-preserve-reward-flow");
            return false;
        }
        if (!strong && !sdkAdView) {
            if (view instanceof TextView && hasAdLabel((TextView) view)) {
                ParentEvidence parent = findStrongAdParent(view);
                return parent != null && categoryMatches(parent.value, target, false);
            }
            return false;
        }
        return categoryMatches(evidence, target, sdkAdView);
    }

    private boolean containsRewardedEvidenceInSubtree(View view, int depth, int[] count) {
        if (view == null || depth > 8 || count[0]++ >= 240) return false;
        if (view instanceof TextView && isRewardedFlowEvidence((TextView) view)) return true;
        if (!(view instanceof ViewGroup)) return false;
        ViewGroup group = (ViewGroup) view;
        int n;
        try { n = Math.min(group.getChildCount(), 80); } catch (Throwable ignored) { return false; }
        for (int i = 0; i < n && count[0] < 240; i++) {
            try {
                if (containsRewardedEvidenceInSubtree(group.getChildAt(i), depth + 1, count)) return true;
            } catch (Throwable ignored) {}
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
        if (sdkView) return target.feed;
        int enabled = (target.splash ? 1 : 0) + (target.feed ? 1 : 0) + (target.overlay ? 1 : 0);
        // With automatic recognition all three categories are enabled. Strong
        // generic Ad markers (for example AdBannerView) must still match even
        // when the class/resource name has no category-specific token.
        return enabled > 0;
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
     * Bounded, opt-in discovery of membership-state candidates. This is strictly
     * observational: getter return values, purchase state and entitlements are
     * never changed. Scanning is capped by APK count, class count, time and hook count.
     */
    private volatile ClassLoader targetMemberClassLoader;

    private void installDynamicMemberClassDiscovery(final ClassLoader loader, final String pkg) {
        if (loader == null) return;
        targetMemberClassLoader = loader;
        if (dynamicMemberDiscoveryInstalled) {
            startBoundedMemberDexScan(loader, pkg);
            return;
        }
        dynamicMemberDiscoveryInstalled = true;
        int loaderHooks = 0;
        try {
            Method loadClass = ClassLoader.class.getDeclaredMethod("loadClass", String.class);
            hook(loadClass).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                if (result instanceof Class<?>) {
                    Class<?> candidate = (Class<?>) result;
                    inspectDynamicallyLoadedMemberClass(candidate);
                }
                return result;
            });
            loaderHooks++;
        } catch (Throwable t) {
            logFx(Log.DEBUG, "member classloader observer unavailable=" + t.getClass().getSimpleName());
        }
        logFx(Log.INFO, "dynamic member class discovery installed; loaderHooks=" + loaderHooks
                + "; member runtime discovery installed");
        startBoundedMemberDexScan(loader, pkg);
    }

    private void startBoundedMemberDexScan(final ClassLoader loader, final String pkg) {
        Thread worker = new Thread(() -> {
            int apkFilesScanned = 0;
            int classesScanned = 0;
            long deadline = System.currentTimeMillis() + 6000L;
            List<String> apkPaths = new ArrayList<>();
            try {
                Class<?> activityThread = Class.forName("android.app.ActivityThread");
                Method currentApplication = activityThread.getDeclaredMethod("currentApplication");
                currentApplication.setAccessible(true);
                Object appObject = currentApplication.invoke(null);
                if (!(appObject instanceof Application)) {
                    logFx(Log.WARN, "member DEX candidate scan skipped: application unavailable");
                    return;
                }
                ApplicationInfo info = ((Application) appObject).getApplicationInfo();
                if (info.packageName != null && !pkg.equals(info.packageName)) {
                    logFx(Log.WARN, "member DEX scan package mismatch; refusing cross-package scan");
                    return;
                }
                if (info.sourceDir != null) apkPaths.add(info.sourceDir);
                String[] splitSourceDirs = info.splitSourceDirs;
                if (splitSourceDirs != null) {
                    for (String split : splitSourceDirs) if (split != null && !apkPaths.contains(split)) apkPaths.add(split);
                }
            } catch (Throwable t) {
                logFx(Log.WARN, "member DEX candidate scan cannot enumerate APK paths=" + t.getClass().getSimpleName());
                return;
            }
            for (String apkPath : apkPaths) {
                if (apkFilesScanned >= 16 || memberClassesInspected.get() >= MAX_DYNAMIC_MEMBER_CLASSES
                        || System.currentTimeMillis() > deadline) break;
                DexFile dex = null;
                try {
                    dex = new DexFile(apkPath);
                    apkFilesScanned++;
                    Enumeration<String> entries = dex.entries();
                    while (entries.hasMoreElements() && classesScanned < 24000
                            && memberClassesInspected.get() < MAX_DYNAMIC_MEMBER_CLASSES
                            && System.currentTimeMillis() <= deadline) {
                        String name = entries.nextElement();
                        classesScanned++;
                        boolean namedCandidate = isMemberClassNameCandidate(name);
                        // Sample metadata across the DEX rather than examining only
                        // classes whose names already reveal "vip/member/premium".
                        if (!namedCandidate && (classesScanned % 43 != 0
                                || memberMetadataProbes.get() >= MAX_MEMBER_METADATA_PROBES)) continue;
                        try {
                            Class<?> candidate = Class.forName(name, false, loader);
                            inspectDynamicallyLoadedMemberClass(candidate);
                        } catch (Throwable ignored) { /* optional split/obfuscated classes may not resolve */ }
                    }
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "member DEX path unavailable=" + t.getClass().getSimpleName());
                } finally {
                    if (dex != null) try { dex.close(); } catch (Throwable ignored) {}
                }
            }
            logFx(Log.INFO, "member DEX candidate scan finished; apkFilesScanned=" + apkFilesScanned
                    + " classesScanned=" + classesScanned + " memberClassesInspected=" + memberClassesInspected.get()
                    + " memberMethodsHooked=" + memberMethodsHooked.get());
        }, "FX-member-dex-scan");
        worker.setDaemon(true);
        worker.start();
    }

    private boolean isMemberClassNameCandidate(String name) {
        String n = lower(name);
        return n.contains("member") || n.contains("vip") || n.contains("premium")
                || n.contains("entitle") || n.contains("subscription") || n.contains("purchase")
                || n.contains("billing") || n.contains("license") || n.contains("benefit")
                || n.contains("privilege") || n.contains("order");
    }

    private void inspectDynamicallyLoadedMemberClass(Class<?> candidate) {
        if (candidate == null || !belongsToTargetClassLoader(candidate, targetMemberClassLoader)) return;
        String name = candidate.getName();
        boolean namedCandidate = isMemberClassNameCandidate(name);
        if (!namedCandidate) {
            if (memberMetadataProbes.incrementAndGet() > MAX_MEMBER_METADATA_PROBES) return;
        }
        if (!memberMetadataInspectedClasses.add(name)) return;
        observeLoadedMemberClass(candidate, namedCandidate);
    }

    private boolean belongsToTargetClassLoader(Class<?> candidate, ClassLoader targetLoader) {
        if (candidate == null || targetLoader == null) return false;
        ClassLoader current = candidate.getClassLoader();
        while (current != null) {
            if (current == targetLoader) return true;
            current = current.getParent();
        }
        return false;
    }

    private void observeLoadedMemberClass(Class<?> candidate, boolean namedCandidate) {
        if (candidate == null || memberClassesInspected.get() >= MAX_DYNAMIC_MEMBER_CLASSES) return;
        String name = candidate.getName();
        boolean fieldCandidate = hasMemberStateField(candidate);
        boolean methodCandidate = hasMemberStateMethod(candidate);
        boolean obfuscatedShapeCandidate = !namedCandidate && hasObfuscatedMemberStateShape(candidate);
        if (!fieldCandidate && !methodCandidate && !obfuscatedShapeCandidate) return;
        if (!memberCandidateClasses.add(name)) return;
        int count = memberClassesInspected.incrementAndGet();
        if (count > MAX_DYNAMIC_MEMBER_CLASSES) return;
        logFx(Log.INFO, "member discovery candidate=" + shortName(name)
                + " member-field-candidate=" + fieldCandidate
                + " member-method-candidate=" + methodCandidate
                + " obfuscated-shape-candidate=" + obfuscatedShapeCandidate
                + " member-interface-candidate=" + candidate.isInterface()
                + " obfuscated-status-candidate=" + !namedCandidate);
        installReadOnlyMemberCandidateHook(candidate, namedCandidate, obfuscatedShapeCandidate);
    }

    /**
     * Conservative shape heuristic for obfuscated DTOs: require both a Boolean/Enum
     * state-like value and a numeric/String descriptor. This only marks a candidate;
     * unknown obfuscated methods are not automatically hooked or invoked.
     */
    private boolean hasObfuscatedMemberStateShape(Class<?> candidate) {
        return MemberCandidateClassifier.hasObfuscatedStateShape(candidate);
    }

    /** Inspect method metadata only; never invoke candidate methods during discovery. */
    private boolean hasMemberStateMethod(Class<?> candidate) {
        try {
            Method[] methods = candidate.getDeclaredMethods();
            int limit = Math.min(methods.length, 128);
            for (int i = 0; i < limit; i++) {
                Method method = methods[i];
                MemberCandidateClassifier.Candidate classification =
                        MemberCandidateClassifier.inspect(method);
                String methodName = lower(method.getName());
                boolean getter = methodName.startsWith("get") || methodName.startsWith("is");
                if (getter && classification.kind != MemberCandidateClassifier.Kind.UNKNOWN
                        && classification.isWorthInspecting()) return true;
                if (classification.kind == MemberCandidateClassifier.Kind.ASYNC_FLOW
                        && method.getParameterTypes().length == 1) return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    private boolean hasMemberStateField(Class<?> candidate) {
        try {
            Field[] fields = candidate.getDeclaredFields();
            int limit = Math.min(fields.length, 128);
            for (int i = 0; i < limit; i++) {
                Field field = fields[i];
                String fieldName = lower(field.getName());
                String typeName = lower(field.getType().getName());
                if (hasAny(fieldName, MEMBER_STATE_FIELD_MARKERS)
                        || hasMemberStateType(field.getType())) return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    private boolean hasMemberStateType(Class<?> type) {
        if (type == null) return false;
        String name = lower(type.getName());
        return hasAny(name, MEMBER_STATE_FIELD_MARKERS)
                || type.isEnum() && hasAny(name, new String[]{"state", "status", "purchase", "member"});
    }

    private void installReadOnlyMemberCandidateHook(Class<?> candidate, boolean namedCandidate,
                                                    boolean obfuscatedShapeCandidate) {
        int installed = 0;
        int hierarchyDepth = 0;
        // Membership state is frequently inherited from a shared account/base model.
        // Walk only app-owned classes in this target loader; never hook framework
        // ancestors or unrelated parent-loader methods.
        for (Class<?> owner = candidate; owner != null && hierarchyDepth < 5
                && installed < MAX_AUTO_MEMBER_METHOD_HOOKS
                && memberMethodsHooked.get() < 128; owner = owner.getSuperclass(), hierarchyDepth++) {
            if (!belongsToTargetClassLoader(owner, targetMemberClassLoader)) break;
            try {
                Method[] methods = owner.getDeclaredMethods();
                int limit = Math.min(methods.length, 128);
                for (int i = 0; i < limit && installed < MAX_AUTO_MEMBER_METHOD_HOOKS
                        && memberMethodsHooked.get() < 128; i++) {
                    Method method = methods[i];
                    if (Modifier.isStatic(method.getModifiers())
                            || method.isSynthetic() || method.isBridge()) continue;
                    if (!MemberCandidateClassifier.shouldObserveMethod(
                            method, namedCandidate, obfuscatedShapeCandidate)) continue;
                    String key = method.toGenericString();
                    if (!memberHookedMethods.add(key)) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                            Object result = chain.proceed();
                            if (memberStateObservationCount.incrementAndGet() <= MAX_MEMBER_STATE_OBSERVATIONS) {
                                MemberCandidateClassifier.Kind runtimeKind =
                                        MemberCandidateClassifier.kindOfRuntimeValue(result);
                                logFx(Log.DEBUG, "member state observation owner=" + shortName(method.getDeclaringClass().getName())
                                        + " method=" + method.getName()
                                        + " result-kind=" + runtimeKind.name()
                                        + " mode=read-only");
                            }
                            return result;
                        });
                        installed++;
                        memberMethodsHooked.incrementAndGet();
                    } catch (Throwable ignored) {
                        memberHookedMethods.remove(key);
                    }
                }
            } catch (Throwable t) {
                logFx(Log.DEBUG, "member hierarchy metadata unavailable owner="
                        + shortName(owner.getName()) + " reason=" + t.getClass().getSimpleName());
            }
        }
        logFx(Log.INFO, "auto member candidate hooks installed=" + installed
                + " class=" + shortName(candidate.getName())
                + " hierarchyDepth=" + hierarchyDepth + " mode=read-only");
    }

    private boolean containsRewardedUiSignal(String text) {
        return text != null && hasAny(lower(text), REWARDED_FLOW_MARKERS);
    }

    private boolean isRewardedFlowEvidence(TextView textView) {
        if (textView == null) return false;
        try {
            String text = String.valueOf(textView.getText());
            String description = String.valueOf(textView.getContentDescription());
            String resource = resourceName(textView);
            return containsRewardedUiSignal(text) || containsRewardedUiSignal(description)
                    || containsRewardedUiSignal(resource);
        } catch (Throwable ignored) { return false; }
    }

    private void recordRewardedAdEvidence(View view, String reason) {
        if (view == null || rewardedEvidenceCount.get() >= MAX_REWARDED_AD_EVIDENCE) return;
        String pkg = "";
        String evidence = "";
        try {
            pkg = view.getContext().getPackageName();
            // Do not retain or log raw UI text; dedupe only on package, view class and resource id.
            evidence = shortName(view.getClass().getName()) + " " + resourceName(view);
        } catch (Throwable ignored) {}
        String key = pkg + ":" + lower(evidence);
        if (!rewardedEvidenceSeen.add(key)) return;
        if (rewardedEvidenceCount.incrementAndGet() > MAX_REWARDED_AD_EVIDENCE) return;
        logFx(Log.INFO, "rewarded-ad lifecycle candidate=" + pkg + " reason=" + reason
                + " action=observe-only; reward callback/server validation unchanged");
    }

    private void inspectMemberViewTree(View root, String pkg) {
        if (root == null) return;
        int[] count = new int[]{0};
        inspectMemberViewTreeBounded(root, pkg, 0, count);
    }

    private void inspectMemberViewTreeBounded(View view, String pkg, int depth, int[] count) {
        if (view == null || depth > 10 || count[0]++ >= 400) return;
        if (view instanceof TextView && isRewardedFlowEvidence((TextView) view)) {
            recordRewardedAdEvidence(view, "view-tree-evidence");
        }
        if (!(view instanceof ViewGroup)) return;
        ViewGroup group = (ViewGroup) view;
        int n;
        try { n = Math.min(group.getChildCount(), 200); } catch (Throwable ignored) { return; }
        for (int i = 0; i < n && count[0] < 400; i++) {
            try { inspectMemberViewTreeBounded(group.getChildAt(i), pkg, depth + 1, count); }
            catch (Throwable ignored) {}
        }
    }

    private void installReadOnlyBillingDiagnostics(ClassLoader loader) {
        int installed = 0;
        // Hook concrete value getters which apps actually call. Hooking abstract
        // BillingClient declarations alone can look successful while never firing.
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.BillingResult",
                "getResponseCode", "billing responseCode")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "getPurchaseState", "billing purchaseState")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "isAcknowledged", "billing purchaseAcknowledged")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "isAutoRenewing", "billing purchaseAutoRenewing")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.BillingClient",
                "isReady", "billing clientReady")) installed++;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "read-only concrete billing value diagnostics installed=" + installed + "/4; read-only billing diagnostics installed=" + installed);
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
            hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                if (result instanceof Number) {
                    logFx(Log.INFO, label + "=" + ((Number) result).intValue());
                }
                return result;
            });
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
