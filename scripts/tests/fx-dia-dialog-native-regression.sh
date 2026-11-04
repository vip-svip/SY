#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
UI="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDialogMatchPolicy.java"
TEST="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaDialogMatchPolicyTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$TEST"; do [ -s "$f" ] || fail "missing Dialog source: $f"; done
python3 - "$HOOK" "$PARSER" "$SER" "$UI" "$POLICY" "$TEST" <<'PY'
from pathlib import Path
import re, sys
hook, parser, ser, ui, policy, test = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
imports = re.findall(r"^import de\\.privacyguard\\.adhook\\.imported\\.dia\\.FxDiaDialogMatchPolicy;$", hook, re.M)
assert len(imports) == 1, f"Dialog policy import count must be one, got {len(imports)}"
assert 'Dialog.class.getDeclaredMethod("show")' in hook
assert "dialogRulesFor(dialogPackage)" in hook
assert "dialog pre-display match failed open" in hook
assert "new int[]{512}" in hook and "depth > 16" in hook
assert "dialogNotifyLastShown.put(packageName, now)" in hook
assert "dialogMatchEnabled" in parser and "dialog_text_terms_b64" in parser and "dialog_id_terms_b64" in parser
assert "dialogMatchEnabled" in ser and "dialog rules/feedback require dialogMatchEnabled" in ser
assert "showDiaDialogTarget" in ui and "保存并发布 Dialog 规则" in ui
assert "parseTerms" in policy and "MAX_TERMS = 32" in policy and "MAX_RAW_UTF8_BYTES = 1024" in policy
assert "matchesResourceIdExactly" in test and "rejectsRawRuleTextOverOneKiB" in test
print("PASS: Dialog UI/config/runtime contracts, bounded matcher, fail-open, throttled feedback and single import")
PY
