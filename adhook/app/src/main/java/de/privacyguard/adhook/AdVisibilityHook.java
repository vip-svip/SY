package de.privacyguard.adhook;

import android.app.Activity;
import android.app.Dialog;
import android.app.Instrumentation;
import android.content.ContentResolver;
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

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
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
    private static final String CONFIG_NAME = "fx-hook-targets.conf";
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
    private volatile boolean adObserversInstalled;
    private final WeakHashMap<Activity, Long> lastActivityScan = new WeakHashMap<>();
    private final WeakHashMap<View, Long> lastRootScan = new WeakHashMap<>();
    private boolean adsEnabled;
    private boolean privacyEnabled;
    private boolean configLoaded;
    private boolean remoteFilesAvailable;
    private String currentPackage = "";

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
        if (NEVER.contains(pkg)) return;
        if (!configLoaded) return;
        final UnifiedHookConfigParser.Target target = targets.get(pkg);
        if (target == null) return;
        final boolean adsForPackage = adsEnabled && target.enabled();
        final boolean privacyForPackage = privacyEnabled && target.privacy;
        if (!adsForPackage && !privacyForPackage) return;
        if (!hooksInstalledFor.add(pkg)) return;
        if (adsForPackage && (target.splash || target.feed || target.overlay)) installAdViewHooks();
        if (adsForPackage && target.memberDiag) installReadOnlyBillingDiagnostics(param.getClassLoader());
        if (privacyForPackage) installPrivacyIdentifierHooks(pkg);
        logFx(Log.INFO, "package ready=" + pkg +
                " ads=" + adsForPackage + " privacy=" + privacyForPackage +
                " splash=" + target.splash + " feed=" + target.feed +
                " overlay=" + target.overlay + " memberDiagReadOnly=" + target.memberDiag +
                " sdk=" + Build.VERSION.SDK_INT);
    }

    private boolean loadConfig() {
        if (!remoteFilesAvailable) return false;
        // Do not activate a partially parsed target list. The independent parser
        // validates the entire config before any target is committed.
        targets.clear();
        adsEnabled = false;
        privacyEnabled = false;
        try (InputStreamReader isr = new InputStreamReader(
                    new ParcelFileDescriptor.AutoCloseInputStream(openRemoteFile(CONFIG_NAME)),
                    StandardCharsets.UTF_8);
             BufferedReader reader = new BufferedReader(isr)) {
            StringBuilder content = new StringBuilder();
            String line;
            int lines = 0;
            while ((line = reader.readLine()) != null) {
                if (++lines > 1000) {
                    logFx(Log.WARN, "remote config exceeds 1000 lines; rejecting all targets");
                    return false;
                }
                content.append(line).append('\n');
            }
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(content.toString());
            adsEnabled = parsed.adsEnabled;
            privacyEnabled = parsed.privacyEnabled;
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
    private void installPrivacyIdentifierHooks(final String pkg) {
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
                try {
                    return PrivacyIdentifier.forPackage(pkg, (String) original);
                } catch (Throwable t) {
                    logFx(Log.WARN, "Android ID privacy transform fallback for " + pkg);
                    return original;
                }
            });
            logFx(Log.INFO, "app-scoped Android ID privacy hook installed for " + pkg);
        } catch (Throwable t) {
            logFx(Log.WARN, "Android ID privacy hook unavailable for " + pkg +
                    ": " + t.getClass().getSimpleName());
        }
    }


    /** Install process-global framework observers once; resolve app scope per callback. */
    private synchronized void installAdViewHooks() {
        if (adObserversInstalled) return;
        try {
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
        } catch (Throwable t) { logFx(Log.WARN, "activity observer unavailable: " + t.getClass().getSimpleName()); }
        try {
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
        } catch (Throwable t) { logFx(Log.WARN, "dialog observer unavailable: " + t.getClass().getSimpleName()); }
        int installed = 0;
        try {
            for (Method method : PopupWindow.class.getDeclaredMethods()) {
                String name = method.getName();
                if (!("showAsDropDown".equals(name) || "showAtLocation".equals(name)) || method.isSynthetic() || method.isBridge()) continue;
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
                    installed++;
                } catch (Throwable ignored) {}
            }
        } catch (Throwable t) { logFx(Log.WARN, "popup observers unavailable: " + t.getClass().getSimpleName()); }
        logFx(Log.INFO, "global popup observers installed=" + installed);
        installDynamicAdChildHooks();
        // Mark complete only after every observer family has had an installation attempt.
        // The synchronized method prevents concurrent duplicate installation while running.
        adObserversInstalled = true;
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
    private void installDynamicAdChildHooks() {
        int installed = 0;
        Set<String> hooked = new HashSet<>();
        try {
            for (Method method : ViewGroup.class.getDeclaredMethods()) {
                if (!"addView".equals(method.getName()) || method.isSynthetic() || method.isBridge()) continue;
                if ((method.getModifiers() & java.lang.reflect.Modifier.PUBLIC) == 0) continue;
                Class<?>[] types = method.getParameterTypes();
                if (types.length == 0 || !View.class.isAssignableFrom(types[0]) || !hooked.add(method.toGenericString())) continue;
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
                    installed++;
                } catch (Throwable t) { logFx(Log.DEBUG, "addView overload unavailable: " + t.getClass().getSimpleName()); }
            }
        } catch (Throwable t) { logFx(Log.WARN, "dynamic addView hooks unavailable: " + t.getClass().getSimpleName()); }
        logFx(Log.INFO, "global dynamic ad child observers installed=" + installed);
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
        String cls = lower(view.getClass().getName());
        String id = resourceName(view);
        String evidence = cls + " " + id;
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

    private void installReadOnlyBillingDiagnostics(ClassLoader loader) {
        int installed = 0;
        // Hook concrete value getters which apps actually call. Hooking abstract
        // BillingClient declarations alone can look successful while never firing.
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.BillingResult",
                "getResponseCode", "billing responseCode")) installed++;
        if (installBillingValueDiagnostic(loader, "com.android.billingclient.api.Purchase",
                "getPurchaseState", "billing purchaseState")) installed++;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "read-only concrete billing value diagnostics installed=" + installed + "/2");
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
