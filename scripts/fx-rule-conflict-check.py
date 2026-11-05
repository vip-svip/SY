#!/usr/bin/env python3
"""Cross-check Hosts / Adblock / PAC rule sources for contradictions.

Requirement G of the FX 1.0.0 handoff asks each rule format to have its own
parser, validator *and* conflict check. Each format now has a parser, but a
device can carry all three at once, and they can contradict each other:

* a domain blocked at the Hosts/DNS layer but routed through a proxy by PAC -
  the proxy path can never be exercised, so the operator's proxy rule silently
  never applies;
* a domain that is both blocked and allowed across the sources;
* a blocked subdomain covered by a broader allow rule;
* a PAC rule that is unreachable because an earlier rule already matched it.

Those are only detectable by reading all three sources together, so this script
is the join. It never edits or rewrites the sources: it reports findings with a
severity, and the exit code is a gate.

Ordering rules are format specific and are honoured as such: PAC is first-match
wins, AdGuard Home allow rules are more specific than a block rule, and Hosts has
no ordering at all.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import sys
import tempfile
from pathlib import Path

MAX_LINE_BYTES = 8192
MAX_FINDINGS = 20000
MAX_REPORTED_SAMPLES = 50

HOSTS_PREFIXES = ("0.0.0.0", "127.0.0.1", "::1", "::")
LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
IPV4 = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")

SEVERITY_ORDER = {"error": 3, "warning": 2, "info": 1}


class SourceError(Exception):
    """A source could not be read or parsed; the check must not guess."""


def reject_symlink_components(path: Path) -> Path:
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
            pass
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


def normalize_domain(value: str) -> str:
    candidate = value.strip().strip(".").lower()
    if not candidate:
        raise SourceError("empty domain")
    if len(candidate) > 253:
        raise SourceError(f"domain longer than 253 bytes: {candidate[:40]}")
    if IPV4.match(candidate) or ":" in candidate:
        raise SourceError(f"IP literal is not a Hosts domain: {candidate}")
    labels = candidate.split(".")
    if len(labels) < 2:
        raise SourceError(f"single-label host is not routable: {candidate}")
    for label in labels:
        if not LABEL.match(label):
            raise SourceError(f"invalid DNS label in {candidate}")
    return candidate


def read_lines(path: Path) -> list[str]:
    reject_symlink_components(path)
    if not path.is_file():
        raise SourceError(f"{path}: not a regular file")
    if path.stat().st_size == 0:
        raise SourceError(f"{path}: file is empty")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise SourceError(f"{path}: not valid UTF-8 ({error})") from error
    return text.splitlines()


def parse_hosts(paths: list[Path]) -> dict[str, list[str]]:
    """Return {domain: [source, ...]} for a Hosts layer."""
    found: dict[str, list[str]] = {}
    for path in paths:
        for number, raw in enumerate(read_lines(path), start=1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                raise SourceError(f"{path}:{number}: line longer than 8 KiB")
            if line.startswith("!"):
                continue
            tokens = line.split()
            if len(tokens) >= 2 and tokens[0] in HOSTS_PREFIXES:
                # A Hosts row may carry several hostnames for one address; every
                # one of them is blocked, so all of them must be read.
                for token in tokens[1:]:
                    domain = normalize_domain(token)
                    found.setdefault(domain, []).append(f"{path.name}:{number}")
                continue
            if len(tokens) == 1:
                domain = normalize_domain(tokens[0])
            else:
                raise SourceError(f"{path}:{number}: unsupported Hosts row {line[:80]!r}")
            found.setdefault(domain, []).append(f"{path.name}:{number}")
    return found


def parse_adblock(paths: list[Path], *, allow: bool) -> dict[str, list[str]]:
    """Parse AdGuard Home style ``||d^`` / ``@@||d^`` rows."""
    found: dict[str, list[str]] = {}
    prefix = "@@||" if allow else "||"
    for path in paths:
        for number, raw in enumerate(read_lines(path), start=1):
            line = raw.strip()
            if not line or line.startswith(("!", "#", "[")):
                continue
            if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                raise SourceError(f"{path}:{number}: line longer than 8 KiB")
            if not line.startswith(prefix):
                raise SourceError(
                    f"{path}:{number}: expected a {'@@||' if allow else '||'} rule, got {line[:60]!r}"
                )
            body = line[len(prefix):]
            if not body.endswith("^"):
                raise SourceError(f"{path}:{number}: rule needs a trailing '^': {line[:60]!r}")
            found.setdefault(normalize_domain(body[:-1]), []).append(f"{path.name}:{number}")
    return found


def parse_pac(path: Path) -> list[dict]:
    reject_symlink_components(path)
    if not path.is_file():
        raise SourceError(f"{path}: PAC routing table is not a regular file")
    try:
        table = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SourceError(f"{path}: PAC routing table is not readable JSON ({error})") from error
    rules = table.get("rules")
    if not isinstance(rules, list):
        raise SourceError(f"{path}: PAC routing table has no rules array")
    for index, rule in enumerate(rules):
        match = rule.get("match") or {}
        if match.get("type") not in ("domain_suffix", "host_exact", "cidr", "default"):
            raise SourceError(f"{path}: rule {index} has an unknown match type {match.get('type')!r}")
        if not isinstance(rule.get("proxies"), list) or not rule["proxies"]:
            raise SourceError(f"{path}: rule {index} has no proxy chain")
    return rules


def rule_matches(match: dict, host: str) -> bool | None:
    """Return True/False, or None when the rule cannot be decided statically."""
    kind = match.get("type")
    value = match.get("value")
    if kind == "domain_suffix":
        return host == value or host.endswith("." + str(value))
    if kind == "host_exact":
        return host == value
    if kind == "default":
        return True
    if kind == "cidr":
        try:
            address = ipaddress.IPv4Address(host)
        except ValueError:
            return None  # needs live DNS; cannot be decided statically
        return address in ipaddress.IPv4Network(value, strict=False)
    return None


def first_matching_rule(rules: list[dict], host: str) -> dict | None:
    """PAC first-match-wins resolution, with undecidable rules noted."""
    for rule in rules:
        verdict = rule_matches(rule["match"], host)
        if verdict is True:
            return rule
        if verdict is None:
            return {"match": dict(rule["match"]), "proxies": rule["proxies"],
                    "undecidable": True}
    return None


def covers(outer: dict, inner: dict) -> bool:
    """True when *outer* strictly shadows *inner* under PAC first-match rules."""
    o_kind, i_kind = outer.get("type"), inner.get("type")
    if o_kind == "default":
        return True
    if o_kind == "cidr" or i_kind == "cidr":
        return False
    o_val, i_val = str(outer.get("value")), str(inner.get("value"))
    if o_kind == "host_exact":
        return i_kind == "host_exact" and o_val == i_val
    if o_kind == "domain_suffix":
        if i_kind in ("domain_suffix", "host_exact"):
            return i_val == o_val or i_val.endswith("." + o_val)
    return False


def stringify_chain(chain: list[dict]) -> str:
    parts = []
    for entry in chain:
        if entry.get("type") == "DIRECT":
            parts.append("DIRECT")
        else:
            parts.append(f"{entry.get('type')} {entry.get('host')}:{entry.get('port')}")
    return "; ".join(parts) or "(empty)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hosts", action="append", default=[], type=Path,
                        help="Hosts file to check (repeatable)")
    parser.add_argument("--block-rules", action="append", default=[], type=Path,
                        help="AdGuard Home ||domain^ block list (repeatable)")
    parser.add_argument("--allow-rules", action="append", default=[], type=Path,
                        help="AdGuard Home @@||domain^ allow list (repeatable)")
    parser.add_argument("--pac-routing", type=Path,
                        help="routing table JSON produced by scripts/fx-pac-profile.py")
    parser.add_argument("--report", required=True, type=Path, help="JSON report path")
    parser.add_argument("--fail-on", choices=("none", "warning", "error"), default="error",
                        help="exit non-zero at or above this severity")
    args = parser.parse_args()

    if not (args.hosts or args.block_rules or args.allow_rules or args.pac_routing):
        raise SystemExit("at least one rule source is required")

    try:
        dns_blocked = parse_hosts(args.hosts)
        for domain, where in parse_adblock(args.block_rules, allow=False).items():
            dns_blocked.setdefault(domain, []).extend(where)
        dns_allowed = parse_adblock(args.allow_rules, allow=True)
        pac_rules = parse_pac(args.pac_routing) if args.pac_routing else []
    except SourceError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    findings: list[dict] = []

    def add(severity: str, code: str, message: str, **details) -> None:
        if len(findings) >= MAX_FINDINGS:
            return
        findings.append({"severity": severity, "code": code, "message": message, **details})

    # --- 1. A domain must not be both blocked and allowed.
    for domain in sorted(set(dns_blocked) & set(dns_allowed)):
        add("error", "blocked_and_allowed",
            f"{domain} is blocked by {', '.join(sorted(set(dns_blocked[domain])))} "
            f"and allowed by {', '.join(sorted(set(dns_allowed[domain])))}",
            domain=domain)

    # --- 2. A broader allow rule must not be undermined by a narrower block.
    allow_suffixes = sorted(set(dns_allowed))
    for domain in sorted(dns_blocked):
        if domain in dns_allowed:
            continue  # already reported above
        for suffix in allow_suffixes:
            if suffix != domain and domain.endswith("." + suffix):
                add("error", "block_under_allow",
                    f"{domain} is blocked, but the broader allow rule @@||{suffix}^ "
                    f"already permits that namespace",
                    domain=domain, allow_rule=suffix)
                break

    # --- 3. PAC must not route a DNS-blocked domain, and a route must be usable.
    proxy_routed_blocked: list[str] = []
    direct_consistent = 0
    undecidable = 0
    for domain in sorted(dns_blocked):
        if not pac_rules:
            break
        rule = first_matching_rule(pac_rules, domain)
        if rule is None:
            continue
        if rule.get("undecidable"):
            undecidable += 1
            continue
        chain = rule["proxies"]
        if any(entry.get("type") != "DIRECT" for entry in chain):
            proxy_routed_blocked.append(domain)
            add("error", "blocked_domain_is_proxied",
                f"{domain} is blocked at the DNS layer but PAC rule "
                f"'{stringify_chain(chain)}' routes it through a proxy, "
                f"so that proxy route can never be exercised",
                domain=domain, pac_chain=stringify_chain(chain))
        else:
            direct_consistent += 1

    # --- 4. A DNS allow rule cannot exempt a domain PAC sends to a proxy.
    for domain in sorted(dns_allowed):
        if not pac_rules:
            break
        rule = first_matching_rule(pac_rules, domain)
        if rule is None or rule.get("undecidable"):
            continue
        chain = rule["proxies"]
        if any(entry.get("type") != "DIRECT" for entry in chain):
            add("info", "allowed_domain_is_proxied",
                f"{domain} is DNS-allowed but PAC routes it to "
                f"'{stringify_chain(chain)}'; allowing DNS does not bypass the proxy",
                domain=domain, pac_chain=stringify_chain(chain))

    # --- 5. PAC rules shadowed by an earlier rule never apply.
    for index, rule in enumerate(pac_rules):
        for earlier_index in range(index):
            outer = pac_rules[earlier_index]["match"]
            if covers(outer, rule["match"]):
                add("warning", "unreachable_pac_rule",
                    f"PAC rule {index} ({rule['match']['type']} "
                    f"{rule['match'].get('value')!r}) can never match because rule "
                    f"{earlier_index} ({outer['type']} {outer.get('value')!r}) already covers it",
                    rule_index=index, shadowed_by=earlier_index)
                break

    # --- 6. Report what could not be checked, so silence is never mistaken for proof.
    cidr_rules = sum(1 for rule in pac_rules if rule["match"]["type"] == "cidr")
    if cidr_rules and (dns_blocked or dns_allowed):
        add("info", "cidr_needs_live_dns",
            f"{cidr_rules} isInNet rule(s) can only be cross-checked for IP literals; "
            f"domain names would need live DNS resolution",
            cidr_rules=cidr_rules)

    counts: dict[str, int] = {"error": 0, "warning": 0, "info": 0}
    for finding in findings:
        counts[finding["severity"]] += 1

    report = {
        "inputs": {
            "hosts": [os.path.abspath(os.fspath(p)) for p in args.hosts],
            "block_rules": [os.path.abspath(os.fspath(p)) for p in args.block_rules],
            "allow_rules": [os.path.abspath(os.fspath(p)) for p in args.allow_rules],
            "pac_routing": os.path.abspath(os.fspath(args.pac_routing)) if args.pac_routing else None,
        },
        "domains": {
            "blocked": len(dns_blocked),
            "allowed": len(dns_allowed),
        },
        "pac": {
            "rules": len(pac_rules),
            "blocked_domains_with_direct_route": direct_consistent,
            "blocked_domains_with_proxy_route": len(proxy_routed_blocked),
            "undecidable_matches": undecidable,
        },
        "counts": counts,
        "findings": findings[:MAX_REPORTED_SAMPLES],
        "findings_truncated": len(findings) > MAX_REPORTED_SAMPLES,
        "fail_on": args.fail_on,
    }

    atomic_write_text(
        args.report,
        lambda stream: stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n"),
    )

    print(
        f"checked {len(dns_blocked)} blocked and {len(dns_allowed)} allowed domain(s) "
        f"against {len(pac_rules)} PAC rule(s): "
        f"{counts['error']} error(s), {counts['warning']} warning(s), {counts['info']} info"
    )
    for finding in findings[:10]:
        print(f"  [{finding['severity']}] {finding['code']}: {finding['message']}")

    threshold = {"none": 99, "warning": 2, "error": 3}[args.fail_on]
    worst = max((SEVERITY_ORDER[f["severity"]] for f in findings), default=0)
    if worst >= threshold:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
