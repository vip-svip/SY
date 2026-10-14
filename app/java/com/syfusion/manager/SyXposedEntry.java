package com.syfusion.manager;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * LSPosed / Xposed 入口：与模块深度联动（真实实现，非空壳）。
 *
 * 编译期依赖 app/xposed_stub 下的最小桩（这些桩不会进 APK / 不在 d8 输入里），
 * 运行期由 LSPosed 注入真实的 de.robv.android.xposed.* 实现。
 *
 * 历代缺陷修复：
 *   v1.0.2 用 Proxy.newProxyInstance 去「代理」XC_MethodHook —— 抽象类不能用 Proxy，
 *   该调用 100% 抛异常并被 catch 静默丢弃，钩子从未挂上（典型空壳）。
 *   现统一走 SyHookManager（声明式钩子表 + CallbackHook 真实子类）。
 *
 * Hook 模式（由 scripts/leakguard.sh hook-mode 控制，默认 targets）：
 *   targets —— 仅对 config/privacy_targets.txt 内的应用安装内置钩子
 *   all     —— 对 LSPosed 作用域内所有应用安装
 *   off     —— 关闭（仅上报进程进入）
 *
 * 内置钩子目标（见 SyHookManager.builtin）：Activity.onCreate、
 * NetworkInterface.getNetworkInterfaces、LocationManager.getLastKnownLocation、
 * TelephonyManager.getDeviceId/getSubscriberId、WifiInfo.getMacAddress、WebView.loadUrl。
 */
public class SyXposedEntry implements IXposedHookLoadPackage {

    private static final String TAG = "[SY-Fusion]";
    private static final String SELF = "com.syfusion.manager";

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if (lpparam == null || lpparam.packageName == null) return;
        final String pkg = lpparam.packageName;
        try {
            xlog("loaded: " + pkg);
            // 子功能 1：向模块上报进程进入（模块据此按应用收敛隐私出口）
            notifyModule("hook-enter", pkg);

            // 自身 / 系统进程不挂钩，避免自锁与不稳
            if (SELF.equals(pkg) || "android".equals(pkg) || "system".equals(pkg)) return;

            // 子功能 2：按模式安装内置隐私钩子
            String mode = modCall("hook-mode");
            if ("off".equals(mode)) {
                xlog("hook mode off");
                return;
            }
            boolean install = "all".equals(mode) || "on".equals(mode) || isPrivacyTarget(pkg);
            if (!install) {
                xlog("skip (not a privacy target): " + pkg);
                return;
            }

            int ok = SyHookManager.install(lpparam.classLoader, pkg);
            xlog("installed hooks: " + ok + " in " + pkg);
        } catch (Throwable t) {
            xlog("handleLoadPackage err: " + t);
        }
    }

    private void notifyModule(final String sub, final String pkg) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    modCall(sub + " " + pkg);
                } catch (Throwable ignored) {
                }
            }
        }, "sy-hook-notify").start();
    }

    /** 调用模块内 leakguard.sh（阻塞，带超时）。 */
    private String modCall(String argsCmd) {
        try {
            return RootShell.exec("sh " + RootShell.MODDIR
                    + "/scripts/leakguard.sh " + argsCmd + " 2>/dev/null", 6000);
        } catch (Throwable t) {
            return "";
        }
    }

    private boolean isPrivacyTarget(String pkg) {
        try {
            String raw = RootShell.exec(
                    "cat " + RootShell.MODDIR + "/config/privacy_targets.txt 2>/dev/null", 4000);
            if (raw == null) return false;
            for (String line : raw.split("\n")) {
                String p = line.trim();
                if (p.length() > 0 && p.charAt(0) != '#' && p.equals(pkg)) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private void xlog(String msg) {
        try {
            XposedBridge.log(TAG + " " + msg);
        } catch (Throwable ignored) {
        }
    }
}
