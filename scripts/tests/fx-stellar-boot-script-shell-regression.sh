#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE="$ROOT/scripts/yulong-stellar-control.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Stellar control source missing"
sh -n "$SOURCE" || fail "Stellar control source shell syntax invalid"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-stellar-boot-script.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/data/adb" "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs" "$TMP/bin" "$TMP/app/lib/arm64-v8a"
: > "$TMP/app/base.apk"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ "$1" = path ] && [ "$2" = de.privacyguard.adhook ] || exit 2
printf 'package:%s\n' "$MOCK_FX_APK"
PM
cat > "$TMP/bin/getprop" <<'GETPROP'
#!/bin/sh
[ "${1:-}" = sys.boot_completed ] && { echo 1; exit 0; }
exit 1
GETPROP
cat > "$TMP/bin/sleep" <<'SLEEP'
#!/bin/sh
exit 0
SLEEP
chmod 0755 "$TMP/bin/pm" "$TMP/bin/getprop" "$TMP/bin/sleep"
cat > "$TMP/app/lib/arm64-v8a/libstellar.so" <<LAUNCHER
#!/bin/sh
printf 'FX_STELLAR_LAUNCHER_EXECUTED\n' > "$TMP/launched.marker"
LAUNCHER
chmod 0755 "$TMP/app/lib/arm64-v8a/libstellar.so"
export MOCK_FX_APK="$TMP/app/base.apk"
export PATH="$TMP/bin:$PATH"

# Redirect only fixed filesystem roots in an isolated script copy; command
# grammar and boot script body remain byte-for-byte identical.
sed \
  -e "s|^DIR=/data/local/tmp/stellar_guard$|DIR=$TMP/stellar_guard|" \
  -e "s|/data/adb|$TMP/data/adb|g" \
  -e "s|/data/local/tmp/fx_stellar_boot.log|$TMP/fx_stellar_boot.log|g" \
  -e "s|^DROP_PREFS_FILE=.*$|DROP_PREFS_FILE=$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml|" \
  "$SOURCE" > "$TMP/control.sh"
sh -n "$TMP/control.sh" || fail "isolated control script shell syntax invalid"
run(){ sh "$TMP/control.sh" "$@"; }

status=$(run boot-script status)
printf '%s\n' "$status" | grep -Fq 'boot_script=absent' || fail "new install must report no boot script"
installed=$(run boot-script install)
printf '%s\n' "$installed" | grep -Fq 'success=1 boot_script=installed' || fail "boot script install did not report success"
SCRIPT="$TMP/data/adb/service.d/stellar.sh"
[ -f "$SCRIPT" ] && [ -x "$SCRIPT" ] || fail "boot script was not installed as an executable file"
grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$SCRIPT" || fail "FX boot script ownership marker missing"
grep -Fq 'de.privacyguard.adhook' "$SCRIPT" || fail "boot script does not resolve the FX Hook application id"
grep -Fq 'libstellar.so' "$SCRIPT" || fail "boot script does not invoke the packaged Stellar daemon"
grep -Fq 'sys.boot_completed' "$SCRIPT" || fail "boot script does not wait for Android boot completion"
grep -Fq '[ "$i" -lt 100 ]' "$SCRIPT" || fail "boot script wait has no finite deadline"
grep -Fq 'com.youlong.hd' "$SCRIPT" && fail "boot script still resolves the original package id"
status=$(run boot-script status)
printf '%s\n' "$status" | grep -Fq 'boot_script=installed' || fail "status must detect the installed FX boot script"

cat > "$TMP/app/lib/arm64-v8a/libchid.so" <<CHID
#!/bin/sh
printf '%s|%s\\n' "$1" "$2" > "$TMP/chid.args"
"$2"
CHID
chmod 0755 "$TMP/app/lib/arm64-v8a/libchid.so"
# Run the generated boot script against mock Android commands and a fake
# executable payload: this verifies the installed script actually resolves
# and executes the selected ABI launcher rather than only existing on disk.
sh "$SCRIPT" || fail "generated boot script failed with a ready boot property"
# Original Starter.getInternalCommand() uses libchid.so 2000 libstellar.so
# when drop_privileges=true. The FX boot script must preserve that mode.
cat > "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml" <<PREFS
<map><boolean name="drop_privileges" value="true" /></map>
PREFS
rm -f "$TMP/launched.marker" "$TMP/chid.args"
sh "$SCRIPT" || fail "boot script rejected a valid drop_privileges preference"
grep -Fq "2000|$TMP/app/lib/arm64-v8a/libstellar.so" "$TMP/chid.args" || fail "boot script did not call libchid with UID 2000 and libstellar path"
[ "$(cat "$TMP/launched.marker")" = "FX_STELLAR_LAUNCHER_EXECUTED" ] || fail "libchid did not launch libstellar"

# Missing helper must never silently fall back to root.
rm -f "$TMP/app/lib/arm64-v8a/libchid.so" "$TMP/launched.marker" "$TMP/chid.args"
if sh "$SCRIPT"; then fail "drop_privileges silently fell back to root without libchid"; fi
[ ! -e "$TMP/launched.marker" ] || fail "root launcher ran after libchid was missing"
cat > "$TMP/app/lib/arm64-v8a/libchid.so" <<CHID
#!/bin/sh
printf '%s|%s\\n' "$1" "$2" > "$TMP/chid.args"
"$2"
CHID
chmod 0755 "$TMP/app/lib/arm64-v8a/libchid.so"

status=$(run boot-script status)
printf '%s\\n' "$status" | grep -Fq 'drop_privileges=1' || fail "status omitted the active drop_privileges setting"

# A preference symlink is never followed or interpreted as a request for root launch.
mv "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml" "$TMP/settings.saved"
ln -s "$TMP/settings.saved" "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml"
if sh "$SCRIPT"; then fail "boot script followed a symlinked drop_privileges preference"; fi
rm "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml"
mv "$TMP/settings.saved" "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml"

[ "$(cat "$TMP/launched.marker")" = "FX_STELLAR_LAUNCHER_EXECUTED" ] || fail "generated boot script did not execute the located launcher"
[ -s "$TMP/fx_stellar_boot.log" ] || fail "boot script did not record its launch result"

# The installer must fail closed when the package or executable payload is
# missing, without replacing a previously installed working script.
cp "$SCRIPT" "$TMP/known-good-script"
rm "$TMP/app/lib/arm64-v8a/libchid.so"
if run boot-script install >/dev/null 2>&1; then fail "installer accepted drop_privileges without libchid.so"; fi
cmp -s "$SCRIPT" "$TMP/known-good-script" || fail "missing libchid replaced the known-good boot script"
cat > "$TMP/app/lib/arm64-v8a/libchid.so" <<CHID
#!/bin/sh
printf '%s|%s\\n' "$1" "$2" > "$TMP/chid.args"
"$2"
CHID
chmod 0755 "$TMP/app/lib/arm64-v8a/libchid.so"

# Switch back to the default Root preference for the following legacy-install checks.
cat > "$TMP/data/user_de/0/de.privacyguard.adhook/shared_prefs/settings.xml" <<PREFS
<map><boolean name="drop_privileges" value="false" /></map>
PREFS
rm -rf "$TMP/app/lib"
if run boot-script install >/dev/null 2>&1; then fail "installer accepted an app package without libstellar.so"; fi
cmp -s "$SCRIPT" "$TMP/known-good-script" || fail "failed reinstall replaced the known-good boot script"
mkdir -p "$TMP/app/lib/arm64-v8a"
cat > "$TMP/app/lib/arm64-v8a/libstellar.so" <<LAUNCHER
#!/bin/sh
exit 0
LAUNCHER
chmod 0755 "$TMP/app/lib/arm64-v8a/libstellar.so"

# An unrelated file or a symlink at the managed path must never be silently
# replaced or removed.
printf 'user-owned-script\n' > "$TMP/user-owned"
cp "$TMP/user-owned" "$SCRIPT"
if run boot-script install >/dev/null 2>&1; then fail "installer overwrote an unrecognized user-owned script"; fi
[ "$(cat "$SCRIPT")" = "user-owned-script" ] || fail "unrecognized boot script content changed"
if run boot-script remove >/dev/null 2>&1; then fail "remover deleted an unrecognized user-owned script"; fi
[ "$(cat "$SCRIPT")" = "user-owned-script" ] || fail "unrecognized boot script was removed"

rm -f "$SCRIPT"
ln -s "$TMP/user-owned" "$SCRIPT"
if run boot-script install >/dev/null 2>&1; then fail "installer followed a symlink at the managed boot script path"; fi
if run boot-script remove >/dev/null 2>&1; then fail "remover followed a symlink at the managed boot script path"; fi
[ "$(cat "$TMP/user-owned")" = "user-owned-script" ] || fail "boot script symlink handling modified the target"
rm -f "$SCRIPT"

# The original Stellar BootScriptManager script is recognized for migration,
# but the FX replacement and removal are still scoped to this exact file.
printf '%s\n' '#!/system/bin/sh' 'S=$(ls $(pm path com.youlong.hd | cut -d: -f2 | sed "s/base.apk//")lib/*/libstellar.so | head -n 1); [ -n "$S" ] && "$S"' > "$SCRIPT"
chmod 0755 "$SCRIPT"
status=$(run boot-script status)
printf '%s\n' "$status" | grep -Fq 'boot_script=legacy' || fail "original Stellar boot script was not recognized as a migration candidate"
run boot-script install >/dev/null
grep -Fq '# FX_STELLAR_BOOT_SCRIPT_V1' "$SCRIPT" || fail "recognized legacy script was not atomically migrated"
run boot-script remove >/dev/null
[ ! -e "$SCRIPT" ] || fail "remove left the FX boot script installed"
status=$(run boot-script status)
printf '%s\n' "$status" | grep -Fq 'boot_script=absent' || fail "remove did not return to the absent state"

# Command dispatcher rejects unsupported arity/actions.
if run boot-script 'install;id' >/dev/null 2>&1; then fail "boot script dispatcher accepted shell syntax as an action"; fi
if run boot-script execute >/dev/null 2>&1; then fail "boot script dispatcher accepted an unsupported operation"; fi
! find "$TMP/data/adb/service.d" -maxdepth 1 -name '.stellar.sh.fx.*' -print -quit | grep -q . || fail "boot script temporary file leaked"
echo "PASS: Stellar SCRIPT boot manager, Shell UID 2000 drop_privileges, fail-closed helper/read protection, legacy migration and symlink/overwrite protection"
