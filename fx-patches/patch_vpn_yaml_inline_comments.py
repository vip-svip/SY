#!/usr/bin/env python3
"""Preserve quoted # characters while stripping legal trailing YAML comments."""
from pathlib import Path
import re
import shutil
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("fx-module")
source = root / "scripts/vpnsub.sh"
if not source.is_file():
    raise SystemExit(f"missing {source}")
text = source.read_text(encoding="utf-8")
function = r'''function strip_yaml_comment(v,    i,c,q,esc,sq){
  q = ""; esc = 0; sq = sprintf("%c", 39)
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (q == "\"") {
      if (esc) esc = 0
      else if (c == "\\") esc = 1
      else if (c == "\"") q = ""
    } else if (q == sq) {
      if (c == sq) q = ""
    } else if (c == "\"" || c == sq) q = c
    else if (c == "#" && (i == 1 || substr(v, i - 1, 1) ~ /[ \t]/)) return substr(v, 1, i - 1)
  }
  return v
}
'''
if "function strip_yaml_comment(" not in text:
    # Insert before the first YAML scalar helper, even if formatting changed.
    marker = re.search(r"(?m)^function\s+(?:unq|reset|setkv)\s*\(", text)
    if not marker:
        raise SystemExit("cannot locate a YAML parser function insertion point")
    text = text[:marker.start()] + function + text[marker.start():]

if "strip_yaml_comment($0)" not in text:
    # Match both compact and spaced forms of the input-record assignment.
    assignment = re.search(r"(?m)^([ \t]*)line[ \t]*=[ \t]*\$0[ \t]*$", text)
    if not assignment:
        raise SystemExit("cannot locate YAML parser input record assignment")
    replacement = assignment.group(1) + "line = strip_yaml_comment($0)"
    text = text[:assignment.start()] + replacement + text[assignment.end():]

source.write_text(text, encoding="utf-8")
test_source = Path(__file__).resolve().parents[1] / "scripts/tests/v1.0.0-vpn-yaml-inline-comment-regression.sh"
test_target = root / "scripts/tests/v1.0.0-vpn-yaml-inline-comment-regression.sh"
if not test_source.is_file():
    raise SystemExit(f"missing regression source {test_source}")
test_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(test_source, test_target)
print("Patched Clash YAML trailing-comment handling and staged its regression test")
