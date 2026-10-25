package de.privacyguard.hook;

import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.ResolveInfo;
import android.content.pm.PackageManager;
import android.content.pm.ActivityInfo;
import android.content.pm.ServiceInfo;
import android.content.pm.ProviderInfo;
import android.os.Build;
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
        "com.android.vpndialogs",
        "com.wireguard.android",
        "com.openvpn",
        "de.blinkt.openvpn",
        "com.nordvpn.android",
        "com.expressvpn.vpn",
        "com.surfshark.vpnclient.android",
        "com.cloudflare.onedotonedotonedotone",
        "com.protonvpn.android",
        "com.privateinternetaccess.android",
        "com.strongvpn",
        "com.pia",
        "com.ixolit.ipvanish"
    )));

    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        if (lpparam == null || lpparam.packageName == null) return;
        if (lpparam.packageName.equals("de.privacyguard.hook")) return;
        try {
            hookPackageManager(lpparam.classLoader);
            hookActivityThread(lpparam.classLoader);
            XposedBridge.log(TAG + ": hooks installed in " + lpparam.packageName);
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": hook setup error in " + lpparam.packageName + " " + t);
        }
    }

    private static boolean hidden(String packageName) {
        return packageName != null && HIDE.contains(packageName);
    }

    private static void hookPackageManager(ClassLoader loader) {
        hookMethods(loader, "android.app.ApplicationPackageManager", "getPackageInfo", new ResultFilter() {
            public Object filter(Object result) { return hiddenPackageInfo(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "getApplicationInfo", new ResultFilter() {
            public Object filter(Object result) { return hiddenApplicationInfo(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "getInstalledPackages", new ResultFilter() {
            public Object filter(Object result) { return filterPackageInfos(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "getInstalledApplications", new ResultFilter() {
            public Object filter(Object result) { return filterApplicationInfos(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "queryIntentActivities", new ResultFilter() {
            public Object filter(Object result) { return filterResolveInfos(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "queryIntentServices", new ResultFilter() {
            public Object filter(Object result) { return filterResolveInfos(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "queryBroadcastReceivers", new ResultFilter() {
            public Object filter(Object result) { return filterResolveInfos(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "resolveActivity", new ResultFilter() {
            public Object filter(Object result) { return filterResolveInfo(result); }
        });
        hookMethods(loader, "android.app.ApplicationPackageManager", "resolveService", new ResultFilter() {
            public Object filter(Object result) { return filterResolveInfo(result); }
        });
    }

    private static void hookActivityThread(ClassLoader loader) {
        hookMethods(loader, "android.app.ApplicationPackageManager", "getLaunchIntentForPackage", new ResultFilter() {
            public Object filter(Object result) {
                if (result instanceof Intent) {
                    ComponentName c = ((Intent) result).getComponent();
                    if (c != null && hidden(c.getPackageName())) return null;
                }
                return result;
            }
        });
    }

    private interface ResultFilter { Object filter(Object result); }

    private static void hookMethods(ClassLoader loader, String className, String methodName, final ResultFilter filter) {
        try {
            Class<?> clazz = XposedHelpersSafe.findClass(className, loader);
            for (Method method : clazz.getDeclaredMethods()) {
                if (!method.getName().equals(methodName)) continue;
                XposedBridge.hookMethod(method, new XC_MethodHook() {
                    @Override protected void afterHookedMethod(MethodHookParam param) {
                        try { param.setResult(filter.filter(param.getResult())); }
                        catch (Throwable ignored) { }
                    }
                });
            }
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": unable to hook " + className + "." + methodName + ": " + t);
        }
    }

    private static Object hiddenPackageInfo(Object result) {
        if (result instanceof PackageInfo && hidden(((PackageInfo) result).packageName)) return null;
        return result;
    }
    private static Object hiddenApplicationInfo(Object result) {
        if (result instanceof ApplicationInfo && hidden(((ApplicationInfo) result).packageName)) return null;
        return result;
    }
    private static Object filterPackageInfos(Object result) {
        if (!(result instanceof List)) return result;
        List<?> in = (List<?>) result; List<PackageInfo> out = new ArrayList<>();
        for (Object o : in) if (o instanceof PackageInfo && !hidden(((PackageInfo)o).packageName)) out.add((PackageInfo)o);
        return out;
    }
    private static Object filterApplicationInfos(Object result) {
        if (!(result instanceof List)) return result;
        List<?> in = (List<?>) result; List<ApplicationInfo> out = new ArrayList<>();
        for (Object o : in) if (o instanceof ApplicationInfo && !hidden(((ApplicationInfo)o).packageName)) out.add((ApplicationInfo)o);
        return out;
    }
    private static Object filterResolveInfos(Object result) {
        if (!(result instanceof List)) return result;
        List<?> in = (List<?>) result; List<ResolveInfo> out = new ArrayList<>();
        for (Object o : in) if (o instanceof ResolveInfo && !hidden(resolvePackage((ResolveInfo)o))) out.add((ResolveInfo)o);
        return out;
    }
    private static Object filterResolveInfo(Object result) {
        if (result instanceof ResolveInfo && hidden(resolvePackage((ResolveInfo)result))) return null;
        return result;
    }
    private static String resolvePackage(ResolveInfo ri) {
        if (ri == null) return null;
        if (ri.activityInfo != null) return ri.activityInfo.packageName;
        if (ri.serviceInfo != null) return ri.serviceInfo.packageName;
        if (ri.providerInfo != null) return ri.providerInfo.packageName;
        return null;
    }

    private static final class XposedHelpersSafe {
        static Class<?> findClass(String name, ClassLoader loader) throws ClassNotFoundException {
            return Class.forName(name, false, loader);
        }
    }
}
