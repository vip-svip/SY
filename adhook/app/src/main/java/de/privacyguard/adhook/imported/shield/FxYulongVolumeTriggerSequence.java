package de.privacyguard.adhook.imported.shield;

/**
 * Pure sequence detector for the migrated Yulong volume-key rescue trigger.
 * It does not consume key events; callers decide whether to display the rescue notice.
 */
public final class FxYulongVolumeTriggerSequence {
    public static final int MIN_COUNT = 2;
    public static final int MAX_COUNT = 10;
    public static final int DEFAULT_COUNT = 3;
    public static final long MIN_WINDOW_MS = 2500L;
    public static final long PER_PRESS_WINDOW_MS = 700L;
    public static final long TRIGGER_COOLDOWN_MS = 10000L;
    public static final int DIRECTION_DOWN = -1;
    public static final int DIRECTION_UP = 1;

    private long sequenceStartedAt = -1L;
    private int pressCount;
    private long lastTriggeredAt = -1L;
    private int activeWantedDirection;
    private int activeRequiredCount;

    public static int normalizeCount(int value) {
        return Math.max(MIN_COUNT, Math.min(MAX_COUNT, value));
    }

    /** Legacy Yulong default is the volume-down key. */
    public static int directionForPreference(String value) {
        return "up".equalsIgnoreCase(value) ? DIRECTION_UP : DIRECTION_DOWN;
    }

    public static long sequenceWindowMs(int count) {
        return Math.max(MIN_WINDOW_MS, normalizeCount(count) * PER_PRESS_WINDOW_MS);
    }

    /**
     * Records one completed physical key press.
     *
     * @param direction actual key direction (+1 up, -1 down)
     * @param wantedDirection configured trigger direction
     * @param requiredCount configured press count, clamped to the original 2..10 range
     * @param elapsedRealtimeMs monotonic time from SystemClock.elapsedRealtime()
     * @return true only once when the selected key reaches the configured threshold
     */
    public boolean recordPress(int direction, int wantedDirection, int requiredCount,
            long elapsedRealtimeMs) {
        if ((direction != DIRECTION_UP && direction != DIRECTION_DOWN)
                || direction != wantedDirection || elapsedRealtimeMs < 0L) {
            resetSequence();
            return false;
        }

        int normalizedCount = normalizeCount(requiredCount);
        if (pressCount > 0 && (activeWantedDirection != wantedDirection
                || activeRequiredCount != normalizedCount)) {
            resetSequence();
        }
        activeWantedDirection = wantedDirection;
        activeRequiredCount = normalizedCount;

        long window = sequenceWindowMs(normalizedCount);
        if (sequenceStartedAt < 0L || elapsedRealtimeMs < sequenceStartedAt
                || elapsedRealtimeMs - sequenceStartedAt > window) {
            sequenceStartedAt = elapsedRealtimeMs;
            pressCount = 0;
        }
        pressCount++;

        if (pressCount < normalizedCount) return false;

        resetSequence();
        if (lastTriggeredAt >= 0L && (elapsedRealtimeMs < lastTriggeredAt
                || elapsedRealtimeMs - lastTriggeredAt < TRIGGER_COOLDOWN_MS)) {
            return false;
        }
        lastTriggeredAt = elapsedRealtimeMs;
        return true;
    }

    public void resetSequence() {
        sequenceStartedAt = -1L;
        pressCount = 0;
        activeWantedDirection = 0;
        activeRequiredCount = 0;
    }
}
