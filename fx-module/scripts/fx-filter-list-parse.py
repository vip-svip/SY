#!/usr/bin/env python3
"""Parse AdGuard / uBlock Origin / Adblock Plus filter lists into FX DNS streams.

FX keeps five separate Ad layers, and only the DNS/Hosts layers can be fed from
a third-party blocklist. Widening a filter list into hosts entries is only sound
for rules that are provably domain scoped, so this parser refuses to guess:

* ``||example.com^`` becomes a blocked domain (subdomains follow at DNS level);
* ``@@||example.com^`` becomes an allowed domain;
* cosmetic rules (``##`` / ``#@#`` / ``#$#`` / ``#?#`` / ``#%#``) are preserved
  verbatim in their own stream and are never enabled by the DNS importer;
* hosts-format rows (``0.0.0.0 domain``) are accepted as blocked domains;
* every other rule shape - substring rules, regex rules, ``$`` option sets,
  ``|http://`` URL anchors, wildcards in the middle of a host - is reported as
  unsupported with a reason instead of being silently turned into a domain.

Requirement G asks for parse, validate and conflict-check to be verifiable
separately, so blocked domains, allowed domains, cosmetic rules and the report
are four distinct artifacts, written atomically and deterministically.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from collections import Counter
from pathlib import Path

MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_LINE_BYTES = 8192
MAX_DOMAIN_LENGTH = 253
MAX_LABEL_LENGTH = 63
MAX_REPORTED_SAMPLES = 25

# Cosmetic markers, longest first so "#@$#" is not read as "#$#".
COSMETIC_MARKERS = ("#@$#", "#@?#", "#@%#", "#@#", "#$#", "#?#", "#%#", "##")
HOSTS_PREFIXES = ("0.0.0.0", "127.0.0.1", "::1", "::")
LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
PUNYCODE_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
IPV4_LIKE = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")


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


def normalize_domain(value: str) -> tuple[str | None, str | None]:
    """Return (domain, None) when DNS safe, else (None, reason)."""
    candidate = value.strip().strip(".").lower()
    if not candidate:
        return None, "empty domain"
    if len(candidate) > MAX_DOMAIN_LENGTH:
        return None, "domain longer than 253 bytes"
    if IPV4_LIKE.fullmatch(candidate) or ":" in candidate:
        return None, "IP literal, not a DNS-blockable domain"
    if "*" in candidate:
        return None, "wildcard outside the leading label; DNS cannot express it"
    labels = candidate.split(".")
    if len(labels) < 2:
        return None, "single-label host; DNS blocking would need a search list"
    for label in labels:
        if len(label) > MAX_LABEL_LENGTH:
            return None, "label longer than 63 bytes"
        if not LABEL.fullmatch(label):
            return None, "invalid DNS label"
    tld = labels[-1]
    if tld.startswith("xn--"):
        if len(tld) <= 4 or not PUNYCODE_LABEL.fullmatch(tld):
            return None, "invalid punycode TLD"
    elif tld.isdigit() or len(tld) < 2:
        return None, "implausible TLD"
    return candidate, None


def strip_leading_wildcard(host: str) -> str:
    while host.startswith("*."):
        host = host[2:]
    return host


def parse_network_rule(body: str) -> tuple[str | None, str | None]:
    """Parse the body of a ``||``-anchored rule into a domain or a reason."""
    if "$" in body:
        # AdGuard/ABP options change matching semantics ($third-party, $important,
        # $dnstype, ...). A DNS layer cannot honour them, so the rule is reported
        # instead of being applied with different meaning. This must be checked
        # before the anchor is truncated, because the options sit after the "^".
        return None, "option set ($) is not expressible at the DNS layer"
    host = body
    for stopper in ("^", "|", "/"):
        index = host.find(stopper)
        if index >= 0:
            host = host[:index]
    host = strip_leading_wildcard(host.strip())
    if not host:
        return None, "empty anchor"
    return normalize_domain(host)


def classify(line: str) -> tuple[str, str | None, str | None]:
    """Classify one raw line.

    Returns (kind, payload, reason) where kind is one of:
    skip, block, allow, cosmetic, unsupported.
    """
    text = line.strip()
    if not text:
        return "skip", None, None
    if text.startswith("!"):
        return "skip", None, None
    if text.startswith("[") and text.endswith("]"):
        return "skip", None, None
    if text.startswith("#"):
        # Hosts-file comment. ABP comments use "!";
        # "##" is already caught by the cosmetic branch below, so a leading "#"
        # here can only be a comment.
        if not any(marker in text for marker in COSMETIC_MARKERS):
            return "skip", None, None
    for marker in COSMETIC_MARKERS:
        if marker in text:
            return "cosmetic", text, None
    tokens = text.split()
    if len(tokens) >= 2 and tokens[0] in HOSTS_PREFIXES:
        domain, reason = normalize_domain(tokens[1])
        if domain is None:
            return "unsupported", text, reason
        return "block", domain, None
    if text.startswith("@@"):
        body = text[2:]
        if not body.startswith("||"):
            return "unsupported", text, "exception is not a domain anchor"
        domain, reason = parse_network_rule(body[2:])
        if domain is None:
            return "unsupported", text, reason
        return "allow", domain, None
    if text.startswith("||"):
        domain, reason = parse_network_rule(text[2:])
        if domain is None:
            return "unsupported", text, reason
        return "block", domain, None
    if text.startswith("/") or text.endswith("/"):
        return "unsupported", text, "regular-expression rule is not a domain"
    if text.startswith("|"):
        return "unsupported", text, "URL-anchored rule is not a domain"
    if "*" in text or "/" in text:
        return "unsupported", text, "substring or path rule is not a domain"
    # A bare token could be a domain, but in ABP a bare line is a substring match.
    return "unsupported", text, "substring rule is not a domain; DNS widening refused"


def read_source(path: Path) -> list[str]:
    reject_symlink_components(path)
    if not path.is_file():
        raise ValueError(f"{path}: filter list is not a regular file")
    size = path.stat().st_size
    if size == 0:
        raise ValueError(f"{path}: filter list is empty")
    if size > MAX_FILE_BYTES:
        raise ValueError(f"{path}: filter list larger than 64 MiB")
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{path}: filter list is not valid UTF-8 ({error})") from error
    return text.splitlines()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=Path, help="filter list files to merge")
    parser.add_argument("--block-hosts", required=True, type=Path,
                        help="hosts-format output, '0.0.0.0 domain' per line")
    parser.add_argument("--block-rules", required=True, type=Path,
                        help="AdGuard Home block syntax, '||domain^' per line")
    parser.add_argument("--allow-rules", required=True, type=Path,
                        help="AdGuard Home allow syntax, '@@||domain^' per line")
    parser.add_argument("--cosmetic-output", required=True, type=Path,
                        help="cosmetic selectors preserved verbatim")
    parser.add_argument("--report", required=True, type=Path,
                        help="JSON report with counts, conflicts and reasons")
    parser.add_argument("--fail-on-unsupported", action="store_true",
                        help="exit non-zero when any rule could not be expressed at the DNS layer")
    args = parser.parse_args()

    outputs = [args.block_hosts, args.block_rules, args.allow_rules,
               args.cosmetic_output, args.report]
    resolved = [os.path.abspath(os.fspath(p)) for p in outputs]
    if len(set(resolved)) != len(resolved):
        raise SystemExit("output paths must all be distinct")

    blocked: set[str] = set()
    allowed: set[str] = set()
    cosmetic: set[str] = set()
    unsupported: list[dict[str, str]] = []
    unsupported_reasons: Counter[str] = Counter()
    per_file: list[dict[str, object]] = []
    total_lines = 0

    for source in args.sources:
        lines = read_source(source)
        counts = Counter()
        for line in lines:
            total_lines += 1
            if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                unsupported.append({"rule": line[:200], "reason": "line longer than 8 KiB"})
                unsupported_reasons["line longer than 8 KiB"] += 1
                counts["unsupported"] += 1
                continue
            kind, payload, reason = classify(line)
            counts[kind] += 1
            if kind == "block":
                blocked.add(payload)  # type: ignore[arg-type]
            elif kind == "allow":
                allowed.add(payload)  # type: ignore[arg-type]
            elif kind == "cosmetic":
                cosmetic.add(payload)  # type: ignore[arg-type]
            elif kind == "unsupported":
                unsupported_reasons[reason] += 1
                if len(unsupported) < 5000:
                    unsupported.append({"rule": payload, "reason": reason})
        per_file.append({"file": str(source), "lines": len(lines), **counts})

    # Conflict check: an allowed domain must never also be blocked. The allow
    # entry wins because the user's exception is the more specific intent.
    conflicts = sorted(blocked & allowed)
    for domain in conflicts:
        blocked.discard(domain)

    block_rules = sorted(blocked)
    allow_rules = sorted(allowed)
    cosmetic_rules = sorted(cosmetic)

    atomic_write_text(args.block_hosts, lambda stream: _write_hosts(stream, block_rules))
    atomic_write_text(args.block_rules,
                      lambda stream: _write_lines(stream, [f"||{d}^" for d in block_rules]))
    atomic_write_text(args.allow_rules,
                      lambda stream: _write_lines(stream, [f"@@||{d}^" for d in allow_rules]))
    atomic_write_text(args.cosmetic_output,
                      lambda stream: _write_lines(stream, cosmetic_rules))

    report = {
        "sources": per_file,
        "total_lines": total_lines,
        "blocked_domains": len(block_rules),
        "allowed_domains": len(allow_rules),
        "cosmetic_rules": len(cosmetic_rules),
        "unsupported_rules": len(unsupported),
        "conflicts": {
            "count": len(conflicts),
            "resolution": "allow wins; the domain is removed from the block stream",
            "domains": conflicts[:MAX_REPORTED_SAMPLES],
        },
        "unsupported_reasons": dict(sorted(unsupported_reasons.items())),
        "unsupported_samples": unsupported[:MAX_REPORTED_SAMPLES],
        "outputs": {
            "block_hosts": os.path.abspath(os.fspath(args.block_hosts)),
            "block_rules": os.path.abspath(os.fspath(args.block_rules)),
            "allow_rules": os.path.abspath(os.fspath(args.allow_rules)),
            "cosmetic": os.path.abspath(os.fspath(args.cosmetic_output)),
        },
    }
    atomic_write_text(
        args.report,
        lambda stream: stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n"),
    )

    print(
        f"parsed {len(per_file)} list(s), {total_lines} lines: "
        f"{len(block_rules)} blocked, {len(allow_rules)} allowed, "
        f"{len(cosmetic_rules)} cosmetic, {len(unsupported)} unsupported, "
        f"{len(conflicts)} conflict(s) resolved by the allow stream"
    )
    if args.fail_on_unsupported and unsupported:
        print("::error::filter list contains rules that cannot be expressed at the DNS layer",
              file=sys.stderr)
        return 2
    return 0


def _write_lines(stream, lines: list[str]) -> None:
    for line in lines:
        stream.write(line + "\n")


def _write_hosts(stream, domains: list[str]) -> None:
    stream.write("# Generated by scripts/fx-filter-list-parse.py - do not edit by hand\n")
    _write_lines(stream, [f"0.0.0.0 {domain}" for domain in domains])


if __name__ == "__main__":
    sys.exit(main())
