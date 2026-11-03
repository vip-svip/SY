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
    # root -> "com" -> terminal "example", yielding example.com after reversal.
    root_offset = DECODER_MODULE.HEADER_SIZE
    middle_offset = root_offset + 5 + 2 + 3 + 4
    leaf_offset = middle_offset + 5 + 2 + 7 + 4
    header = struct.pack(
        ">IIII", DECODER_MODULE.MAGIC, DECODER_MODULE.VERSION, 3, 1
    )
    root = (
        b"\x00" + struct.pack(">I", 1)
        + struct.pack(">H", 3) + b"com"
        + struct.pack(">I", middle_offset)
    )
    middle = (
        b"\x00" + struct.pack(">I", 1)
        + struct.pack(">H", 7) + b"example"
        + struct.pack(">I", leaf_offset)
    )
    leaf = b"\x01" + struct.pack(">I", 0)
    return header + root + middle + leaf


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
    report = tmp / "Yulong_AdBlock-report.json"
    completed = subprocess.run(
        [
            sys.executable, str(DECODER), str(assets), str(output),
            "--cosmetic-output", str(cosmetic), "--report", str(report),
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
    if result.get("unique_valid_dns_domains") != 1 or "0.0.0.0 example.com" not in output.read_text():
        fail("valid TRIE terminals were not decoded into the expected DNS domain")
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

print("PASS: Yulong TRIE v2 and paired BLOOM v1 headers, missing assets, corruption and symlink rejection")
