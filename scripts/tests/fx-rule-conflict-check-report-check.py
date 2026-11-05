#!/usr/bin/env python3
"""Assert the cross-format conflict report against the synthetic CI fixture."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: fx-rule-conflict-check-report-check.py <report.json>", file=sys.stderr)
        return 2
    report = json.loads(Path(argv[1]).read_text(encoding="utf-8"))

    problems: list[str] = []
    findings = report.get("findings") or []
    proxied = [f for f in findings if f.get("code") == "blocked_domain_is_proxied"]
    if not proxied:
        problems.append(f"the blocked-and-proxied finding is missing: {findings!r}")
    else:
        finding = proxied[0]
        if finding.get("domain") != "proxied.example":
            problems.append(f"unexpected conflicting domain: {finding.get('domain')!r}")
        if finding.get("severity") != "error":
            problems.append(f"severity should be error, got {finding.get('severity')!r}")
        if "10.0.0.5:8080" not in str(finding.get("pac_chain")):
            problems.append(f"the PAC chain is not reported: {finding.get('pac_chain')!r}")

    # clean.example must not be reported: it is blocked and routed DIRECT.
    names = {f.get("domain") for f in findings}
    if "clean.example" in names:
        problems.append("a consistently DIRECT-routed blocked domain was reported as a conflict")

    if report.get("domains", {}).get("blocked") != 2:
        problems.append(f"unexpected blocked count: {report.get('domains')!r}")
    if report.get("counts", {}).get("error", 0) < 1:
        problems.append(f"no error was counted: {report.get('counts')!r}")

    if problems:
        for problem in problems:
            print(f"::error::{problem}", file=sys.stderr)
        return 1
    print("cross-format conflict report is correct")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
