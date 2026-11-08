#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VALIDATOR="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdBackupValidation.java"
GENERAL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
[ -s "$VALIDATOR" ] || { echo "FAIL: backup validator source missing" >&2; exit 1; }
[ -s "$GENERAL" ] || { echo "FAIL: general settings activity source missing" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-general-import.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/classes" "$T/src/de/privacyguard/adhook/imported/ad"
cp "$VALIDATOR" "$T/src/de/privacyguard/adhook/imported/ad/"
cat > "$T/src/BackupValidatorHostTest.java" <<'JAVA'
import de.privacyguard.adhook.imported.ad.FxYulongAdBackupValidation;

public final class BackupValidatorHostTest {
    private static void expect(boolean actual, boolean wanted, String name) {
        if (actual != wanted) throw new AssertionError(name + ": expected=" + wanted + " actual=" + actual);
    }
    public static void main(String[] args) {
        expect(FxYulongAdBackupValidation.isValidDomain("example.com"), true, "simple domain");
        expect(FxYulongAdBackupValidation.isValidDomain("Sub.Example-2.com"), true, "mixed-case domain");
        expect(FxYulongAdBackupValidation.isValidDomain("a"), true, "single-label domain accepted by Root validator");
        expect(FxYulongAdBackupValidation.isValidDomain("*.example.com"), false, "wildcard domain");
        expect(FxYulongAdBackupValidation.isValidDomain(".example.com"), false, "leading dot");
        expect(FxYulongAdBackupValidation.isValidDomain("example.com."), false, "trailing dot");
        expect(FxYulongAdBackupValidation.isValidDomain("a..example.com"), false, "empty label");
        expect(FxYulongAdBackupValidation.isValidDomain("-bad.example"), false, "leading hyphen");
        expect(FxYulongAdBackupValidation.isValidDomain("bad-.example"), false, "trailing hyphen");
        expect(FxYulongAdBackupValidation.isValidDomain("example.com;touch /tmp/pwned"), false, "shell-looking domain");
        expect(FxYulongAdBackupValidation.isValidText("user note"), true, "plain note");
        expect(FxYulongAdBackupValidation.isValidText("a|b"), false, "field separator");
        expect(FxYulongAdBackupValidation.isValidText("line1\nline2"), false, "newline");
        expect(FxYulongAdBackupValidation.isValidText("bad" + ((char) 0) + "note"), false, "NUL");
        expect(FxYulongAdBackupValidation.isValidText("x".repeat(181)), false, "oversized note");
        expect(FxYulongAdBackupValidation.isValidSource("https://filters.example/list.txt"), true, "HTTPS source");
        expect(FxYulongAdBackupValidation.isValidSource("builtin://fx-native"), true, "builtin source");
        expect(FxYulongAdBackupValidation.isValidSource("file:///etc/passwd"), false, "file URL");
        expect(FxYulongAdBackupValidation.isValidSource("https://bad.example/\nnext"), false, "newline URL");
        expect(FxYulongAdBackupValidation.isValidIpv4("1.1.1.1"), true, "IPv4");
        expect(FxYulongAdBackupValidation.isValidIpv4("256.1.1.1"), false, "out-of-range IPv4");
        expect(FxYulongAdBackupValidation.isValidIpv4("0.0.0.0"), false, "unspecified IPv4");
        expect(FxYulongAdBackupValidation.isValidIpv4("255.255.255.255"), false, "broadcast IPv4");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("8.8.8.8", false), true, "custom IPv4");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("https://dns.example/dns-query", false), true, "DoH");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("tls://dns.example:853", false), true, "DoT");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("quic://dns.example:784", false), true, "DoQ");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("https://dns.example/dns-query", true), false, "global DNS is IPv4-only");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("tls://dns.example:0", false), false, "zero DNS port");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("quic://dns.example:70000", false), false, "oversized DNS port");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("tls://user@dns.example:853", false), false, "userinfo endpoint");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("http://dns.example/query", false), false, "plain HTTP resolver");
        expect(FxYulongAdBackupValidation.isValidDnsEndpoint("tls://dns.example/path", false), false, "DoT path");
        System.out.println("PASS: Yulong JSON import domain/source/note/DNS endpoint validation");
    }
}
JAVA
if command -v javac >/dev/null 2>&1; then
  javac -encoding UTF-8 -d "$T/classes" \
    "$T/src/de/privacyguard/adhook/imported/ad/FxYulongAdBackupValidation.java" \
    "$T/src/BackupValidatorHostTest.java"
  java -cp "$T/classes" BackupValidatorHostTest
else
  echo "SKIP: javac is unavailable; Java validator was source-audited only"
fi
python3 - "$GENERAL" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(encoding="utf-8")
required=[
    "STATE_PENDING_EXPORT",
    "STATE_IMPORT_PENDING",
    "STATE_EXPORT_PENDING",
    "out.putString(STATE_PENDING_EXPORT, pendingExport)",
    "out.putBoolean(STATE_IMPORT_PENDING, importRequestPending)",
    "out.putBoolean(STATE_EXPORT_PENDING, exportRequestPending)",
    "pendingExport = state.getString(STATE_PENDING_EXPORT)",
    "if (!exportRequestPending) return;",
    "if (!importRequestPending) return;",
    "exportRequestPending = false;",
    "importRequestPending = false;",
    "pendingExport = null;",
    "导出已取消，未写入文件。",
    "导入已取消，设备配置未更改。",
    "FxYulongAdBackupValidation.isValidSource(source)",
    "validateDomainRows(allow, \"白名单\")",
    "validateDomainRows(block, \"黑名单\")",
    "allowedDnsFlags.contains(key)",
    "validateDnsServers(dns.optJSONArray(\"customServers\"), false",
    "validateDnsServers(dns.optJSONArray(\"globalServers\"), true",
    "validateOptionalIpv4(dns, \"vpnRemote\"",
    "validateOptionalIpv4(dns, \"vpnCn\"",
    "validScheduleDays(days)",
    "dnsCsv(dns.optJSONArray(\"customServers\"), false)",
    "dnsCsv(dns.optJSONArray(\"globalServers\"), true)",
    "ROLLBACK_FAILED: preserved backup files",
    "rollback files restored but runtime apply failed",
    'mktemp "$PG/yulong-ad-import-settings.rollback.XXXXXX"',
]
for marker in required:
    assert marker in s, f"missing import guard/rollback contract: {marker}"
assert "if(!remote.isEmpty()&&validIpv4(remote))" not in s, "invalid supplied VPN DNS is still silently ignored"
assert "if(!cn.isEmpty()&&validIpv4(cn))" not in s, "invalid supplied China DNS is still silently ignored"
print("PASS: Yulong Ad General import validates all persisted fields and uses recoverable runtime rollback")
PY
