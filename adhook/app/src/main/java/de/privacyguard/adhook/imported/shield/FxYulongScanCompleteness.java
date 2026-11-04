package de.privacyguard.adhook.imported.shield;

/** Pure completeness rules shared by scan results and UI. */
public final class FxYulongScanCompleteness {
    private FxYulongScanCompleteness() { }

    public static boolean isComplete(boolean inventoryComplete, boolean contentScanEnabled,
                                     boolean contentDatabaseReady, boolean contentTruncated,
                                     int contentReadFailures) {
        if (!inventoryComplete || contentReadFailures > 0 || contentTruncated) return false;
        return !contentScanEnabled || contentDatabaseReady;
    }

    public static String noFindingMessage(boolean complete) {
        return complete
                ? "没有命中当前名单。这不代表设备绝对安全。"
                : "未发现已扫描项目的名单命中，但扫描存在未完成部分；不能据此判定设备安全。";
    }
}
