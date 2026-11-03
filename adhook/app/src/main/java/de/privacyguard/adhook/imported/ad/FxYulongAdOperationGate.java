package de.privacyguard.adhook.imported.ad;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Serializes the shared ad-master configuration writer across Tasker,
 * the home-screen widget and the Quick Settings tile in the default app process.
 */
public final class FxYulongAdOperationGate {
    private static final AtomicBoolean BUSY = new AtomicBoolean(false);

    private FxYulongAdOperationGate() {
    }

    public static boolean tryAcquire() {
        return BUSY.compareAndSet(false, true);
    }

    public static void release() {
        BUSY.set(false);
    }
}
