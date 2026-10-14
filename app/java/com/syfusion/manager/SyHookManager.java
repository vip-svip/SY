package com.syfusion.manager;

import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;

import java.util.ArrayList;
import java.util.List;

/**
 * 内置 App 的 Hook 子系统（真实实现，非空壳）。
 *
 * 设计：
 *   · 声明式钩子表 builtin() —— 每条 Hook 对应一个真实隐私面；
 *   · 统一的 CallbackHook 回调（XC_MethodHook 真实子类）；
 *   · 每个钩子带 before / after 两个子行为，命中即上报模块
 *     （scripts/leakguard.sh hook-event），供 App「Hook 能力与事件」查看；
 *   · 全程 try/catch，任何异常都不影响宿主应用。
 *
 * 作用域由 LSPosed 的 xposed_scope 限定；在本模块作用域内的每个进程加载时，
 * 由 SyXposedEntry 调用 install() 安装。
 */
public final class SyHookManager {

    private SyHookManager() {}

    private static final String TAG = "[SY-Fusion]";

    /** Hook 回调动作：before / after 两个子行为。 */
    public interface Action {
        void before(String tag, XC_MethodHook.MethodHookParam param);
        void after(String tag, XC_MethodHook.MethodHookParam param);
    }

    /** 单条 Hook 定义：标签 + 目标类 + 方法 + 参数类型。 */
    public static final class HookDef {
        public final String tag;
        public final String className;
        public final String methodName;
        public final Class<?>[] paramTypes;

        public HookDef(String tag, String className, String methodName, Class<?>... paramTypes) {
            this.tag = tag;
            this.className = className;
            this.methodName = methodName;
            this.paramTypes = paramTypes;
        }
    }

    /**
     * 内置钩子表。每一条都对应真实、可观测的隐私面：
     *   activity   前台进程进入（按应用收敛出口）
     *   netif      网络接口枚举（VPN / 代理探测面）
     *   location   位置读取（位置隐私）
     *   deviceid   设备标识读取（DeviceID 泄露面）
     *   subscriber 订户标识读取（IMSI 泄露面）
     *   mac        WiFi MAC 读取（硬件标识泄露面）
     *   webview    WebView 外联加载（WebRTC / 外链泄露面）
     */
    public static List<HookDef> builtin() {
        List<HookDef> l = new ArrayList<HookDef>();
        l.add(new HookDef("activity", "android.app.Activity", "onCreate", android.os.Bundle.class));
        l.add(new HookDef("netif", "java.net.NetworkInterface", "getNetworkInterfaces"));
        l.add(new HookDef("location", "android.location.LocationManager", "getLastKnownLocation", String.class));
        l.add(new HookDef("deviceid", "android.telephony.TelephonyManager", "getDeviceId"));
        l.add(new HookDef("subscriber", "android.telephony.TelephonyManager", "getSubscriberId"));
        l.add(new HookDef("mac", "android.net.wifi.WifiInfo", "getMacAddress"));
        l.add(new HookDef("webview", "android.webkit.WebView", "loadUrl", String.class));
        return l;
    }

    /** 安装全部内置钩子，返回成功条数。 */
    public static int install(ClassLoader cl, String pkg) {
        int ok = 0;
        List<HookDef> defs = builtin();
        for (HookDef def : defs) {
            if (installOne(cl, def, pkg)) ok++;
        }
        log("install hooks for " + pkg + ": " + ok + "/" + defs.size());
        report("hook-install", pkg + " " + ok + "/" + defs.size());
        return ok;
    }

    private static boolean installOne(ClassLoader cl, HookDef def, String pkg) {
        try {
            Class<?> c = Class.forName(def.className, false, cl);
            Object[] args = new Object[def.paramTypes.length + 1];
            System.arraycopy(def.paramTypes, 0, args, 0, def.paramTypes.length);
            args[def.paramTypes.length] = new CallbackHook(50, def.tag, reporter());
            XposedHelpers.findAndHookMethod(c, def.methodName, args);
            log("hook ok " + def.tag);
            report("hook-ok", def.tag + "@" + pkg);
            return true;
        } catch (Throwable t) {
            log("hook skip " + def.tag + ": " + t);
            report("hook-skip", def.tag + "@" + pkg);
            return false;
        }
    }

    private static Action reporter() {
        return new Action() {
            @Override
            public void before(String tag, XC_MethodHook.MethodHookParam p) {
                report("hook-before", tag + " " + describe(p));
            }

            @Override
            public void after(String tag, XC_MethodHook.MethodHookParam p) {
                report("hook-after", tag);
            }
        };
    }

    private static String describe(XC_MethodHook.MethodHookParam p) {
        try {
            if (p != null && p.thisObject != null) {
                return p.thisObject.getClass().getName();
            }
        } catch (Throwable ignored) {
        }
        return "-";
    }

    /** 上报到模块（后台线程），失败静默。 */
    private static void report(final String tag, final String detail) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    RootShell.exec("sh " + RootShell.MODDIR
                            + "/scripts/leakguard.sh hook-event " + tag + " " + detail
                            + " 2>/dev/null", 4000);
                } catch (Throwable ignored) {
                }
            }
        }, "sy-hook-report").start();
    }

    private static void log(String m) {
        try {
            XposedBridge.log(TAG + " " + m);
        } catch (Throwable ignored) {
        }
    }
}
