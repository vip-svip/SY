package de.privacyguard.adhook.imported.dia;

/** Formats explicit copy/share payloads; redact raw text before optional HEX encoding. */
public final class FxDiaCrashExportFormatter {
    private static final String RAW_STACK_MARKER = "堆栈:\n";
    private static final String HEX_STACK_MARKER = "堆栈（HEX 编码；可逆，不是加密）:\n";

    private FxDiaCrashExportFormatter() { }

    public static String format(FxDiaCrashRecord record, boolean hexEncodeStack) {
        if (record == null) return "";
        String redacted = FxDiaCrashRedactor.redact(record.format(false));
        if (!hexEncodeStack) return redacted;
        int marker = redacted.indexOf(RAW_STACK_MARKER);
        if (marker < 0) return redacted;
        int stackStart = marker + RAW_STACK_MARKER.length();
        String safeStack = redacted.substring(stackStart);
        return redacted.substring(0, marker) + HEX_STACK_MARKER
                + FxDiaCrashRecord.hexUtf8(safeStack);
    }
}
