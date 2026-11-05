package de.privacyguard.adhook.imported.ad;

import org.junit.Test;
import static org.junit.Assert.*;

public class FxYulongScheduleDayMappingTest {
    @Test public void mondayFirstUiMapsToOriginalCalendarIndexes() {
        int[] expected = {1, 2, 3, 4, 5, 6, 0};
        for (int ui = 0; ui < expected.length; ui++) {
            assertEquals("UI weekday index " + ui, expected[ui],
                    FxYulongScheduleDayMapping.workerDayForUiIndex(ui));
        }
    }

    @Test public void defaultWeekSelectsAllSevenDaysAndRoundTrips() {
        String all = FxYulongScheduleDayMapping.defaultWeekCsv();
        assertEquals("1,2,3,4,5,6,0", all);
        for (int ui = 0; ui < 7; ui++) {
            assertTrue("default week omitted UI weekday " + ui,
                    FxYulongScheduleDayMapping.isUiDaySelected(all, ui));
        }
    }

    @Test public void sundayAndSaturdayDoNotShiftIntoWrongCheckboxes() {
        assertTrue(FxYulongScheduleDayMapping.isUiDaySelected("0", 6));
        assertFalse(FxYulongScheduleDayMapping.isUiDaySelected("0", 5));
        assertTrue(FxYulongScheduleDayMapping.isUiDaySelected("6", 5));
        assertFalse(FxYulongScheduleDayMapping.isUiDaySelected("6", 6));
        assertTrue(FxYulongScheduleDayMapping.isUiDaySelected("1, 3, 5", 0));
        assertTrue(FxYulongScheduleDayMapping.isUiDaySelected("1, 3, 5", 2));
        assertTrue(FxYulongScheduleDayMapping.isUiDaySelected("1, 3, 5", 4));
        assertFalse(FxYulongScheduleDayMapping.isUiDaySelected("1, 3, 5", 6));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUiWeekdayOutsideMondayFirstRange() {
        FxYulongScheduleDayMapping.workerDayForUiIndex(7);
    }
}
