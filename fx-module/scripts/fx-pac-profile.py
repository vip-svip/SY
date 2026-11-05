#!/usr/bin/env python3
"""Compile a Proxy Auto-Config script into an auditable FX routing table.

Requirement G (FX 1.0.0 handoff, "规则格式") requires a separate parser,
validator and conflict check for PAC alongside Hosts, DNS blocklist and ABP.
FX previously had no PAC support at all: a PAC file given to the device was
never parsed, validated or compiled.

A PAC script is arbitrary JavaScript, so deciding what it does in general is
undecidable. This compiler therefore accepts a **documented declarative
subset** and refuses everything else with a reason instead of guessing:

    function FindProxyForURL(url, host) {
      if (shExpMatch(host, "*.corp.example")) return "PROXY 10.0.0.5:8080; DIRECT";
      if (dnsDomainIs(host, ".internal.example")) return "DIRECT";
      if (isInNet(host, "10.20.0.0", "255.255.0.0")) return "SOCKS5 127.0.0.1:1080";
      if (host == "only.example") return "HTTPS proxy.example:443";
      return "DIRECT";
    }

Supported conditions: ``shExpMatch(host, "*.d")``, ``dnsDomainIs(host, ".d")``,
``isInNet(host, ip, mask)`` and ``host == "h"``. Pacific-northwest semantics are
kept: rules are evaluated in source order and the first match wins, so the
emitted table is order significant and the trailing ``return`` is the default.

Anything that makes the outcome non-deterministic or unauditable -
``eval``, ``Function``, ``importScripts``, ``dnsResolve``, ``myIpAddress``,
``alert``, loops, variable assignment, ``else`` branches, nested blocks,
string concatenation, unsupported conditions - is reported and the compile
fails loudly rather than silently producing a wrong route.

Outputs: a normalised PAC script that re-parses to the identical table, a
routing-table JSON, and a report with counts, defaults filled in and conflicts.
All writes are atomic with symlink rejection.
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

MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_RULES = 5000
MAX_REPORTED_SAMPLES = 25

# Refused constructs, checked before any structural parsing so the reason is
# about the real hazard rather than a downstream syntax complaint.
FORBIDDEN_TOKENS = (
    ("eval", "eval executes its argument; the route cannot be audited"),
    ("Function(", "Function() compiles source at run time"),
    ("new Function", "Function() compiles source at run time"),
    ("importScripts", "remote script import makes the route environment dependent"),
    ("dnsResolve", "dnsResolve performs live DNS; the compiled table must be static"),
    ("myIpAddress", "myIpAddress depends on the host NIC state; the table must be static"),
    ("alert", "alert is a side effect and not a routing decision"),
    ("while", "loops make the route unbounded; use explicit rules"),
    ("for ", "loops make the route unbounded; use explicit rules"),
    ("for(", "loops make the route unbounded; use explicit rules"),
    ("while(", "loops make the route unbounded; use explicit rules"),
)

PROXY_TYPES = {
    "DIRECT": None,
    "PROXY": 80,
    "HTTP": 80,
    "HTTPS": 443,
    "SOCKS": 1080,
    "SOCKS4": 1080,
    "SOCKS5": 1080,
}

COND_SHEXPMATCH = re.compile(r'^shExpMatch\s*\(\s*host\s*,\s*"([^"]*)"\s*\)$')
COND_DNSDOMAINIS = re.compile(r'^dnsDomainIs\s*\(\s*host\s*,\s*"([^"]*)"\s*\)$')
COND_ISINNET = re.compile(r'^isInNet\s*\(\s*host\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)$')
COND_HOST_EQ = re.compile(r'^host\s*===?\s*"([^"]*)"$')
IF_RETURN = re.compile(r'^if\s*\((.*)\)\s*return\s*"([^"]*)"$', re.DOTALL)
PLAIN_RETURN = re.compile(r'^return\s*"([^"]*)"$')

LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


class CompileError(Exception):
    """A refusal: the PAC source cannot be compiled into a sound route table."""


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


def strip_comments(source: str) -> str:
    """Remove // and /* */ comments without touching string literals."""
    out: list[str] = []
    index = 0
    length = len(source)
    in_string: str | None = None
    while index < length:
        char = source[index]
        if in_string is not None:
            out.append(char)
            if char == "\\" and index + 1 < length:
                out.append(source[index + 1])
                index += 2
                continue
            if char == in_string:
                in_string = None
            index += 1
            continue
        if char in ("'", '"'):
            in_string = char
            out.append(char)
            index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "/":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if char == "/" and index + 1 < length and source[index + 1] == "*":
            end = source.find("*/", index + 2)
            index = length if end < 0 else end + 2
            continue
        out.append(char)
        index += 1
    if in_string is not None:
        raise CompileError("unterminated string literal in PAC source")
    return "".join(out)


def code_only(source: str) -> str:
    """Return the source with string literal contents removed.

    Refusal checks must inspect code, not data: a proxy host such as
    ``eval.example`` is a legitimate string, while ``eval(`` is a real hazard.
    """
    out: list[str] = []
    index = 0
    length = len(source)
    in_string: str | None = None
    while index < length:
        char = source[index]
        if in_string is not None:
            if char == "\\" and index + 1 < length:
                index += 2
                continue
            if char == in_string:
                in_string = None
                out.append(char)
            index += 1
            continue
        if char in ("'", '"'):
            in_string = char
            out.append(char)
            index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def extract_function(source: str) -> str:
    """Return the body of FindProxyForURL, refusing a missing definition."""
    match = re.search(r"function\s+FindProxyForURL\s*\(", source)
    if not match:
        raise CompileError("PAC source defines no FindProxyForURL")
    index = match.end() - 1
    depth = 0
    while index < len(source):
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                break
        index += 1
    else:
        raise CompileError("FindProxyForURL parameter list is unterminated")
    index += 1
    while index < len(source) and source[index] in " \t\r\n":
        index += 1
    if index >= len(source) or source[index] != "{":
        raise CompileError("FindProxyForURL has no function body")
    start = index + 1
    depth = 1
    in_string: str | None = None
    index = start
    while index < len(source):
        char = source[index]
        if in_string is not None:
            if char == "\\":
                index += 2
                continue
            if char == in_string:
                in_string = None
        elif char in ("'", '"'):
            in_string = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start:index]
        index += 1
    raise CompileError("FindProxyForURL body is unterminated")


def split_statements(body: str) -> list[str]:
    """Split on ; and newlines while respecting strings and parentheses."""
    statements: list[str] = []
    buffer: list[str] = []
    in_string: str | None = None
    depth = 0
    index = 0
    while index < len(body):
        char = body[index]
        if in_string is not None:
            buffer.append(char)
            if char == "\\" and index + 1 < len(body):
                buffer.append(body[index + 1])
                index += 2
                continue
            if char == in_string:
                in_string = None
            index += 1
            continue
        if char in ("'", '"'):
            in_string = char
            buffer.append(char)
            index += 1
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        if char in ";\n" and depth == 0:
            text = "".join(buffer).strip()
            if text:
                statements.append(text)
            buffer = []
            index += 1
            continue
        buffer.append(char)
        index += 1
    text = "".join(buffer).strip()
    if text:
        statements.append(text)
    return statements


def normalize_domain(value: str, *, allow_ip: bool) -> str:
    candidate = value.strip().strip(".").lower()
    if not candidate:
        raise CompileError("empty domain in PAC condition")
    if len(candidate) > 253:
        raise CompileError(f"domain longer than 253 bytes: {candidate[:40]}")
    ip_like = False
    try:
        ipaddress.IPv4Address(candidate)
        ip_like = True
    except ValueError:
        ip_like = False
    if ip_like:
        if not allow_ip:
            raise CompileError(f"IP literal is not valid in this condition: {candidate}")
        return candidate
    if ":" in candidate:
        raise CompileError(f"IPv6 literal is not supported in the PAC subset: {candidate}")
    labels = candidate.split(".")
    if len(labels) < 2:
        raise CompileError(f"single-label host is not a routable domain: {candidate}")
    for label in labels:
        if not LABEL.match(label):
            raise CompileError(f"invalid DNS label in {candidate}")
    return candidate


def contiguous_prefix(mask: str) -> int:
    """Return the prefix length, refusing a netmask that is not contiguous."""
    try:
        value = int(ipaddress.IPv4Address(mask))
    except ValueError as error:
        raise CompileError(f"invalid netmask {mask!r}: {error}") from error
    inverted = (~value) & 0xFFFFFFFF
    if inverted & (inverted + 1):
        raise CompileError(f"netmask {mask!r} is not contiguous")
    return 32 - inverted.bit_length()


def parse_proxy_chain(raw: str) -> list[dict[str, object]]:
    if not raw.strip():
        raise CompileError("empty proxy directive")
    chain: list[dict[str, object]] = []
    for raw_token in raw.split(";"):
        token = raw_token.strip()
        if not token:
            raise CompileError(f"empty entry in proxy chain {raw!r}")
        parts = token.split()
        if not parts:
            raise CompileError(f"malformed proxy entry {token!r}")
        kind = parts[0].upper()
        if kind not in PROXY_TYPES:
            raise CompileError(f"unsupported proxy type {parts[0]!r}")
        if kind == "DIRECT":
            if len(parts) != 1:
                raise CompileError(f"DIRECT takes no address: {token!r}")
            chain.append({"type": "DIRECT", "host": None, "port": None})
            continue
        if len(parts) != 2:
            raise CompileError(f"{kind} needs exactly one host:port: {token!r}")
        endpoint = parts[1]
        host, port = endpoint, None
        if ":" in endpoint:
            host, _, port_text = endpoint.rpartition(":")
            if not port_text.isdigit():
                raise CompileError(f"non-numeric port in {token!r}")
            port = int(port_text)
            if not 1 <= port <= 65535:
                raise CompileError(f"port out of range in {token!r}")
        if not host or len(host) > 253 or any(c in host for c in " ;/\t"):
            raise CompileError(f"invalid proxy host in {token!r}")
        if port is None:
            port = PROXY_TYPES[kind]
        chain.append({"type": kind, "host": host.lower(), "port": port})
    if not chain:
        raise CompileError("proxy chain resolved to no entry")
    return chain


def parse_condition(condition: str) -> dict[str, object]:
    text = condition.strip()
    match = COND_SHEXPMATCH.match(text)
    if match:
        pattern = match.group(1).strip()
        if "*" not in pattern:
            return {"type": "host_exact", "value": normalize_domain(pattern, allow_ip=True)}
        if not pattern.startswith("*."):
            raise CompileError(f"only a leading '*.' wildcard is supported: {pattern!r}")
        suffix = pattern[2:]
        if "*" in suffix:
            raise CompileError(f"wildcard in the middle of a host is not supported: {pattern!r}")
        return {"type": "domain_suffix", "value": normalize_domain(suffix, allow_ip=False)}
    match = COND_DNSDOMAINIS.match(text)
    if match:
        return {"type": "domain_suffix",
                "value": normalize_domain(match.group(1), allow_ip=False)}
    match = COND_ISINNET.match(text)
    if match:
        base, mask = match.group(1), match.group(2)
        prefix = contiguous_prefix(mask)
        try:
            network = ipaddress.IPv4Network(f"{base}/{prefix}", strict=False)
        except ValueError as error:
            raise CompileError(f"invalid isInNet base {base!r}: {error}") from error
        return {"type": "cidr", "value": str(network)}
    match = COND_HOST_EQ.match(text)
    if match:
        return {"type": "host_exact", "value": normalize_domain(match.group(1), allow_ip=True)}
    raise CompileError(f"unsupported PAC condition: {text[:80]}")


def compile_source(source: str) -> tuple[list[dict], dict[str, object] | None, dict[str, object]]:
    """Return (rules, default_rule, report_fragment)."""
    cleaned = strip_comments(source)
    code = code_only(cleaned)
    lowered = code.lower()
    for token, reason in FORBIDDEN_TOKENS:
        if token.lower() in lowered:
            raise CompileError(f"refused construct {token!r}: {reason}")
    if re.search(r"\belse\b", lowered):
        raise CompileError("else branches are refused; add an explicit trailing return")
    if re.search(r"\b(var|let|const)\b", lowered):
        raise CompileError("variable assignment is refused; the table must be literal")

    body = extract_function(cleaned)
    statements = split_statements(body)
    if not statements:
        raise CompileError("FindProxyForURL body is empty")

    rules: list[dict[str, object]] = []
    default_rule: dict[str, object] | None = None
    for statement in statements:
        if default_rule is not None:
            raise CompileError("a default return must be the final statement")
        match = IF_RETURN.match(statement)
        if match:
            condition = parse_condition(match.group(1))
            chain = parse_proxy_chain(match.group(2))
            if len(rules) >= MAX_RULES:
                raise CompileError(f"more than {MAX_RULES} rules")
            rules.append({"match": condition, "proxies": chain})
            continue
        match = PLAIN_RETURN.match(statement)
        if match:
            chain = parse_proxy_chain(match.group(1))
            default_rule = {"match": {"type": "default", "value": None}, "proxies": chain}
            continue
        raise CompileError(f"unsupported PAC statement: {statement[:100]}")

    if default_rule is None:
        raise CompileError("FindProxyForURL has no default return; unmatched hosts would fall through")

    keys: dict[str, int] = {}
    conflicts: list[dict[str, object]] = []
    for index, rule in enumerate(rules):
        key = json.dumps(rule["match"], sort_keys=True)
        if key in keys:
            conflicts.append({
                "condition": rule["match"],
                "first_index": keys[key],
                "duplicate_index": index,
                "resolution": "the earlier rule wins, matching PAC first-match semantics",
            })
            continue
        keys[key] = index

    report = {
        "rules": len(rules),
        "has_default": True,
        "distinct_conditions": len(keys),
        "conflicts": {"count": len(conflicts), "items": conflicts[:MAX_REPORTED_SAMPLES]},
        "default_chain": [dict(entry) for entry in default_rule["proxies"]],  # type: ignore[index]
    }
    return rules, default_rule, report


def render_pac(rules: list[dict], default_rule: dict) -> str:
    lines = [
        "// Generated by scripts/fx-pac-profile.py",
        "// Declarative subset only; recompiling this file is a no-op.",
        "function FindProxyForURL(url, host) {",
    ]
    for rule in rules:
        lines.append(f"  if ({render_condition(rule['match'])}) return {json.dumps(render_chain(rule['proxies']))};")
    lines.append(f"  return {json.dumps(render_chain(default_rule['proxies']))};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_condition(match: dict) -> str:
    kind = match["type"]
    value = match["value"]
    if kind == "domain_suffix":
        return f'shExpMatch(host, "*.{value}")'
    if kind == "host_exact":
        return f'host == "{value}"'
    if kind == "cidr":
        network = ipaddress.IPv4Network(value, strict=False)
        return f'isInNet(host, "{network.network_address}", "{network.netmask}")'
    raise CompileError(f"cannot render condition type {kind!r}")


def render_chain(chain: list[dict]) -> str:
    tokens = []
    for entry in chain:
        if entry["type"] == "DIRECT":
            tokens.append("DIRECT")
        else:
            tokens.append(f"{entry['type']} {entry['host']}:{entry['port']}")
    return "; ".join(tokens)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="PAC file to compile")
    parser.add_argument("--normalized", required=True, type=Path, help="normalised PAC output")
    parser.add_argument("--routing-json", required=True, type=Path, help="compiled routing table")
    parser.add_argument("--report", required=True, type=Path, help="JSON report")
    args = parser.parse_args()

    paths = [args.normalized, args.routing_json, args.report]
    resolved = [os.path.abspath(os.fspath(p)) for p in paths]
    if len(set(resolved)) != len(resolved):
        raise SystemExit("output paths must all be distinct")

    reject_symlink_components(args.source)
    if not args.source.is_file():
        raise SystemExit(f"{args.source}: PAC source is not a regular file")
    size = args.source.stat().st_size
    if size == 0:
        raise SystemExit(f"{args.source}: PAC source is empty")
    if size > MAX_FILE_BYTES:
        raise SystemExit(f"{args.source}: PAC source larger than 4 MiB")
    try:
        source = args.source.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise SystemExit(f"{args.source}: PAC source is not valid UTF-8 ({error})")

    try:
        rules, default_rule, report_fragment = compile_source(source)
    except CompileError as error:
        print(f"::error::PAC refused: {error}", file=sys.stderr)
        return 1
    assert default_rule is not None

    normalized = render_pac(rules, default_rule)

    # Self-check: the emitted script must compile back to the identical table.
    try:
        again_rules, again_default, _ = compile_source(normalized)
    except CompileError as error:
        raise SystemExit(f"internal error: emitted PAC does not recompile ({error})")
    if again_rules != rules or again_default != default_rule:
        raise SystemExit("internal error: emitted PAC does not round-trip")

    routing = {
        "source": os.path.abspath(os.fspath(args.source)),
        "order": "first match wins, PAC semantics",
        "rules": rules,
        "default": default_rule["proxies"],
    }
    report = {
        "source": os.path.abspath(os.fspath(args.source)),
        "bytes": size,
        **report_fragment,
        "proxy_endpoints": sorted({
            f"{entry['type']} {entry['host']}:{entry['port']}"
            for rule in rules for entry in rule["proxies"] if entry["type"] != "DIRECT"
        } | {
            f"{entry['type']} {entry['host']}:{entry['port']}"
            for entry in default_rule["proxies"] if entry["type"] != "DIRECT"
        }),
        "outputs": {
            "normalized": os.path.abspath(os.fspath(args.normalized)),
            "routing_json": os.path.abspath(os.fspath(args.routing_json)),
        },
    }

    atomic_write_text(args.normalized, lambda stream: stream.write(normalized))
    atomic_write_text(
        args.routing_json,
        lambda stream: stream.write(json.dumps(routing, indent=2, sort_keys=True) + "\n"),
    )
    atomic_write_text(
        args.report,
        lambda stream: stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n"),
    )

    print(
        f"compiled {report['rules']} PAC rule(s), "
        f"{report['distinct_conditions']} distinct condition(s), "
        f"{report['conflicts']['count']} conflict(s), "
        f"{len(report['proxy_endpoints'])} proxy endpoint(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
