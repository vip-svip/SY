#!/usr/bin/env python3
"""Assert the PAC compiler outputs for the synthetic CI fixture."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: fx-pac-profile-report-check.py <routing.json> <report.json>",
              file=sys.stderr)
        return 2
    routing = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    report = json.loads(Path(argv[2]).read_text(encoding="utf-8"))

    problems: list[str] = []
    rules = routing.get("rules") or []
    if len(rules) != 2:
        problems.append(f"expected 2 rules, got {len(rules)}")
    else:
        if rules[0]["match"] != {"type": "domain_suffix", "value": "corp.example"}:
            problems.append(f"unexpected first rule: {rules[0]['match']!r}")
        if rules[0]["proxies"][0] != {"type": "PROXY", "host": "10.0.0.5", "port": 8080}:
            problems.append(f"unexpected first chain: {rules[0]['proxies']!r}")
        if rules[1]["match"] != {"type": "cidr", "value": "10.20.0.0/16"}:
            problems.append(f"unexpected second rule: {rules[1]['match']!r}")
    if routing.get("default") != [{"type": "DIRECT", "host": None, "port": None}]:
        problems.append(f"unexpected default route: {routing.get('default')!r}")
    if report.get("conflicts", {}).get("count") != 0:
        problems.append(f"unexpected conflicts: {report.get('conflicts')!r}")
    if report.get("has_default") is not True:
        problems.append("report does not record the default route")
    if not routing.get("order", "").startswith("first match wins"):
        problems.append(f"routing order is not documented: {routing.get('order')!r}")

    if problems:
        for problem in problems:
            print(f"::error::{problem}", file=sys.stderr)
        return 1
    print("PAC compiler outputs are correct")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
