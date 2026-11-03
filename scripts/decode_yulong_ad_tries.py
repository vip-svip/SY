#!/usr/bin/env python3
"""Decode Yulong Ad Plugin 7.0.1 native TRIE v2 assets into safe FX DNS rules.

Only validated FQDN terminals become hosts entries. Cosmetic selectors and
exceptions are preserved separately and are not enabled by the DNS importer.
"""
from __future__ import annotations
import argparse
import json
import re
import struct
from collections import Counter
from pathlib import Path

MAGIC = 0x54524945
VERSION = 2
HEADER_SIZE = 16
HOST_RE = re.compile(
    r"(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)"
    r"(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.?$"
)
TRIE_FILES = (
    "builtin_adguard_dns.trie",
    "builtin_adguard_mobile.trie",
    "builtin_yoyo_adservers.trie",
    "builtin_cn_domestic.trie",
)
LICENSE = """# Bundled source: Yulong Ad Plugin 7.0.1 built-in rule tries.
# Decoder format: pass-with-high-score/blockads-tunnel trie.go (TRIE v2).
# AdGuard DNS/Mobile and AdGuard China: AdGuard Team, GPL-3.0.
# Peter Lowe's ad server list: CC BY-NC-SA 4.0.
# Mainland curated set includes anti-AD (GPL-3.0), EasyList China
# (CC BY-SA 3.0 / GPL-3.0), ADgk (GPL-3.0), and AdGuard Chinese filter (GPL-3.0).
# Domain-only export: ABP cosmetic selectors and exceptions are not widened.
"""

def decode_trie(path: Path):
    data = path.read_bytes()
    if len(data) < HEADER_SIZE:
        raise ValueError(f"{path.name}: file shorter than TRIE header")
    magic, version, expected_nodes, expected_rules = struct.unpack_from(">IIII", data, 0)
    if magic != MAGIC or version != VERSION:
        raise ValueError(f"{path.name}: invalid TRIE header magic={magic:08x} version={version}")
    if expected_nodes <= 0 or expected_nodes > 5_000_000 or expected_rules > 2_000_000:
        raise ValueError(f"{path.name}: implausible header counts")

    parsed = {}
    indegree = Counter()

    def node(off: int):
        if off < HEADER_SIZE or off + 5 > len(data):
            raise ValueError(f"{path.name}: node offset out of range: {off}")
        if off in parsed:
            return parsed[off]
        terminal = data[off] != 0
        child_count = struct.unpack_from(">I", data, off + 1)[0]
        if child_count > expected_nodes:
            raise ValueError(f"{path.name}: child count too large at {off}")
        pos = off + 5
        children = []
        for _ in range(child_count):
            if pos + 2 > len(data):
                raise ValueError(f"{path.name}: truncated child label length")
            label_len = struct.unpack_from(">H", data, pos)[0]
            pos += 2
            if label_len == 0 or pos + label_len + 4 > len(data):
                raise ValueError(f"{path.name}: invalid child label at {pos}")
            raw = data[pos:pos + label_len]
            pos += label_len
            label = raw.decode("utf-8")
            child_off = struct.unpack_from(">I", data, pos)[0]
            pos += 4
            if child_off < HEADER_SIZE or child_off + 5 > len(data):
                raise ValueError(f"{path.name}: child offset out of range")
            indegree[child_off] += 1
            children.append((label, child_off))
        parsed[off] = (terminal, children)
        return parsed[off]

    root = node(HEADER_SIZE)
    if indegree[HEADER_SIZE]:
        raise ValueError(f"{path.name}: root node is referenced by a child")
    terminals = []
    visiting = set()
    visited = set()

    def walk(off: int, labels: list[str]):
        if off in visiting:
            raise ValueError(f"{path.name}: cyclic trie at offset {off}")
        if off in visited:
            raise ValueError(f"{path.name}: shared node {off}; trie is not a tree")
        visiting.add(off)
        visited.add(off)
        terminal, children = node(off)
        if terminal:
            terminals.append(".".join(reversed(labels)))
        for label, child_off in children:
            walk(child_off, labels + [label])
        visiting.remove(off)

    walk(HEADER_SIZE, [])
    if len(visited) != expected_nodes:
        raise ValueError(f"{path.name}: node count header={expected_nodes}, decoded={len(visited)}")
    if len(terminals) != expected_rules:
        raise ValueError(f"{path.name}: terminal count header={expected_rules}, decoded={len(terminals)}")
    return terminals, {"bytes": len(data), "nodes": len(visited), "terminals": len(terminals)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("assets", type=Path, help="extracted 7.0.1 assets directory")
    ap.add_argument("output", type=Path, help="FX rulefiles/Yulong_AdBlock.txt")
    ap.add_argument("--cosmetic-output", type=Path, required=True)
    ap.add_argument("--report", type=Path, required=True)
    args = ap.parse_args()
    if not args.assets.is_dir():
        raise SystemExit(f"assets directory does not exist: {args.assets}")

    per_file = {}
    hosts = set()
    cosmetic = set()
    invalid = Counter()
    total = 0
    for name in TRIE_FILES:
        path = args.assets / name
        if not path.is_file():
            raise SystemExit(f"required trie is missing: {path}")
        entries, stats = decode_trie(path)
        total += len(entries)
        file_hosts = set()
        file_cosmetic = set()
        for entry in entries:
            value = entry.strip()
            if "##" in value or "#@#" in value or "#?#" in value:
                file_cosmetic.add(value)
                continue
            domain = value.rstrip(".").lower()
            if HOST_RE.fullmatch(domain) and "." in domain and ".." not in domain:
                file_hosts.add(domain)
            else:
                invalid[name] += 1
        hosts.update(file_hosts)
        cosmetic.update(file_cosmetic)
        per_file[name] = {
            **stats,
            "valid_dns_hosts": len(file_hosts),
            "cosmetic_and_exception_rules": len(file_cosmetic),
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        f.write(LICENSE)
        f.write(f"# Decoded terminals: {total}; unique validated DNS domains: {len(hosts)}.\n")
        f.write("# DNS-safe hosts entries only; no cosmetic selectors widened into host blocks.\n")
        for domain in sorted(hosts):
            f.write(f"0.0.0.0 {domain}\n")
    tmp.replace(args.output)

    args.cosmetic_output.parent.mkdir(parents=True, exist_ok=True)
    ctmp = args.cosmetic_output.with_suffix(args.cosmetic_output.suffix + ".tmp")
    with ctmp.open("w", encoding="utf-8", newline="\n") as f:
        f.write("! Preserved rules from Yulong Ad Plugin 7.0.1 / AdGuard Mobile trie.\n")
        f.write("! Not activated by DNS/hosts importer; use only after a reviewed cosmetic parser.\n")
        for rule in sorted(cosmetic):
            f.write(rule + "\n")
    ctmp.replace(args.cosmetic_output)

    report = {
        "format": "TRIE v2",
        "asset_count": len(TRIE_FILES),
        "decoded_terminals": total,
        "unique_valid_dns_domains": len(hosts),
        "preserved_cosmetic_rules": len(cosmetic),
        "rejected_non_dns_terminals": dict(invalid),
        "files": per_file,
        "output": str(args.output),
        "cosmetic_output": str(args.cosmetic_output),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
