from pathlib import Path

source = Path("adhook/app/src/main/java/de/privacyguard/hook/MainHook.java")
text = source.read_text(encoding="utf-8")
old = """        if (lpp.appInfo != null && lpp.appInfo.sharedUserId != null
                && !lpp.appInfo.sharedUserId.isEmpty()) {
            log("shared UID process: legacy hooks disabled for " + pkg);
            return;
        }
"""
new = """        if (hasMultiplePackagesForUid(lpp.appInfo)) {
            log("shared UID process or package identity unavailable: legacy hooks disabled for " + pkg);
            return;
        }
"""
if old not in text:
    raise SystemExit("API82 shared-UID guard anchor missing or already patched")
anchor = """    /* ================= 入口 ================= */

"""
helper = """    /**
     * ApplicationInfo.sharedUserId is not part of the public SDK surface on
     * current compile SDKs. Query the framework package manager reflectively.
     * If the UID-to-package mapping cannot be established, fail open by
     * disabling this legacy process rather than risk cross-package policy bleed.
     */
    private static boolean hasMultiplePackagesForUid(ApplicationInfo appInfo) {
        if (appInfo == null || appInfo.uid <= 0) return true;
        try {
            Class<?> appGlobals = Class.forName("android.app.AppGlobals");
            Object packageManager = XposedHelpers.callStaticMethod(appGlobals, "getPackageManager");
            Object packages = XposedHelpers.callMethod(packageManager, "getPackagesForUid", appInfo.uid);
            if (packages instanceof String[]) return ((String[]) packages).length > 1;
        } catch (Throwable ignored) {
            // Unknown identity is not safe to hook; keep the process untouched.
        }
        return true;
    }

"""
if anchor not in text:
    raise SystemExit("API82 entry helper insertion anchor missing")
text = text.replace(old, new, 1).replace(anchor, anchor + helper, 1)
source.write_text(text, encoding="utf-8")
