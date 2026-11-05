#!/usr/bin/env python3
"""Regression for scripts/fx-filter-list-parse.py.

Covers the requirement-G obligations that must be verifiable without a device:
parse each supported rule shape, keep exceptions and cosmetic rules in their own
streams, refuse to widen unexpressible rules, resolve block/allow conflicts
deterministically, and write atomically with symlink protection.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARSER = ROOT / "scripts/fx-filter-list-parse.py"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS {message}")
    else:
        failures.append(message)
        print(f"FAIL {message}")


ABP_LIST = """\
[Adblock Plus 2.0]
! Title: FX regression fixture
! Expires: 1 day
||ads.example.com^
||*.tracker.example^
||Beacon.Example.COM^
@@||good.example.com^
||dup.example.com^
@@||dup.example.com^
example.com##.ad-banner
example.com#@#.ad-banner
example.com#$#body { color: red; }
||opts.example.com^$third-party
||important.example.com^$important
/banner\\d+/
|https://url.example.com/path
adserver
||bad_domain^
||-bad.example^
||localhost^
||192.0.2.10^
||a.*.example^
"""

HOSTS_LIST = """\
# hosts style fixture
0.0.0.0 hosts.example.com
127.0.0.1 alt.example.com
::1  v6.example.com
0.0.0.0 0.0.0.0
"""


def run_parser(tmp: Path, extra: list[str] | None = None) -> subprocess.CompletedProcess:
    cmd = [
        sys.executable, os.fspath(PARSER),
        os.fspath(tmp / "abp.txt"), os.fspath(tmp / "hosts.txt"),
        "--block-hosts", os.fspath(tmp / "block.hosts"),
        "--block-rules", os.fspath(tmp / "block.rules"),
        "--allow-rules", os.fspath(tmp / "allow.rules"),
        "--cosmetic-output", os.fspath(tmp / "cosmetic.txt"),
        "--report", os.fspath(tmp / "report.json"),
    ]
    if extra:
        cmd.extend(extra)
    return subprocess.run(cmd, capture_output=True, text=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        tmp = Path(name)
        (tmp / "abp.txt").write_text(ABP_LIST, encoding="utf-8")
        (tmp / "hosts.txt").write_text(HOSTS_LIST, encoding="utf-8")

        result = run_parser(tmp)
        check(result.returncode == 0, f"parser exits 0 ({result.returncode})")
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr)

        block_hosts = (tmp / "block.hosts").read_text(encoding="utf-8").splitlines()
        block_rules = (tmp / "block.rules").read_text(encoding="utf-8").splitlines()
        allow_rules = (tmp / "allow.rules").read_text(encoding="utf-8").splitlines()
        cosmetic = (tmp / "cosmetic.txt").read_text(encoding="utf-8").splitlines()
        report = json.loads((tmp / "report.json").read_text(encoding="utf-8"))

        # --- parse: domain-anchored rules become blocked domains, lowercased.
        check("0.0.0.0 ads.example.com" in block_hosts, "||ads.example.com^ becomes a blocked domain")
        check("0.0.0.0 tracker.example" in block_hosts, "leading wildcard ||*.tracker.example is normalised")
        check("0.0.0.0 beacon.example.com" in block_hosts, "rule domains are lowercased")
        check("0.0.0.0 hosts.example.com" in block_hosts, "hosts-format 0.0.0.0 row is imported")
        check("0.0.0.0 alt.example.com" in block_hosts, "hosts-format 127.0.0.1 row is imported")

        # --- exceptions kept in their own stream, never in the block stream.
        check("@@||good.example.com^" in allow_rules, "||@@ exception goes to the allow stream")
        check("0.0.0.0 good.example.com" not in block_hosts, "exception domain is not blocked")
        check(all(not line.startswith("@@") for line in block_rules),
              "block stream contains no allow rules")
        check(all(line.startswith("||") and line.endswith("^") for line in block_rules),
              "block stream is well-formed AdGuard Home syntax")

        # --- cosmetic rules preserved verbatim and never enabled as DNS.
        check("example.com##.ad-banner" in cosmetic, "cosmetic rule preserved verbatim")
        check("example.com#$#body { color: red; }" in cosmetic, "AdGuard CSS injection preserved")
        check("example.com#@#.ad-banner" in cosmetic, "cosmetic exception preserved separately")
        check(not any("##" in line or "#$#" in line for line in block_rules),
              "cosmetic rules never leak into the block stream")

        # --- refusal to widen unexpressible rules.
        blocked_text = "\n".join(block_hosts)
        for forbidden in ("opts.example.com", "important.example.com", "url.example.com",
                          "adserver", "bad_domain", "-bad.example", "a.*.example"):
            check(forbidden not in blocked_text, f"unexpressible rule not blocked: {forbidden}")
        reasons = report["unsupported_reasons"]
        check(any("option set" in reason for reason in reasons),
              "option-set rules reported with a reason")
        check(any("regular-expression" in reason for reason in reasons),
              "regex rules reported with a reason")
        check(any("URL-anchored" in reason for reason in reasons),
              "URL-anchored rules reported with a reason")
        check(any("substring" in reason for reason in reasons),
              "substring rules reported with a reason")
        check("localhost" not in blocked_text, "single-label host is refused, not blocked")
        check("192.0.2.10" not in blocked_text, "IP literal is refused, not blocked")

        # --- conflict resolution: allow wins, deterministically.
        check("dup.example.com" not in blocked_text, "blocked+allowed domain is removed from block")
        check("@@||dup.example.com^" in allow_rules, "conflicting domain stays in the allow stream")
        check(report["conflicts"]["count"] == 1, "exactly one conflict reported")
        check(report["conflicts"]["domains"] == ["dup.example.com"], "conflict names the domain")

        # --- counts and structure are internally consistent.
        check(report["blocked_domains"] == len(block_rules), "blocked count matches block stream")
        check(report["allowed_domains"] == len(allow_rules), "allowed count matches allow stream")
        check(report["cosmetic_rules"] == len(cosmetic), "cosmetic count matches cosmetic stream")
        check(report["total_lines"] == len(ABP_LIST.splitlines()) + len(HOSTS_LIST.splitlines()),
              "total_lines counts every source line")
        check(len(report["sources"]) == 2, "report records one entry per source")
        check(len(block_rules) == len(set(block_rules)), "block stream is deduplicated")
        check(block_rules == sorted(block_rules), "block stream is deterministically sorted")

        # --- idempotency: a second run produces byte-identical artifacts.
        snapshot = {p.name: p.read_bytes() for p in tmp.iterdir() if p.is_file()}
        second = run_parser(tmp)
        check(second.returncode == 0, "second run exits 0")
        for filename, payload in snapshot.items():
            check((tmp / filename).read_bytes() == payload,
                  f"second run is byte-identical: {filename}")

        # --- --fail-on-unsupported is a real gate, not decoration.
        strict = run_parser(tmp, ["--fail-on-unsupported"])
        check(strict.returncode == 2, "strict mode exits 2 when unsupported rules exist")

        # --- symlink output is refused instead of silently written through.
        link = tmp / "evil.hosts"
        target = tmp / "elsewhere.hosts"
        target.write_text("# untouched\n", encoding="utf-8")
        if not link.exists():
            link.symlink_to(target)
        rejected = subprocess.run([
            sys.executable, os.fspath(PARSER), os.fspath(tmp / "abp.txt"),
            "--block-hosts", os.fspath(link),
            "--block-rules", os.fspath(tmp / "b2.rules"),
            "--allow-rules", os.fspath(tmp / "a2.rules"),
            "--cosmetic-output", os.fspath(tmp / "c2.txt"),
            "--report", os.fspath(tmp / "r2.json"),
        ], capture_output=True, text=True)
        check(rejected.returncode != 0, "symlinked output path is rejected")
        check("symlink" in (rejected.stderr + rejected.stdout).lower(),
              "symlink rejection explains itself")
        check(target.read_text(encoding="utf-8") == "# untouched\n",
              "symlink target is never written through")

        # --- a broken source fails loudly instead of yielding an empty blocklist.
        bad = tmp / "bad.txt"
        bad.write_bytes(b"\xff\xfe\x00broken")
        broken = subprocess.run([
            sys.executable, os.fspath(PARSER), os.fspath(bad),
            "--block-hosts", os.fspath(tmp / "b3.hosts"),
            "--block-rules", os.fspath(tmp / "b3.rules"),
            "--allow-rules", os.fspath(tmp / "a3.rules"),
            "--cosmetic-output", os.fspath(tmp / "c3.txt"),
            "--report", os.fspath(tmp / "r3.json"),
        ], capture_output=True, text=True)
        check(broken.returncode != 0, "non-UTF-8 source is rejected")
        check("UTF-8" in (broken.stderr + broken.stdout), "encoding failure is explained")

    print()
    if failures:
        print(f"{len(failures)} assertion(s) failed")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("filter-list parser regression: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
