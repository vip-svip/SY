package de.privacyguard.adhook;

/** Fail-open gate for hiding input-method enumeration from one selected app. */
public final class InputMethodPrivacyPolicy {
    private InputMethodPrivacyPolicy() {}

    public static boolean shouldHideInputMethods(boolean privacyEnabled, int processPackageCount,
                                                 String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null && target != null
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName)
                && target.blockImeLogging;
    }
}
