#!/usr/bin/env python3
"""Preserve quoted # characters while stripping legal trailing YAML comments."""
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("fx-module")
source = root / "scripts/vpnsub.sh"
if not source.is_file():
    raise SystemExit(f"missing {source}")
text = source.read_text(encoding="utf-8")
old = 'function trim(v){ gsub(/^[ \\t]+/, "", v); gsub(/[ \\t]+$/, "", v); return v }\\nfunction unq(v)'
new = '''function trim(v){ gsub(/^[ \\t]+/, "", v); gsub(/[ \\t]+$/, "", v); return v }
function strip_yaml_comment(v,    i,c,q,esc,sq){
  q = ""; esc = 0; sq = sprintf("%c", 39)
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (q == "\\\"") {
      if (esc) esc = 0
      else if (c == "\\\\") esc = 1
      else if (c == "\\\"") q = ""
    } else if (q == sq) {
      if (c == sq) q = ""
    } else if (c == "\\\"" || c == sq) q = c
    else if (c == "#" && (i == 1 || substr(v, i - 1, 1) ~ /[ \\t]/)) return substr(v, 1, i - 1)
  }
  return v
}
function unq(v)'''
if 'function strip_yaml_comment(' not in text:
    if old not in text:
        raise SystemExit("cannot find YAML parser trim/unquote anchor")
    text = text.replace(old, new, 1)
old_line = '  line = $0\\n  sub(/\\\\r$/, "", line)'
new_line = '  line = strip_yaml_comment($0)\\n  sub(/\\\\r$/, "", line)'
if new_line not in text:
    if old_line not in text:
        raise SystemExit("cannot find YAML parser input-line anchor")
    text = text.replace(old_line, new_line, 1)
source.write_text(text, encoding="utf-8")

test_source = Path(__file__).resolve().parents[1] / "scripts/tests/v1.0.0-vpn-yaml-inline-comment-regression.sh"
test_target = root / "scripts/tests/v1.0.0-vpn-yaml-inline-comment-regression.sh"
if not test_source.is_file():
    raise SystemExit(f"missing regression source {test_source}")
test_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(test_source, test_target)
print("Patched Clash YAML trailing-comment handling and staged its regression test")
