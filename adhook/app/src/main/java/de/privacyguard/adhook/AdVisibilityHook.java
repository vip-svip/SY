package de.privacyguard.adhook;

import android.app.Activity;
import android.app.Dialog;
import android.app.Instrumentation;
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
    private static final Set<String> BILLING_METHODS = new HashSet<>(Arrays.asList(
            "isReady", "queryPurchases", "queryPurchasesAsync", "queryPurchaseHistoryAsync",
            "queryProductDetailsAsync", "querySkuDetailsAsync", "launchBillingFlow",
            "acknowledgePurchase", "consumeAsync", "consumePurchase", "getConnectionState"));
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
            "advertisement", "advertising", "splashad", "splash_ad", "splash-ad",
            "ad_splash", "ad-splash", "open_ad", "openad", "launchscreenad", "splashpage",
            "splashview", "splashactivity", "splashcontainer", "ppssplash", "mimosplash",
            "mimo_ad", "mimoad", "mobad", "heytap_ad", "vivo_ad", "huawei_ad", "hihonor_ad",
            "feedad", "feed_ad", "feed-ad", "nativead", "native_ad", "native-ad",
            "bannerad", "banner_ad", "banner-ad", "interstitial", "rewardedad",
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
            "ad_container", "adslot", "ad_slot", "mimo_ad", "mimoad", "mobad",
            "hms_ads", "heytap_ad", "vivo_ad", "huawei_ad", "hihonor_ad"
    };
    private static final String[] OVERLAY_MARKERS = {
            "interstitial", "rewardedad", "rewarded_ad", "fullscreenad",
            "full_screen_ad", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };

    private final Map<String, Target> targets = new HashMap<>();
    private final Set<String> hooksInstalledFor = ConcurrentHashMap.newKeySet();
    private final WeakHashMap<Activity, Long> lastActivityScan = new WeakHashMap<>();
    private final WeakHashMap<View, Long> lastRootScan = new WeakHashMap<>();
    private boolean adsEnabled;
    private boolean configLoaded;
    private boolean remoteFilesAvailable;
    private String currentPackage = "";

    private static final class Target {
        boolean splash;
        boolean feed;
        boolean overlay;
        boolean memberDiag;
        boolean enabled() { return splash || feed || overlay || memberDiag; }
    }

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
        if (!configLoaded || !adsEnabled) return;
        final Target target = targets.get(pkg);
        if (target == null || !target.enabled()) return;
        if (!hooksInstalledFor.add(pkg)) return;
        if (target.splash || target.feed || target.overlay) installAdViewHooks(pkg, target);
        if (target.memberDiag) installReadOnlyBillingDiagnostics(param.getClassLoader());
        logFx(Log.INFO, "package ready=" + pkg +
                " splash=" + target.splash + " feed=" + target.feed +
                " overlay=" + target.overlay + " memberDiagReadOnly=" + target.memberDiag +
                " sdk=" + Build.VERSION.SDK_INT);
    }

    private boolean loadConfig() {
        if (!remoteFilesAvailable) return false;
        // AutoCloseInputStream owns the descriptor, so it is closed exactly once.
        try (InputStreamReader isr = new InputStreamReader(
                    new ParcelFileDescriptor.AutoCloseInputStream(openRemoteFile(CONFIG_NAME)),
                    StandardCharsets.UTF_8);
             BufferedReader reader = new BufferedReader(isr)) {
            String section = "";
            String line;
            int lines = 0;
            while ((line = reader.readLine()) != null) {
                if (++lines > 1000) {
                    logFx(Log.WARN, "remote config exceeds 1000 lines; rejected");
                    targets.clear();
                    return false;
                }
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                if (line.startsWith("[") && line.endsWith("]")) {
                    section = line.substring(1, line.length() - 1);
                    continue;
                }
                if (section.isEmpty()) {
                    int eq = line.indexOf('=');
                    if (eq > 0 && "hook_ads_enabled".equals(line.substring(0, eq).trim())) {
                        adsEnabled = "1".equals(line.substring(eq + 1).trim());
                    }
                } else if ("list:hook_targets".equals(section)) {
                    parseTarget(line);
                }
            }
            return true;
        } catch (Throwable t) {
            targets.clear();
            logFx(Log.WARN, "openRemoteFile failed: " + t.getClass().getSimpleName());
            return false;
        }
    }

    private void parseTarget(String line) {
        // FX list row: package,splash=1,feed=0,overlay=1,member_diag=0|note|1
        String config = line.trim();
        int metadata = config.indexOf('|');
        if (metadata >= 0) config = config.substring(0, metadata);
        String[] parts = config.split(",");
        if (parts.length < 2) return;
        String pkg = parts[0].trim();
        if (!validPackage(pkg) || NEVER.contains(pkg)) return;
        Target target = new Target();
        Set<String> seen = new HashSet<>();
        for (int i = 1; i < parts.length; i++) {
            int eq = parts[i].indexOf('=');
            if (eq <= 0) return;
            String key = parts[i].substring(0, eq).trim();
            String value = parts[i].substring(eq + 1).trim();
            if (!("0".equals(value) || "1".equals(value)) || !seen.add(key)) return;
            boolean enabled = "1".equals(value);
            if ("splash".equals(key)) target.splash = enabled;
            else if ("feed".equals(key)) target.feed = enabled;
            else if ("overlay".equals(key)) target.overlay = enabled;
            else if ("member_diag".equals(key)) target.memberDiag = enabled;
            else return;
        }
        if (target.enabled()) targets.put(pkg, target);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }

    private void installAdViewHooks(final String pkg, final Target target) {
        try {
            Method resume = Instrumentation.class.getDeclaredMethod("callActivityOnResume", Activity.class);
            hook(resume).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                Object result = chain.proceed();
                try {
                    Object arg = chain.getArgs().isEmpty() ? null : chain.getArgs().get(0);
                    if (arg instanceof Activity) {
                        Activity activity = (Activity) arg;
                        if (pkg.equals(activity.getPackageName())) scheduleScans(activity, target);
                    }
                } catch (Throwable t) {
                    logFx(Log.WARN, "activity resume observer failed: " + t.getClass().getSimpleName());
                }
                return result;
            });
            logFx(Log.INFO, "activity ad observer installed for " + pkg);
        } catch (Throwable t) {
            logFx(Log.WARN, "activity ad observer unavailable for " + pkg + ": " + t.getClass().getSimpleName());
        }

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
    }

    private void scheduleScans(final Activity activity, final Target target) {
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

    private void scheduleRootScans(final View initialRoot, final Target target, final String pkg) {
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

    private void scanTree(View view, View root, int depth, int[] count, Target target, String pkg) {
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

    private boolean shouldHide(View view, Target target) {
        String cls = lower(view.getClass().getName());
        String id = resourceName(view);
        String evidence = cls + " " + id;
        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);
        boolean sdkView = hasAny(cls, AD_CLASS_MARKERS);
        if (!strong && !sdkView) {
            if (view instanceof TextView && hasAdLabel((TextView) view)) {
                ParentEvidence parent = findStrongAdParent(view);
                return parent != null && categoryMatches(parent.value, target, false);
            }
            return false;
        }
        return categoryMatches(evidence, target, sdkView);
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

    private boolean categoryMatches(String evidence, Target target, boolean sdkView) {
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
        try {
            Class<?> billing = Class.forName("com.android.billingclient.api.BillingClient", false, loader);
            int hooked = 0;
            for (Method method : billing.getDeclaredMethods()) {
                if (!BILLING_METHODS.contains(method.getName()) || method.isSynthetic() || method.isBridge()) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE).intercept(chain -> {
                        Object result = chain.proceed();
                        logFx(Log.INFO, "billing diagnostic call=" + method.getName() +
                                " returnType=" + (result == null ? "null" : result.getClass().getSimpleName()));
                        return result;
                    });
                    hooked++;
                } catch (Throwable ignored) {}
            }
            logFx(Log.INFO, "read-only billing diagnostics hooks=" + hooked);
        } catch (Throwable t) {
            logFx(Log.INFO, "billing diagnostics unavailable: Google Play Billing client not found");
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
