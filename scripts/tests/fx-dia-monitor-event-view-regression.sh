#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventParser.java"
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventParserTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ACTIVITY" ] && [ -s "$PARSER" ] && [ -s "$UNIT" ] || fail "Dia monitor-event sources missing"
grep -Fq 'button("查看结构化监控事件", () -> showMonitorEvents())' "$ACTIVITY" || fail "Frida screen has no native monitor-event browser"
grep -Fq 'tail -n 800' "$ACTIVITY" || fail "monitor-event reader is not bounded at the source"
grep -Fq 'MAX_EVENTS = 300' "$PARSER" || fail "monitor-event parser has no event-count bound"
grep -Fq 'MAX_LOG_CHARS = 256 * 1024' "$PARSER" || fail "monitor-event parser has no input-size bound"
grep -Fq 'case "SQL":' "$PARSER" || fail "SQL monitor family is not supported"
grep -Fq 'case "HTTP":' "$PARSER" || fail "HTTP monitor family is not supported"
grep -Fq 'case "RUNTIME":' "$PARSER" || fail "Runtime monitor family is not supported"
grep -Fq 'SQL 文本' "$ACTIVITY" || fail "event view does not explain content redaction"
grep -Fq 'private void showMonitorEvents()' "$ACTIVITY" || fail "event filtering UI is missing"
grep -Fq 'matched > shown' "$ACTIVITY" || fail "event view has no render-row cap"
grep -Fq 'private int monitorEventGeneration;' "$ACTIVITY" || fail "event requests have no generation guard"
grep -Fq 'final String requestedPackage = targetPackage;' "$ACTIVITY" || fail "event reader does not snapshot the requested target"
grep -Fq '!requestedPackage.equals(targetPackage)' "$ACTIVITY" || fail "late event results can be shown for a newly selected target"
grep -Fq 'monitorEventGeneration++;' "$ACTIVITY" || fail "target changes and Activity teardown do not invalidate stale event reads"
echo "PASS: Dia monitor-event browser is bounded, filterable and metadata-only"
