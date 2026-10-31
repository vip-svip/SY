#!/usr/bin/env python3
"""Remove the obsolete WebUI LSPosed manager; native FX Hook tab is authoritative."""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: retire_webui_legacy_hook.py <webroot-index.html>")

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
module_root = target.parent.parent
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
        if new in source:
            continue
        count = source.count(old)
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
     '''grep -q 'hook_notification_permission_hide_enabled' "$UI"'''),
    ('''grep -q 'clipboardIsolateEnabled' "$UI"''',
     '''grep -q 'hook_clipboard_isolate_enabled' "$UI"'''),
    ('''grep -q 'memberDiagEnabled' "$UI"''',
     '''grep -q 'hook_member_diag_enabled' "$UI"'''),
    ('''grep -q '独立于广告总开关' "$UI" || fail "UI does not explain independent member diagnostics scope"''',
     '''grep -q '会员诊断仅记录应用内可观察状态' "$UI" || fail "UI does not explain read-only member diagnostics"'''),
    ('''grep -q 'function refreshRemoteStatus()' "$UI"''',
     '''grep -q 'private void refreshHookRemoteStatus(TextView target)' "$UI"'''),
    ('''grep -q '配置发布失败' "$UI"''',
     '''grep -q 'Root 发布失败' "$UI"'''),
    ('''grep -q '仍需在管理器确认模块启用和相同 App 作用域' "$UI"''',
     '''grep -q '目标应用加入作用域' "$UI"'''),
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
    ('''SCRIPT=$(sed -n '/<script id="fx-lsposed-ad-hook-controller">/,/<\/script>/p' "$UI")
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
