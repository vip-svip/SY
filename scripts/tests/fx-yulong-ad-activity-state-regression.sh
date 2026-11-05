#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Yulong Ad Activity source missing" >&2; exit 1; }
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSnapshotPolicy.java"
HOST_TEST="$ROOT/scripts/tests/FxYulongAdSnapshotPolicyHostTest.java"
[ -s "$POLICY" ] && [ -s "$HOST_TEST" ] || { echo "FAIL: Yulong Ad snapshot policy sources missing" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-ad-snapshot.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  javac -d "$WORK" "$POLICY" "$HOST_TEST"
  java -cp "$WORK" de.privacyguard.adhook.imported.ad.FxYulongAdSnapshotPolicyHostTest
else
  echo "SKIP: JDK unavailable; Ad snapshot parser Host test not executed."
fi
python3 - "$ACTIVITY" "$ROOT" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
ROOT = Path(sys.argv[2])

# Root-backed Ad commands must resolve only a real FX 1.0.0 module tree.
cmd_start = s.index("private String cmd(String args)")
cmd_end = s.index("private void root(", cmd_start)
cmd = s[cmd_start:cmd_end]
for token in (
    "[ -d '/data' ]", "[ ! -L '/data' ]",
    "[ -d '/data/adb' ]", "[ ! -L '/data/adb' ]",
    "[ -d '/data/adb/modules' ]", "[ ! -L '/data/adb/modules' ]",
    "[ ! -L '/data/adb/modules_update' ]",
    'if [ -d \\"$d\\" ] && [ ! -L \\"$d\\" ]',
    '&& [ -f \\"$d/module.prop\\" ] && [ ! -L \\"$d/module.prop\\" ]',
    "grep -qx 'id=privacyguard'",
    "grep -qx 'version=1.0.0'",
    '&& [ -d \\"$d/scripts\\" ] && [ ! -L \\"$d/scripts\\" ]',
    '&& [ -f \\"$d/scripts/yulong-ad-control.sh\\" ]',
    '&& [ ! -L \\"$d/scripts/yulong-ad-control.sh\\" ]',
):
    assert token in cmd, f"Ad Root module resolution must enforce: {token}"

# Async Root callbacks may update only the page that issued the request.
assert "private long pageGeneration;" in s, "Ad page generation token is missing"
assert "private void render(){pageGeneration++;" in s, "page rebuild must invalidate earlier requests"
for method_name, next_method in (
    ("private void root(", "private String safe("),
    ("private void apply(", "@Override protected void onCreate"),
    ("private void profileRoot(", "private void renderProfiles("),
):
    start = s.index(method_name)
    end = s.index(next_method, start + len(method_name))
    method = s[start:end]
    assert "final long requestGeneration=pageGeneration;" in method, f"{method_name} must capture page generation"
    assert "final String requestPage=page;" in method, f"{method_name} must capture page identity"
    assert "requestGeneration!=pageGeneration" in method or "requestGeneration==pageGeneration" in method, f"{method_name} must discard stale callbacks"
assert "boolean samePage=requestGeneration==pageGeneration&&requestPage.equals(page);" in s, "write completion must not update a different page"
assert "@Override protected void onDestroy(){pageGeneration++;" in s, "destroy must invalidate page callbacks"


required = [
    'private static final String STATE_PAGE="fx_yulong_ad_page";',
    'private static final String STATE_DRAFTS="fx_yulong_ad_drafts";',
    'private static final String STATE_SCROLL_Y="fx_yulong_ad_scroll_y";',
    'private Bundle captureDrafts(){',
    'private Bundle retainedDrafts=new Bundle();',
    'Bundle drafts=new Bundle(retainedDrafts);',
    'if(pendingRestoredDrafts!=null)retainedDrafts=new Bundle(pendingRestoredDrafts);',
    'retainedDrafts=captureDrafts();',
    'out.putBundle(STATE_DRAFTS,retainedDrafts);',
    'private void open(String p){retainedDrafts=captureDrafts();page=p;',
    'render();restoreDrafts(retainedDrafts);bind();}',
    'private ScrollView pageScroll;',
    'private int pendingPageScrollY;',
    'private boolean pendingPageScrollRestore;',
    'pendingPageScrollY=Math.max(0,b.getInt(STATE_SCROLL_Y,0));',
    'pendingPageScrollRestore=true;',
    'out.putInt(STATE_SCROLL_Y,Math.max(0,pageScroll.getScrollY()));',
    'private void restorePageScrollIfNeeded()',
    'pageScroll.scrollTo(0,y);',
    'pendingPageScrollRestore=false;',
    'private final java.util.Map<String,EditText> draftFields=new java.util.LinkedHashMap<>();',
    'private EditText draftField(String key)',
    'field.setTag("fx-yulong-ad-draft:"+key);',
    'pendingRestoredDrafts=b.getBundle(STATE_DRAFTS);',
    'page=b.getString(STATE_PAGE,"首页与防护");',
    'restoreDrafts(pendingRestoredDrafts);pendingRestoredDrafts=null;',
    'out.putString(STATE_PAGE,page);',
    'out.putBundle(STATE_DRAFTS,retainedDrafts);',
    'private static final int BULK_DRAFT_MAX_CHARS=48*1024;',
    'private static final int TEXT_DRAFT_MAX_CHARS=4096;',
    'field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(maxChars)});',
    'int maxChars=key.endsWith("_bulk")?BULK_DRAFT_MAX_CHARS:TEXT_DRAFT_MAX_CHARS;',
    '最多 2000 条、48 Ki 字符（导入字节仍限制为 64 KiB）',
    'draftFields.clear();body.removeAllViews();',
]
for token in required:
    assert token in s, f"missing Yulong editor recreation invariant: {token}"
open_start = s.index("private void open(String p)")
open_end = s.index("\n", open_start)
open_method = s[open_start:open_end]
assert open_method.index("retainedDrafts=captureDrafts()") < open_method.index("page=p;")
assert "pendingPageScrollRestore=false" in open_method and "pendingPageScrollY=0" in open_method
assert open_method.index("render();") < open_method.index("restoreDrafts(retainedDrafts)") < open_method.index("bind();"), \
    "page switching must reset scroll while restoring unsaved form drafts"

keys = (
    "rule_url", "rule_name", "rule_search",
    "dns_custom_servers", "dns_fallback_servers", "dns_global_servers",
    "vpn_remote_dns", "vpn_cn_dns", "allow_domain", "allow_note",
    "allow_bulk", "block_domain", "block_note", "block_bulk",
    "schedule_start", "schedule_end",
)
for key in keys:
    assert f'draftField("{key}")' in s, f"EditText draft key missing: {key}"

assert s.count("new EditText(this)") == 1, "all UI EditTexts must use the stable draft-key factory"
assert "for(java.util.Map.Entry<String,EditText> entry:draftFields.entrySet())" in s, \
    "onSaveInstanceState must capture the current page's complete draft map"
assert "saved.containsKey(entry.getKey())" in s and \
       'entry.getValue().setText(saved.getString(entry.getKey(),""))' in s, \
    "restoration must reapply saved text after the page controls are rebuilt"
create = s.index("@Override protected void onCreate")
render_call = s.index("render();", create)
restore = s.index("restoreDrafts(pendingRestoredDrafts)", create)
load = s.index("load();", create)
assert create < render_call < restore < load, \
    "onCreate must build page controls before restoring drafts and refreshing data"
general = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java").read_text(encoding="utf-8")
dns = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongDnsActivity.java").read_text(encoding="utf-8")
summary = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java").read_text(encoding="utf-8")
dns_required = [
    'private static final String STATE_SEARCH = "fx_dns_search";',
    'private static final String STATE_SCROLL_Y = "fx_dns_scroll_y";',
    'outState.putString(STATE_SEARCH, search.getText().toString())',
    'outState.putInt(STATE_SCROLL_Y, Math.max(0, scroll.getScrollY()))',
    'state.getString(STATE_SEARCH, "")',
    'state.getInt(STATE_SCROLL_Y, 0)',
    'private final AtomicInteger loadGeneration = new AtomicInteger();',
    'final int generation = loadGeneration.incrementAndGet();',
    'if (generation != loadGeneration.get()) return;',
    'private void restoreScrollIfNeeded()',
    'pendingScrollRestore = true;',
    'loadGeneration.incrementAndGet();',
    'int total = 0, blocked = 0, malformed = 0;',
    'if (domain.isEmpty()) { malformed++; continue; }',
    '} catch (Exception ignored) { malformed++; }',
    '无法解析/缺少域名 ',
]
for token in dns_required:
    assert token in dns, f"missing DNS page state/lifecycle invariant: {token}"
destroy_start = dns.index("@Override protected void onDestroy()")
destroy_end = dns.index("\n    }", destroy_start)
destroy_body = dns[destroy_start:destroy_end]
assert destroy_body.index("loadGeneration.incrementAndGet();") < destroy_body.index("worker.shutdownNow();"), \
    "DNS log callbacks must be invalidated before the worker is shut down"
assert "if (refreshButton != null) refreshButton.setEnabled(false);" in dns, \
    "DNS refresh must prevent duplicate queued reads"
assert "if (clearButton != null) clearButton.setEnabled(false);" in dns, \
    "DNS log clear must prevent duplicate queued destructive operations"

for label, source, capacity in (("Ad backup", general, "ArrayBlockingQueue<>(8)"),
                                ("DNS log", dns, "ArrayBlockingQueue<>(16)"),
                                ("daily summary", summary, "ArrayBlockingQueue<>(8)")):
    assert capacity in source, f"{label} worker queue must remain bounded"
    assert "new ThreadPoolExecutor.AbortPolicy()" in source, f"{label} worker must fail closed on queue saturation"
    assert "RejectedExecutionException" in source, f"{label} queue saturation must be handled"
    assert "worker.shutdownNow()" in source, f"{label} worker must stop with Activity lifecycle"
assert "private void submitWorker(Runnable task)" in general, "backup import/export must surface worker rejection"
for token in (
    "FxYulongAdSnapshotPolicy.parseAdMasterEnabled(snapshot)",
    'Boolean master=adMaster();',
    "广告过滤主开关状态未知（暂不可切换）",
    "setAdMasterUnknown();",
    "if(master==null)",
    "sw.setEnabled(false)",
):
    assert token in s, f"Ad master unknown-state behavior missing: {token}"
assert "private Boolean adMaster()" in s, "Ad master parser must return an explicit unknown state"
ad_master_method = s[s.index("private Boolean adMaster()"):s.index("private void setAdMasterUnknown()")]
assert "return true;" not in ad_master_method, "missing AD_MASTER must not default to enabled"
print("PASS: Yulong Ad drafts persist across multiple page switches and recreation; page scroll and DNS log search/scroll state survive recreation; stale DNS refresh results are discarded")
PY
