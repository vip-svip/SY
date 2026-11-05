#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
PUBLISHER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxHookConfigPublisher.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
LEGACY_PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/HookTargetConfigParser.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
ROOT_ACCESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MAIN" "$PUBLISHER" "$PARSER" "$SERIALIZER" "$LEGACY_PARSER" "$HOOK" "$ROOT_ACCESS"; do
  [ -s "$file" ] || fail "missing Hook config streaming source: $file"
done
python3 - "$MAIN" "$PUBLISHER" "$PARSER" "$LEGACY_PARSER" "$HOOK" <<'PY'
from pathlib import Path
import sys
main, publisher, parser, legacy, hook = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
for token in ("rows.size()>990", "configBytes.length>65536", "managedBytes.length>65536",
              "android.util.Base64.encodeToString(configBytes"):
    assert token not in main, "MainActivity still embeds an old config publication cap: " + token
assert "FxHookConfigPublisher.publish(configBytes, managedBytes, androidUser)" in main
assert "RootAccess.executeWithInput(" in publisher and "new ByteArrayInputStream(payload.bytes)" in publisher
for token in ("sha256sum ", "FX_STAGE_HASH_MISMATCH", "rollback()", "FX_ROLLBACK_FAILED",
              "FX_COMMIT_HASH_MISMATCH_", "cp -p ", "mv -f "):
    assert token in publisher, "publisher missing transaction safety contract: " + token
assert "config exceeds 64 KiB" not in parser and "config exceeds 1000 lines" not in parser
assert "config exceeds 1000 lines" not in legacy
assert "InputStreamReader reader" in hook and "remote config exceeds 64 KiB" not in hook
assert "content.append(chunk, 0, count);" in hook
print("PASS: Hook config is streamed, SHA-256 checked, rollback protected and has no config byte/target/line cap")
assert "MAX_DEVELOPER_RULES_PER_TARGET" not in parser
assert "too many developer rules" not in parser
assert "slot > 64" not in main and "最多 64 条" not in main
assert "for (int slot = 1; slot <= 64; slot++)" not in main
assert "getCustomRuleSlots(selectedPackage)" in main
assert "getCustomRuleSlots(p)" in main
assert '当前匹配：" + shown + " / 64' not in main
print("PASS: Developer Hook rules have no fixed 64-rule parser, serializer or UI cap; sparse preference slots are enumerated dynamically")
PY

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/fake-bin" "$T/classes"
cat > "$T/fake-bin/su" <<'SU'
#!/bin/sh
[ "$1" = "-c" ] || exit 2
exec /bin/sh -c "$2"
SU
cat > "$T/fake-bin/chown" <<'CMD'
#!/bin/sh
exit 0
CMD
cat > "$T/fake-bin/chcon" <<'CMD'
#!/bin/sh
exit 0
CMD
cat > "$T/fake-bin/mv" <<'MV'
#!/bin/sh
for arg do destination="$arg"; done
if [ -n "\${FX_FAIL_TRIGGER_FILE:-}" ] && [ -e "$FX_FAIL_TRIGGER_FILE" ]; then
  case "$destination" in
    */fx-api101-managed.conf)
      /bin/rm -f "$FX_FAIL_TRIGGER_FILE"
      exit 1
      ;;
  esac
fi
exec /bin/mv "$@"
MV
chmod 700 "$T/fake-bin/"*
cat > "$T/HookConfigPublisherHostTest.java" <<'JAVA'
package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

public final class HookConfigPublisherHostTest {
    private static byte[] payload(int length, int seed) {
        byte[] bytes = new byte[length];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) (i * 31 + seed);
        return bytes;
    }
    private static void write(Path path, byte[] data) throws Exception {
        Files.createDirectories(path.getParent());
        Files.write(path, data);
    }
    private static void expect(Path path, byte[] expected) throws Exception {
        byte[] actual = Files.readAllBytes(path);
        if (!Arrays.equals(expected, actual)) throw new AssertionError("payload mismatch at " + path);
    }
    private static void noTransientFiles(FxHookConfigPublisher.Layout layout) throws Exception {
        for (String path : new String[]{layout.remotePath(), layout.nativePath(), layout.managedPath()}) {
            Path parent = Paths.get(path).getParent();
            try (java.util.stream.Stream<Path> entries = Files.list(parent)) {
                if (entries.anyMatch(entry -> entry.getFileName().toString().contains(".fx-stage-")
                        || entry.getFileName().toString().contains(".fx-backup-"))) {
                    throw new AssertionError("temporary or backup file leaked in " + parent);
                }
            }
        }
    }
    public static void main(String[] args) throws Exception {
        Path root = Paths.get(args[0]).toAbsolutePath();
        byte[] config = payload(256 * 1024, 7);
        byte[] managed = payload(96 * 1024, 19);
        FxHookConfigPublisher.Layout success = new FxHookConfigPublisher.Layout(
                root.resolve("success/data").toString(), 0);
        write(Paths.get(success.remotePath()), "old remote".getBytes(StandardCharsets.UTF_8));
        write(Paths.get(success.nativePath()), "old overlay".getBytes(StandardCharsets.UTF_8));
        write(Paths.get(success.managedPath()), "old ownership".getBytes(StandardCharsets.UTF_8));
        RootAccess.Result committed = FxHookConfigPublisher.publish(config, managed, success);
        if (committed.exitCode != 0 || committed.output == null
                || !committed.output.contains("SHA256=")
                || !committed.output.contains("API101_OVERLAY_SHA256=")
                || !committed.output.contains("API101_OWNERSHIP_SHA256=")) {
            throw new AssertionError("large config publish failed: " + committed.exitCode + " " + committed.output);
        }
        expect(Paths.get(success.remotePath()), config);
        expect(Paths.get(success.nativePath()), config);
        expect(Paths.get(success.managedPath()), managed);
        noTransientFiles(success);

        FxHookConfigPublisher.Layout rollback = new FxHookConfigPublisher.Layout(
                root.resolve("rollback/data").toString(), 0);
        byte[] oldRemote = "preserve old remote".getBytes(StandardCharsets.UTF_8);
        byte[] oldNative = "preserve old native".getBytes(StandardCharsets.UTF_8);
        byte[] oldManaged = "preserve old managed".getBytes(StandardCharsets.UTF_8);
        write(Paths.get(rollback.remotePath()), oldRemote);
        write(Paths.get(rollback.nativePath()), oldNative);
        write(Paths.get(rollback.managedPath()), oldManaged);
        String trigger = System.getenv("FX_FAIL_TRIGGER_FILE");
        if (trigger == null || trigger.isEmpty()) throw new AssertionError("missing injected failure trigger");
        Files.write(Paths.get(trigger), new byte[]{1});
        RootAccess.Result failed = FxHookConfigPublisher.publish(config, managed, rollback);
        if (failed.exitCode == 0 || failed.output == null
                || !failed.output.contains("FX_COMMIT_FAILED_MANAGED")) {
            throw new AssertionError("injected rename failure not reported: " + failed.exitCode + " " + failed.output);
        }
        expect(Paths.get(rollback.remotePath()), oldRemote);
        expect(Paths.get(rollback.nativePath()), oldNative);
        expect(Paths.get(rollback.managedPath()), oldManaged);
        noTransientFiles(rollback);
        System.out.println("PASS: 256 KiB config and 96 KiB ownership streams; injected third-file rename failure restores all prior files");
    }
}
JAVA
command -v javac >/dev/null 2>&1 || fail "javac is required"
command -v java >/dev/null 2>&1 || fail "java is required"
javac -d "$T/classes" "$ROOT_ACCESS" "$PUBLISHER" "$T/HookConfigPublisherHostTest.java"
PATH="$T/fake-bin:$PATH" FX_FAIL_TRIGGER_FILE="$T/fail-managed-move" \
  java -cp "$T/classes" de.privacyguard.adhook.HookConfigPublisherHostTest "$T"

mkdir -p "$T/parser-classes"
cat > "$T/HookConfigParserHostTest.java" <<'JAVA'
package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;

public final class HookConfigParserHostTest {
    public static void main(String[] args) {
        StringBuilder modern = new StringBuilder(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n");
        for (int i = 0; i < 2500; i++) {
            modern.append("com.example.target").append(i).append(",privacy=1\n");
        }
        String modernText = modern.toString();
        if (modernText.getBytes(StandardCharsets.UTF_8).length <= 65536
                || modernText.split("\\R", -1).length <= 1000) {
            throw new AssertionError("modern stress fixture did not exceed former byte/line thresholds");
        }
        UnifiedHookConfigParser.Result parsedModern = UnifiedHookConfigParser.parse(modernText);
        if (parsedModern.targets.size() != 2500
                || !parsedModern.isPrivacyEnabledFor("com.example.target2499")) {
            throw new AssertionError("versioned parser dropped large target sets");
        }

        StringBuilder legacy = new StringBuilder("hook_ads_enabled=1\n[list:hook_targets]\n");
        for (int i = 0; i < 2500; i++) {
            legacy.append("com.example.legacytarget").append(i)
                    .append(",splash=1 | retained metadata ").append(i).append("\n");
        }
        String legacyText = legacy.toString();
        if (legacyText.getBytes(StandardCharsets.UTF_8).length <= 65536
                || legacyText.split("\\R", -1).length <= 1000) {
            throw new AssertionError("legacy stress fixture did not exceed former byte/line thresholds");
        }
        UnifiedHookConfigParser.Result parsedLegacy = UnifiedHookConfigParser.parse(legacyText);
        HookTargetConfigParser.Result parsedLegacyAd = HookTargetConfigParser.parse(legacyText);
        if (parsedLegacy.targets.size() != 2500
                || !parsedLegacy.targets.get("com.example.legacytarget2499").splash
                || parsedLegacyAd.targets.size() != 2500
                || !parsedLegacyAd.targets.get("com.example.legacytarget2499").splash
                || parsedLegacy.privacyEnabled) {
            throw new AssertionError("legacy parser did not preserve large target sets or privacy isolation");
        }
        StringBuilder developerRules = new StringBuilder(
                "schema_version=1\\nads_enabled=0\\nprivacy_enabled=0\\n[list:targets]\\n"
                        + "com.example.vpn,dev_hook_enabled=1");
        for (int i = 1; i <= 96; i++) {
            developerRules.append(",dev_rule_").append(i).append("=rule").append(i)
                    .append("|com.example.vpn.Rule").append(i)
                    .append("#isEnabled()Z|OBSERVE|").append(i);
        }
        developerRules.append('\\n');
        UnifiedHookConfigParser.Result parsedRules =
                UnifiedHookConfigParser.parse(developerRules.toString());
        if (parsedRules.targets.get("com.example.vpn").developerRules.size() != 96) {
            throw new AssertionError("parser capped Developer Hook rules below 96");
        }
        String serializedRules = UnifiedHookConfigSerializer.serialize(false, false, parsedRules.targets);
        if (!serializedRules.contains("dev_rule_b64_96=")
                || UnifiedHookConfigParser.parse(serializedRules)
                        .targets.get("com.example.vpn").developerRules.size() != 96) {
            throw new AssertionError("serializer/parser failed the 96-rule round trip");
        }
        System.out.println("PASS: Developer Hook parser and serializer round-trip 96 rules for one target");
        StringBuilder developerRules = new StringBuilder(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n"
                        + "com.example.owned,dev_hook_enabled=1");
        for (int i = 1; i <= 96; i++) {
            developerRules.append(",dev_rule_").append(i).append("=rule").append(i)
                    .append("|com.example.owned.Rule").append(i).append("#isEnabled()Z|OBSERVE|").append(i);
        }
        UnifiedHookConfigParser.Result parsedDeveloperRules =
                UnifiedHookConfigParser.parse(developerRules.toString());
        if (parsedDeveloperRules.targets.get("com.example.owned").developerRules.size() != 96) {
            throw new AssertionError("parser still caps Developer Hook rules at 64");
        }
        String serializedDeveloperRules = UnifiedHookConfigSerializer.serialize(
                false, false, parsedDeveloperRules.targets);
        UnifiedHookConfigParser.Result roundTripDeveloperRules =
                UnifiedHookConfigParser.parse(serializedDeveloperRules);
        if (roundTripDeveloperRules.targets.get("com.example.owned").developerRules.size() != 96
                || !serializedDeveloperRules.contains("dev_rule_b64_96=")) {
            throw new AssertionError("serializer did not preserve more than 64 Developer Hook rules");
        }
        System.out.println("PASS: Developer Hook parser and serializer round-trip 96 rules per target");
        System.out.println("PASS: both current and legacy parsers accept 2,500 targets above 64 KiB and 1,000 lines");
    }
}
JAVA
javac -d "$T/parser-classes" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperExecutableDescriptor.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/SensorPrivacyPolicy.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaKeyGesturePolicy.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDialogMatchPolicy.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/HookTargetConfigParser.java" \
  "$T/HookConfigParserHostTest.java"
java -cp "$T/parser-classes" de.privacyguard.adhook.HookConfigParserHostTest
