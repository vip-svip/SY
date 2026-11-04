package de.privacyguard.adhook.imported.dia;

import org.junit.Test;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxDiaCrashRecordTest {
    @Test public void hexEncodingIsByteAccurateAndReversible() {
        assertEquals("41e4b8ad", FxDiaCrashRecord.hexUtf8("A中"));
    }

    @Test public void rawAndHexReportsAreDistinctAndClearlyLabeled() {
        FxDiaCrashRecord record = new FxDiaCrashRecord(
                1000L, 12L, "fx:remote", "main", "Acme Test / Android 14",
                "IllegalStateException: boom", "stack line one\nline two");
        String raw = record.format(false);
        String hex = record.format(true);
        assertTrue(raw.contains("stack line one\nline two"));
        assertTrue(hex.contains("HEX 编码；可逆，不是加密"));
        assertTrue(hex.contains("737461636b206c696e65206f6e65"));
        assertFalse(hex.contains("stack line one\nline two"));
    }

    @Test public void nativeCrashCallbackDataIsIncludedInExistingReport() {
        FxDiaCrashRecord record = new FxDiaCrashRecord(
                1000L, 7L, "fx", "RenderThread", "Device",
                "Native / Breakpad 崩溃\nMinidump: private/minidump.dmp",
                "Native thread trace:\nlibnative.so!crash\nJVM thread snapshot:\nstack frame");
        String raw = record.format(false);
        assertTrue(raw.contains("Native / Breakpad 崩溃"));
        assertTrue(raw.contains("private/minidump.dmp"));
        assertTrue(raw.contains("libnative.so!crash"));
        assertTrue(raw.contains("stack frame"));
    }

    @Test public void recordFieldsAreBounded() {
        String huge = "x".repeat(FxDiaCrashRecord.MAX_STACK_CHARS + 100);
        FxDiaCrashRecord record = new FxDiaCrashRecord(1L, 1L, huge, huge, huge, huge, huge);
        assertTrue(record.processName.length() <= 512 + 20);
        assertTrue(record.threadName.length() <= 256 + 20);
        assertTrue(record.deviceInfo.length() <= 1024 + 20);
        assertTrue(record.message.length() <= 8192 + 20);
        assertTrue(record.stack.length() <= FxDiaCrashRecord.MAX_STACK_CHARS);
    }

    @Test public void copyShareRedactionCoversHeadersJsonQueryUrlAndJwt() {
        String input = "Authorization: Bearer header-secret\n"
                + "\"access_token\": \"json-secret\", refresh_token=refresh-secret\n"
                + "https://user:pass@example.test/path?api_key=query-secret\n"
                + "cookie: session-cookie\n"
                + "Bearer loose-secret "
                + "eyJabcdefghijk.abcdefghijk.abcdefghijk";
        String redacted = FxDiaCrashRedactor.redact(input);
        assertFalse(redacted.contains("header-secret"));
        assertFalse(redacted.contains("json-secret"));
        assertFalse(redacted.contains("refresh-secret"));
        assertFalse(redacted.contains("user:pass@"));
        assertFalse(redacted.contains("query-secret"));
        assertFalse(redacted.contains("session-cookie"));
        assertFalse(redacted.contains("loose-secret"));
        assertFalse(redacted.contains("eyJabcdefghijk."));
        assertTrue(redacted.contains("[REDACTED]"));
        assertTrue(redacted.contains("[REDACTED_JWT]"));
    }

    @Test public void redactionLeavesOrdinaryDiagnosticTextAlone() {
        String input = "IllegalStateException: app database is closed\n"
                + "at de.privacyguard.MainActivity.onCreate(MainActivity.java:42)";
        assertEquals(input, FxDiaCrashRedactor.redact(input));
    }
}
