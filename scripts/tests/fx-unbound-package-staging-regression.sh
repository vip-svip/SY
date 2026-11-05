#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PACKAGE="$ROOT/.github/workflows/build-fx-kernelsu.yml"
UNBOUND="$ROOT/.github/workflows/build-unbound-android-arm64.yml"
[ -s "$PACKAGE" ] || { echo "FAIL: KernelSU package workflow missing" >&2; exit 1; }
[ -s "$UNBOUND" ] || { echo "FAIL: Unbound ARM64 build workflow missing" >&2; exit 1; }
python3 - "$PACKAGE" "$UNBOUND" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

package = Path(sys.argv[1]).read_text(encoding="utf-8")
unbound = Path(sys.argv[2]).read_text(encoding="utf-8")
root = Path(sys.argv[1]).parents[2]
module_script_path = root / "fx-module/scripts/unbound.sh"
root_proxy_path = root / "fx-module/scripts/yulong-root-proxy.sh"
assert module_script_path.is_file(), "tracked FX Unbound lifecycle script missing"
assert root_proxy_path.is_file(), "tracked FX Root Proxy lifecycle script missing"
module_script = module_script_path.read_text(encoding="utf-8")
root_proxy = root_proxy_path.read_text(encoding="utf-8")
for token in (
    'ROOT="$MODDIR/engines/unbound"',
    'BIN="$ROOT/unbound"',
    'CHECKBIN="$ROOT/unbound-checkconf"',
    'ANCHOR="$ROOT/unbound-anchor"',
    'PROBE="$ROOT/fx-dns-probe"',
    'ROOT_HINTS="$ROOT/root.hints"',
    'ROOT_KEY_SEED="$ROOT/root.key.seed"',
    '_hash "$BIN" "$ROOT/unbound.sha256"',
    '_hash "$ROOT_HINTS" "$ROOT/root.hints.sha256"',
    'interface: 127.0.0.1',
    'port: 5353',
    'do-tcp: yes',
    'do-udp: yes',
):
    assert token in module_script, f"FX Unbound lifecycle contract missing: {token}"
assert 'sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG"' in root_proxy, "Root Proxy does not start the independent local Unbound resolver"
start = package.find("      - name: Stage checksum-verified Unbound Android ARM64 runtime\n")
end = package.find("      - name: Decode and integrate Yulong 7.0.1 built-in DNS/Hosts rules", start)
assert start >= 0 and end > start, "KernelSU package must stage Unbound before Yulong DNS/Hosts integration"
section = package[start:end]
required = (
    'GH_TOKEN: ${{ github.token }}',
    'gh run list --workflow "$workflow"',
    '--status success',
    'artifact_sha="$(gh run view "$run_id"',
    'source_sha="$(git log -1 --format=%H',
    '"$artifact_sha" = "$source_sha"',
    'gh run download "$run_id"',
    'fx-unbound-android-arm64-v1.26.2',
    'destination="fx-module/engines/unbound"',
    'for executable in unbound unbound-checkconf unbound-anchor fx-dns-probe',
    'for data_file in root.hints root.key.seed',
    'sha256sum "$source_dir/$executable"',
    'sha256sum "$source_dir/$data_file"',
    'ROOT="$MODDIR/engines/unbound"',
    'sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG"',
)
for token in required:
    assert token in section, f"Unbound package staging is missing contract: {token}"
assert "Upload local recursive DNS runtime" in unbound
assert "name: fx-unbound-android-arm64-v1.26.2" in unbound
assert "interface: 127.0.0.1" in unbound and "port: 5353" in unbound
assert "access-control: 127.0.0.0/8 allow" in unbound
assert "do-ip6: yes" in unbound and "do-tcp: yes" in unbound
run_marker = "        run: |\n"
run_start = section.find(run_marker)
assert run_start >= 0, "Unbound staging step must have an executable run block"
shell_lines = section[run_start + len(run_marker):].splitlines()
shell = "\n".join(line[10:] if line.startswith("          ") else line for line in shell_lines)
with tempfile.NamedTemporaryFile("w", suffix=".sh", encoding="utf-8", delete=False) as f:
    f.write(shell)
    shell_path = f.name
try:
    subprocess.run(["bash", "-n", shell_path], check=True)
finally:
    Path(shell_path).unlink(missing_ok=True)
print("PASS: final KernelSU package stages only the latest successful, checksum-verified Unbound ARM64 runtime at the exact Root Proxy lifecycle paths")
PY
