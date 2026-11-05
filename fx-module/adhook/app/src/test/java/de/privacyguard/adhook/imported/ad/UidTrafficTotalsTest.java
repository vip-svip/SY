package de.privacyguard.adhook.imported.ad;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class UidTrafficTotalsTest {
    @Test public void countsSharedUidOnlyOnce() {
        UidTrafficTotals totals = new UidTrafficTotals();
        assertTrue(totals.add(10001, 1024, 2048));
        assertFalse(totals.add(10001, 1024, 2048));
        assertEquals(1, totals.getUidCount());
        assertEquals(1, totals.getAvailableUidCount());
        assertEquals(0, totals.getUnavailableUidCount());
        assertEquals(1024L, totals.getRxBytes());
        assertEquals(2048L, totals.getTxBytes());
    }

    @Test public void tracksUnsupportedUidCountersOnce() {
        UidTrafficTotals totals = new UidTrafficTotals();
        assertTrue(totals.add(10002, -1, -1));
        assertFalse(totals.add(10002, -1, -1));
        assertEquals(1, totals.getUidCount());
        assertEquals(0, totals.getAvailableUidCount());
        assertEquals(1, totals.getUnavailableUidCount());
        assertEquals(0L, totals.getRxBytes());
        assertEquals(0L, totals.getTxBytes());
    }

    @Test public void saturatesAggregateInsteadOfOverflowing() {
        UidTrafficTotals totals = new UidTrafficTotals();
        totals.add(10003, Long.MAX_VALUE, Long.MAX_VALUE);
        totals.add(10004, 1L, 2L);
        assertEquals(Long.MAX_VALUE, totals.getRxBytes());
        assertEquals(Long.MAX_VALUE, totals.getTxBytes());
    }
}
