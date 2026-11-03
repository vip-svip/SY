package de.privacyguard.adhook.imported.ad;

import java.util.HashSet;
import java.util.Set;

/** Aggregates TrafficStats counters once per UID, not once per installed package. */
public final class UidTrafficTotals {
    private final Set<Integer> seenUids = new HashSet<>();
    private long rxBytes;
    private long txBytes;
    private int unavailableUidCount;

    /** Returns false when this UID was already included in the aggregate. */
    public boolean add(int uid, long rx, long tx) {
        if (!seenUids.add(uid)) return false;
        if (rx < 0 || tx < 0) {
            unavailableUidCount++;
            return true;
        }
        rxBytes = saturatedAdd(rxBytes, rx);
        txBytes = saturatedAdd(txBytes, tx);
        return true;
    }

    private static long saturatedAdd(long current, long value) {
        return value > Long.MAX_VALUE - current ? Long.MAX_VALUE : current + value;
    }

    public int getUidCount() { return seenUids.size(); }
    public int getUnavailableUidCount() { return unavailableUidCount; }
    public int getAvailableUidCount() { return getUidCount() - unavailableUidCount; }
    public long getRxBytes() { return rxBytes; }
    public long getTxBytes() { return txBytes; }
}
