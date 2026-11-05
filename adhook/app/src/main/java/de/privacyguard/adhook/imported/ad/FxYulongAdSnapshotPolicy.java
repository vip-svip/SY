package de.privacyguard.adhook.imported.ad;

/** Strict, Android-free parser for the FX Yulong Ad control snapshot master state. */
public final class FxYulongAdSnapshotPolicy {
    private static final String HEADER = "FXYULONGAD1";

    private FxYulongAdSnapshotPolicy() { }

    /**
     * Returns true/false only for a complete, unambiguous master-state record.
     * Null means absent, wrong-protocol, duplicate, or malformed state; callers
     * must not infer that the filter is either enabled or disabled.
     */
    public static Boolean parseAdMasterEnabled(String raw) {
        if (raw == null) return null;
        String[] lines = raw.split("\\r?\\n", -1);
        boolean sawHeader = false;
        boolean sawMaster = false;
        Boolean enabled = null;
        for (String line : lines) {
            if (line.isEmpty()) continue;
            if (!sawHeader) {
                if (!HEADER.equals(line)) return null;
                sawHeader = true;
                continue;
            }
            if (HEADER.equals(line)) return null;
            String[] fields = line.split("\\|", -1);
            if (!"AD_MASTER".equals(fields[0])) continue;
            if (sawMaster || fields.length != 2
                    || !("0".equals(fields[1]) || "1".equals(fields[1]))) {
                return null;
            }
            enabled = "1".equals(fields[1]);
            sawMaster = true;
        }
        return sawHeader && sawMaster ? enabled : null;
    }
}
