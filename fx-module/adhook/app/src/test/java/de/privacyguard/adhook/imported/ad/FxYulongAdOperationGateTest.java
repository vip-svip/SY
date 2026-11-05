package de.privacyguard.adhook.imported.ad;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

/** Verifies that only the current operation owner can release the shared gate. */
public class FxYulongAdOperationGateTest {
    @Test
    public void unrelatedOrStaleTokenCannotReleaseAnotherWriter() {
        long owner = FxYulongAdOperationGate.tryAcquire();
        assertNotEquals("a successful lease must have a non-zero token", 0L, owner);
        try {
            assertEquals("a second writer must be rejected while owned",
                    0L, FxYulongAdOperationGate.tryAcquire());
            assertFalse("zero is never a valid owner token",
                    FxYulongAdOperationGate.release(0L));
            assertFalse("an unrelated token must not unlock the current owner",
                    FxYulongAdOperationGate.release(owner + 1L));
            assertEquals("the original owner must remain protected",
                    0L, FxYulongAdOperationGate.tryAcquire());
        } finally {
            assertTrue("the rightful owner must be able to release",
                    FxYulongAdOperationGate.release(owner));
        }
        assertFalse("a stale token must not release a later operation",
                FxYulongAdOperationGate.release(owner));
        long next = FxYulongAdOperationGate.tryAcquire();
        assertNotEquals("each successful lease must have a fresh token", owner, next);
        assertNotEquals(0L, next);
        assertTrue(FxYulongAdOperationGate.release(next));
    }
}
