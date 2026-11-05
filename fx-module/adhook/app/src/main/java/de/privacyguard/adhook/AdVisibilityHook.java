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
import android.content.pm.ApplicationInfo;
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
import android.view.ViewGroup;
import android.view.Window;
import android.widget.PopupWindow;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
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
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook", "org.lsposed.manager")));
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

    private final Map<String, UnifiedHookConfigParser.Target> targets = new HashMap<>();
    private final Set<String> hooksInstalledFor = ConcurrentHashMap.newKeySet();
    private final Set<String> processPackages = ConcurrentHashMap.newKeySet();
    // Settings.Secure.getString is process-global. Register one interceptor per process;
    // adding one per package would stack transforms when a process exposes multiple packages.
    private volatile boolean privacyIdentifierHookInstalled;
    private volatile boolean clipboardReadHooksInstalled;
    private volatile boolean clipboardIsolationHooksInstalled;
    private static volatile Object processClipboardShadow;
    private volatile boolean sensorHooksInstalled;
    private volatile boolean wifiScanHooksInstalled;
    private volatile boolean notificationListenHooksInstalled;
    private volatile boolean notificationPermissionHooksInstalled;
    private final Set<Method> microphoneSilenceHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> cameraAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> microphoneAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> locationAccessHookedMethods = ConcurrentHashMap.newKeySet();
    private final Set<Method> mediaStoreQueryHookedMethods = ConcurrentHashMap.newKeySet();
    private volatile boolean activityObserverInstalled;
    private volatile boolean dialogObserverInstalled;
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
        currentPackage = pkg;
        processPackages.add(pkg);
        if (NEVER.contains(pkg)) return;
        if (!configLoaded) return;
        final UnifiedHookConfigParser.Target target = targets.get(pkg);
        if (target == null) return;
        final boolean adsForPackage = adsEnabled && target.enabled();
        final boolean memberDiagForPackage = target.memberDiag;
        final boolean privacyForPackage = privacyEnabled && target.privacy;
        final boolean exifForPackage = privacyEnabled && target.exifStrip;
        final boolean clipboardBlockForPackage = privacyEnabled && target.clipboardReadBlock;
        final boolean clipboardIsolateForPackage = privacyEnabled && clipboardIsolationEnabled && target.clipboardIsolate;
        final boolean sensorForPackage = privacyEnabled && (target.sensorAccel || target.sensorGyro
                || target.sensorLight || target.sensorMagnet || target.sensorPressure || target.sensorProx
                || target.sensorRateLimit);
        final boolean wifiScanForPackage = wifiScanEnabled && target.wifiScanBlock;
        final boolean notificationListenForPackage = notificationListenEnabled && target.notificationListenBlock;
        final boolean notificationPermissionHideForPackage = notificationPermissionHideEnabled && target.notificationPermissionHide;
        final boolean microphoneSilenceForPackage = privacyEnabled && target.microphoneSilence;
        final boolean cameraAccessBlockForPackage = privacyEnabled && target.cameraAccessBlock;
        final boolean locationAccessBlockForPackage = privacyEnabled && target.locationAccessBlock;
        final boolean microphoneAccessBlockForPackage = privacyEnabled && target.microphoneAccessBlock;
        final boolean mediaStoreQueryBlockForPackage = privacyEnabled && target.mediaStoreQueryBlock;
        if (!adsForPackage && !memberDiagForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !notificationListenForPackage && !notificationPermissionHideForPackage && !microphoneSilenceForPackage && !cameraAccessBlockForPackage && !locationAccessBlockForPackage && !microphoneAccessBlockForPackage && !mediaStoreQueryBlockForPackage) return;
        // Global observers must get another chance on each eligible package load;
        // a failed registration must not be hidden by the per-package idempotency guard.
        if (adsForPackage && (target.splash || target.feed || target.overlay)) installAdViewHooks();
        // Retry privacy registration independently from the one-shot package guard.
        if (privacyForPackage) installPrivacyIdentifierHooks(pkg);
        if (exifForPackage) installExifStripHooks(param.getClassLoader(), pkg);
        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);
        if (clipboardIsolateForPackage) installClipboardIsolationHooks(pkg);
        if (sensorForPackage) installSensorEnumerationHooks(pkg);
        if (wifiScanForPackage) installWifiScanPrivacyHooks(pkg);
        if (notificationListenForPackage) installNotificationListenPrivacyHooks(pkg);
        if (notificationPermissionHideForPackage) installNotificationPermissionPrivacyHooks(pkg);
        if (microphoneSilenceForPackage) installAudioRecordSilenceHooks(pkg);
        if (cameraAccessBlockForPackage) installCameraAccessBlockHooks(pkg);
        if (locationAccessBlockForPackage) installLocationAccessBlockHooks(pkg);
        if (microphoneAccessBlockForPackage) installMicrophoneAccessBlockHooks(pkg);
        if (mediaStoreQueryBlockForPackage) installMediaStoreQueryBlockHooks(pkg);
        // Member diagnostics are independent of ads/privacy and must run before
        // the unrelated per-package one-shot guard.
        if (memberDiagForPackage) {
            installReadOnlyBillingDiagnostics(param.getClassLoader());
            installDynamicMemberClassDiscovery(param.getClassLoader(), pkg);
        }
        if (!hooksInstalledFor.add(pkg)) return;
        logFx(Log.INFO, "package ready=" + pkg +
                " ads=" + adsForPackage + " privacy=" + privacyForPackage + " exifStrip=" + exifForPackage + " clipboardReadBlock=" + clipboardBlockForPackage + " clipboardIsolate=" + clipboardIsolateForPackage + " sensors=" + sensorForPackage + " wifiScanEnabled=" + wifiScanEnabled + " wifiScanBlock=" + wifiScanForPackage + " notificationListenBlock=" + notificationListenForPackage + " notificationPermissionHide=" + notificationPermissionHideForPackage + " micSilence=" + microphoneSilenceForPackage + " cameraBlock=" + cameraAccessBlockForPackage + " locationBlock=" + locationAccessBlockForPackage + " micAccessBlock=" + microphoneAccessBlockForPackage + " mediaStoreQueryBlock=" + mediaStoreQueryBlockForPackage +
                " splash=" + target.splash + " feed=" + target.feed +
                " overlay=" + target.overlay + " memberDiagReadOnly=" + target.memberDiag +
                " sdk=" + Build.VERSION.SDK_INT);
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
                    "getLastKnownLocation", "getCurrentLocation",
                    "requestLocationUpdates", "requestSingleUpdate"));
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
        // Bound bytes before decoding so a single giant line cannot grow a StringBuilder
        // without limit. The wire format is UTF-8 and the 64 KiB limit is byte-based.
        targets.clear();
        adsEnabled = false;
        privacyEnabled = false;
        wifiScanEnabled = false;
        notificationListenEnabled = false;
        notificationPermissionHideEnabled = false;
        clipboardIsolationEnabled = false;
        try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(openRemoteFile(CONFIG_NAME));
             ByteArrayOutputStream bytes = new ByteArrayOutputStream(4096)) {
            byte[] chunk = new byte[4096];
            int count;
            while ((count = input.read(chunk)) != -1) {
                if (bytes.size() + count > 65536) {
                    logFx(Log.WARN, "remote config exceeds 64 KiB; rejecting all targets");
                    return false;
                }
                bytes.write(chunk, 0, count);
            }
            String content;
            try {
                content = StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(bytes.toByteArray())).toString();
            } catch (CharacterCodingException malformed) {
                logFx(Log.WARN, "remote config is not valid UTF-8; rejecting all targets");
                return false;
            }
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(content);
            adsEnabled = parsed.adsEnabled;
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
                                if (key instanceof String && ((String) key).startsWith("GPS")
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
                                    if (!SensorPrivacyPolicy.shouldClampRate(privacyEnabled, processPackages.size(),
                                            activePackage, active)) return chain.proceed();
                                    java.util.List<Object> args = new java.util.ArrayList<>(chain.getArgs());
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
                if (!("getSensorList".equals(name) || "getDefaultSensor".equals(name))
                        || parameters.length < 1 || parameters[0] != int.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                                if (!(arg instanceof Integer)) return chain.proceed();
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (!SensorPrivacyPolicy.shouldHide(privacyEnabled, processPackages.size(),
                                        activePackage, active, ((Integer) arg).intValue())) {
                                    return chain.proceed();
                                }
                                if ("getSensorList".equals(name)) return Collections.emptyList();
                                return null;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "sensor hook unavailable: " + name + "(" + parameters.length + ")");
                }
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

    /**
     * Opt-in clipboard read protection. Writes remain untouched; reads are hidden only
     * for a single-package process. Shared-package processes fail open to avoid
     * blocking clipboard access for an unrelated package sharing the same process.
     */
    private synchronized boolean installClipboardReadBlockHooks(final String pkg) {
        if (clipboardReadHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.content.ClipboardManager", false, null);
            for (String name : new String[]{"getPrimaryClip", "hasPrimaryClip", "getText"}) {
                try {
                    final Method method = type.getDeclaredMethod(name);
                    final boolean booleanResult = "hasPrimaryClip".equals(name);
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (ClipboardPrivacyPolicy.shouldBlockRead(privacyEnabled, processPackages.size(),
                                        activePackage, active)) {
                                    return booleanResult ? Boolean.FALSE : null;
                                }
                                return chain.proceed();
                            });
                    installed++;
                } catch (NoSuchMethodException missing) {
                    logFx(Log.DEBUG, "clipboard API unavailable: " + name);
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "clipboard hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "clipboard manager unavailable: " + t.getClass().getSimpleName());
            return false;
        }
        clipboardReadHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in clipboard read protection installed=" + installed + " for " + pkg);
        return clipboardReadHooksInstalled;
    }

    /**
     * Process-local clipboard shadowing migrated from API-82. This is NOT OS-wide isolation.
     * Only single-package processes are hooked; shared processes fail open.
     */
    private synchronized boolean installClipboardIsolationHooks(final String pkg) {
        if (clipboardIsolationHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.content.ClipboardManager", false, null);
            try {
                Method set = type.getDeclaredMethod("setPrimaryClip", Class.forName("android.content.ClipData", false, null));
                hook(set).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                    Object clip = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    Object result = chain.proceed();
                    if (processPackages.size() <= 1 && clip != null) processClipboardShadow = clip;
                    return result;
                });
                installed++;
            } catch (Throwable t) { logFx(Log.DEBUG, "clipboard isolate write hook unavailable"); }
            for (String name : new String[]{"getPrimaryClip", "hasPrimaryClip"}) {
                try {
                    Method read = type.getDeclaredMethod(name);
                    final boolean bool = "hasPrimaryClip".equals(name);
                    hook(read).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        if (processPackages.size() > 1) return chain.proceed();
                        return bool ? Boolean.valueOf(processClipboardShadow != null) : processClipboardShadow;
                    });
                    installed++;
                } catch (Throwable t) { logFx(Log.DEBUG, "clipboard isolate read hook unavailable: " + name); }
            }
        } catch (Throwable t) { logFx(Log.WARN, "clipboard isolate manager unavailable"); return false; }
        clipboardIsolationHooksInstalled = installed == 3;
        logFx(clipboardIsolationHooksInstalled ? Log.INFO : Log.WARN, "process-local clipboard isolation hooks=" + installed + " for " + pkg);
        return clipboardIsolationHooksInstalled;
    }

    /**
     * Opt-in Wi-Fi scan suppression. It is scoped to a single-package process;
     * shared-UID/shared-process cases fail open to avoid affecting another app.
     * Wi-Fi association, DHCP, sockets, VPN routing and DNS are not intercepted.
     */
    private synchronized boolean installWifiScanPrivacyHooks(final String pkg) {
        if (wifiScanHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.net.wifi.WifiManager", false, null);
            for (final Method method : type.getDeclaredMethods()) {
                final String name = method.getName();
                final Class<?> result = method.getReturnType();
                final boolean listResult = "getScanResults".equals(name)
                        && java.util.List.class.isAssignableFrom(result);
                final boolean booleanResult = ("startScan".equals(name)
                        || "isScanAlwaysAvailable".equals(name)) && result == boolean.class;
                if (!listResult && !booleanResult) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (WifiScanPrivacyPolicy.shouldBlock(wifiScanEnabled, processPackages.size(),
                                        activePackage, active)) {
                                    return listResult ? Collections.emptyList() : Boolean.FALSE;
                                }
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "Wi-Fi scan hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "WifiManager unavailable; Wi-Fi scan privacy fails open ("
                    + t.getClass().getSimpleName() + ")");
            return false;
        }
        wifiScanHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in Wi-Fi scan privacy hooks installed=" + installed + " for " + pkg);
        return wifiScanHooksInstalled;
    }

    /**
     * Opt-in per-app suppression of active-notification reads. Only the two
     * read APIs returning StatusBarNotification[] are intercepted. Posting,
     * notification shade rendering, listener registration and system services
     * are untouched. Shared-package processes fail open.
     */
    private synchronized boolean installNotificationListenPrivacyHooks(final String pkg) {
        if (notificationListenHooksInstalled) return true;
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
            if (getString.getReturnType() == String.class) {
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
                installed++;
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "notification listener setting query hook unavailable");
        }
        notificationListenHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in active-notification read hooks installed=" + installed + " for " + pkg);
        return notificationListenHooksInstalled;
    }


    /**
     * Per-app masking of NotificationManager.areNotificationsEnabled().
     * It changes only the target app's query result; actual grants, listener
     * registration, posting, and notification display are not modified.
     */
    private synchronized boolean installNotificationPermissionPrivacyHooks(final String pkg) {
        if (notificationPermissionHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.app.NotificationManager", false, null);
            for (final Method method : type.getDeclaredMethods()) {
                if (!"areNotificationsEnabled".equals(method.getName())
                        || method.getParameterTypes().length != 0
                        || method.getReturnType() != boolean.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (NotificationPrivacyPolicy.shouldHidePermission(notificationPermissionHideEnabled,
                                        processPackages.size(), activePackage, active)) return Boolean.FALSE;
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "notification permission query hook unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "NotificationManager permission query unavailable");
            return false;
        }
        notificationPermissionHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in notification permission query hooks installed=" + installed + " for " + pkg);
        return notificationPermissionHooksInstalled;
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
            logFx(Log.INFO, "process-scoped Android ID privacy hook installed for " + pkg);
            return true;
        } catch (Throwable t) {
            logFx(Log.WARN, "Android ID privacy hook unavailable for " + pkg +
                    ": " + t.getClass().getSimpleName());
            return false;
        }
    }


    /** Install process-global framework observers once; resolve app scope per callback. */
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
                Object result = chain.proceed();
                try {
                    Object object = chain.getThisObject();
                    if (object instanceof Dialog) {
                        Dialog dialog = (Dialog) object;
                        String pkg = dialog.getContext().getPackageName();
                        UnifiedHookConfigParser.Target target = adTargetFor(pkg);
                        Window window = dialog.getWindow();
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
        if (pkg == null || !adsEnabled || NEVER.contains(pkg)) return null;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return target != null && target.enabled() && (target.splash || target.feed || target.overlay) ? target : null;
    }

    /**
     * Ad SDKs often insert feed/native ad views after Activity.onResume and after
     * the first four delayed scans. Observe child insertion only inside processes
     * already explicitly scoped to a selected app, then check the inserted view itself with the same conservative markers. Child
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
        final Handler handler;
        try { handler = new Handler(Looper.getMainLooper()); }
        catch (Throwable t) { return; }
        try {
            handler.postDelayed(() -> {
                try {
                    if (added.getParent() == null) return;
                    if (shouldHide(added, target)) {
                        if (added.getVisibility() != View.GONE) {
                            added.setVisibility(View.GONE);
                            logFx(Log.INFO, "hidden dynamically added ad view in " + pkg +
                                    " class=" + shortName(added.getClass().getName()));
                        }
                        return;
                    }
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
            try {
                if (view.getVisibility() != View.GONE) {
                    view.setVisibility(View.GONE);
                    logFx(Log.INFO, "hidden ad view in " + pkg + " class=" + shortName(view.getClass().getName()));
                }
                return;
            } catch (Throwable ignored) {}
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
        return enabled == 1;
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
        installReadOnlyMemberCandidateHook(candidate);
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

    private void installReadOnlyMemberCandidateHook(Class<?> candidate) {
        int installed = 0;
        try {
            for (Method method : candidate.getDeclaredMethods()) {
                if (installed >= MAX_AUTO_MEMBER_METHOD_HOOKS
                        || memberMethodsHooked.get() >= 128
                        || Modifier.isStatic(method.getModifiers())
                        || method.isSynthetic() || method.isBridge()) continue;
                String methodName = lower(method.getName());
                MemberCandidateClassifier.Candidate classification =
                        MemberCandidateClassifier.inspect(method);
                boolean getter = methodName.startsWith("get") || methodName.startsWith("is");
                boolean suspendLike = classification.kind == MemberCandidateClassifier.Kind.ASYNC_FLOW
                        && method.getParameterTypes().length == 1;
                if (method.getParameterTypes().length != 0 && !suspendLike) continue;
                // Getter-like methods may expose Boolean, numeric, String, Enum, or
                // object/bean state. Kotlin suspend signatures are observed separately.
                // No candidate method is invoked by the discovery path itself.
                if ((!getter && !suspendLike)
                        || classification.kind == MemberCandidateClassifier.Kind.UNKNOWN) continue;
                String key = method.toGenericString();
                if (!memberHookedMethods.add(key)) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        // Record invocation only. Never log or alter returned membership data.
                        if (memberStateObservationCount.incrementAndGet() <= MAX_MEMBER_STATE_OBSERVATIONS) {
                            logFx(Log.DEBUG, "member state observation class=" + shortName(candidate.getName())
                                    + " method=" + method.getName() + " mode=read-only");
                        }
                        return result;
                    });
                    installed++;
                    memberMethodsHooked.incrementAndGet();
                } catch (Throwable ignored) { memberHookedMethods.remove(key); }
            }
        } catch (Throwable ignored) {}
        logFx(Log.INFO, "auto member candidate hook installed=" + installed
                + " class=" + shortName(candidate.getName()) + " mode=read-only");
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
