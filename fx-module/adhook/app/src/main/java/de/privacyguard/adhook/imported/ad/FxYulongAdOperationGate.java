package de.privacyguard.adhook.imported.ad;

import java.util.concurrent.atomic.AtomicLong;

/** Token-owned lease for serializing Yulong ad-master/settings writes. */
public final class FxYulongAdOperationGate {
    private static final AtomicLong NEXT_TOKEN = new AtomicLong(0L);
    private static final AtomicLong OWNER_TOKEN = new AtomicLong(0L);

    private FxYulongAdOperationGate() { }

    /** Returns a non-zero ownership token, or zero when another writer owns the gate. */
    public static long tryAcquire() {
        long token = NEXT_TOKEN.incrementAndGet();
        if (token == 0L) token = NEXT_TOKEN.incrementAndGet();
        return OWNER_TOKEN.compareAndSet(0L, token) ? token : 0L;
    }

    /** Releases only the exact lease acquired by this operation. */
    public static boolean release(long token) {
        return token != 0L && OWNER_TOKEN.compareAndSet(token, 0L);
    }
}
