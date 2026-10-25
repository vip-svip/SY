package de.privacyguard.hook;

import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.ResolveInfo;
import android.os.Build;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

public final class MainHook implements IXposedHookLoadPackage {
    private static final String TAG = "PrivacyGuardHook";
    private static final Set<String> HIDE = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
        "com.android.vpndialogs", "com.wireguard.android", "com.openvpn",
        "de.blinkt.openvpn", "com.nordvpn.android", "com.expressvpn.vpn",
        "com.surfshark.vpnclient.android", "com.cloudflare.onedotonedotonedotone",
        "com.protonvpn.android", "com.privateinternetaccess.android",
        "com.strongvpn", "com.pia", "com.ixolit.ipvanish"
    )));

    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam p) {
        if (p == null || p.packageName == null || p.packageName.equals("de.privacyguard.hook")) return;
        try {
            // Legacy LSPosed identifies system_server as "system"; "android"
            // is the separate framework UI process on recent LSPosed versions.
            if ("system".equals(p.packageName) || "system_server".equals(p.processName)) {
                hookSystemPackageManager(p.classLoader);
            } else {
                hookClientPackageManager(p.classLoader);
            }
            XposedBridge.log(TAG + ": installed for " + p.packageName + "/" + p.processName);
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": setup error in " + p.packageName + ": " + t);
        }
    }

    private static boolean hidden(String name) { return name != null && HIDE.contains(name); }

    private static void hookClientPackageManager(ClassLoader loader) {
        hook(loader, "android.app.ApplicationPackageManager", "getPackageInfo", r -> {
            if (r instanceof PackageInfo && hidden(((PackageInfo) r).packageName)) return null;
            return r;
        });
        hook(loader, "android.app.ApplicationPackageManager", "getApplicationInfo", r -> {
            if (r instanceof ApplicationInfo && hidden(((ApplicationInfo) r).packageName)) return null;
            return r;
        });
        hook(loader, "android.app.ApplicationPackageManager", "getInstalledPackages", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "getInstalledApplications", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "queryIntentActivities", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "queryIntentServices", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "queryBroadcastReceivers", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "resolveActivity", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "resolveService", MainHook::filterContainer);
        hook(loader, "android.app.ApplicationPackageManager", "getLaunchIntentForPackage", r -> {
            if (r instanceof Intent) {
                ComponentName c = ((Intent) r).getComponent();
                if (c != null && hidden(c.getPackageName())) return null;
            }
            return r;
        });
    }

    /*
     * The "android" LSPosed scope also loads the module in system_server on
     * compatible builds. Filtering here is the cross-app path; client hooks
     * alone only affect processes in which LSPosed loads this module.
     */
    private static void hookSystemPackageManager(ClassLoader loader) {
        String[] classes = {
            "com.android.server.pm.PackageManagerService",
            "com.android.server.pm.ComputerEngine"
        };
        // Hook outward-facing PackageManagerService entry points only. Avoid
        // internal helpers because framework code also calls them during installs.
        String[] methods = {
            "getPackageInfo", "getApplicationInfo",
            "getInstalledPackages", "getInstalledApplications",
            "queryIntentActivities", "queryIntentServices",
            "queryIntentReceivers", "resolveIntent"
        };
        for (String cn : classes) for (String mn : methods) {
            hook(loader, cn, mn, MainHook::filterContainer);
        }
    }

    private interface Filter { Object apply(Object result) throws Throwable; }

    private static void hook(ClassLoader loader, String className, String methodName, Filter filter) {
        try {
            Class<?> c = Class.forName(className, false, loader);
            for (Method m : c.getDeclaredMethods()) {
                if (!m.getName().equals(methodName)) continue;
                XposedBridge.hookMethod(m, new XC_MethodHook() {
                    @Override protected void afterHookedMethod(MethodHookParam p) {
                        try { p.setResult(filter.apply(p.getResult())); }
                        catch (Throwable t) { XposedBridge.log(TAG + ": result filter failed " + className + "." + methodName + ": " + t); }
                    }
                });
            }
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": unavailable " + className + "." + methodName + ": " + t);
        }
    }

    private static Object filterContainer(Object result) throws Throwable {
        if (result == null) return null;
        if (result instanceof PackageInfo) {
            return hidden(((PackageInfo) result).packageName) ? null : result;
        }
        if (result instanceof ApplicationInfo) {
            return hidden(((ApplicationInfo) result).packageName) ? null : result;
        }
        if (result instanceof ResolveInfo) {
            return hidden(resolvePackage((ResolveInfo) result)) ? null : result;
        }
        if (result instanceof List) return filterList((List<?>) result);
        // PackageManagerService commonly wraps results in ParceledListSlice.
        // Mutate only a recognized List field; leave unknown framework objects untouched.
        for (Class<?> c = result.getClass(); c != null; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                if (!List.class.isAssignableFrom(f.getType())) continue;
                try {
                    f.setAccessible(true);
                    Object value = f.get(result);
                    if (value instanceof List) f.set(result, filterList((List<?>) value));
                    return result;
                } catch (Throwable ignored) { }
            }
        }
        return result;
    }

    private static List<?> filterList(List<?> in) {
        List<Object> out = new ArrayList<>(in.size());
        for (Object o : in) {
            String pkg = packageName(o);
            if (pkg == null || !hidden(pkg)) out.add(o);
        }
        return out;
    }

    private static String packageName(Object o) {
        if (o instanceof PackageInfo) return ((PackageInfo) o).packageName;
        if (o instanceof ApplicationInfo) return ((ApplicationInfo) o).packageName;
        if (o instanceof ResolveInfo) return resolvePackage((ResolveInfo) o);
        return null;
    }

    private static String resolvePackage(ResolveInfo r) {
        if (r == null) return null;
        if (r.activityInfo != null) return r.activityInfo.packageName;
        if (r.serviceInfo != null) return r.serviceInfo.packageName;
        if (r.providerInfo != null) return r.providerInfo.packageName;
        return null;
    }
}
