package de.privacyguard.adhook;

/** Process-scoped, opt-in clipboard isolation gate. */
public final class ClipboardIsolationPolicy {
    private ClipboardIsolationPolicy() {}

    public static boolean shouldIsolate(boolean privacyMasterEnabled, int processPackageCount,
                                        String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1 || packageName == null
                || packageName.isEmpty() || target == null || !target.clipboardIsolate
                || target.clipboardReadBlock) return false;
        return !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }
}
