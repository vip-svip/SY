package de.privacyguard.adhook.imported.ad;

/**
 * Maps the Monday-first native UI to Yulong's original Calendar.DAY_OF_WEEK - 1
 * storage format: Sunday=0, Monday=1, ..., Saturday=6.
 */
public final class FxYulongScheduleDayMapping {
    private FxYulongScheduleDayMapping() { }

    public static int workerDayForUiIndex(int mondayFirstIndex) {
        if (mondayFirstIndex < 0 || mondayFirstIndex > 6) {
            throw new IllegalArgumentException("weekday index must be 0..6");
        }
        return (mondayFirstIndex + 1) % 7;
    }

    public static boolean isUiDaySelected(String storedDays, int mondayFirstIndex) {
        int workerDay = workerDayForUiIndex(mondayFirstIndex);
        if (storedDays == null || storedDays.isEmpty()) return false;
        String[] values = storedDays.split(",", -1);
        for (String value : values) {
            if (value.trim().equals(String.valueOf(workerDay))) return true;
        }
        return false;
    }

    public static String defaultWeekCsv() {
        return "1,2,3,4,5,6,0";
    }
}
