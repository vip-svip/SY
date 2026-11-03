#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
DEPLOY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGadgetDeployment.java"
TARGET_HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/hook/DiaFridaTargetHook.java"
MERGER="$ROOT/fx-patches/merge_hook_single_apk.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACTIVITY" "$DEPLOY" "$TARGET_HOOK" "$MERGER"; do
  [ -s "$file" ] || fail "required Dia Gadget deployment source missing: $file"
done
python3 - "$ACTIVITY" "$DEPLOY" "$TARGET_HOOK" "$MERGER" <<'PY'
from pathlib import Path
import sys
activity = Path(sys.argv[1]).read_text(encoding="utf-8")
deploy = Path(sys.argv[2]).read_text(encoding="utf-8")
hook = Path(sys.argv[3]).read_text(encoding="utf-8")
merger = Path(sys.argv[4]).read_text(encoding="utf-8")

# Normalize escaped double quotes in Java command strings before checking the generated shell contract.
deploy_contract = deploy.replace(chr(92) + '"', '"')


for label, needle in {
    "deploy action UI": 'button("部署 Gadget 到当前目标应用", () -> confirmDeployGadgetToTarget())',
    "remove action UI": 'button("移除当前目标的 FX Gadget 部署", () -> confirmRemoveGadgetFromTarget())',
    "deployment command builder": "buildDeployCommand(",
    "removal command builder": "buildRemoveCommand(",
    "LSPosed target scope instructions": "在 LSPosed 中启用 FX 对该目标的作用域",
    "restart after Gadget deployment": "完全停止并重启目标应用",
    "re-deploy after app update": "需要重新部署",
    "one process selector UI": "private EditText gadgetProcess",
    "default to target main process": "gadgetProcess.setText(targetPackage)",
    "process selection passed to deployment backend": "port, processName",
    "process selection saved across recreation": 'outState.putString("fx_frida_gadget_process"',
    "process selection restored after recreation": 'state.getString("fx_frida_gadget_process"',
}.items():
    activity_labels = {
        "deploy action UI",
        "remove action UI",
        "LSPosed target scope instructions",
        "restart after Gadget deployment",
        "re-deploy after app update",
        "one process selector UI",
        "default to target main process",
        "process selection saved across recreation",
        "process selection restored after recreation",
    }
    haystack = activity if label in activity_labels else deploy_contract
    if needle not in haystack:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

for label, needle in {
    "user-install/debuggable gate": "ApplicationInfo.FLAG_DEBUGGABLE",
    "system-app exclusion": "ApplicationInfo.FLAG_SYSTEM",
    "package native library directory": "info.nativeLibraryDir",
    "native library path constrained to /data/app": 'path.startsWith("/data/app/")',
    "Gadget ELF ABI validation": "matchesElfAbi",
    "deployment rejects invalid/default ports": "if (!isValidListenPort(expectedPort))",
    "Root command builder rejects invalid/default ports": "if (!isValidListenPort(port))",
    "port policy is enforced centrally": "return port >= 1024 && port <= 65535 && port != 27042;",
    "library size bounded to 150 MiB": "150L * 1024L * 1024L",
    "config size bounded to 16 KiB": "16L * 1024L",
    "loopback Listen config verified": '"127.0.0.1".equals(interaction.optString("address"))',
    "random same-filesystem staging directory": '.fx-dia-gadget-deploy.XXXXXX',
    "per-target deploy lock": ".fx-dia-gadget.deploy.lock",
    "source and config symlink rejection": '[ ! -L "$src" ]',
    "target directory symlink rejection": '[ -d "$dest" ] && [ ! -L "$dest" ]',
    "Gadget file hash created": 'libhash=$(sha256sum "$stage/$gadget"',
    "config file hash created": 'confhash=$(sha256sum "$stage/$conf"',
    "marker binds exact package": "package=%s",
    "marker process is bound to one named process": "processes=%s",
    "process name validator is available": "validateProcessName",
    "marker binds port": "port=%s",
    "marker is committed after library and config": 'mv "$stage/$marker" "$dest/$marker"; new_m=1',
    "rollback trap": 'trap cleanup 0',
    "remove verifies marker package": 'grep -Fxq "package=$pkg"',
    "remove verifies current library/config hashes": 'FX_GADGET_HASH_CONFLICT',
    "remove rejects symlinked Gadget files": '[ -f "$dest/$gadget" ] && [ ! -L "$dest/$gadget" ]',
}.items():
    if needle not in deploy_contract:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
if 'owner=$(stat -c \'%u:%g\' "$dest")' not in deploy_contract:
    raise SystemExit("FAIL: deployment does not match staged files to app UID/GID")
lib_commit = deploy_contract.find('mv "$stage/$gadget" "$dest/$gadget"; new_g=1')
config_commit = deploy_contract.find('mv "$stage/$conf" "$dest/$conf"; new_c=1')
marker_commit = deploy_contract.find('mv "$stage/$marker" "$dest/$marker"; new_m=1')
commit_flag = deploy_contract.find('committed=1; echo FX_GADGET_DEPLOYED')
if min(lib_commit, config_commit, marker_commit, commit_flag) < 0 or not (lib_commit < config_commit < marker_commit < commit_flag):
    raise SystemExit("FAIL: target marker must be published after the Gadget library and config")
matcher_start = hook.find("private static boolean matchesProcess(")
if matcher_start < 0:
    raise SystemExit("FAIL: target loader exact process matcher is missing")
matcher_end = hook.find("\\n    }", matcher_start)
if matcher_end < 0:
    raise SystemExit("FAIL: target loader process matcher body is incomplete")
matcher = hook[matcher_start:matcher_end]
if '"*".equals(allowed)' in matcher or 'allowed.split(' in matcher:
    raise SystemExit("FAIL: target loader still accepts wildcard or multi-process Gadget markers")
if "allowed.equals(process)" not in matcher:
    raise SystemExit("FAIL: target loader does not require exact Gadget process identity")

for label, needle in {
    "marker schema checked": 'MARKER_SCHEMA.equals(record.get("schema"))',
    "package identity checked": 'expectedPackage.equals(record.get("package"))',
    "process identity checked": "matchesProcess(markerProcesses, expectedProcess)",
    "marker port syntax checked": 'markerPort.matches("[0-9]{4,5}")',
    "config port must equal marker port": "Integer.toString(configPort).equals(markerPort)",
    "library/config SHA checked": 'constantEquals(record.get("library_sha256"), libraryHash)',
    "absolute Gadget load": "System.load(gadget.getAbsolutePath())",
}.items():
    if needle not in hook:
        raise SystemExit(f"FAIL: target loader {label}: missing {needle!r}")
if "processes=*" in deploy_contract:
    raise SystemExit("FAIL: Gadget marker must bind one explicit process per listener port")
if "de.privacyguard.hook.DiaFridaTargetHook" not in merger:
    raise SystemExit("FAIL: unified Hook merge does not register the Dia target-side Gadget loader")
print("PASS: Dia Gadget deploy/remove UI, package scope, ABI, hashes and target loader contracts are present")
PY

echo "PASS: Gadget deploy/remove migration regression source checks"
