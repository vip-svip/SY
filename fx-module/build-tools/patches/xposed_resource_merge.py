#!/usr/bin/env python3
"""Remove only the legacy static xposed_scope resource before merging Android values XML."""
from __future__ import annotations

import os
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

_ARRAY_TAGS = {"array", "string-array", "integer-array"}


def _parse(path: Path) -> tuple[ET.ElementTree, ET.Element]:
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    tree = ET.parse(path, parser=parser)
    root = tree.getroot()
    if root.tag != "resources":
        raise ValueError(f"{path}: expected <resources> root")
    return tree, root


def _find_scope(root: ET.Element) -> list[ET.Element]:
    return [
        node for node in list(root)
        if isinstance(node.tag, str)
        and node.tag in _ARRAY_TAGS
        and node.get("name") == "xposed_scope"
    ]


def _write_atomic(tree: ET.ElementTree, path: Path) -> None:
    ET.indent(tree, space="    ")
    fd, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    os.close(fd)
    temp = Path(name)
    try:
        tree.write(temp, encoding="utf-8", xml_declaration=True)
        os.replace(temp, path)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def remove_legacy_scope_resource(legacy_arrays_path: Path, fx_scope_path: Path) -> bool:
    """Keep the empty, user-managed FX scope and strip only the old static scope.

    The modern libxposed module declares staticScope=false. Pre-populating the
    legacy scope array would silently select arbitrary apps, so the FX resource
    must remain exactly one empty string-array. Unrelated legacy arrays survive.
    """
    legacy_arrays_path = Path(legacy_arrays_path)
    fx_scope_path = Path(fx_scope_path)
    legacy_tree, legacy_root = _parse(legacy_arrays_path)
    _, fx_root = _parse(fx_scope_path)

    fx_matches = _find_scope(fx_root)
    if len(fx_matches) != 1 or fx_matches[0].tag != "string-array":
        raise ValueError(f"{fx_scope_path}: expected exactly one canonical string-array xposed_scope")
    fx_items = [node for node in list(fx_matches[0]) if isinstance(node.tag, str) and node.tag == "item"]
    if fx_items:
        raise ValueError(f"{fx_scope_path}: dynamic xposed_scope must remain empty")

    legacy_matches = _find_scope(legacy_root)
    if len(legacy_matches) > 1:
        raise ValueError(f"{legacy_arrays_path}: multiple legacy xposed_scope resources found")
    if not legacy_matches:
        return False

    # Discard only this obsolete static scope resource. All other arrays and
    # their values are preserved in the copied legacy arrays.xml.
    legacy_root.remove(legacy_matches[0])
    _write_atomic(legacy_tree, legacy_arrays_path)

    if _find_scope(_parse(legacy_arrays_path)[1]):
        raise ValueError(f"{legacy_arrays_path}: legacy xposed_scope remained after removal")
    final_fx = _find_scope(_parse(fx_scope_path)[1])
    if len(final_fx) != 1 or any(
        isinstance(node.tag, str) and node.tag == "item" for node in list(final_fx[0])
    ):
        raise ValueError("FX dynamic xposed_scope was altered during legacy resource cleanup")
    return True
