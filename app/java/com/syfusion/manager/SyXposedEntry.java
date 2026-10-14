package com.syfusion.manager;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

import java.lang.reflect.Method;

/**
 * LSPosed / Xposed 入口：与模块深度联动。
 *
 * 编译期只依赖 app/xposed_stub 下的最小接口桩（这些桩不会被打进 APK），
 * 运行期由 LSPosed 注入真实的 de.robv.android.xposed.* 实现。
 * 因此这里不直接 import XposedBridge / XposedHelpers，统一走反射，
 * 保证「编译期零依赖、运行期可选」。
 *
 * 联动能力：
 *   · 记录宿主包并上报模块（leakguard.sh hook-enter / privacy_targets.txt），
 *     由模块统一决定该包是否需要按应用收敛隐私出口；
 *   · 对模块指定的隐私目标应用，会尝试挂 Activity.onCreate（尽力而为，失败静默）。
 * 全部包在 try/catch，任何异常都不影响宿主。
 */
public class SyXposedEntry implements IXposedHookLoadPackage {

    private static final String TAG = "[SY-Fusion]";
    private static final String SELF = "com.syfusion.manager";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        try {
            if (lpparam == null || lpparam.packageName == null) return;
            final String pkg = lpparam.packageName;
            xlog("loaded: " + pkg);

            // 系统框架与自身：只记录，不 hook
            if (SELF.equals(pkg) || "android".equals(pkg) || "system".equals(pkg)) return;

            // 上报模块：由模块脚本决定该包是否属于隐私收敛目标
            notifyModule(pkg);

            // 对模块配置的隐私目标应用，尝试在进程内挂轻量钩子
            if (isPrivacyTarget(pkg) && lpparam.classLoader != null) {
                hookActivityOnCreate(lpparam.classLoader, pkg);
            }
        } catch (Throwable ignored) {
        }
    }

    private void notifyModule(final String pkg) {
        try {
            Class<?> rs = Class.forName("com.syfusion.manager.RootShell");
            final Method exec = rs.getMethod("exec", String.class, int.class);
            final Object lock = rs;
            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        exec.invoke(lock,
                                "sh " + RootShell.MODDIR + "/scripts/leakguard.sh hook-enter " + pkg + " 2>/dev/null",
                                6000);
                    } catch (Throwable ignored) {
                    }
                }
            }).start();
        } catch (Throwable ignored) {
        }
    }

    private boolean isPrivacyTarget(String pkg) {
        try {
            String raw = RootShell.exec(
                    "cat " + RootShell.MODDIR + "/config/privacy_targets.txt 2>/dev/null", 4000);
            if (raw == null) return false;
            for (String line : raw.split("\\r?\\n")) {
                String p = line.trim();
                if (p.length() > 0 && !p.startsWith("#") && p.equals(pkg)) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private void hookActivityOnCreate(ClassLoader cl, final String pkg) {
        try {
            Class<?> helpers = Class.forName("de.robv.android.xposed.XposedHelpers", false, cl);
            Class<?> activity = Class.forName("android.app.Activity", false, cl);

            // 找一个 XC_MethodHook 的匿名子类实例：优先用反射构造，失败则跳过
            Object hook = newHookInstance(cl, pkg);
            if (hook == null) return;

            Method findHook = null;
            for (Method m : helpers.getMethods()) {
                if (m.getName().equals("findAndHookMethod") && m.isVarArgs()) { findHook = m; break; }
            }
            if (findHook == null) return;
            findHook.invoke(null, activity, "onCreate", android.os.Bundle.class, hook);
            xlog("hooked Activity.onCreate in " + pkg);
        } catch (Throwable t) {
            xlog("hook skip: " + t);
        }
    }

    /** 通过反射生成 XC_MethodHook 子类实例；任何失败都返回 null（静默降级）。 */
    private Object newHookInstance(ClassLoader cl, final String pkg) {
        try {
            Class<?> hookCls = Class.forName("de.robv.android.xposed.XC_MethodHook", false, cl);
            final Class<?> callbackCls = hookCls;
            return java.lang.reflect.Proxy.newProxyInstance(
                    cl, new Class<?>[]{hookCls},
                    new java.lang.reflect.InvocationHandler() {
                        @Override
                        public Object invoke(Object proxy, Method method, Object[] args) {
                            return null;
                        }
                    });
        } catch (Throwable t) {
            return null;
        }
    }

    private void xlog(String msg) {
        try {
            Class<?> b = Class.forName("de.robv.android.xposed.XposedBridge");
            Method log = b.getMethod("log", String.class);
            log.invoke(null, TAG + " " + msg);
        } catch (Throwable ignored) {
        }
    }
}
