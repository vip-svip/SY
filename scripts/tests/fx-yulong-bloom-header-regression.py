#!/usr/bin/env python3
"""Verify FX validates Yulong 7.0.1's paired TRIE v2 and BLOOM v1 assets."""
from __future__ import annotations

import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DECODER = ROOT / "scripts/decode_yulong_ad_tries.py"
SPEC = importlib.util.spec_from_file_location("fx_yulong_decoder", DECODER)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("FAIL: unable to load Yulong trie decoder")
DECODER_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DECODER_MODULE)


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


def minimal_trie() -> bytes:
    """Build a valid TRIE v2 fixture with DNS, cosmetic and review-only terms."""
    terminals = (
        "example.com",
        "cdn.example.net^",
        "|a.klaviyo.com^",
        "news.example.org##.ad",
        "1.2.3.4",
    )

    class Node:
        def __init__(self):
            self.terminal = False
            self.children = {}

    root = Node()
    for terminal in terminals:
        node = root
        for label in reversed(terminal.split(".")):
            node = node.children.setdefault(label, Node())
        node.terminal = True

    nodes = []
    queue = [root]
    while queue:
        current = queue.pop(0)
        nodes.append(current)
        for label in sorted(current.children):
            queue.append(current.children[label])

    offsets = {}
    offset = DECODER_MODULE.HEADER_SIZE
    for current in nodes:
        offsets[id(current)] = offset
        offset += 5 + sum(
            2 + len(label.encode("utf-8")) + 4
            for label in current.children
        )

    payload = bytearray()
    for current in nodes:
        payload.append(1 if current.terminal else 0)
        payload.extend(struct.pack(">I", len(current.children)))
        for label in sorted(current.children):
            encoded = label.encode("utf-8")
            payload.extend(struct.pack(">H", len(encoded)))
            payload.extend(encoded)
            payload.extend(struct.pack(">I", offsets[id(current.children[label])]))

    header = struct.pack(
        ">IIII", DECODER_MODULE.MAGIC, DECODER_MODULE.VERSION,
        len(nodes), len(terminals)
    )
    return header + bytes(payload)

def valid_bloom() -> bytes:
    return struct.pack(
        ">II", DECODER_MODULE.BLOOM_MAGIC, DECODER_MODULE.BLOOM_VERSION
    ) + b"\x01" * 16


with tempfile.TemporaryDirectory(prefix="fx-yulong-bloom-") as temp:
    tmp = Path(temp)
    assets = tmp / "assets"
    assets.mkdir()
    trie_bytes = minimal_trie()
    bloom_bytes = valid_bloom()

    for trie_name in DECODER_MODULE.TRIE_FILES:
        (assets / trie_name).write_bytes(trie_bytes)
        (assets / Path(trie_name).with_suffix(".bloom").name).write_bytes(bloom_bytes)

    # Exercise the complete decoder path and assert it reports all four paired
    # Bloom headers, rather than merely testing a helper in isolation.
    output = tmp / "Yulong_AdBlock.txt"
    cosmetic = tmp / "Yulong_AdBlock_Cosmetic.txt"
    review = tmp / "Yulong_AdBlock_Review.jsonl"
    report = tmp / "Yulong_AdBlock-report.json"
    completed = subprocess.run(
        [
            sys.executable, str(DECODER), str(assets), str(output),
            "--cosmetic-output", str(cosmetic), "--review-output", str(review),
            "--report", str(report),
        ],
        capture_output=True, text=True, check=False,
    )
    if completed.returncode != 0:
        fail("valid paired TRIE/BLOOM fixtures were rejected: " + completed.stderr)
    result = json.loads(report.read_text(encoding="utf-8"))
    if result.get("format") != "TRIE v2 + BLOOM v1":
        fail("decoder report does not identify both native formats")
    if result.get("trie_asset_count") != 4 or result.get("bloom_asset_count") != 4:
        fail("decoder report does not count all four native asset pairs")
    rules_text = output.read_text(encoding="utf-8")
    if result.get("unique_valid_dns_domains") != 2:
        fail("expected plain and safe separator DNS domains")
    if "0.0.0.0 example.com" not in rules_text or "0.0.0.0 cdn.example.net" not in rules_text:
        fail("plain or safely normalized DNS terminal missing")
    if result.get("normalized_separator_terminals") != 4:
        fail("separator normalization count is incorrect")
    cosmetic_text = cosmetic.read_text(encoding="utf-8")
    if "news.example.org##.ad" not in cosmetic_text:
        fail("cosmetic rule was not preserved separately")
    review_rows = [json.loads(line) for line in review.read_text(encoding="utf-8").splitlines()
                   if line and not line.startswith("#")]
    if len(review_rows) != 8:
        fail("two review-only terminals per source Trie should be preserved")
    review_terms = {row["terminal"] for row in review_rows}
    if not {"|a.klaviyo.com^", "1.2.3.4"} <= review_terms:
        fail("non-DNS filter terminals were not preserved for review")
    if "0.0.0.0 a.klaviyo.com" in rules_text:
        fail("URL-start anchored terminal was incorrectly widened into DNS blocking")
    if result.get("preserved_review_terminal_count") != 8:
        fail("review terminal count should preserve two unsupported terminals per source trie")
    for item in result["files"].values():
        bloom = item.get("bloom", {})
        if bloom.get("version") != 1 or bloom.get("magic") != "0x424c4f4d":
            fail("per-file Bloom v1 metadata missing from decoder report")

    # The original app rejects a wrong BLOOM magic/version even if the TRIE
    # remains valid. The FX build decoder must fail closed in the same case.
    bloom_path = assets / Path(DECODER_MODULE.TRIE_FILES[0]).with_suffix(".bloom").name
    bad_headers = {
        "truncated": b"BLOOM",
        "wrong magic": struct.pack(">II", 0xDEADBEEF, 1) + b"\x00" * 16,
        "wrong version": struct.pack(">II", DECODER_MODULE.BLOOM_MAGIC, 2) + b"\x00" * 16,
    }
    for label, raw in bad_headers.items():
        bloom_path.write_bytes(raw)
        try:
            DECODER_MODULE.validate_bloom(bloom_path)
        except ValueError:
            pass
        else:
            fail(f"invalid Bloom header accepted: {label}")

    bloom_path.unlink()
    try:
        DECODER_MODULE.validate_bloom(bloom_path)
    except ValueError:
        pass
    else:
        fail("missing paired Bloom asset was accepted")

    # A symlink must not silently substitute an unrelated Bloom binary.
    outside = tmp / "outside.bloom"
    outside.write_bytes(valid_bloom())
    try:
        bloom_path.symlink_to(outside)
    except OSError:
        pass
    else:
        try:
            DECODER_MODULE.validate_bloom(bloom_path)
        except ValueError:
            pass
        else:
            fail("symlinked Bloom asset was accepted")


    # Output paths must never follow a pre-planted symlink.
    bloom_path.unlink()
    bloom_path.write_bytes(valid_bloom())
    sentinel = tmp / "output-sentinel.txt"
    sentinel.write_text("do-not-overwrite\n", encoding="utf-8")
    symlink_output = tmp / "symlink-output.txt"
    try:
        symlink_output.symlink_to(sentinel)
    except OSError:
        pass
    else:
        blocked = subprocess.run(
            [sys.executable, str(DECODER), str(assets), str(symlink_output),
             "--cosmetic-output", str(tmp / "blocked-cosmetic.txt"),
             "--review-output", str(tmp / "blocked-review.jsonl"),
             "--report", str(tmp / "blocked-report.json")],
            capture_output=True, text=True, check=False,
        )
        if blocked.returncode == 0:
            fail("decoder accepted a symlink output destination")
        if sentinel.read_text(encoding="utf-8") != "do-not-overwrite\n":
            fail("symlink output destination modified its target")
        if not symlink_output.is_symlink():
            fail("decoder replaced or removed the output symlink")

    # Legacy deterministic .tmp links must be neither followed nor modified.
    safe_output = tmp / "safe-output.txt"
    legacy_tmp = tmp / "safe-output.txt.tmp"
    try:
        legacy_tmp.symlink_to(sentinel)
    except OSError:
        pass
    completed = subprocess.run(
        [sys.executable, str(DECODER), str(assets), str(safe_output),
         "--cosmetic-output", str(tmp / "safe-cosmetic.txt"),
         "--review-output", str(tmp / "safe-review.jsonl"),
         "--report", str(tmp / "safe-report.json")],
        capture_output=True, text=True, check=False,
    )
    if completed.returncode != 0:
        fail("decoder failed with legacy .tmp symlink present: " + completed.stderr)
    if sentinel.read_text(encoding="utf-8") != "do-not-overwrite\n":
        fail("legacy .tmp symlink target was modified")
    if legacy_tmp.is_symlink() is False:
        fail("legacy .tmp symlink was unexpectedly replaced")
    if not safe_output.is_file() or safe_output.is_symlink():
        fail("decoder did not install a regular output file")
    if list(tmp.glob(".safe-output.txt.fx-*.tmp")):
        fail("random same-directory output temp leaked after replace")
    if list(tmp.glob(".safe-cosmetic.txt.fx-*.tmp")) or list(tmp.glob(".safe-report.json.fx-*.tmp")):
        fail("cosmetic/report temporary files leaked after replace")

print("PASS: Yulong TRIE v2 and paired BLOOM v1 headers, missing assets, corruption and symlink rejection")
