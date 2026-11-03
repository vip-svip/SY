#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Yulong Ad Activity source missing" >&2; exit 1; }
python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")

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
print("PASS: Yulong Ad page and 16 editable field drafts survive Activity recreation")
PY
