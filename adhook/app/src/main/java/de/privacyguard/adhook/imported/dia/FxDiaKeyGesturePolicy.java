package de.privacyguard.adhook.imported.dia;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Pure-Java decoder for the original Dia ActivityKey gestures.
 *
 * Trigger IDs: 0 volume-down double, 1 Back double, 2 volume-down triple,
 * 3 Back triple, 4 volume-up double, 5 Back long press, 6 volume-down/up chord.
 * Repeat-generated key-down events are ignored so a held key cannot masquerade
 * as a deliberate multi-press gesture.
 */
public final class FxDiaKeyGesturePolicy {
    public static final int TRIGGER_VOLUME_DOWN_DOUBLE = 0;
    public static final int TRIGGER_BACK_DOUBLE = 1;
    public static final int TRIGGER_VOLUME_DOWN_TRIPLE = 2;
    public static final int TRIGGER_BACK_TRIPLE = 3;
    public static final int TRIGGER_VOLUME_UP_DOUBLE = 4;
    public static final int TRIGGER_BACK_LONG_PRESS = 5;
    public static final int TRIGGER_VOLUME_DOWN_UP_CHORD = 6;

    public static final int KEYCODE_BACK = 4;
    public static final int KEYCODE_VOLUME_UP = 24;
    public static final int KEYCODE_VOLUME_DOWN = 25;

    public static final long MIN_DOUBLE_PRESS_GAP_MS = 200L;
    public static final long MULTI_PRESS_WINDOW_MS = 2000L;
    public static final long CHORD_WINDOW_MS = 400L;

    private long lastVolumeDownDouble;
    private long lastVolumeDownTriple;
    private int volumeDownTripleCount;
    private long lastBackDouble;
    private long lastBackTriple;
    private int backTripleCount;
    private long lastVolumeUpDouble;
    private long lastVolumeDownChord;
    private long lastVolumeUpChord;

    public synchronized List<Integer> onKeyDown(int keyCode, long eventTimeMs,
                                                int repeatCount) {
        if (eventTimeMs <= 0L || repeatCount > 0) return Collections.emptyList();
        List<Integer> events = new ArrayList<>(3);
        if (keyCode == KEYCODE_VOLUME_DOWN) {
            long delta = eventTimeMs - lastVolumeDownDouble;
            if (lastVolumeDownDouble > 0L && delta > MIN_DOUBLE_PRESS_GAP_MS
                    && delta < MULTI_PRESS_WINDOW_MS) {
                events.add(TRIGGER_VOLUME_DOWN_DOUBLE);
                lastVolumeDownDouble = 0L;
            }
            lastVolumeDownDouble = eventTimeMs;

            long tripleDelta = eventTimeMs - lastVolumeDownTriple;
            if (lastVolumeDownTriple == 0L || tripleDelta > MULTI_PRESS_WINDOW_MS) {
                volumeDownTripleCount = 1;
            } else if (tripleDelta > MIN_DOUBLE_PRESS_GAP_MS) {
                volumeDownTripleCount++;
            }
            lastVolumeDownTriple = eventTimeMs;
            if (volumeDownTripleCount == 3) {
                events.add(TRIGGER_VOLUME_DOWN_TRIPLE);
                volumeDownTripleCount = 0;
                lastVolumeDownTriple = 0L;
            }
            lastVolumeDownChord = eventTimeMs;
        } else if (keyCode == KEYCODE_BACK) {
            long delta = eventTimeMs - lastBackDouble;
            if (lastBackDouble > 0L && delta > 0L && delta < MULTI_PRESS_WINDOW_MS) {
                events.add(TRIGGER_BACK_DOUBLE);
                lastBackDouble = 0L;
            }
            lastBackDouble = eventTimeMs;

            long tripleDelta = eventTimeMs - lastBackTriple;
            if (lastBackTriple == 0L || tripleDelta > MULTI_PRESS_WINDOW_MS) {
                backTripleCount = 1;
            } else {
                backTripleCount++;
            }
            lastBackTriple = eventTimeMs;
            if (backTripleCount == 3) {
                events.add(TRIGGER_BACK_TRIPLE);
                backTripleCount = 0;
                lastBackTriple = 0L;
            }
        } else if (keyCode == KEYCODE_VOLUME_UP) {
            long delta = eventTimeMs - lastVolumeUpDouble;
            if (lastVolumeUpDouble > 0L && delta > MIN_DOUBLE_PRESS_GAP_MS
                    && delta < MULTI_PRESS_WINDOW_MS) {
                events.add(TRIGGER_VOLUME_UP_DOUBLE);
                lastVolumeUpDouble = 0L;
            }
            lastVolumeUpDouble = eventTimeMs;
            lastVolumeUpChord = eventTimeMs;
        }

        if (lastVolumeDownChord > 0L && lastVolumeUpChord > 0L
                && Math.abs(lastVolumeDownChord - lastVolumeUpChord) < CHORD_WINDOW_MS) {
            events.add(TRIGGER_VOLUME_DOWN_UP_CHORD);
            lastVolumeDownChord = 0L;
            lastVolumeUpChord = 0L;
        }
        return events.isEmpty() ? Collections.emptyList()
                : Collections.unmodifiableList(events);
    }

    public synchronized List<Integer> onLongPress(int keyCode) {
        if (keyCode != KEYCODE_BACK) return Collections.emptyList();
        return Collections.singletonList(TRIGGER_BACK_LONG_PRESS);
    }

    public synchronized void reset() {
        lastVolumeDownDouble = 0L;
        lastVolumeDownTriple = 0L;
        volumeDownTripleCount = 0;
        lastBackDouble = 0L;
        lastBackTriple = 0L;
        backTripleCount = 0;
        lastVolumeUpDouble = 0L;
        lastVolumeDownChord = 0L;
        lastVolumeUpChord = 0L;
    }
}
