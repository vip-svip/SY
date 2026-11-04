package de.privacyguard.adhook.imported.dia;

/** Single migration policy for the current and original Dia crash-capture switches. */
public final class FxDiaCrashCapturePolicy {
    private FxDiaCrashCapturePolicy() { }

    public static boolean isEnabled(boolean captureEnabled,
                                    boolean currentDisabled,
                                    boolean legacyDisabled) {
        return captureEnabled && !currentDisabled && !legacyDisabled;
    }
}
