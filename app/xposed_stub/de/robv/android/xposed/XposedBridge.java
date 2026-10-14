package de.robv.android.xposed;

/**
 * 编译期占位桩（compile-only）。运行期由 LSPosed 注入真实实现。
 * 见 XC_MethodHook.java 的说明。
 */
public class XposedBridge {

    public static void log(String text) {}

    public static void log(Throwable t) {}

    public static void hookAllMethods(Class<?> hookClass, String methodName,
                                      XC_MethodHook callback) {}
}
