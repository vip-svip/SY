#!/usr/bin/env python3
"""Remove the obsolete WebUI LSPosed manager; native FX Hook tab is authoritative."""
from pathlib import Path
import re
import sys

if len(sys.argv) not in (2, 3):
    raise SystemExit("usage: retire_webui_legacy_hook.py <webroot-index.html> [module-root]")

target = Path(sys.argv[1])
if not target.is_file():
    raise SystemExit(f"WebUI file not found: {target}")
html = target.read_text(encoding="utf-8")


def remove_div_by_id(source: str, element_id: str) -> str:
    pattern = re.compile(
        r"""<div\b(?=[^>]*\bid=["']""" + re.escape(element_id)
        + r"""["'])[^>]*>""",
        re.IGNORECASE,
    )
    matches = list(pattern.finditer(source))
    if not matches:
        # Release WebUI may already have retired this legacy entry. Treat the
        # absent element as the desired state, but reject a same-ID non-div.
        if re.search(r"""\bid=["']""" + re.escape(element_id) + r"""["']""", source, re.I):
            raise SystemExit(f"legacy id {element_id} exists on an unexpected element")
        return source
    if len(matches) != 1:
        raise SystemExit(
            f"expected at most one <div id={element_id}>, found {len(matches)}"
        )
    start = matches[0].start()
    depth = 0
    token_pattern = re.compile(r"</?div\b[^>]*>", re.IGNORECASE)
    for token in token_pattern.finditer(source, start):
        if token.group(0).lower().startswith("</"):
            depth -= 1
        else:
            depth += 1
        if depth == 0:
            return source[:start] + source[token.end():]
    raise SystemExit(f"unbalanced <div id={element_id}>")


def remove_script_by_id(source: str, element_id: str) -> str:
    pattern = re.compile(
        r"""<script\b(?=[^>]*\bid=["']""" + re.escape(element_id)
        + r"""["'])[^>]*>.*?</script\s*>""",
        re.IGNORECASE | re.DOTALL,
    )
    result, count = pattern.subn("", source)
    if count == 0:
        # Already retired in a previously published APK/WebUI.
        if re.search(r"""\bid=["']""" + re.escape(element_id) + r"""["']""", source, re.I):
            raise SystemExit(f"legacy id {element_id} exists outside a script element")
        return source
    if count != 1:
        raise SystemExit(
            f"expected at most one <script id={element_id}>, found {count}"
        )
    return result


# This old controller writes a legacy schema that diverged from the native
# API-101 publisher. Retire it to avoid two competing LSPosed configuration
# surfaces. Keep the separate UID network-blocking card (#cardHook) intact.
html = remove_div_by_id(html, "cardFxAdHook")
html = remove_div_by_id(html, "fxHookDialog")
html = remove_script_by_id(html, "fx-lsposed-ad-hook-controller")

for obsolete in (
    'id="cardFxAdHook"',
    "id='cardFxAdHook'",
    'id="fxHookDialog"',
    "id='fxHookDialog'",
    'id="fx-lsposed-ad-hook-controller"',
    "id='fx-lsposed-ad-hook-controller'",
    'id="fxHookManage"',
    'id="fxHookSave"',
    'id="fxHookMaster"',
):
    if obsolete in html:
        raise SystemExit(f"obsolete WebUI Hook entry remains: {obsolete}")

if 'id="cardHook"' not in html and "id='cardHook'" not in html:
    raise SystemExit("separate UID network-blocking Hook card was unexpectedly removed")
if 'id="pageScript"' not in html or 'id="pageMore"' not in html:
    raise SystemExit("required WebUI pages missing after legacy Hook retirement")

target.write_text(html, encoding="utf-8")

# Migrate regression coverage from the retired WebUI controller to the native APK.
module_root = Path(sys.argv[2]) if len(sys.argv) == 3 else target.parent.parent
repo_root = Path(__file__).resolve().parent.parent
native_ui = repo_root / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
if not native_ui.is_file():
    raise SystemExit("native FX Hook UI source missing: " + str(native_ui))
tests = module_root / "scripts/tests"

def migrate_test(name, replacements):
    path = tests / name
    if not path.is_file():
        raise SystemExit("required Hook regression missing: " + str(path))
    source = path.read_text(encoding="utf-8")
    changed = False
    for old, new in replacements:
        old = old.rstrip()
        if new in source:
            continue
        count = source.count(old)
        if count == 0 and 'UI="$ROOT/webroot/index.html"' not in source and '"$UI"' not in source:
            # Backend-only regression (for example AudioRecord policy) has no
            # WebUI assertions to migrate; preserve its focused coverage.
            continue
        if count != 1:
            raise SystemExit(str(path) + ": expected one legacy assertion, found " + str(count) + ": " + old[:100])
        source = source.replace(old, new, 1)
        changed = True
    if changed:
        path.write_text(source, encoding="utf-8")

native_path = 'UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"'
migrate_test("v1.0.0-lsposed-audiorecord-mic-silence-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    (r'''grep -q "\['mic_silence'" "$UI"''',
     '''grep -Fq 'toggle("录音静音（保留录音流程）", "mic_silence"' "$UI"'''),
])

# The older test omitted its fail() helper even though several assertions call it.
notif_test = tests / "v1.0.0-lsposed-notification-listen-migration-regression.sh"
notif_source = notif_test.read_text(encoding="utf-8")
if "fail(){" not in notif_source:
    notif_source = notif_source.replace("set -eu\n", "set -eu\nfail(){ echo \"FAIL: $*\" >&2; exit 1; }\n", 1)
    notif_test.write_text(notif_source, encoding="utf-8")
migrate_test("v1.0.0-lsposed-notification-listen-migration-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    ('''grep -q 'notification_listen_block' "$UI"''',
     '''grep -Fq 'toggle("阻止通知监听注册", "notification_listen_block"' "$UI"'''),
    ('''grep -q 'notification_permission_hide_block' "$UI" || fail 'notification permission query target must be editable per app' ''',
     '''grep -Fq 'toggle("隐藏通知权限提示", "notification_permission_hide"' "$UI" || fail 'notification permission query target must be editable per app' '''),
])
migrate_test("v1.0.0-lsposed-remote-status-ui-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    ('''grep -q 'notification_permission_hide_enabled' "$UI"''',
     '''grep -q 'hook_native_notification_permission_hide_enabled' "$UI"'''),
    ('''grep -q 'clipboardIsolateEnabled' "$UI"''',
     '''grep -q 'hook_native_clipboard_isolate_enabled' "$UI"'''),
    ('''grep -q 'memberDiagEnabled' "$UI"''',
     '''grep -q 'hook_native_member_diag_enabled' "$UI"'''),
    ('''grep -q '独立于广告总开关' "$UI" || fail "UI does not explain independent member diagnostics scope"''',
     '''grep -q '会员诊断仅记录应用内可观察状态' "$UI" || fail "UI does not explain read-only member diagnostics"'''),
    ('''grep -q 'function refreshRemoteStatus()' "$UI"''',
     '''grep -q 'private void refreshHookRemoteStatus(TextView target)' "$UI"
grep -q 'hook_native_config_found' "$UI" || fail "native status UI does not distinguish missing overlay config"
grep -q 'hook_native_wifi_scan_enabled' "$UI" || fail "native status UI omits Wi-Fi overlay status"'''),
    ('''grep -q '配置发布失败' "$UI"''',
     '''grep -q 'Root 发布失败' "$UI"'''),
    ('''grep -q '仍需在管理器确认模块启用和相同 App 作用域' "$UI"''',
     '''grep -q '目标应用加入作用域' "$UI"'''),
    ('''grep -q '"hook_remote_status":"%s"' "$STATUS" || fail "remote status missing from JSON"''',
     '''grep -q '"hook_remote_status":"%s"' "$STATUS" || fail "remote status missing from JSON"
grep -q '"hook_native_config_found":"%s"' "$STATUS" || fail "native overlay presence missing from JSON"
grep -q '"hook_native_privacy_enabled":"%s"' "$STATUS" || fail "native privacy status missing from JSON"
grep -q '"hook_native_wifi_scan_enabled":"%s"' "$STATUS" || fail "native Wi-Fi status missing from JSON"
grep -q '"hook_native_notification_listen_enabled":"%s"' "$STATUS" || fail "native notification status missing from JSON"
grep -q '"hook_native_notification_permission_hide_enabled":"%s"' "$STATUS" || fail "native notification permission status missing from JSON"
grep -q '"hook_native_clipboard_isolate_enabled":"%s"' "$STATUS" || fail "native clipboard status missing from JSON"
grep -q '"hook_native_member_diag_enabled":"%s"' "$STATUS" || fail "native member diagnostics status missing from JSON"'''),
    ('''echo "PASS: remote publication status, notification permission-query and clipboard-isolation master/target status, and target scope caveat are surfaced truthfully"''',
     '''echo "PASS: remote publication status, notification permission-query and clipboard-isolation master/target status, and target scope caveat are surfaced truthfully"
cat > "$TMP/pg/fx-native-hook-targets-0.conf" <<'NATIVE'
schema_version=1
ads_enabled=1
privacy_enabled=1
wifi_scan_enabled=1
notification_listen_enabled=1
notification_permission_hide_enabled=1
clipboard_isolate_enabled=1
[list:targets]
com.native.app,privacy=1,wifi_scan_block=1,notification_listen_block=1,notification_permission_hide=1,clipboard_isolate=1,member_diag=1
NATIVE
OUT=$(PG="$TMP/pg" PG_XPOSED_DIR="$TMP/xposed" sh "$STATUS" json 2>/dev/null) || fail "native overlay status JSON execution failed"
printf '%s' "$OUT" | grep -q '"hook_native_config_found":"1"' || fail "native overlay not detected"
printf '%s' "$OUT" | grep -q '"hook_native_config_users":1' || fail "native overlay user count incorrect"
printf '%s' "$OUT" | grep -q '"hook_native_privacy_enabled":"1"' || fail "native privacy master not read"
printf '%s' "$OUT" | grep -q '"hook_native_wifi_scan_enabled":"1"' || fail "native Wi-Fi master not read"
printf '%s' "$OUT" | grep -q '"hook_native_notification_listen_enabled":"1"' || fail "native notification master not read"
printf '%s' "$OUT" | grep -q '"hook_native_notification_permission_hide_enabled":"1"' || fail "native notification permission master not read"
printf '%s' "$OUT" | grep -q '"hook_native_clipboard_isolate_enabled":"1"' || fail "native clipboard master not read"
printf '%s' "$OUT" | grep -q '"hook_native_member_diag_enabled":"1"' || fail "native member diagnostics not derived from targets"
printf '%s' "$OUT" | grep -q '"hook_native_targets":1' || fail "native target count incorrect"
printf '%s' "$OUT" | grep -q '"hook_native_notification_permission_hide_targets":1' || fail "native notification permission target count incorrect"
printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const x=JSON.parse(s);if(x.hook_native_config_found!=="1"||x.hook_native_targets!==1||x.hook_native_member_diag_enabled!=="1"||x.hook_native_privacy_targets!==1)process.exit(2)})' || fail "native overlay JSON is inconsistent"
echo "PASS: native Hook status is derived from the unified APK overlay, not legacy settings.conf"'''),
])
migrate_test("v1.0.0-lsposed-sensor-config-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    ('''grep -q "'$key'" "$UI"''',
     '''grep -Fq "\\"$key\\"" "$UI"'''),
    ('''grep -q "sensor_rate_limit='" "$UI"''',
     '''grep -Fq "row.append(',').append(k).append('=')" "$UI"'''),
])
migrate_test("v1.0.0-lsposed-ui-single-apply-pipeline-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    (r'''SCRIPT=$(sed -n '/<script id="fx-lsposed-ad-hook-controller">/,/<\/script>/p' "$UI")
[ -n "$SCRIPT" ] || fail "LSPosed controller script missing"
printf '%s' "$SCRIPT" | grep -q "window.applyRun(null,{label:'同步 LSPosed 应用 Hook 配置'})" || fail "target save must use unified apply pipeline"
printf '%s' "$SCRIPT" | grep -q "window.applyRun(null,{label:'应用 LSPosed Hook 主开关'})" || fail "master switch must use unified apply pipeline"
if printf '%s' "$SCRIPT" | grep -q "window.pgPersistNow().then(function(saved)"; then fail "Hook controller must not save separately before applyRun (double write)"; fi''',
     '''grep -Fq 'save.setOnClickListener(v -> {' "$UI" || fail "native Hook save action missing"
grep -Fq 'publishConfig();' "$UI" || fail "native Hook save does not use the single publisher"
grep -Fq 'private void publishConfig()' "$UI" || fail "native Hook publisher missing"
grep -Fq 'if (hookPublisherThread != null && hookPublisherThread.isAlive())' "$UI" || fail "duplicate concurrent publishes are not rejected"
grep -Fq 'Thread publisher = new Thread(() -> {' "$UI" || fail "native Hook publication is not off the UI thread"'''),
])
migrate_test("v1.0.0-lsposed-wifi-scan-migration-regression.sh", [
    ('UI="$ROOT/webroot/index.html"', native_path),
    ('''grep -q 'wifi_scan_block' "$UI"''',
     '''grep -Fq 'toggle("限制 Wi-Fi 扫描", "wifi_scan_block"' "$UI"'''),
])
migrate_test("v1.0.0-ui-performance-regression.sh", [
    ('''HTML="$ROOT/webroot/index.html"
fail()''',
     '''HTML="$ROOT/webroot/index.html"
NATIVE_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail()'''),
    ('''# Package-app Hook selector should progressively render app rows, not create the whole tree at once.
grep -Fq 'var drawRowsGeneration=0,drawRowsBusy=false' "$HTML" || fail 'Hook app list render generation guard missing'
grep -Fq 'var frag=document.createDocumentFragment(),end=Math.min(total,i+24)' "$HTML" || fail 'Hook app list does not batch rows' ''',
     '''# Hook app selection is native: async loading is generation-guarded and rows are paginated.
grep -Fq 'MAX_APP_ROWS_PER_PAGE = 40' "$NATIVE_UI" || fail 'native Hook page size is not bounded'
grep -Fq 'appLoadGeneration' "$NATIVE_UI" || fail 'native Hook app loader generation missing'
grep -Fq 'generation != appLoadGeneration' "$NATIVE_UI" || fail 'stale native app-list results are not discarded'
grep -Fq 'while (content.getChildCount() > 5) content.removeViewAt(5)' "$NATIVE_UI" || fail 'native Hook list rerender does not preserve fixed controls'
grep -Fq '加载更多应用' "$NATIVE_UI" || fail 'native Hook app list pagination missing'
grep -Fq 'return size() > 80' "$NATIVE_UI" || fail 'native Hook icon cache is not bounded'
grep -Fq 'new Thread(() -> {' "$NATIVE_UI" || fail 'native Hook app index is not loaded asynchronously' '''),
])
print("Retired duplicate WebUI LSPosed manager and migrated legacy regressions to native Hook UI.")
