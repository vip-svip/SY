#!/usr/bin/env python3
"""Regression for deduplicating legacy static scope without dropping unrelated arrays."""
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "fx-patches"))
from xposed_resource_merge import remove_legacy_scope_resource


def array_nodes(path, name):
    root = ET.parse(path).getroot()
    return [
        node for node in list(root)
        if node.tag in ("array", "string-array", "integer-array") and node.get("name") == name
    ]


with tempfile.TemporaryDirectory(prefix="fx-xposed-resource-") as temp:
    base = Path(temp)
    legacy = base / "arrays.xml"
    fx_scope = base / "xposed_scope.xml"
    legacy.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '  <!-- unrelated legacy controls must be retained -->\n'
        '  <string-array name="hook_modes"><item>global</item><item>per_app</item></string-array>\n'
        '  <string-array name="xposed_scope"><item>com.example.legacy</item></string-array>\n'
        '  <string-array name="hook_targets"><item>example.rule</item></string-array>\n'
        '</resources>\n',
        encoding="utf-8",
    )
    fx_scope.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '  <!-- Manager-controlled dynamic scope; intentionally empty. -->\n'
        '  <string-array name="xposed_scope" />\n'
        '</resources>\n',
        encoding="utf-8",
    )

    assert remove_legacy_scope_resource(legacy, fx_scope) is True
    assert array_nodes(legacy, "xposed_scope") == [], "legacy static scope resource was not removed"
    canonical = array_nodes(fx_scope, "xposed_scope")
    assert len(canonical) == 1, "FX canonical scope resource is missing or duplicated"
    assert not list(canonical[0]), "FX dynamic scope must remain empty"

    modes = array_nodes(legacy, "hook_modes")
    targets = array_nodes(legacy, "hook_targets")
    assert len(modes) == 1 and [x.text for x in modes[0]] == ["global", "per_app"]
    assert len(targets) == 1 and [x.text for x in targets[0]] == ["example.rule"]

    # Re-running the merger is safe and does not rewrite or broaden scope.
    assert remove_legacy_scope_resource(legacy, fx_scope) is False
    assert len(array_nodes(fx_scope, "xposed_scope")) == 1
    assert not list(array_nodes(fx_scope, "xposed_scope")[0])

print("PASS: only legacy static xposed_scope removed; FX empty scope and unrelated arrays preserved; idempotent")
