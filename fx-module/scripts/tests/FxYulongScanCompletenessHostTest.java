package de.privacyguard.adhook.imported.shield;

/** Host-JVM behavioral regression for fail-closed scan completion reporting. */
public final class FxYulongScanCompletenessHostTest {
    private static void expect(boolean actual, boolean expected, String label) {
        if (actual != expected) throw new AssertionError(label + ": expected " + expected + ", got " + actual);
    }

    public static void main(String[] args) {
        expect(FxYulongScanCompleteness.isComplete(true, false, false, false, 0), true, "inventory-only scan");
        expect(FxYulongScanCompleteness.isComplete(false, false, false, false, 0), false, "partial inventory");
        expect(FxYulongScanCompleteness.isComplete(true, true, false, false, 0), false, "missing content database");
        expect(FxYulongScanCompleteness.isComplete(true, true, true, true, 0), false, "budget truncation");
        expect(FxYulongScanCompleteness.isComplete(true, true, true, false, 1), false, "unreadable APK");
        expect(FxYulongScanCompleteness.isComplete(true, true, true, false, -1), false, "invalid negative read-failure count");
        expect(FxYulongScanCompleteness.isComplete(true, true, true, false, 0), true, "full scan");
        if (!FxYulongScanCompleteness.noFindingMessage(false).contains("不能据此判定设备安全")) {
            throw new AssertionError("incomplete no-hit result must not imply safety");
        }
        System.out.println("PASS: Shield scan completeness fails closed");
    }
}
