#!/usr/bin/env python3
"""Generate native privacy UI metadata from real top-level boolean module settings."""
from html import unescape
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
assets = Path(sys.argv[2] if len(sys.argv) > 2 else "adhook/app/src/main/assets")
html = root / "webroot/index.html"
defaults = root / "scripts/default.conf"
if not html.is_file() or not defaults.is_file():
    raise SystemExit("FX WebUI or scripts/default.conf source is missing")
source = html.read_text(encoding="utf-8")
default_text = defaults.read_text(encoding="utf-8")
# Only expose actual top-level 0/1 flags. Section keys and editable values must
# remain on their existing specialized UI and must never be turned into switches.
boolean_keys = set()
for line in default_text.splitlines():
    if line.lstrip().startswith("["):
        break
    match = re.match(r"^([A-Za-z0-9_.-]{1,96})=([01])$", line.strip())
    if match:
        boolean_keys.add(match.group(1))

allowed_panels = {
    "vpnPanel", "rootPanel", "advPanel", "netPanel", "permPanel", "sensorPanel",
    "locationPanel", "devicePanel", "mediaPanel", "filePanel",
    "notifyPanel", "kernelPanel", "miscPanel"
}
panel_re = re.compile(
    r"""<div\s+class=["'][^"']*\bstylepanel\b[^"']*["'][^>]*\bid=["']([^"']+)["'][^>]*>(.*?)(?=<div\s+class=["'][^"']*\bstylepanel\b|<div\s+class=["'][^"']*editor)""",
    re.S
)
panels = []
for panel_id, fragment in panel_re.findall(source):
    if panel_id not in allowed_panels:
        continue
    items = []
    row_re = re.compile(r"""<button\b[^>]*class=["'][^"']*\bsetrow\b[^"']*["'][^>]*>.*?</button>""", re.S)
    for row in row_re.findall(fragment):
        key_match = re.search(r"""data-key=["']([A-Za-z0-9_.-]{1,96})["']""", row)
        if not key_match or key_match.group(1) not in boolean_keys:
            continue
        key = key_match.group(1)
        title_match = re.search(r"""<div\s+class=["'][^"']*\bs-title\b[^"']*["']>(.*?)</div>""", row, re.S)
        desc_match = re.search(r"""<div\s+class=["'][^"']*\bs-sub\b[^"']*["']>(.*?)</div>""", row, re.S)
        def clean(value):
            return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]+>", "", value))).strip()
        items.append({
            "key": key,
            "title": clean(title_match.group(1)) if title_match else key,
            "description": clean(desc_match.group(1)) if desc_match else ""
        })
    panels.append({"id": panel_id, "items": items})

found = {panel["id"] for panel in panels}
if found != allowed_panels:
    raise SystemExit("privacy panel schema incomplete: " + ", ".join(sorted(allowed_panels - found)))
keys = [item["key"] for panel in panels for item in panel["items"]]
if len(keys) < 20:
    raise SystemExit("too few top-level boolean privacy controls; refusing partial native migration")
if len(keys) != len(set(keys)):
    raise SystemExit("duplicate top-level privacy setting keys; refusing ambiguous ownership")
assets.mkdir(parents=True, exist_ok=True)
(assets / "native-privacy-settings.json").write_text(
    json.dumps({"schema_version": 1, "panels": panels}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8"
)
module_script = root / "scripts/native-privacy-settings.sh"
module_script.parent.mkdir(parents=True, exist_ok=True)
module_script.write_text(
    Path(__file__).with_name("native-privacy-settings.sh").read_text(encoding="utf-8"),
    encoding="utf-8"
)
module_script.chmod(0o755)
print("Generated %d native privacy panels with %d top-level boolean controls." %
      (len(panels), len(keys)))
