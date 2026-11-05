#!/usr/bin/env python3
"""Assert the filter-list parser report shape for the synthetic CI fixture.

Kept as a file (not an inline heredoc) so the workflow stays a plain block
scalar and the JSON expectations are themselves reviewable code.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

EXPECTED = {
    "blocked_domains": 1,
    "allowed_domains": 1,
    "cosmetic_rules": 1,
    "unsupported_rules": 1,
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: fx-filter-list-parse-report-check.py <report.json>", file=sys.stderr)
        return 2
    report = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    problems: list[str] = []
    for key, expected in EXPECTED.items():
        actual = report.get(key)
        if actual != expected:
            problems.append(f"{key}: expected {expected}, got {actual!r}")
    if report.get("conflicts", {}).get("count") != 0:
        problems.append(f"unexpected conflicts: {report.get('conflicts')!r}")
    reasons = report.get("unsupported_reasons") or {}
    if not any("option set" in reason for reason in reasons):
        problems.append(f"the option-set refusal reason is missing: {reasons!r}")
    if problems:
        for problem in problems:
            print(f"::error::{problem}", file=sys.stderr)
        return 1
    print("parser report shape is correct")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
