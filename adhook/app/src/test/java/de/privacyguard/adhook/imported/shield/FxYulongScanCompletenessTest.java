package de.privacyguard.adhook.imported.shield;

import org.junit.Test;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxYulongScanCompletenessTest {
    @Test public void incompleteInventoryNeverReportsComplete() {
        assertFalse(FxYulongScanCompleteness.isComplete(false, false, false, false, 0));
    }

    @Test public void contentScanRequiresReadyDatabaseAndCompleteReads() {
        assertFalse(FxYulongScanCompleteness.isComplete(true, true, false, false, 0));
        assertFalse(FxYulongScanCompleteness.isComplete(true, true, true, true, 0));
        assertFalse(FxYulongScanCompleteness.isComplete(true, true, true, false, 2));
        assertTrue(FxYulongScanCompleteness.isComplete(true, true, true, false, 0));
    }
}
