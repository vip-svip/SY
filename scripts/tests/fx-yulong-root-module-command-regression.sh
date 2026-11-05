#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HELPER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongRootModuleCommand.java"
HOST_TEST="$ROOT/scripts/tests/FxYulongRootModuleCommandHostTest.java"
AD="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
GENERAL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
WHITELIST="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$HELPER" "$HOST_TEST" "$AD" "$GENERAL" "$WHITELIST" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongVpnTileService.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java"; do
  [ -s "$file" ] || fail "Root module command integration file missing: $file"
done
python3 - "$HELPER" "$AD" "$GENERAL" "$WHITELIST" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongVpnTileService.java" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java" <<'PY'
from pathlib import Path
import sys
helper, ad, general, whitelist, widget, ad_tile, vpn_tile, tasker, ad_summary = [
    Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]
]
for token in (
    '"yulong-ad-control.sh".equals(name)',
    '"yulong-profiles.sh".equals(name)',
    '"yulong-app-whitelist.sh".equals(name)',
    '"yulong-vpn-control.sh".equals(name)',
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
widget_command = method(widget, "private static String shell(String operation)", "private static final class VpnState")
assert 'FxYulongRootModuleCommand.command("yulong-vpn-control.sh"' in widget_command and "MP='';" not in widget_command
ad_tile_command = method(ad_tile, "private String command(String args)", "private int readState()")
assert 'FxYulongRootModuleCommand.command("yulong-ad-control.sh", args)' in ad_tile_command and "MP='';" not in ad_tile_command
vpn_tile_command = method(vpn_tile, "private String vpnCommand(String action)", "private VpnState readState()")
assert 'FxYulongRootModuleCommand.command("yulong-vpn-control.sh"' in vpn_tile_command
assert '"$MP" /data/adb/privacyguard' in vpn_tile_command and "MP='';" not in vpn_tile_command
tasker_prefix = method(tasker, "private static String modulePrefix(String requiredScript)", "@Override public void onReceive")
assert "FxYulongRootModuleCommand.prefix(requiredScript)" in tasker_prefix and "MP='';" not in tasker_prefix
assert 'modulePrefix(adFilterAction ? "yulong-ad-control.sh" : "yulong-vpn-control.sh")' in tasker
summary_module = method(ad_summary, "private String moduleShell(String scriptArgs)", "private void root(")
assert 'FxYulongRootModuleCommand.command("yulong-ad-control.sh", scriptArgs)' in summary_module and "MP='';" not in summary_module
print("PASS: Ad profiles, General/import, whitelist, summary, widget, both tiles and Tasker use the shared Root module resolver")
PY

if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-root-command.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT HUP INT TERM
  javac -d "$WORK" "$HELPER" "$HOST_TEST"
  java -cp "$WORK" de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommandHostTest
else
  echo "SKIP: JDK unavailable; shared Root command builder Host test not executed."
fi
