package de.privacyguard.adhook;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.res.Resources;
import android.os.Build;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * FXAdHook: opt-in ad-view detector for one LSPosed-scoped application.
 * Missing or invalid configuration is a no-op. Billing diagnostics are read-only.
 */
public final class AdVisibilityHook implements IXposedHookLoadPackage {
    private static final String TAG = "FXAdHook";
    private static final String CONFIG_PATH = "/data/local/tmp/privacyguard/xposed.conf";
    private static final String SELF = "de.privacyguard.adhook";
    private static final Set<String> NEVER = new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook", SELF, "org.lsposed.manager"));
    private static final Set<String> BILLING_METHODS = new HashSet<>(Arrays.asList(
            "isReady", "queryPurchases", "queryPurchasesAsync", "queryPurchaseHistoryAsync",
            "queryProductDetailsAsync", "querySkuDetailsAsync", "launchBillingFlow",
            "acknowledgePurchase", "consumeAsync", "consumePurchase", "getConnectionState"));
    private static final String[] AD_CLASS_MARKERS = {
            "com.google.android.gms.ads", "com.bytedance.sdk.openadsdk",
            "com.qq.e.ads", "com.kwad.sdk", "com.baidu.mobads",
            "com.applovin", "com.facebook.ads", "com.unity3d.services.ads",
            "com.sigmob.sdk", "com.pangle"
    };
    private static final String[] STRONG_AD_MARKERS = {
            "adview", "ad_view", "ad-view", "adcontainer", "ad_container", "ad-container",
            "advertisement", "advertising", "splashad", "splash_ad", "splash-ad",
            "feedad", "feed_ad", "feed-ad", "nativead", "native_ad", "native-ad",
            "bannerad", "banner_ad", "banner-ad", "interstitial", "rewardedad",
            "rewarded_ad", "rewarded-ad", "fullscreenad", "full_screen_ad",
            "adslot", "ad_slot", "ad-slot", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };
    private static final String[] SPLASH_MARKERS = {
            "splashad", "splash_ad", "splash-ad", "splashadvert", "launch_ad", "launchad"
    };
    private static final String[] FEED_MARKERS = {
            "feedad", "feed_ad", "feed-ad", "nativead", "native_ad", "native-ad",
            "bannerad", "banner_ad", "banner-ad", "adview", "ad_view", "adcontainer",
            "ad_container", "adslot", "ad_slot"
    };
    private static final String[] OVERLAY_MARKERS = {
            "interstitial", "rewardedad", "rewarded_ad", "fullscreenad",
            "full_screen_ad", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };

    private final Map<String, String> top = new HashMap<>();
    private final Map<String, Target> targets = new HashMap<>();
    private final WeakHashMap<Activity, Long> lastScan = new WeakHashMap<>();
    private String packageName = "";
    private Target target;

    private static final class Target {
        boolean splash, feed, overlay, memberDiag;
        boolean enabled() { return splash || feed || overlay || memberDiag; }
    }
    private static final class ParentEvidence {
        final String value;
        ParentEvidence(String v) { value = v; }
    }

    @Override
    public void handleLoadPackage(final XC_LoadPackage.LoadPackageParam lpp) {
        packageName = lpp.packageName == null ? "" : lpp.packageName;
        if (NEVER.contains(packageName)) return;
        if (!loadConfig()) {
            log("inactive: missing/unreadable config");
            return;
        }
        if (!"1".equals(top.get("hook_ads_enabled"))) {
            log("inactive: master switch off");
            return;
        }
        target = targets.get(packageName);
        if (target == null || !target.enabled()) {
            log("inactive: package not selected in FX target list");
            return;
        }
        if (target.splash || target.feed || target.overlay) installAdViewHook();
        if (target.memberDiag) installReadOnlyBillingDiagnostics(lpp.classLoader);
        log("loaded package=" + packageName + " splash=" + target.splash +
                " feed=" + target.feed + " overlay=" + target.overlay +
                " memberDiagReadOnly=" + target.memberDiag +
                " android=" + Build.VERSION.SDK_INT);
    }

    private boolean loadConfig() {
        File file = new File(CONFIG_PATH);
        if (!file.isFile() || !file.canRead()) return false;
        String section = "";
        try (BufferedReader r = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                if (line.startsWith("[") && line.endsWith("]")) {
                    section = line.substring(1, line.length() - 1);
                    continue;
                }
                if ("list:hook_targets".equals(section)) {
                    parseTarget(line);
                } else if (section.isEmpty()) {
                    int i = line.indexOf('=');
                    if (i > 0) top.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
                }
            }
            return true;
        } catch (Throwable t) {
            log("config parse failed: " + t.getClass().getSimpleName());
            return false;
        }
    }

    private void parseTarget(String line) {
        String[] parts = line.split("\\|");
        if (parts.length < 2) return;
        String pkg = parts[0].trim();
        if (!validPackage(pkg)) return;
        Target t = new Target();
        for (int i = 1; i < parts.length; i++) {
            int eq = parts[i].indexOf('=');
            if (eq <= 0) continue;
            String key = parts[i].substring(0, eq).trim();
            boolean yes = "1".equals(parts[i].substring(eq + 1).trim());
            if ("splash".equals(key)) t.splash = yes;
            else if ("feed".equals(key)) t.feed = yes;
            else if ("overlay".equals(key)) t.overlay = yes;
            else if ("member_diag".equals(key)) t.memberDiag = yes;
        }
        if (t.enabled()) targets.put(pkg, t);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }

    private void installAdViewHook() {
        try {
            XposedHelpers.findAndHookMethod(Instrumentation.class, "callActivityOnResume",
                    Activity.class, new XC_MethodHook() {
                        @Override protected void afterHookedMethod(MethodHookParam param) {
                            try {
                                if (!(param.args[0] instanceof Activity)) return;
                                Activity a = (Activity) param.args[0];
                                if (!packageName.equals(a.getPackageName())) return;
                                scheduleScans(a);
                            } catch (Throwable t) {
                                log("resume hook failed: " + t.getClass().getSimpleName());
                            }
                        }
                    });
            log("ad view observer installed");
        } catch (Throwable t) {
            log("ad view observer unavailable: " + t.getClass().getSimpleName());
        }
    }

    private void scheduleScans(final Activity activity) {
        final View decor;
        try {
            if (activity.isFinishing() || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
            decor = activity.getWindow() == null ? null : activity.getWindow().getDecorView();
        } catch (Throwable t) { return; }
        if (decor == null) return;
        long now = System.currentTimeMillis();
        synchronized (lastScan) {
            Long prior = lastScan.get(activity);
            if (prior != null && now - prior < 350L) return;
            lastScan.put(activity, now);
        }
        final int[] delays = new int[]{180, 650, 1500, 3200};
        for (final int delay : delays) {
            try {
                decor.postDelayed(new Runnable() {
                    @Override public void run() {
                        try {
                            if (activity.isFinishing() || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
                            View root = activity.getWindow() == null ? null : activity.getWindow().getDecorView();
                            if (root != null) scanTree(root, root, 0, new int[]{0});
                        } catch (Throwable t) {
                            log("scan failed: " + t.getClass().getSimpleName());
                        }
                    }
                }, delay);
            } catch (Throwable ignored) {}
        }
    }

    private void scanTree(View view, View root, int depth, int[] count) {
        if (view == null || depth > 20 || count[0]++ >= 1800) return;
        if (view != root && shouldHide(view)) {
            try {
                if (view.getVisibility() != View.GONE) {
                    view.setVisibility(View.GONE);
                    log("hidden ad view in " + packageName + " class=" + shortName(view.getClass().getName()));
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
            scanTree(child, root, depth + 1, count);
        }
    }

    private boolean shouldHide(View view) {
        String cls = lower(view.getClass().getName());
        String id = resourceName(view);
        String evidence = cls + " " + id;
        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);
        boolean sdkAdView = false;
        for (String marker : AD_CLASS_MARKERS) {
            if (cls.contains(marker)) { sdkAdView = true; break; }
        }
        if (!strong && !sdkAdView) {
            if (view instanceof TextView && hasAdLabel((TextView) view)) {
                ParentEvidence parent = findStrongAdParent(view);
                return parent != null && categoryMatches(parent.value, true);
            }
            return false;
        }
        return categoryMatches(evidence, sdkAdView);
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

    private boolean categoryMatches(String evidence, boolean sdkAdView) {
        String e = lower(evidence);
        boolean splash = hasAny(e, SPLASH_MARKERS);
        boolean overlay = hasAny(e, OVERLAY_MARKERS);
        boolean feed = hasAny(e, FEED_MARKERS) || sdkAdView;
        if (splash) return target.splash;
        if (overlay) return target.overlay;
        if (feed) return target.feed;
        int enabled = (target.splash ? 1 : 0) + (target.feed ? 1 : 0) + (target.overlay ? 1 : 0);
        return enabled == 1;
    }

    private static boolean hasAdLabel(TextView text) {
        try {
            CharSequence c = text.getText();
            CharSequence d = text.getContentDescription();
            String all = lower(String.valueOf(c)) + " " + lower(String.valueOf(d));
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
            Class<?> billing = XposedHelpers.findClassIfExists(
                    "com.android.billingclient.api.BillingClient", loader);
            if (billing == null) {
                log("member diagnostic unavailable: Google Play Billing client class not found");
                return;
            }
            int hooked = 0;
            for (Method m : billing.getDeclaredMethods()) {
                if (!BILLING_METHODS.contains(m.getName()) || m.isSynthetic()) continue;
                try {
                    XposedBridge.hookMethod(m, new XC_MethodHook() {
                        @Override protected void beforeHookedMethod(MethodHookParam param) {
                            log("billing diagnostic call: " + param.method.getName());
                        }
                        @Override protected void afterHookedMethod(MethodHookParam param) {
                            Object result = param.getResult();
                            String type = result == null ? "void/null" : result.getClass().getSimpleName();
                            log("billing diagnostic return: " + param.method.getName() + " type=" + type);
                        }
                    });
                    hooked++;
                } catch (Throwable ignored) {}
            }
            log("read-only billing diagnostic hooks=" + hooked);
        } catch (Throwable t) {
            log("billing diagnostics unavailable: " + t.getClass().getSimpleName());
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
    private static void log(String message) {
        try { XposedBridge.log("[" + TAG + "] " + message); } catch (Throwable ignored) {}
    }
}
