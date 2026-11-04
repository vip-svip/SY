import de.privacyguard.adhook.imported.dia.FxDiaCrashRecord;
import de.privacyguard.adhook.imported.dia.FxDiaCrashExportFormatter;

public final class DiaCrashExportFormatterHostTest {
    public static void main(String[] args) {
        String stack = "Authorization: Bearer stack-header-secret\n"
                + "request https://user:pass@example.test/path?api_key=query-stack-secret\n"
                + "token=plain-stack-secret\n"
                + "-----BEGIN PRIVATE KEY-----\nprivate-key-material\n-----END PRIVATE KEY-----";
        FxDiaCrashRecord record = new FxDiaCrashRecord(1L, 2L, "fx", "main", "device",
                "IllegalStateException: password=message-secret", stack);
        String hex = FxDiaCrashExportFormatter.format(record, true);
        String raw = FxDiaCrashExportFormatter.format(record, false);
        for (String secret : new String[]{"stack-header-secret", "user:pass", "query-stack-secret",
                "plain-stack-secret", "private-key-material", "message-secret"}) {
            if (hex.contains(FxDiaCrashRecord.hexUtf8(secret)) || raw.contains(secret)) {
                throw new AssertionError("crash export leaked secret: " + secret);
            }
        }
        if (!hex.contains("堆栈（HEX 编码；可逆，不是加密）:")) {
            throw new AssertionError("HEX export label missing");
        }
        if (!hex.contains(FxDiaCrashRecord.hexUtf8("[REDACTED_PRIVATE_KEY]"))) {
            throw new AssertionError("PEM private key block was not redacted before HEX encoding");
        }
        System.out.println("PASS: crash export redacts secrets before optional reversible HEX encoding");
    }
}
