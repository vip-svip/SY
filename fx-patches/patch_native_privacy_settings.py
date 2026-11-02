#!/usr/bin/env python3
"""Generate native privacy setting metadata and install the root-side writer."""
from html import unescape
from pathlib import Path
import json
import re
import shutil
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
assets = Path(sys.argv[2] if len(sys.argv) > 2 else "adhook/app/src/main/assets")
html = root / "webroot/index.html"
if not html.is_file():
    raise SystemExit("FX WebUI source is missing")
source = html.read_text(encoding="utf-8")
panels = []
for panel_id, fragment in re.findall(
    r'<div\\s+class=["\\']stylepanel["\\']\\s+id=["\\']([^"\\']+)["\\']>(.*?)(?=<div\\s+class=["\\']stylepanel["\\']|<div\\s+class=["\\']editor["\\'])',
    source, re.S
):
    if panel_id not in {
        "rootPanel", "advPanel", "netPanel", "permPanel", "sensorPanel",
        "locationPanel", "devicePanel", "mediaPanel", "filePanel",
        "notifyPanel", "kernelPanel", "miscPanel"
    }:
        continue
    items = []
    for row in re.findall(r'<button\\b[^>]*class=["\\']setrow["\\'][^>]*>.*?</button>', fragment, re.S):
        key_match = re.search(r'data-key=["\\']([A-Za-z0-9_.-]{1,96})["\\']', row)
        title_match = re.search(r'<div\\s+class=["\\']s-title["\\']>(.*?)</div>', row, re.S)
        desc_match = re.search(r'<div\\s+class=["\\']s-sub["\\']>(.*?)</div>', row, re.S)
        if not key_match or not title_match:
            continue
        clean = lambda value: re.sub(r'\\s+', ' ', unescape(re.sub(r'<[^>]+>', '', value))).strip()
        items.append({
            "key": key_match.group(1),
            "title": clean(title_match.group(1)),
            "description": clean(desc_match.group(1)) if desc_match else ""
        })
    panels.append({"id": panel_id, "items": items})
expected = {
    "rootPanel", "advPanel", "netPanel", "permPanel", "sensorPanel",
    "locationPanel", "devicePanel", "mediaPanel", "filePanel",
    "notifyPanel", "kernelPanel", "miscPanel"
}
found = {panel["id"] for panel in panels}
if found != expected:
    raise SystemExit("privacy panel schema incomplete: " + ", ".join(sorted(expected - found)))
if sum(len(panel["items"]) for panel in panels) < 40:
    raise SystemExit("privacy panel schema unexpectedly small; refusing to generate native UI metadata")
assets.mkdir(parents=True, exist_ok=True)
(assets / "native-privacy-settings.json").write_text(
    json.dumps({"schema_version": 1, "panels": panels}, ensure_ascii=False, indent=2) + "\\n",
    encoding="utf-8"
)
module_script = root / "scripts/native-privacy-settings.sh"
module_script.write_text(Path(__file__).with_name("native-privacy-settings.sh").read_text(encoding="utf-8"), encoding="utf-8")
module_script.chmod(0o755)
print("Generated native privacy schema (%d panels, %d controls) and installed root writer." %
      (len(panels), sum(len(panel["items"]) for panel in panels)))
