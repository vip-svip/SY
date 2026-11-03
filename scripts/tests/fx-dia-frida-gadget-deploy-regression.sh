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

for label, needle in {
    "deploy action UI": 'button("部署 Gadget 到当前目标应用", () -> confirmDeployGadgetToTarget())',
    "remove action UI": 'button("移除当前目标的 FX Gadget 部署", () -> confirmRemoveGadgetFromTarget())',
    "deployment command builder": "buildDeployCommand(",
    "removal command builder": "buildRemoveCommand(",
}.items():
    haystack = activity if label.endswith("UI") else deploy
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
    "marker restricts process set": "processes=*",
    "marker binds port": "port=%s",
    "marker is committed after library and config": 'mv "$stage/$marker" "$dest/$marker"; new_m=1',
    "rollback trap": 'trap cleanup 0',
    "remove verifies marker package": 'grep -Fxq "package=$pkg"',
    "remove verifies current library/config hashes": 'FX_GADGET_HASH_CONFLICT',
    "remove rejects symlinked Gadget files": '[ -f "$dest/$gadget" ] && [ ! -L "$dest/$gadget" ]',
}.items():
    if needle not in deploy:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
if 'owner=$(stat -c \'%u:%g\' "$dest")' not in deploy:
    raise SystemExit("FAIL: deployment does not match staged files to app UID/GID")
lib_commit = deploy.find('mv "$stage/$gadget" "$dest/$gadget"; new_g=1')
config_commit = deploy.find('mv "$stage/$conf" "$dest/$conf"; new_c=1')
marker_commit = deploy.find('mv "$stage/$marker" "$dest/$marker"; new_m=1')
commit_flag = deploy.find('committed=1; echo FX_GADGET_DEPLOYED')
if min(lib_commit, config_commit, marker_commit, commit_flag) < 0 or not (lib_commit < config_commit < marker_commit < commit_flag):
    raise SystemExit("FAIL: target marker must be published after the Gadget library and config")
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
if "de.privacyguard.hook.DiaFridaTargetHook" not in merger:
    raise SystemExit("FAIL: unified Hook merge does not register the Dia target-side Gadget loader")
print("PASS: Dia Gadget deploy/remove UI, package scope, ABI, hashes and target loader contracts are present")
PY

echo "PASS: Gadget deploy/remove migration regression source checks"
