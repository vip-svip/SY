#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Yulong Ad Activity source missing" >&2; exit 1; }
python3 - "$ACTIVITY" "$ROOT" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
ROOT = Path(sys.argv[2])

required = [
    'private static final String STATE_PAGE="fx_yulong_ad_page";',
    'private static final String STATE_DRAFTS="fx_yulong_ad_drafts";',
    'private final java.util.Map<String,EditText> draftFields=new java.util.LinkedHashMap<>();',
    'private EditText draftField(String key)',
    'field.setTag("fx-yulong-ad-draft:"+key);',
    'pendingRestoredDrafts=b.getBundle(STATE_DRAFTS);',
    'page=b.getString(STATE_PAGE,"首页与防护");',
    'restoreDrafts(pendingRestoredDrafts);pendingRestoredDrafts=null;',
    'out.putString(STATE_PAGE,page);',
    'out.putBundle(STATE_DRAFTS,drafts);',
    'private static final int BULK_DRAFT_MAX_CHARS=48*1024;',
    'private static final int TEXT_DRAFT_MAX_CHARS=4096;',
    'field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(maxChars)});',
    'int maxChars=key.endsWith("_bulk")?BULK_DRAFT_MAX_CHARS:TEXT_DRAFT_MAX_CHARS;',
    '最多 2000 条、48 Ki 字符（导入字节仍限制为 64 KiB）',
    'draftFields.clear();body.removeAllViews();',
]
for token in required:
    assert token in s, f"missing Yulong editor recreation invariant: {token}"

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
]
for token in dns_required:
    assert token in dns, f"missing DNS page state/lifecycle invariant: {token}"
assert "loadGeneration.incrementAndGet();\\n        worker.shutdownNow();" in dns, \
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
print("PASS: Yulong Ad page and 16 editable field drafts survive Activity recreation")
PY
