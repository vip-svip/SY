package de.robv.android.xposed;

/**
 * 编译期占位桩（compile-only）。运行期由 LSPosed 注入真实实现。
 * 见 XC_MethodHook.java 的说明。
 */
public class XposedHelpers {

    public static Object findAndHookMethod(Class<?> clazz, String methodName,
                                           Object... parameterTypesAndCallback) {
        return null;
    }

    public static Object findAndHookMethod(String className, ClassLoader classLoader, String methodName,
                                           Object... parameterTypesAndCallback) {
        return null;
    }

    public static Object callMethod(Object obj, String methodName, Object... args) {
        return null;
    }

    public static Object getObjectField(Object obj, String fieldName) {
        return null;
    }

    public static void setObjectField(Object obj, String fieldName, Object value) {}
}
