#!/usr/bin/env python3
"""Execute the Yulong whitelist Release patcher against a minimal FX module fixture."""
from pathlib import Path
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_yulong_app_whitelist.py"
WHITELIST = ROOT / "scripts/yulong-app-whitelist.sh"
WHITELIST_TEST = ROOT / "scripts/tests/fx-yulong-app-whitelist-runtime-regression.sh"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for required in (PATCHER, WHITELIST, WHITELIST_TEST):
    assert required.is_file(), f"missing patcher input: {required}"

with tempfile.TemporaryDirectory(prefix="fx-yulong-whitelist-patcher-") as td:
    temp = Path(td)
    repo = temp / "repo"
    module = temp / "module"
    (repo / "fx-patches").mkdir(parents=True)
    (repo / "scripts/tests").mkdir(parents=True)
    (module / "scripts").mkdir(parents=True)
    shutil.copy2(PATCHER, repo / "fx-patches/patch_yulong_app_whitelist.py")
    shutil.copy2(WHITELIST, repo / "scripts/yulong-app-whitelist.sh")
    shutil.copy2(WHITELIST_TEST, repo / "scripts/tests/fx-yulong-app-whitelist-runtime-regression.sh")

    # Minimal source anchors representing the real restored FX Release layout.
    (module / "scripts/vpncore.sh").write_text(
        "vpncore_genconf() {\n"
        "  printf '{\\"type\\":\\"tun\\",\\"exclude_uid\\":[0]}\\\\n'\n"
        "}\n", encoding="utf-8"
    )
    (module / "scripts/yulong-root-proxy.sh").write_text(
        "_build_chain4() {\n"
        '  iptables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1\n'
        "}\n"
        "_build_chain6() {\n"
        '  ip6tables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1\n'
        "}\n", encoding="utf-8"
    )
    (module / "scripts/apply.sh").write_text(
        "  nat4 -N PGNAT 2>/dev/null\n"
        "  ip6tables $FWWAIT -t nat -N PGNAT >/dev/null 2>&1 || _agh6_ok=0\n"
        "  for _mu in $VPN_MOD_UIDS; do\n"
        "    nat4 -A PGVPN -m owner --uid-owner \\"$_mu\\" -j RETURN 2>/dev/null\n"
        "  done\n"
        "    for _mu in $VPN_MOD_UIDS; do\n"
        "      nat6 -A PGVPN6 -m owner --uid-owner \\"$_mu\\" -j RETURN 2>/dev/null\n"
        "    done\n"
        "# 提交 nat 表队列（只提交 nat 部分，filter/mangle 队列保持不动）\n",
        encoding="utf-8"
    )
    patcher = repo / "fx-patches/patch_yulong_app_whitelist.py"

    def apply_patcher():
        result = subprocess.run(
            [sys.executable, str(patcher), str(module)],
            cwd=repo, text=True, capture_output=True, check=False
        )
        assert result.returncode == 0, (
            "Yulong whitelist patcher failed:\n" + result.stdout + "\n" + result.stderr
        )

    apply_patcher()
    script_target = module / "scripts/yulong-app-whitelist.sh"
    test_target = module / "scripts/tests/v1.0.0-yulong-app-whitelist-runtime-regression.sh"
    assert script_target.read_bytes() == WHITELIST.read_bytes(), "Release whitelist source is stale"
    assert test_target.read_bytes() == WHITELIST_TEST.read_bytes(), "Release whitelist test is stale"
    assert stat.S_IMODE(script_target.stat().st_mode) == 0o755, "Release whitelist script is not executable"
    assert stat.S_IMODE(test_target.stat().st_mode) == 0o755, "Release whitelist test is not executable"

    vpncore = (module / "scripts/vpncore.sh").read_text(encoding="utf-8")
    proxy = (module / "scripts/yulong-root-proxy.sh").read_text(encoding="utf-8")
    apply = (module / "scripts/apply.sh").read_text(encoding="utf-8")
    assert "vpncore_yulong_exclude_uids()" in vpncore and '"exclude_uid":[%s]' in vpncore
    assert proxy.count("yulong_app_whitelist") == 2, "both IPv4 and IPv6 Root Proxy chains need bypass rules"
    for marker in (
        "pg_yulong_whitelist_dns4", "pg_yulong_whitelist_dns6",
        "pg_yulong_whitelist_vpn4", "pg_yulong_whitelist_vpn6"
    ):
        assert marker in apply, f"legacy NAT bypass path missing: {marker}"

    first = {
        p: digest(module / p)
        for p in ("scripts/vpncore.sh", "scripts/yulong-root-proxy.sh", "scripts/apply.sh",
                  "scripts/yulong-app-whitelist.sh",
                  "scripts/tests/v1.0.0-yulong-app-whitelist-runtime-regression.sh")
    }
    apply_patcher()
    second = {
        p: digest(module / p)
        for p in first
    }
    assert first == second, "Yulong whitelist patcher is not idempotent"

print("PASS: whitelist Release patcher applies TUN/Root Proxy/NAT bypass, stages identical executable source/tests, and is idempotent")
