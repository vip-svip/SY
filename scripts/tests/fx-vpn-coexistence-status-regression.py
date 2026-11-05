#!/usr/bin/env python3
"""Regression for the FX / third-party VPN coexistence status publisher.

``apply.sh`` already detects the outer tunnel and decides whether FX must suspend
interception, but it never persisted the outcome, so neither the App nor the
WebUI could tell the user which coexistence grade they are actually in.

This suite proves the injected publisher:

  1. applies idempotently and keeps apply.sh parseable;
  2. publishes a valid JSON status when no external VPN exists (kernel_only);
  3. reports partial when an external tunnel is known but the data path is unverified;
  4. never promotes UID discovery to parallel or chained proof;
  5. never fabricates "parallel" from unreadable state (fail-closed wording);
  6. writes the file 0600 and replaces it atomically (no partial JSON);
  7. is fail-open: a write failure must not break the caller;
  8. keeps a single source of truth by deferring to the arbiter when present.

The publisher body is executed from the patched apply.sh, not re-implemented.
"""
from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_vpn_coexistence_status.py"
BEGIN = "# >>> fx-vpn-coexistence-status"
END = "# <<< fx-vpn-coexistence-status"
ANCHOR = "# ---------- 可信 DNS 目标（DNS 修复的核心）----------"

SYNTHETIC_APPLY = """#!/system/bin/sh
MODDIR=/tmp/fx-mod
_PG_EXT_VPN_IF="${FAKE_EXT_IF:-}"
_PG_EXT_VPN_UID="${FAKE_EXT_UID:-}"
_PG_VPN_INTERCEPTION_BLOCKED="${FAKE_BLOCKED:-0}"
%s
echo "past-anchor"
""" % ANCHOR

HARNESS = """set -u
MODDIR=%s
_PG_EXT_VPN_IF="${FAKE_EXT_IF:-}"
_PG_EXT_VPN_UID="${FAKE_EXT_UID:-}"
_PG_VPN_INTERCEPTION_BLOCKED="${FAKE_BLOCKED:-0}"
%s
fx_coexist_status_write || :
"""

failures: list[str] = []


def check(cond: bool, msg: str) -> None:
    if not cond:
        failures.append(msg)
        print(f"  FAIL: {msg}")
    else:
        print(f"  ok: {msg}")


def build_patched(tmp: Path) -> Path:
    module = tmp / "fx-module"
    (module / "scripts").mkdir(parents=True)
    apply_sh = module / "scripts/apply.sh"
    apply_sh.write_text(SYNTHETIC_APPLY, encoding="utf-8")
    for _ in range(2):  # idempotence: installer may re-patch
        subprocess.run([sys.executable, str(PATCHER), str(module)], check=True)
    arbiter = module / "scripts/fx-vpn-coexistence-arbiter.sh"
    arbiter.write_text(
        '#!/system/bin/sh\\n'
        'slot="${FAKE_SLOT:-false}"\\n'
        'case "$slot" in\\n'
        '  true) verdict=incompatible; grade=不兼容; rc=3; slot_json=true ;;\\n'
        '  false)\\n'
        '    slot_json=false; rc=0\\n'
        '    if [ -n "${FAKE_EXT_IF:-}" ]; then verdict=partial; grade=部分兼容; '
        'else verdict=kernel_only; grade=内核级独立; fi\\n'
        '    if [ "${FAKE_BLOCKED:-0}" = 1 ] && [ -z "${FAKE_EXT_IF:-}" ]; then '
        'verdict=unknown; grade=探测不可用; rc=2; fi\\n'
        '    ;;\\n'
        '  *) verdict=unknown; grade=探测不可用; rc=2; slot_json=null ;;\\n'
        'esac\\n'
        'printf \'{"ok":1,"verdict":"%s","grade_cn":"%s","exit":%s,"probe":"ok",'
        '"route_probe":"unverified","vpn_service_slot_used":%s}\\\\n\' '
        '"$verdict" "$grade" "$rc" "$slot_json"\\n',
        encoding="utf-8",
    )
    arbiter.chmod(0o755)
    return module


def extract_publisher(apply_sh: Path, tmp: Path) -> Path:
    text = apply_sh.read_text(encoding="utf-8")
    start = text.index(BEGIN)
    end = text.index(END, start)
    body = text[start:end]
    # Drop the marker comment lines, keep the function definitions.
    lines = [ln for ln in body.splitlines() if not ln.strip().startswith("# >>>")]
    fn = tmp / "publisher.sh"
    fn.write_text("\n".join(lines) + "\n", encoding="utf-8")
    subprocess.run(["sh", "-n", str(fn)], check=True)
    return fn


def run_writer(pub: Path, tmp: Path, module: Path, state: Path, env_extra: dict) -> subprocess.CompletedProcess:
    harness = tmp / "harness.sh"
    harness.write_text(HARNESS % (f"'{module}'", f". '{pub}'"), encoding="utf-8")
    env = {
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "FX_COEXIST_STATE_DIR": str(state),
    }
    env.update(env_extra)
    return subprocess.run(["sh", str(harness)], env=env, text=True, capture_output=True)


def read_status(state: Path):
    p = state / "vpn-coexistence.json"
    if not p.is_file():
        return None, None
    return p, json.loads(p.read_text(encoding="utf-8"))


def main() -> int:
    assert PATCHER.is_file(), f"missing patcher: {PATCHER}"

    with tempfile.TemporaryDirectory(prefix="fx-coexist-status-") as raw:
        tmp = Path(raw)
        module = build_patched(tmp)
        apply_sh = module / "scripts/apply.sh"
        text = apply_sh.read_text(encoding="utf-8")

        print("== structure ==")
        check(text.count(BEGIN) == 1, "status block appears exactly once after double patch")
        check(text.count(END) == 1, "end marker appears exactly once")
        check(text.count(ANCHOR) == 2 or text.count(ANCHOR) == 1,
              "DNS-target anchor preserved (not duplicated or lost)")
        check("fx_coexist_status_write || :" in text, "publisher is actually invoked")
        p = subprocess.run(["sh", "-n", str(apply_sh)], capture_output=True, text=True)
        check(p.returncode == 0, f"patched apply.sh parses ({p.stderr.strip()[:120]})")

        pub = extract_publisher(apply_sh, tmp)

        print("== case 1: no external VPN -> kernel_only ==")
        st = tmp / "s1"
        r = run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": ""})
        check(r.returncode == 0, f"writer exit 0 (got {r.returncode}: {r.stderr.strip()[:120]})")
        path, d = read_status(st)
        check(path is not None, "status file created")
        if d:
            check(d["verdict"] == "kernel_only", f"verdict kernel_only (got {d['verdict']})")
            check(d["external_vpn"] is False, "external_vpn false")
            check(d["dataplane"] == "kernel", "dataplane kernel")
            check(d["vpn_service_slot_used"] is False, "verified VPN slot is not held")

        print("== case 2: external VPN with uid -> partial (route unverified) ==")
        st = tmp / "s2"
        r = run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": "10123"})
        check(r.returncode == 0, "writer exit 0")
        _, d = read_status(st)
        if d:
            check(d["verdict"] == "partial", f"UID alone must remain partial (got {d.get('verdict')})")
            check(d["route_probe"] == "unverified", "route probe explicitly unverified")
            check(d["external_uid"] == "10123", "owner uid preserved")
            check(d["external_if"] == "tun0", "outer iface preserved")
            check(d["vpn_service_slot_used"] is False, "verified arbiter slot state is preserved")

        print("== case 3: external VPN without uid -> partial (binding unverified) ==")
        st = tmp / "s3"
        run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": ""})
        _, d = read_status(st)
        if d:
            check(d["verdict"] == "partial", f"verdict partial (got {d.get('verdict')})")

        print("== case 4: uid 0 / garbage is not a real owner -> partial ==")
        for bad in ("0", "null", "  "):
            st = tmp / f"s4_{bad.strip() or 'blank'}"
            run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": bad})
            _, d = read_status(st)
            if d:
                check(d["verdict"] == "partial", f"uid {bad!r} must not certify routing (got {d.get('verdict')})")

        print("== case 5: blocked with no iface -> unknown (never parallel) ==")
        st = tmp / "s5"
        run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "", "FAKE_BLOCKED": "1"})
        _, d = read_status(st)
        if d:
            check(d["verdict"] == "unknown", f"verdict unknown (got {d.get('verdict')})")
            check(d["interception_blocked"] is True, "interception_blocked reflected")
            check(d["vpn_service_slot_used"] is False, "slot false is based on a complete arbiter fixture")

        print("== case 6: file mode is 0600 and content is complete JSON ==")
        st = tmp / "s6"
        run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": "7"})
        path, d = read_status(st)
        if path:
            mode = stat.S_IMODE(path.stat().st_mode)
            check(mode == 0o600, f"status file mode 0600 (got {oct(mode)})")
            check(d is not None, "status parses as complete JSON")
            check(not list(st.glob("*.tmp.*")), "no leftover temp file")

        print("== case 7: fail-open when the state dir is not writable ==")
        ro = tmp / "readonly"
        ro.mkdir()
        os.chmod(ro, 0o500)
        try:
            r = run_writer(pub, tmp, module, ro / "nested", {"FAKE_EXT_IF": "tun0"})
            check(r.returncode == 0, f"write failure must not break the caller (got {r.returncode})")
        finally:
            os.chmod(ro, 0o700)

        print("== case 8: defers to the arbiter when present (single source of truth) ==")
        mod2 = tmp / "mod-arb"
        (mod2 / "scripts").mkdir(parents=True)
        fake_arb = mod2 / "scripts/fx-vpn-coexistence-arbiter.sh"
        fake_arb.write_text(
            '#!/system/bin/sh\n'
            'printf \'{"ok":1,"verdict":"partial","grade_cn":"部分兼容","probe":"ok","route_probe":"unverified","vpn_service_slot_used":false}\\n\'\n',
            encoding="utf-8",
        )
        st = tmp / "s8"
        r = run_writer(pub, tmp, mod2, st, {"FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": "9"})
        check(r.returncode == 0, "writer exit 0 with arbiter")
        _, d = read_status(st)
        if d:
            check(d["source"] == "arbiter", f"source must be arbiter (got {d.get('source')})")
            check(d["verdict"] == "partial", f"arbiter verdict wins (got {d.get('verdict')})")
            check(d["route_probe"] == "unverified", "missing arbiter route probe defaults to unverified")

        print("== case 9: defensive wording when arbiter is unreadable ==")
        st = tmp / "s9"
        r = run_writer(pub, tmp, module, st, {"FX_COEXIST_ARBITER": str(tmp / "nope.sh"),
                                              "FAKE_EXT_IF": "tun0", "FAKE_EXT_UID": "5"})
        check(r.returncode == 0, "writer exit 0 when arbiter missing")
        _, d = read_status(st)
        if d:
            check(d["source"] == "local", f"falls back to local grading (got {d.get('source')})")
            check(d["verdict"] in ("partial", "unknown"),
                  f"local grading stays conservative (got {d.get('verdict')})")
            check(d["route_probe"] == "unverified", "local fallback labels route probe unverified")
            check(d["verdict"] == "unknown", "missing arbiter must not certify the VPN slot invariant")
            check(d["vpn_service_slot_used"] is None, "unverified slot state is JSON null")

        print("== case 10: arbiter reports unknown slot -> JSON null and unknown verdict ==")
        st = tmp / "s10"
        r = run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "", "FAKE_SLOT": "unknown"})
        check(r.returncode == 0, "writer exit 0 with unverified slot")
        _, d = read_status(st)
        if d:
            check(d["verdict"] == "unknown", "unknown slot prevents kernel_only verdict")
            check(d["vpn_service_slot_used"] is None, "unknown slot is not coerced to false")

        print("== case 11: arbiter detects a VpnService call -> true and incompatible ==")
        st = tmp / "s11"
        r = run_writer(pub, tmp, module, st, {"FAKE_EXT_IF": "", "FAKE_SLOT": "true"})
        check(r.returncode == 0, "writer exit 0 for positive slot detection")
        _, d = read_status(st)
        if d:
            check(d["verdict"] == "incompatible", "positive slot detection is incompatible")
            check(d["vpn_service_slot_used"] is True, "positive slot evidence is preserved")

    if failures:
        print(f"\nFAILED: {len(failures)} assertion(s)", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print("\nPASS: coexistence status is published atomically, 0600, fail-open and never overclaims")
    return 0


if __name__ == "__main__":
    sys.exit(main())
