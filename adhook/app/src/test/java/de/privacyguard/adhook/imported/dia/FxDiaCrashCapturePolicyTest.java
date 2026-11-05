package de.privacyguard.adhook.imported.dia;

import org.junit.Test;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** Pure policy coverage for the original Dia opt-out and FX capture switch. */
public class FxDiaCrashCapturePolicyTest {
    @Test public void captureIsEnabledOnlyWhenBothLegacyAndCurrentVetoesAreClear() {
        assertTrue(FxDiaCrashCapturePolicy.isEnabled(true, false, false));
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(false, false, false));
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(true, true, false));
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(true, false, true));
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(false, true, true));
    }

    @Test public void explicitEnableRequiresBothLegacyAndCurrentVetoesToBeCleared() {
        // setCaptureEnabled(true) clears both veto keys before committing capture_enabled=true.
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(true, false, true));
        assertFalse(FxDiaCrashCapturePolicy.isEnabled(true, true, false));
        assertTrue(FxDiaCrashCapturePolicy.isEnabled(true, false, false));
    }
}
