#!/usr/bin/env python3
"""Decode Yulong Ad Plugin 7.0.1 native TRIE v2 assets into safe FX DNS rules.

Only validated FQDN terminals become hosts entries. Cosmetic selectors and
exceptions are preserved separately and are not enabled by the DNS importer.
"""
from __future__ import annotations
import argparse
import json
import ipaddress
import os
import re
import struct
import tempfile
from collections import Counter
from pathlib import Path

MAGIC = 0x54524945
VERSION = 2
HEADER_SIZE = 16
BLOOM_MAGIC = 0x424C4F4D
BLOOM_VERSION = 1
BLOOM_HEADER_SIZE = 8
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

def reject_symlink_components(path: Path) -> Path:
    """Return an absolute lexical path after rejecting symlinked components."""
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = absolute
    while True:
        if current.is_symlink():
            raise ValueError(f"{path}: symlinked path component rejected: {current}")
        if current.parent == current:
            break
        current = current.parent
    return absolute


def validate_output_target(path: Path) -> Path:
    target = reject_symlink_components(path)
    parent = target.parent
    parent.mkdir(parents=True, exist_ok=True)
    target = reject_symlink_components(target)
    if target.exists() and not target.is_file():
        raise ValueError(f"{target}: output exists but is not a regular file")
    return target


def atomic_write_text(path: Path, writer) -> None:
    """Write UTF-8 output through a random same-directory file and atomic replace."""
    target = validate_output_target(path)
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{target.name}.fx-", suffix=".tmp", dir=os.fspath(target.parent)
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            writer(stream)
            stream.flush()
            os.fsync(stream.fileno())
        # The temporary file is unique and exclusive. Re-check the destination
        # path immediately before replace; os.replace replaces a link itself but
        # never writes through its target.
        reject_symlink_components(target.parent)
        if target.is_symlink():
            raise ValueError(f"{target}: output became a symlink during generation")
        if target.exists() and not target.is_file():
            raise ValueError(f"{target}: output changed to a non-regular file")
        os.chmod(temp_path, 0o644)
        os.replace(temp_path, target)
        try:
            dir_fd = os.open(target.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            # Some host filesystems do not support directory fsync.
            pass
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


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

def validate_bloom(path: Path):
    """Validate the paired BLOOM v1 header used by Yulong's native engine.

    The original 7.0.1 BuiltinRuleSource checks both files independently:
    TRIE_MAGIC/TRIE_VERSION for .trie and BLOOM_MAGIC/BLOOM_VERSION for
    .bloom. Its hasHeader() reads the first eight bytes as two big-endian
    integers. Keep the binary payload opaque; FX exports only the DNS-safe
    terminals decoded from the paired TRIE.
    """
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"{path.name}: paired Bloom asset is missing or is a symlink")
    size = path.stat().st_size
    if size < BLOOM_HEADER_SIZE:
        raise ValueError(f"{path.name}: file shorter than BLOOM header")
    with path.open("rb") as stream:
        header = stream.read(BLOOM_HEADER_SIZE)
    if len(header) != BLOOM_HEADER_SIZE:
        raise ValueError(f"{path.name}: truncated BLOOM header")
    magic, version = struct.unpack(">II", header)
    if magic != BLOOM_MAGIC or version != BLOOM_VERSION:
        raise ValueError(
            f"{path.name}: invalid BLOOM header magic={magic:08x} version={version}"
        )
    return {
        "bytes": size,
        "magic": f"0x{magic:08x}",
        "version": version,
        "header_bytes": BLOOM_HEADER_SIZE,
    }


def normalize_dns_terminal(value: str):
    """Return a DNS-safe hostname and whether an ABP separator was normalized.

    Only a complete hostname, optionally written as an ABP domain anchor
    (||host^) or a plain host with one trailing separator (^), is eligible.
    URL-start anchors, paths, wildcard labels, modifiers and IP literals are
    deliberately not widened into whole-domain DNS blocks.
    """
    token = value.strip().lower()
    if not token:
        return None

    is_domain_anchor = token.startswith("||")
    if is_domain_anchor:
        token = token[2:]
    elif token.startswith("|"):
        return None

    had_separator = token.endswith("^")
    # ||host without a terminating separator can also match non-host suffixes;
    # do not broaden it to a whole DNS suffix.
    if is_domain_anchor and not had_separator:
        return None
    if had_separator:
        token = token[:-1]

    # HOST_RE allows at most one optional terminal dot. Check before stripping
    # it so malformed multiple-dot inputs cannot be silently normalized.
    if not HOST_RE.fullmatch(token) or "." not in token or ".." in token:
        return None
    domain = token[:-1] if token.endswith(".") else token
    if not domain:
        return None
    try:
        ipaddress.ip_address(domain)
        return None
    except ValueError:
        pass
    return domain, had_separator


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("assets", type=Path, help="extracted 7.0.1 assets directory")
    ap.add_argument("output", type=Path, help="FX rulefiles/Yulong_AdBlock.txt")
    ap.add_argument("--cosmetic-output", type=Path, required=True)
    ap.add_argument("--review-output", type=Path, required=True,
                    help="preserved non-DNS terminals; never activated automatically")
    ap.add_argument("--report", type=Path, required=True)
    args = ap.parse_args()
    if not args.assets.is_dir():
        raise SystemExit(f"assets directory does not exist: {args.assets}")

    per_file = {}
    hosts = set()
    cosmetic = set()
    review = set()
    invalid = Counter()
    normalized_separator_total = 0
    total = 0
    for name in TRIE_FILES:
        path = args.assets / name
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f"required trie is missing or is a symlink: {path}")
        bloom_path = path.with_suffix(".bloom")
        try:
            bloom_stats = validate_bloom(bloom_path)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        entries, stats = decode_trie(path)
        total += len(entries)
        file_hosts = set()
        file_cosmetic = set()
        file_review = set()
        file_normalized_separator_count = 0
        for entry in entries:
            value = entry.strip()
            if any(marker in value for marker in ("##", "#@#", "#?#", "#$#", "#%#")):
                file_cosmetic.add(value)
                continue
            normalized = normalize_dns_terminal(value)
            if normalized is None:
                file_review.add(value)
                invalid[name] += 1
                continue
            domain, had_separator = normalized
            file_hosts.add(domain)
            if had_separator:
                file_normalized_separator_count += 1
        hosts.update(file_hosts)
        cosmetic.update(file_cosmetic)
        review.update((name, value) for value in file_review)
        normalized_separator_total += file_normalized_separator_count
        per_file[name] = {
            **stats,
            "bloom": bloom_stats,
            "valid_dns_hosts": len(file_hosts),
            "normalized_separator_terminals": file_normalized_separator_count,
            "cosmetic_and_exception_rules": len(file_cosmetic),
            "preserved_review_terminals": len(file_review),
        }

    output_paths = [args.output, args.cosmetic_output, args.review_output, args.report]
    absolute_outputs = [Path(os.path.abspath(os.fspath(path))) for path in output_paths]
    if len(set(absolute_outputs)) != len(absolute_outputs):
        raise SystemExit("DNS, cosmetic, review and report output paths must be distinct")
    source_assets = set()
    for name in TRIE_FILES:
        trie_path = args.assets / name
        source_assets.add(Path(os.path.abspath(os.fspath(trie_path))))
        source_assets.add(Path(os.path.abspath(os.fspath(trie_path.with_suffix(".bloom")))))
    if set(absolute_outputs) & source_assets:
        raise SystemExit("decoder output must not overwrite a source TRIE/BLOOM asset")
    try:
        output_path = validate_output_target(args.output)
        cosmetic_path = validate_output_target(args.cosmetic_output)
        review_path = validate_output_target(args.review_output)
        report_path = validate_output_target(args.report)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    def write_rules(stream):
        stream.write(LICENSE)
        stream.write(f"# Decoded terminals: {total}; unique validated DNS domains: {len(hosts)}.\n")
        stream.write("# DNS-safe hosts entries only; no cosmetic selectors widened into host blocks.\n")
        for domain in sorted(hosts):
            stream.write(f"0.0.0.0 {domain}\n")

    def write_cosmetic(stream):
        stream.write("! Preserved rules from Yulong Ad Plugin 7.0.1 / AdGuard Mobile trie.\n")
        stream.write("! Not activated by DNS/hosts importer; use only after a reviewed cosmetic parser.\n")
        for rule in sorted(cosmetic):
            stream.write(rule + "\n")

    report = {
        "format": "TRIE v2 + BLOOM v1",
        "trie_asset_count": len(TRIE_FILES),
        "bloom_asset_count": len(TRIE_FILES),
        "decoded_terminals": total,
        "unique_valid_dns_domains": len(hosts),
        "normalized_separator_terminals": normalized_separator_total,
        "preserved_cosmetic_rules": len(cosmetic),
        "preserved_review_terminal_count": len(review),
        "rejected_non_dns_terminals": dict(invalid),
        "files": per_file,
        "output": str(args.output),
        "cosmetic_output": str(args.cosmetic_output),
        "review_output": str(args.review_output),
    }

    atomic_write_text(output_path, write_rules)
    atomic_write_text(cosmetic_path, write_cosmetic)

    def write_review(stream):
        stream.write("# Preserved Yulong 7.0.1 terminals that are not safe DNS host rules.\n")
        stream.write("# Review/format migration only; never loaded automatically by DNS or Hosts.\n")
        stream.write("# JSONL records preserve source trie and exact original terminal.\n")
        for source, value in sorted(review):
            stream.write(json.dumps({"source": source, "terminal": value}, ensure_ascii=False) + "\n")

    atomic_write_text(review_path, write_review)
    atomic_write_text(
        report_path,
        lambda stream: stream.write(json.dumps(report, ensure_ascii=False, indent=2) + "\n"),
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
