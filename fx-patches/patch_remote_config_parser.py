#!/usr/bin/env python3
"""Apply a narrowly scoped compatibility repair to the FX 1.0.0 release source."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
generator = root / "scripts/gen_xposed_conf.sh"
regression = root / "scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh"

if not generator.is_file() or not regression.is_file():
    raise SystemExit("FX Remote Files generator/regression test not found")

src = generator.read_text(encoding="utf-8")
old_condition = 'if (!valid || (clipboard && clipboard_isolate) || (!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence+dev_enabled+dev_rule_count) && rules == "")) next'
new_condition = '''# Developer-defined method hooks are not implemented by the current Android
          # UnifiedHookConfigParser. Do not let unsupported keys invalidate the
          # complete Remote Files payload; omit targets that only request them.
          if (!valid || (clipboard && clipboard_isolate) || (!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence) && rules == "")) next'''
old_emit = '''          printf ",dev_hook_enabled=%s", dev_enabled
          if (dev_rules != "") printf "%s", dev_rules
'''
if src.count(old_condition) != 1 or src.count(old_emit) != 1:
    raise SystemExit("generator source no longer matches the reviewed patch context; refusing to patch")
src = src.replace(old_condition, new_condition, 1).replace(old_emit, "", 1)
generator.write_text(src, encoding="utf-8")

test = regression.read_text(encoding="utf-8")
needle = "done\n# Member diagnostics alone must publish even with the ad-filtering master off.\n"
addition = r'''done
# Verify the published payload against the exact Java parser shipped in FXAdHook.
OUT="$TMP/lspd/modules/0/de.privacyguard.adhook/files/fx-hook-targets.conf"
if grep -Eq '(^|,)dev_hook_enabled=|(^|,)dev_rule_[0-9]+=' "$OUT"; then
  fail "unsupported developer-hook fields leaked into the runtime schema"
fi
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  cat > "$TMP/RemoteConfigParseCheck.java" <<'JAVA'
package de.privacyguard.adhook;
import java.nio.file.Files;
import java.nio.file.Path;
public final class RemoteConfigParseCheck {
  public static void main(String[] args) throws Exception {
    UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(Files.readString(Path.of(args[0])));
    if (!result.adsEnabled || result.targets.size() != 8 || !result.isMemberDiagnosticsEnabledFor("com.example.app") || !result.targets.get("com.privacy.app").privacy) {
      throw new AssertionError("generated Remote Files payload lost supported targets");
    }
  }
}
JAVA
  javac -d "$TMP/parser-classes" \
    "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java" \
    "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/SensorPrivacyPolicy.java" \
    "$TMP/RemoteConfigParseCheck.java" || fail "runtime parser test compilation failed"
  java -cp "$TMP/parser-classes" de.privacyguard.adhook.RemoteConfigParseCheck "$OUT" || fail "runtime parser rejected generated Remote Files config"
else
  fail "javac/java required to verify Remote Files runtime parser compatibility"
fi
# Member diagnostics alone must publish even with the ad-filtering master off.
'''
if test.count(needle) != 1:
    raise SystemExit("regression test no longer matches the reviewed insertion point; refusing to patch")
regression.write_text(test.replace(needle, addition, 1), encoding="utf-8")
print("Applied Remote Files parser compatibility repair and regression assertion.")
