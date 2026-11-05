package de.privacyguard.adhook.imported.dia;

/**
 * Single source of truth for ownership of Android's global http_proxy value.
 * The persisted "active" preference alone cannot prove the system value is
 * still owned by FX: another app or the user may have changed it.
 */
public final class FxDiaWifiProxyState {
    public enum Status { DISABLED, ACTIVE, EXTERNALLY_CHANGED, UNKNOWN }

    private FxDiaWifiProxyState() { }

    public static Status evaluate(boolean managed, String currentValue,
                                  String expectedValue, boolean readable) {
        if (!readable) return Status.UNKNOWN;
        if (!managed) return Status.DISABLED;
        String expected = normalize(expectedValue);
        if (expected.isEmpty()) return Status.EXTERNALLY_CHANGED;
        return expected.equals(normalize(currentValue))
                ? Status.ACTIVE : Status.EXTERNALLY_CHANGED;
    }

    public static boolean mayRestore(Status status) {
        return status == Status.ACTIVE;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }
}
