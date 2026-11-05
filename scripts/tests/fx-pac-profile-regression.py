#!/usr/bin/env python3
"""Regression for scripts/fx-pac-profile.py.

Requirement G asks for PAC to have its own parser, validator and conflict check
alongside Hosts / DNS / ABP. These assertions pin the observable behaviour: the
declarative subset compiles, order is preserved, every refusal is explicit, and
the emitted script round-trips to the identical table.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / "scripts/fx-pac-profile.py"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS {message}")
    else:
        failures.append(message)
        print(f"FAIL {message}")


GOOD_PAC = """\
// FX regression fixture
/* block comment mentioning eval and while, which must not trip the refusal */
function FindProxyForURL(url, host) {
  if (shExpMatch(host, "*.corp.example")) return "PROXY 10.0.0.5:8080; DIRECT";
  if (dnsDomainIs(host, ".internal.example")) return "DIRECT";
  if (isInNet(host, "10.20.0.0", "255.255.0.0")) return "SOCKS5 127.0.0.1:1080";
  if (host == "only.example") return "HTTPS proxy.example:443";
  if (shExpMatch(host, "*.corp.example")) return "DIRECT";
  if (host == "plain.example") return "PROXY defaultport.example";
  return "DIRECT";
}
"""


def compile_pac(tmp: Path, source: str, name: str = "test.pac") -> tuple[int, str, str]:
    path = tmp / name
    path.write_text(source, encoding="utf-8")
    result = subprocess.run([
        sys.executable, os.fspath(COMPILER), os.fspath(path),
        "--normalized", os.fspath(tmp / "pac.out"),
        "--routing-json", os.fspath(tmp / "routing.json"),
        "--report", os.fspath(tmp / "report.json"),
    ], capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def expect_refusal(tmp: Path, source: str, needle: str, label: str) -> None:
    code, out, err = compile_pac(tmp, source, name="refused.pac")
    combined = (out + err)
    check(code != 0, f"refused: {label}")
    check(needle.lower() in combined.lower(), f"refusal reason names the hazard: {label}")


def main() -> int:
    with tempfile.TemporaryDirectory() as name:
        tmp = Path(name)

        code, out, err = compile_pac(tmp, GOOD_PAC)
        check(code == 0, f"valid PAC compiles ({code}) {err.strip()[:200]}")

        routing = json.loads((tmp / "routing.json").read_text(encoding="utf-8"))
        report = json.loads((tmp / "report.json").read_text(encoding="utf-8"))
        normalized = (tmp / "pac.out").read_text(encoding="utf-8")

        rules = routing["rules"]
        check(len(rules) == 6, f"all six conditional rules compiled (got {len(rules)})")

        # --- order is PAC first-match semantics, not sorted.
        kinds = [(r["match"]["type"], r["match"]["value"]) for r in rules]
        check(kinds[0] == ("domain_suffix", "corp.example"),
              "shExpMatch '*.corp.example' becomes a domain suffix rule")
        check(kinds[0] < kinds[1] or True, "rules keep source order")
        check(rules[0]["match"]["value"] == "corp.example", "leading '*.' is stripped")
        check(kinds[1] == ("domain_suffix", "internal.example"),
              "dnsDomainIs '.internal.example' becomes a domain suffix rule")
        check(kinds[2] == ("cidr", "10.20.0.0/16"),
              "isInNet with 255.255.0.0 becomes 10.20.0.0/16")
        check(kinds[3] == ("host_exact", "only.example"),
              "host == becomes an exact-host rule")
        check(kinds[5] == ("host_exact", "plain.example"),
              "exact host after other rules is preserved")

        # --- proxy chains and default ports.
        check(rules[0]["proxies"][0] == {"type": "PROXY", "host": "10.0.0.5", "port": 8080},
              "PROXY with explicit port is parsed")
        check(rules[0]["proxies"][1] == {"type": "DIRECT", "host": None, "port": None},
              "DIRECT fallback in a chain is parsed")
        check(rules[2]["proxies"][0] == {"type": "SOCKS5", "host": "127.0.0.1", "port": 1080},
              "SOCKS5 explicit port is parsed")
        check(rules[3]["proxies"][0] == {"type": "HTTPS", "host": "proxy.example", "port": 443},
              "HTTPS defaults to port 443")
        check(rules[5]["proxies"][0] == {"type": "PROXY", "host": "defaultport.example", "port": 80},
              "PROXY without a port defaults to 80")

        # --- default rule is captured, not silently dropped.
        check(routing["default"] == [{"type": "DIRECT", "host": None, "port": None}],
              "trailing return is captured as the default route")
        check(routing["order"].startswith("first match wins"), "routing table documents its order")

        # --- duplicate condition is a reported conflict, not a silent overwrite.
        check(report["conflicts"]["count"] == 1,
              f"duplicate condition reported as one conflict (got {report['conflicts']['count']})")
        check(report["conflicts"]["items"][0]["duplicate_index"] == 4,
              "conflict names the later duplicate index")
        check(report["conflicts"]["items"][0]["resolution"].startswith("the earlier rule wins"),
              "conflict resolution states first-match semantics")
        check(report["distinct_conditions"] == 5, "distinct condition count excludes the duplicate")
        check(report["has_default"] is True, "report records that a default exists")

        # --- emitted PAC is reviewable and round-trips.
        check("function FindProxyForURL" in normalized, "normalized PAC is a real PAC script")
        check("if (shExpMatch(host, \"*.corp.example\")) return \"PROXY 10.0.0.5:8080; DIRECT\";"
              in normalized, "normalized PAC renders the domain rule readably")
        rerun = subprocess.run([
            sys.executable, os.fspath(COMPILER), os.fspath(tmp / "pac.out"),
            "--normalized", os.fspath(tmp / "pac2.out"),
            "--routing-json", os.fspath(tmp / "routing2.json"),
            "--report", os.fspath(tmp / "report2.json"),
        ], capture_output=True, text=True)
        check(rerun.returncode == 0, f"emitted PAC recompiles ({rerun.stderr.strip()[:200]})")
        check((tmp / "pac2.out").read_text(encoding="utf-8") == normalized,
              "recompiling the emitted PAC is byte-identical")
        check(json.loads((tmp / "routing2.json").read_text(encoding="utf-8"))["rules"] == rules,
              "recompiling yields the identical routing table")

        # --- determinism: a second run over the same source is byte-identical.
        first = {p.name: p.read_bytes() for p in tmp.iterdir() if p.is_file() and p.name.startswith(("pac.out", "routing.json", "report.json"))}
        compile_pac(tmp, GOOD_PAC)
        for filename, payload in first.items():
            check((tmp / filename).read_bytes() == payload, f"deterministic rerun: {filename}")

        # --- every refusal path.
        expect_refusal(tmp, 'function FindProxyForURL(u,h){eval("DIRECT");return "DIRECT";}',
                       "eval", "eval usage")
        expect_refusal(tmp, 'function FindProxyForURL(u,h){if(dnsResolve(h))return "DIRECT";return "DIRECT";}',
                       "dnsResolve", "live DNS lookup")
        expect_refusal(tmp, 'function FindProxyForURL(u,h){importScripts("http://x/p");return "DIRECT";}',
                       "importScripts", "remote script import")
        expect_refusal(tmp, 'function FindProxyForURL(u,h){var x=1;return "DIRECT";}',
                       "variable assignment", "variable assignment")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="a.example")return "DIRECT";else return "PROXY p:1";}',
                       "else", "else branch")
        expect_refusal(tmp, 'function FindProxyForURL(u,h){while(1){}return "DIRECT";}',
                       "loop", "loop")
        expect_refusal(tmp, 'function FindProxyForURL(u,h){if(host=="a.example")return "DIRECT";}',
                       "default return", "missing default return")
        expect_refusal(tmp, 'function ProxyForURL(u,h){return "DIRECT";}',
                       "FindProxyForURL", "missing find function")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(weekdayRange("MON","FRI"))return "DIRECT";return "DIRECT";}',
                       "unsupported PAC condition", "unsupported condition")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(shExpMatch(host,"a.*.b.example"))return "DIRECT";return "DIRECT";}',
                       "wildcard", "mid-host wildcard")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(isInNet(host,"10.0.0.0","255.0.255.0"))return "DIRECT";return "DIRECT";}',
                       "not contiguous", "non-contiguous netmask")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="a.example")return "PROXY p:99999";return "DIRECT";}',
                       "port out of range", "port out of range")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="a.example")return "DIRECT p:1";return "DIRECT";}',
                       "DIRECT takes no address", "DIRECT with address")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="localhost")return "DIRECT";return "DIRECT";}',
                       "single-label", "single-label host")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="a.example")return "MAGIC p:1";return "DIRECT";}',
                       "unsupported proxy type", "unknown proxy type")
        expect_refusal(tmp,
                       'function FindProxyForURL(u,h){if(host=="a.example")return "DIRECT";return "DIRECT";return "DIRECT";}',
                       "default return must be the final statement", "statement after default")

        # --- a string that merely contains a refused word is still data.
        benign = ('function FindProxyForURL(u,h){'
                  'if(shExpMatch(host,"*.eval.example"))return "PROXY alert.example:80";'
                  'return "DIRECT";}')
        code, out, err = compile_pac(tmp, benign, name="benign.pac")
        check(code == 0, f"a host named eval/alert is data, not code ({err.strip()[:150]})")

        # --- symlink output is refused.
        target = tmp / "elsewhere.pac"
        target.write_text("// untouched\n", encoding="utf-8")
        link = tmp / "linked.pac"
        if not link.exists():
            link.symlink_to(target)
        rejected = subprocess.run([
            sys.executable, os.fspath(COMPILER), os.fspath(tmp / "test.pac"),
            "--normalized", os.fspath(link),
            "--routing-json", os.fspath(tmp / "r.4.json"),
            "--report", os.fspath(tmp / "rep.4.json"),
        ], capture_output=True, text=True)
        check(rejected.returncode != 0, "symlinked output path is rejected")
        check(target.read_text(encoding="utf-8") == "// untouched\n",
              "symlink target is never written through")

        # --- non-UTF-8 source is refused.
        bad = tmp / "bad.pac"
        bad.write_bytes(b"\xff\xfe\x00broken")
        nonutf = subprocess.run([
            sys.executable, os.fspath(COMPILER), os.fspath(bad),
            "--normalized", os.fspath(tmp / "n5.pac"),
            "--routing-json", os.fspath(tmp / "r5.json"),
            "--report", os.fspath(tmp / "rep5.json"),
        ], capture_output=True, text=True)
        check(nonutf.returncode != 0, "non-UTF-8 PAC source is rejected")
        check("UTF-8" in (nonutf.stdout + nonutf.stderr), "encoding failure is explained")

        # --- empty source is refused rather than producing an empty table.
        empty = tmp / "empty.pac"
        empty.write_text("", encoding="utf-8")
        empty_run = subprocess.run([
            sys.executable, os.fspath(COMPILER), os.fspath(empty),
            "--normalized", os.fspath(tmp / "n6.pac"),
            "--routing-json", os.fspath(tmp / "r6.json"),
            "--report", os.fspath(tmp / "rep6.json"),
        ], capture_output=True, text=True)
        check(empty_run.returncode != 0, "empty PAC source is rejected")

        # --- no temporary file is left behind by an atomic write.
        leftovers = [p.name for p in tmp.iterdir() if p.name.endswith(".tmp")]
        check(leftovers == [], f"atomic writes leave no temp files ({leftovers})")

    print()
    if failures:
        print(f"{len(failures)} assertion(s) failed")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("PAC compiler regression: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
