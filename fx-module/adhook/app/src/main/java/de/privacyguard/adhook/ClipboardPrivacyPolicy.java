package de.privacyguard.adhook;

/** Pure fail-open gate for process-scoped clipboard read protection. */
public final class ClipboardPrivacyPolicy {
    private ClipboardPrivacyPolicy() {}

    public static boolean shouldBlockRead(boolean privacyMasterEnabled, int packageCount,
                                          String packageName, UnifiedHookConfigParser.Target target) {
        return privacyMasterEnabled && packageCount == 1 && packageName != null
                && !packageName.isEmpty() && target != null && target.clipboardReadBlock
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }
}
