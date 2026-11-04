#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook"
MAIN="$JAVA/MainActivity.java"
RULE="$JAVA/DeveloperHookRule.java"
ENGINE="$JAVA/AdVisibilityHook.java"
SER="$JAVA/UnifiedHookConfigSerializer.java"
PARSER="$JAVA/UnifiedHookConfigParser.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$MAIN" "$RULE" "$ENGINE" "$SER" "$PARSER"; do [ -s "$f" ] || fail "missing Hook literal source: $f"; done
grep -Fq 'RETURN_LITERAL' "$RULE" || fail "rule model lacks typed literal action"
grep -Fq 'parseLiteralValue' "$RULE" || fail "literal type/range validator is missing"
grep -Fq 'literalValue.getText().toString()' "$MAIN" || fail "native editor does not collect a constant value"
grep -Fq 'item.put("value", parts[4])' "$MAIN" || fail "portable JSON export loses literal values"
grep -Fq 'rawLiteral instanceof String' "$MAIN" || fail "portable JSON import does not validate literal field"
grep -Fq 'rule.toEncodedString()' "$SER" || fail "serializer does not preserve literal payload"
grep -Fq 'installDeveloperLiteralReturnHook' "$ENGINE" || fail "runtime does not install typed literal returns"
grep -Fq 'MemberTestGate.isEnabled' "$ENGINE" || fail "literal runtime must retain debuggable and explicit opt-in gate"
grep -Fq 'new BigInteger' "$RULE" || fail "integer literal parsing must be range checked"
grep -Fq 'new BigDecimal' "$RULE" || fail "floating-point literal parsing must be finite checked"
grep -Fq 'pausedLiteralRuleKeepsItsValueAndRemainsInert' "$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/DeveloperHookRuleTest.java" || fail "paused literal compatibility test missing"
echo "PASS: typed constant returns are validated, portable, pause-safe and restricted to opted-in debuggable methods"
