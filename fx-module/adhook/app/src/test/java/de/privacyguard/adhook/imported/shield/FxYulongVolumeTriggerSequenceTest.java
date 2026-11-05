package de.privacyguard.adhook.imported.shield;

import org.junit.Test;
import static org.junit.Assert.*;

public class FxYulongVolumeTriggerSequenceTest {
    @Test
    public void keepsOriginalDefaultsAndClampRange() {
        assertEquals(3, FxYulongVolumeTriggerSequence.DEFAULT_COUNT);
        assertEquals(2, FxYulongVolumeTriggerSequence.normalizeCount(0));
        assertEquals(2, FxYulongVolumeTriggerSequence.normalizeCount(1));
        assertEquals(2, FxYulongVolumeTriggerSequence.normalizeCount(2));
        assertEquals(10, FxYulongVolumeTriggerSequence.normalizeCount(100));
        assertEquals(FxYulongVolumeTriggerSequence.DIRECTION_DOWN,
                FxYulongVolumeTriggerSequence.directionForPreference(null));
        assertEquals(FxYulongVolumeTriggerSequence.DIRECTION_DOWN,
                FxYulongVolumeTriggerSequence.directionForPreference("down"));
        assertEquals(FxYulongVolumeTriggerSequence.DIRECTION_UP,
                FxYulongVolumeTriggerSequence.directionForPreference("up"));
    }

    @Test
    public void triggersOnlyAfterConfiguredVolumeDownCount() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int down = FxYulongVolumeTriggerSequence.DIRECTION_DOWN;
        assertFalse(sequence.recordPress(down, down, 3, 1000L));
        assertFalse(sequence.recordPress(down, down, 3, 1700L));
        assertTrue(sequence.recordPress(down, down, 3, 2400L));
    }

    @Test
    public void selectedDirectionMustMatchAndOppositeKeyResetsSequence() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int up = FxYulongVolumeTriggerSequence.DIRECTION_UP;
        int down = FxYulongVolumeTriggerSequence.DIRECTION_DOWN;
        assertFalse(sequence.recordPress(up, down, 2, 1000L));
        assertFalse(sequence.recordPress(down, down, 2, 1200L));
        assertTrue(sequence.recordPress(down, down, 2, 1400L));
    }

    @Test
    public void countControlsWindowUsingLegacyMinimumAndPerPressTiming() {
        assertEquals(2500L, FxYulongVolumeTriggerSequence.sequenceWindowMs(2));
        assertEquals(2500L, FxYulongVolumeTriggerSequence.sequenceWindowMs(3));
        assertEquals(2800L, FxYulongVolumeTriggerSequence.sequenceWindowMs(4));
        assertEquals(7000L, FxYulongVolumeTriggerSequence.sequenceWindowMs(10));

        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int down = FxYulongVolumeTriggerSequence.DIRECTION_DOWN;
        assertFalse(sequence.recordPress(down, down, 4, 1000L));
        assertFalse(sequence.recordPress(down, down, 4, 1900L));
        assertFalse(sequence.recordPress(down, down, 4, 2800L));
        assertFalse(sequence.recordPress(down, down, 4, 3801L)); // previous 2.8s window expired
        assertFalse(sequence.recordPress(down, down, 4, 4300L));
        assertFalse(sequence.recordPress(down, down, 4, 4900L));
        assertTrue(sequence.recordPress(down, down, 4, 5500L));
    }

    @Test
    public void completedSequenceHasCooldownAndThenCanTriggerAgain() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int up = FxYulongVolumeTriggerSequence.DIRECTION_UP;
        assertFalse(sequence.recordPress(up, up, 2, 1000L));
        assertTrue(sequence.recordPress(up, up, 2, 1200L));

        assertFalse(sequence.recordPress(up, up, 2, 2000L));
        assertFalse(sequence.recordPress(up, up, 2, 2200L)); // suppressed by 10s cooldown

        assertFalse(sequence.recordPress(up, up, 2, 11000L));
        assertTrue(sequence.recordPress(up, up, 2, 11200L));
    }

    @Test
    public void backwardsTimeResetsInsteadOfTriggering() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int down = FxYulongVolumeTriggerSequence.DIRECTION_DOWN;
        assertFalse(sequence.recordPress(down, down, 2, 1000L));
        assertFalse(sequence.recordPress(down, down, 2, 900L));
        assertTrue(sequence.recordPress(down, down, 2, 1100L));
    }

    @Test
    public void changingDirectionOrRequiredCountCannotReuseOldPartialPresses() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int up = FxYulongVolumeTriggerSequence.DIRECTION_UP;
        int down = FxYulongVolumeTriggerSequence.DIRECTION_DOWN;

        assertFalse(sequence.recordPress(down, down, 3, 1000L));
        // A changed threshold starts a fresh sequence instead of counting the
        // old press toward the newly selected two-press trigger.
        assertFalse(sequence.recordPress(down, down, 2, 1200L));
        assertTrue(sequence.recordPress(down, down, 2, 1400L));

        sequence.resetSequence();
        assertFalse(sequence.recordPress(up, up, 3, 20000L));
        // A direction change also invalidates the partial sequence.
        assertFalse(sequence.recordPress(up, down, 2, 20200L));
        assertFalse(sequence.recordPress(down, down, 2, 20400L));
        assertTrue(sequence.recordPress(down, down, 2, 20600L));
    }

    @Test
    public void resetClearsPartialSequenceWithoutChangingUserOptions() {
        FxYulongVolumeTriggerSequence sequence = new FxYulongVolumeTriggerSequence();
        int up = FxYulongVolumeTriggerSequence.DIRECTION_UP;
        assertFalse(sequence.recordPress(up, up, 2, 1000L));
        sequence.resetSequence();
        assertFalse(sequence.recordPress(up, up, 2, 1100L));
        assertTrue(sequence.recordPress(up, up, 2, 1200L));
    }
}
