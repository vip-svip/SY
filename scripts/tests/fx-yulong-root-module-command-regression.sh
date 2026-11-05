#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HELPER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongRootModuleCommand.java"
HOST_TEST="$ROOT/scripts/tests/FxYulongRootModuleCommandHostTest.java"
AD="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
GENERAL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
WHITELIST="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$HELPER" "$HOST_TEST" "$AD" "$GENERAL" "$WHITELIST"; do
  [ -s "$file" ] || fail "Root module command integration file missing: $file"
done
python3 - "$HELPER" "$AD" "$GENERAL" "$WHITELIST" <<'PY'
from pathlib import Path
import sys
helper, ad, general, whitelist = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
for token in (
    '"yulong-ad-control.sh".equals(name)',
    '"yulong-profiles.sh".equals(name)',
    '"yulong-app-whitelist.sh".equals(name)',
    "[ -d '/data' ]", "[ ! -L '/data' ]",
    "[ -d '/data/adb' ]", "[ ! -L '/data/adb' ]",
    "[ -d '/data/adb/modules' ]", "[ ! -L '/data/adb/modules' ]",
    "grep -qx 'id=privacyguard'", "grep -qx 'version=1.0.0'",
    r'&& [ -f \"$d/module.prop\" ] && [ ! -L \"$d/module.prop\" ]',
    r'&& [ -d \"$d/scripts\" ] && [ ! -L \"$d/scripts\" ]',
    r'&& [ -f \"$d/scripts/util.sh\" ] && [ ! -L \"$d/scripts/util.sh\" ]',
):
    assert token in helper, "shared resolver misses required guard: " + token

def method(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start + len(signature))
    return source[start:end]

profile = method(ad, "private String profileCmd(String args)", "private boolean isTrustedNetworkPageCurrent")
assert 'FxYulongRootModuleCommand.command("yulong-profiles.sh", args)' in profile
assert "MP='';" not in profile

general_root = method(general, "private String rootCommand(String args)", "private RootAccess.Result root(")
assert 'FxYulongRootModuleCommand.command("yulong-ad-control.sh", args)' in general_root
assert "MP='';" not in general_root

general_import_start = general.index('StringBuilder command=new StringBuilder("set -eu; ");')
general_import_end = general.index("RootAccess.Result result=RootAccess.execute(command.toString()", general_import_start)
general_import = general[general_import_start:general_import_end]
assert 'command.append(FxYulongRootModuleCommand.prefix("yulong-ad-control.sh"))' in general_import
assert "MP='';" not in general_import

whitelist_command = method(whitelist, "private String command(String args)", "private void root(")
assert 'FxYulongRootModuleCommand.command("yulong-app-whitelist.sh", args)' in whitelist_command
assert "MP='';" not in whitelist_command
print("PASS: Ad profiles, General settings/import and app whitelist use the shared Root module resolver")
PY

if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-root-command.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM
  javac -d "$WORK" "$HELPER" "$HOST_TEST"
  java -cp "$WORK" de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommandHostTest
else
  echo "SKIP: JDK unavailable; shared Root command builder Host test not executed."
fi
