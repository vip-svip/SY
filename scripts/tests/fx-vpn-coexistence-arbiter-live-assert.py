#!/usr/bin/env python3
"""Assert the FX coexistence arbiter's live verdict is truthful.

Used by CI against the real runner network stack. The point is not to demand one
particular grade, but to forbid the two dishonest outcomes:

  * claiming a coexistable grade while the kernel dataplane actually holds the
    Android VPN slot (that would break third-party VPNs);
  * reporting an "incompatible"/slot-using state on a clean host.

On a host where the link inventory cannot be read (no `ip` command, restricted
container), the arbiter must say so (`probe != ok`, verdict `unknown`) instead of
pretending coexistence. That is an accepted, honest outcome here.
"""
from __future__ import annotations

import json
import sys

ALLOWED = {"kernel_only", "partial", "unknown", "full_parallel", "chained"}


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print("FAIL: arbiter produced no output", file=sys.stderr)
        return 1
    try:
        d = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"FAIL: arbiter output is not JSON: {exc}\n{raw}", file=sys.stderr)
        return 1

    failures = []
    if d.get("ok") != 1:
        failures.append("ok flag must be 1")
    if d.get("dataplane") != "kernel":
        failures.append(f"dataplane must be kernel-level, got {d.get('dataplane')!r}")
    slot = d.get("vpn_service_slot_used")
    if slot not in (False, None):
        failures.append("kernel dataplane must NOT hold the Android VPN slot")
    if slot is None and d.get("verdict") != "unknown":
        failures.append("an unverified module tree must produce an unknown verdict")
    if d.get("verdict") not in ALLOWED:
        failures.append(f"unexpected verdict {d.get('verdict')!r}")
    if d.get("verdict") == "incompatible":
        failures.append("clean host must never be graded incompatible")

    # A clean host with a readable link inventory and no tunnel is kernel_only
    # only when the module source scan actually verified slot non-use.
    if d.get("probe") == "ok" and d.get("external_vpn") is False and slot is False:
        if d.get("verdict") != "kernel_only":
            failures.append(
                f"readable inventory without a tunnel and with verified slot-free source must be kernel_only, got {d.get('verdict')!r}"
            )

    if failures:
        for f in failures:
            print(f"FAIL: {f}", file=sys.stderr)
        print(json.dumps(d, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1

    print(f"live verdict: {d['verdict']} ({d['grade_cn']}), probe={d['probe']}, "
          f"slot_used={d['vpn_service_slot_used']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
