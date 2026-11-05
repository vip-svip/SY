#!/usr/bin/env python3
"""Regression for scripts/fx-rule-conflict-check.py.

Requirement G asks each rule format for parser + validator + conflict check.
The individual parsers exist; a device carries Hosts, Adblock and PAC at once,
so the cross-format join is what catches contradictions between them. These
assertions pin every finding code and the gate semantics.

The fixture deliberately gives each finding code its own domain, so one rule
cannot accidentally satisfy two assertions.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/fx-rule-conflict-check.py"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS {message}")
    else:
        failures.append(message)
        print(f"FAIL {message}")


# blocked.example   - blocked by hosts, PAC sends it DIRECT (consistent)
# both.example      - blocked by hosts + adblock AND allowed by adblock
# sub.allowsub.example - blocked by hosts under the broader @@||allowsub.example^
# proxied.example   - blocked by hosts but PAC proxies it (unreachable route)
# another.example   - blocked by adblock only
HOSTS = """\
# FX regression fixture
0.0.0.0 blocked.example
0.0.0.0 both.example
0.0.0.0 sub.allowsub.example
0.0.0.0 proxied.example
"""

BLOCK_RULES = """\
! AdGuard Home block syntax
||both.example^
||another.example^
"""

ALLOW_RULES = """\
@@||both.example^
@@||allowedproxied.example^
@@||allowsub.example^
"""

PAC_ROUTING = {
    "order": "first match wins, PAC semantics",
    "rules": [
        # 0: proxies a DNS-blocked domain -> unreachable proxy route
        {"match": {"type": "domain_suffix", "value": "proxied.example"},
         "proxies": [{"type": "PROXY", "host": "10.0.0.5", "port": 8080}]},
        # 1: the blocked domain that is consistently routed DIRECT
        {"match": {"type": "host_exact", "value": "blocked.example"},
         "proxies": [{"type": "DIRECT", "host": None, "port": None}]},
        # 2: exact duplicate of rule 0 -> shadowed, can never match
        {"match": {"type": "domain_suffix", "value": "proxied.example"},
         "proxies": [{"type": "DIRECT", "host": None, "port": None}]},
        # 3: an allowed domain that still goes through a proxy (informational)
        {"match": {"type": "domain_suffix", "value": "allowedproxied.example"},
         "proxies": [{"type": "SOCKS5", "host": "127.0.0.1", "port": 1080}]},
        # 4: cannot be decided for domain names without live DNS
        {"match": {"type": "cidr", "value": "10.0.0.0/8"},
         "proxies": [{"type": "PROXY", "host": "10.0.0.5", "port": 8080}]},
    ],
    "default": [{"type": "DIRECT", "host": None, "port": None}],
}


def run_check(tmp: Path, sources: list[str], *, fail_on: str = "error") -> tuple[int, str, str]:
    cmd = [sys.executable, os.fspath(CHECKER)]
    for source in sources:
        if source == "hosts":
            cmd += ["--hosts", os.fspath(tmp / "hosts.txt")]
        elif source == "block":
            cmd += ["--block-rules", os.fspath(tmp / "block.rules")]
        elif source == "allow":
            cmd += ["--allow-rules", os.fspath(tmp / "allow.rules")]
        elif source == "pac":
            cmd += ["--pac-routing", os.fspath(tmp / "routing.json")]
    cmd += ["--report", os.fspath(tmp / "report.json"), "--fail-on", fail_on]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def codes(report: dict) -> dict[str, int]:
    out: dict[str, int] = {}
    for finding in report.get("findings", []):
        out[finding["code"]] = out.get(finding["code"], 0) + 1
    return out


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        tmp = Path(name)
        (tmp / "hosts.txt").write_text(HOSTS, encoding="utf-8")
        (tmp / "block.rules").write_text(BLOCK_RULES, encoding="utf-8")
        (tmp / "allow.rules").write_text(ALLOW_RULES, encoding="utf-8")
        (tmp / "routing.json").write_text(json.dumps(PAC_ROUTING, indent=2), encoding="utf-8")

        code, out, err = run_check(tmp, ["hosts", "block", "allow", "pac"])
        check(code == 2, f"conflicts fail the gate (exit {code}) {err.strip()[:200]}")
        report = json.loads((tmp / "report.json").read_text(encoding="utf-8"))
        found = codes(report)
        all_findings = report["findings"]

        # --- all three sources are actually joined, not checked in isolation.
        check(report["domains"]["blocked"] == 5,
              f"hosts and adblock blocks are merged ({report['domains']['blocked']})")
        check(report["domains"]["allowed"] == 3,
              f"allow rules are counted ({report['domains']['allowed']})")
        check(report["pac"]["rules"] == 5, "PAC rules are read from the routing table")
        check(report["inputs"]["pac_routing"] is not None, "the PAC input is recorded")

        # --- 1. blocked + allowed in the same namespace.
        both = [f for f in all_findings if f["code"] == "blocked_and_allowed"]
        check(len(both) == 1, f"blocked-and-allowed conflict found ({len(both)})")
        check(both and both[0]["domain"] == "both.example", "the conflicting domain is named")
        check(both and "block.rules" in both[0]["message"] and "allow.rules" in both[0]["message"],
              "both sources are cited in the finding")
        check(both and both[0]["severity"] == "error", "blocked-and-allowed is an error")

        # --- 2. narrower block under a broader allow.
        unders = [f for f in all_findings if f["code"] == "block_under_allow"]
        check(len(unders) == 1, f"one block-under-allow finding ({len(unders)})")
        check(unders and unders[0]["domain"] == "sub.allowsub.example",
              "the subdomain blocked under an allow is named")
        check(unders and unders[0]["allow_rule"] == "allowsub.example",
              "the broader allow rule is named")

        # --- 3. DNS-blocked domain that PAC routes through a proxy.
        proxied = [f for f in all_findings if f["code"] == "blocked_domain_is_proxied"]
        check([f["domain"] for f in proxied] == ["proxied.example"],
              f"proxied blocked domain reported ({[f['domain'] for f in proxied]})")
        check(proxied and proxied[0]["pac_chain"] == "PROXY 10.0.0.5:8080",
              "the unreachable proxy chain is named")
        check(report["pac"]["blocked_domains_with_proxy_route"] == 1,
              f"proxy-routed blocked domain is counted "
              f"({report['pac']['blocked_domains_with_proxy_route']})")
        check(report["pac"]["blocked_domains_with_direct_route"] == 1,
              f"a DIRECT-routed blocked domain is counted as consistent "
              f"({report['pac']['blocked_domains_with_direct_route']})")

        # --- 4. PAC shadowing makes a later rule unreachable.
        shadows = [f for f in all_findings if f["code"] == "unreachable_pac_rule"]
        check(len(shadows) == 1, f"one unreachable PAC rule ({len(shadows)})")
        check(shadows and shadows[0]["rule_index"] == 2 and shadows[0]["shadowed_by"] == 0,
              "the shadowed rule is identified by index")
        check(shadows and shadows[0]["severity"] == "warning",
              "shadowed PAC rule carries warning severity")

        # --- 5. DNS-allowed but proxied is informational, not an error.
        info_allowed = [f for f in all_findings if f["code"] == "allowed_domain_is_proxied"]
        check([f["domain"] for f in info_allowed] == ["allowedproxied.example"],
              f"allowed-but-proxied domain reported ({[f['domain'] for f in info_allowed]})")
        check(info_allowed and info_allowed[0]["severity"] == "info",
              "allowed-but-proxied severity is info")
        check(info_allowed and info_allowed[0]["pac_chain"] == "SOCKS5 127.0.0.1:1080",
              "the SOCKS chain is named")

        # --- 6. CIDR limitation is disclosed rather than silently skipped.
        check(found.get("cidr_needs_live_dns") == 1,
              f"the isInNet limitation is disclosed ({found.get('cidr_needs_live_dns')})")
        check(report["pac"]["undecidable_matches"] >= 1,
              f"undecidable PAC matches are counted ({report['pac']['undecidable_matches']})")

        # --- severity accounting is internally consistent.
        check(report["counts"]["error"] == len([f for f in all_findings if f["severity"] == "error"]),
              "error count matches the findings")
        check(report["counts"]["warning"] == len([f for f in all_findings if f["severity"] == "warning"]),
              "warning count matches the findings")
        check(report["counts"]["info"] == len([f for f in all_findings if f["severity"] == "info"]),
              "info count matches the findings")

        # --- gate semantics: --fail-on controls the exit code.
        code_none, _, _ = run_check(tmp, ["hosts", "block", "allow", "pac"], fail_on="none")
        check(code_none == 0, f"--fail-on none never fails the build ({code_none})")
        code_warn, _, _ = run_check(tmp, ["hosts", "block", "allow", "pac"], fail_on="warning")
        check(code_warn == 2, f"--fail-on warning still fails ({code_warn})")

        # --- a clean configuration passes.
        clean = Path(name) / "clean"
        clean.mkdir()
        (clean / "hosts.txt").write_text("0.0.0.0 ads.example\n", encoding="utf-8")
        (clean / "routing.json").write_text(
            json.dumps({"order": "first match wins, PAC semantics", "rules": [],
                        "default": [{"type": "DIRECT", "host": None, "port": None}]}),
            encoding="utf-8")
        code_clean, _, clean_err = run_check(clean, ["hosts", "pac"])
        check(code_clean == 0, f"a consistent configuration exits 0 ({code_clean}) {clean_err[:150]}")
        clean_report = json.loads((clean / "report.json").read_text(encoding="utf-8"))
        check(clean_report["counts"]["error"] == 0, "clean configuration has no errors")

        # --- determinism: the same arguments must produce the same bytes.
        # The report embeds fail_on, so the baseline must come from the same
        # invocation shape rather than from the previous --fail-on warning run.
        run_check(tmp, ["hosts", "block", "allow", "pac"])
        first = (tmp / "report.json").read_bytes()
        run_check(tmp, ["hosts", "block", "allow", "pac"])
        check((tmp / "report.json").read_bytes() == first,
              "report is byte-identical when rerun with the same arguments")

        # --- sources are validated, not guessed.
        (tmp / "bad.rules").write_text("@@||oops.example^\n", encoding="utf-8")
        bad = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--block-rules", os.fspath(tmp / "bad.rules"),
            "--report", os.fspath(tmp / "bad.json"),
        ], capture_output=True, text=True)
        check(bad.returncode != 0, "an allow rule passed as a block list is rejected")
        check("expected a ||" in (bad.stdout + bad.stderr),
              "the parse failure explains the expected syntax")

        # --- a Hosts row may legitimately carry several hostnames.
        multi = Path(name) / "multi"
        multi.mkdir()
        (multi / "hosts.txt").write_text("0.0.0.0 a.example b.example\n", encoding="utf-8")
        code_multi, _, multi_err = run_check(multi, ["hosts"])
        check(code_multi == 0, f"a multi-hostname Hosts row is accepted ({code_multi}) {multi_err[:150]}")
        multi_report = json.loads((multi / "report.json").read_text(encoding="utf-8"))
        check(multi_report["domains"]["blocked"] == 2,
              f"every hostname on the row is counted ({multi_report['domains']['blocked']})")

        # --- a genuinely malformed Hosts row is refused, not ignored.
        (multi / "hosts.txt").write_text("0.0.0.0 not_a_domain!\n", encoding="utf-8")
        malformed = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--hosts", os.fspath(multi / "hosts.txt"),
            "--report", os.fspath(tmp / "malformed.json"),
        ], capture_output=True, text=True)
        check(malformed.returncode != 0, "an invalid Hosts hostname is rejected")

        broken_pac = tmp / "broken.json"
        broken_pac.write_text("{not json", encoding="utf-8")
        badpac = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--pac-routing", os.fspath(broken_pac),
            "--report", os.fspath(tmp / "bp.json"),
        ], capture_output=True, text=True)
        check(badpac.returncode != 0, "an unreadable PAC routing table is rejected")

        unknown_pac = tmp / "unknown.json"
        unknown_pac.write_text(json.dumps({"rules": [
            {"match": {"type": "magic", "value": "x"},
             "proxies": [{"type": "DIRECT", "host": None, "port": None}]}
        ]}), encoding="utf-8")
        badkind = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--pac-routing", os.fspath(unknown_pac),
            "--report", os.fspath(tmp / "bk.json"),
        ], capture_output=True, text=True)
        check(badkind.returncode != 0, "an unknown PAC match type is rejected")

        # --- no source at all is an error, not a trivially clean pass.
        none = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--report", os.fspath(tmp / "none.json"),
        ], capture_output=True, text=True)
        check(none.returncode != 0, "checking nothing is refused")

        # --- symlink output rejected.
        target = Path(name) / "elsewhere.json"
        target.write_text('{"untouched": true}\n', encoding="utf-8")
        link = Path(name) / "linked.json"
        if not link.exists():
            link.symlink_to(target)
        sym = subprocess.run([
            sys.executable, os.fspath(CHECKER),
            "--hosts", os.fspath(tmp / "hosts.txt"),
            "--report", os.fspath(link),
        ], capture_output=True, text=True)
        check(sym.returncode != 0, "symlinked report path is rejected")
        check(target.read_text(encoding="utf-8") == '{"untouched": true}\n',
              "symlink target is never written through")

        leftovers = [p.name for p in Path(name).iterdir() if p.name.endswith(".tmp")]
        check(leftovers == [], f"atomic writes leave no temp files ({leftovers})")

    print()
    if failures:
        print(f"{len(failures)} assertion(s) failed")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("cross-format conflict check regression: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
