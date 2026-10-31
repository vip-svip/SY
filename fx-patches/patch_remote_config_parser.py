#!/usr/bin/env python3
"""Apply a narrowly scoped compatibility repair to the FX 1.0.0 release source."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
generator = root / "scripts/gen_xposed_conf.sh"
regression = root / "scripts/tests/v1.0.0-lsposed-remote-file-config-regression.sh"

if not generator.is_file():
    raise SystemExit("FX Remote Files generator not found")
if not regression.is_file():
    print("Optional legacy Remote Files shell regression is absent from this release archive; APP parser and static migration checks remain authoritative.")

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

if regression.is_file():
    test = regression.read_text(encoding="utf-8")
    needle = "done\n# Member diagnostics alone must publish even with the ad-filtering master off.\n"
    addition = r'''done
# Verify unsupported legacy developer-hook fields do not leak into API-101 schema.
OUT="$TMP/lspd/modules/0/de.privacyguard.adhook/files/fx-hook-targets.conf"
if grep -Eq '(^|,)dev_hook_enabled=|(^|,)dev_rule_[0-9]+=' "$OUT"; then
  fail "unsupported developer-hook fields leaked into the runtime schema"
fi
grep -q '^schema_version=1$' "$OUT" || fail "Remote Files schema version missing"
grep -q '^ads_enabled=1$' "$OUT" || fail "automatic Ad master missing"
grep -q '^\[list:targets\]$' "$OUT" || fail "Remote Files target section missing"
# Member diagnostics alone must publish even with the ad-filtering master off.
'''
    if test.count(needle) != 1:
        raise SystemExit("regression test no longer matches the reviewed insertion point; refusing to patch")
    regression.write_text(test.replace(needle, addition, 1), encoding="utf-8")

print("Applied Remote Files parser compatibility repair and regression assertion.")
