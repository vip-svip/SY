package de.robv.android.xposed.callbacks;

/** 编译期占位桩（不打包，见 IXposedHookLoadPackage.java 说明）。 */
public class XC_LoadPackage {
    public static class LoadPackageParam {
        public String packageName;
        public String processName;
        public ClassLoader classLoader;
        public boolean isFirstApplication;
        public Object appInfo;
    }
}
