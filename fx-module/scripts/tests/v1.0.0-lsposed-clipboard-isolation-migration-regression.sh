#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
GEN="$ROOT/scripts/gen_xposed_conf.sh"
UI="$ROOT/webroot/index.html"
MATRIX="$ROOT/docs/FXHOOK-MIGRATION-MATRIX.md"
for f in "$PARSER" "$SER" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/SensorPrivacyPolicy.java" "$HOOK" "$GEN" "$UI" "$MATRIX"; do [ -s "$f" ] || { echo "FAIL missing $f" >&2; exit 1; }; done
grep -q 'clipboard_isolate_enabled' "$PARSER"
grep -q 'clipboard_isolate_enabled' "$SER"
grep -q 'clipboardIsolate' "$PARSER"
grep -q 'clipboard_isolate' "$GEN"
grep -q 'clipboard_isolate_enabled' "$GEN"
grep -q 'clipboard_isolate' "$ROOT/scripts/apply.sh"
grep -q 'hook_clipboard_isolate_targets' "$ROOT/scripts/status.sh"
grep -q 'clipboard_isolate=' "$GEN"
grep -q 'clipboard_isolate' "$UI"
grep -Fq '启用进程级剪贴板隔离' "$UI"
grep -Fq '不提供系统级跨 APP 隔离' "$UI"
! grep -Fq '不同 APP 剪贴板互相不可见' "$UI"
grep -q 'setPrimaryClip' "$HOOK"
grep -q 'getPrimaryClip' "$HOOK"
grep -q 'hasPrimaryClip' "$HOOK"
grep -q 'processPackages.size() > 1' "$HOOK"
grep -q 'clipboardReadBlock && clipboardIsolate' "$PARSER"
grep -q '不是 OS 级跨应用隔离' "$MATRIX"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
javac -d "$tmp" "$PARSER" "$SER" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/SensorPrivacyPolicy.java"
cat > "$tmp/ClipboardConfigCheck.java" <<'JAVA'
package de.privacyguard.adhook;
import java.util.*;
public class ClipboardConfigCheck {
  public static void main(String[] args) {
    UnifiedHookConfigParser.Result disabled = UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=0\nprivacy_enabled=1\nclipboard_isolate_enabled=0\n[list:targets]\ncom.example.app,clipboard_isolate=1\n");
    if (disabled.isClipboardIsolatedFor("com.example.app")) throw new AssertionError("master-off must disable isolation");
    UnifiedHookConfigParser.Result enabled = UnifiedHookConfigConfig();
    if (!enabled.isClipboardIsolatedFor("com.example.app")) throw new AssertionError("master+target should enable isolation");
    java.util.Map<String, UnifiedHookConfigParser.Target> map = new java.util.HashMap<>(enabled.targets);
    String encoded = UnifiedHookConfigSerializer.serialize(false, true, false, false, false, true, map);
    UnifiedHookConfigParser.Result roundTrip = UnifiedHookConfigParser.parse(encoded);
    if (!roundTrip.isClipboardIsolatedFor("com.example.app")) throw new AssertionError("serializer round-trip lost clipboard isolation");
    System.out.println("clipboard config round-trip passed");
  }
  static UnifiedHookConfigParser.Result UnifiedHookConfigConfig() {
    String cfg = "schema_version=1\nads_enabled=0\nprivacy_enabled=1\nclipboard_isolate_enabled=1\n[list:targets]\ncom.example.app,clipboard_isolate=1\n";
    return UnifiedHookConfigParser.parse(cfg);
  }
}
JAVA
javac -cp "$tmp" -d "$tmp" "$tmp/ClipboardConfigCheck.java"
java -cp "$tmp" de.privacyguard.adhook.ClipboardConfigCheck
echo "PASS: clipboard isolation has distinct master/per-target config, process-local write/read shadow hooks, shared-process fail-open and mutual-exclusion validation"
