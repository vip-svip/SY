package de.robv.android.xposed;

/**
 * 编译期占位桩（compile-only）。
 *
 * 仅用于让模块在不依赖 XposedBridgeApi.jar 的情况下通过 javac；
 * 这些 .class 不会被打进 APK（构建脚本把它们排除在 d8 之外），
 * 运行期由 LSPosed 注入其真实实现，避免重复类导致接口识别失败。
 */
public interface IXposedHookLoadPackage {
    void handleLoadPackage(de.robv.android.xposed.callbacks.XC_LoadPackage.LoadPackageParam lpparam) throws Throwable;
}
