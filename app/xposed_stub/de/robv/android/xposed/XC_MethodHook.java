package de.robv.android.xposed;

/**
 * 编译期占位桩（compile-only）。
 *
 * 仅用于让模块在不依赖 XposedBridgeApi.jar 的情况下通过 javac。
 * 这些 .class 不会被打进 APK（构建脚本把 de/robv/* 排除在 d8 之外），
 * 运行期由 LSPosed 注入其真实实现。
 *
 * 注意：这是「基类」而不是接口。历史上这里把它当接口用
 * （Proxy.newProxyInstance 只能代理接口），导致钩子 100% 抛异常、
 * 静默降级成空壳。现在改为正规子类继承，见 SyHook。
 */
public abstract class XC_MethodHook {

    public XC_MethodHook() {}

    public XC_MethodHook(int priority) {}

    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {}

    protected void afterHookedMethod(MethodHookParam param) throws Throwable {}

    /** 与 LSPosed 同名嵌套类，供子类签名匹配。 */
    public static class MethodHookParam {
        public Object thisObject;
        public Object[] args;

        public Object getResult() {
            return null;
        }

        public void setResult(Object result) {}

        public void setResult(Object result, boolean fromReturnValue) {}

        public Throwable getThrowable() {
            return null;
        }

        public void setThrowable(Throwable t) {}
    }
}
