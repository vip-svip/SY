package de.privacyguard.adhook.imported.dia;

/** Host-side regression for the Dia/FX global proxy ownership state machine. */
public final class FxDiaWifiProxyStateHostTest {
    private static void expect(FxDiaWifiProxyState.Status actual,
                               FxDiaWifiProxyState.Status expected, String label) {
        if (actual != expected) {
            throw new AssertionError(label + ": expected " + expected + ", got " + actual);
        }
    }

    public static void main(String[] args) {
        expect(FxDiaWifiProxyState.evaluate(true, "127.0.0.1:8080", "127.0.0.1:8080", true),
                FxDiaWifiProxyState.Status.ACTIVE, "matching FX-owned proxy");
        expect(FxDiaWifiProxyState.evaluate(true, "proxy.other:3128", "127.0.0.1:8080", true),
                FxDiaWifiProxyState.Status.EXTERNALLY_CHANGED, "external proxy replacement");
        expect(FxDiaWifiProxyState.evaluate(true, "null", "127.0.0.1:8080", true),
                FxDiaWifiProxyState.Status.EXTERNALLY_CHANGED, "external proxy removal");
        expect(FxDiaWifiProxyState.evaluate(true, "127.0.0.1:8080", "", true),
                FxDiaWifiProxyState.Status.EXTERNALLY_CHANGED, "missing ownership marker");
        expect(FxDiaWifiProxyState.evaluate(false, "proxy.other:3128", "127.0.0.1:8080", true),
                FxDiaWifiProxyState.Status.DISABLED, "third-party proxy while FX is not managing");
        expect(FxDiaWifiProxyState.evaluate(true, "127.0.0.1:8080", "127.0.0.1:8080", false),
                FxDiaWifiProxyState.Status.UNKNOWN, "root read failure");
        expect(FxDiaWifiProxyState.evaluate(true, " 127.0.0.1:8080 ", "127.0.0.1:8080", true),
                FxDiaWifiProxyState.Status.ACTIVE, "trimmed shell output");
        if (!FxDiaWifiProxyState.mayRestore(FxDiaWifiProxyState.Status.ACTIVE))
            throw new AssertionError("owned proxy should be restorable");
        for (FxDiaWifiProxyState.Status status : new FxDiaWifiProxyState.Status[] {
                FxDiaWifiProxyState.Status.DISABLED,
                FxDiaWifiProxyState.Status.EXTERNALLY_CHANGED,
                FxDiaWifiProxyState.Status.UNKNOWN
        }) if (FxDiaWifiProxyState.mayRestore(status))
            throw new AssertionError("must not restore when status is " + status);
        System.out.println("PASS: proxy ownership state machine");
    }
}
