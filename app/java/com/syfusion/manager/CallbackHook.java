package com.syfusion.manager;

import de.robv.android.xposed.XC_MethodHook;

/**
 * 通用 Hook 回调（真实实现，非空壳）。
 *
 * 这是 XC_MethodHook 的正规子类 —— 抽象类必须用继承，不能用 Proxy 代理
 * （历史上 SyXposedEntry 用 Proxy.newProxyInstance 代理抽象类，必然抛异常、
 * 钩子从未生效，属于典型空壳；本类彻底替代它）。
 *
 * 把 before/after 两个生命周期子事件转发给 SyHookManager.Action，
 * 由 Action 决定上报、统计或拦截。
 */
public class CallbackHook extends XC_MethodHook {

    private final String tag;
    private final SyHookManager.Action action;

    public CallbackHook(int priority, String tag, SyHookManager.Action action) {
        super(priority);
        this.tag = tag;
        this.action = action;
    }

    @Override
    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {
        try {
            action.before(tag, param);
        } catch (Throwable ignored) {
            // 钩子绝不允许影响宿主应用
        }
    }

    @Override
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
        try {
            action.after(tag, param);
        } catch (Throwable ignored) {
        }
    }
}
