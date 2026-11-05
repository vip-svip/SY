#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APP="$ROOT/scripts/applist.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'cannot enumerate installed packages' "$APP" || fail "no-enumeration path must fail clearly"
if grep -q '_pkgs="de.privacyguard.hook"' "$APP"; then fail "must not fabricate FX's legacy hook package"; fi
grep -q 'de.privacyguard.adhook|org.lsposed.manager' "$APP" || fail "must exclude module/manager packages"
TMP="${TMPDIR:-/tmp}/fx-applist-empty-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# No pm or system package database on host: command must fail without output rather than fake a target.
set +e
OUT=$(PG_HOME="$TMP/pg" PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" sh "$APP" 2>"$TMP/err")
RC=$?
set -e
[ "$RC" -ne 0 ] || fail "empty package enumeration must return failure"
[ -z "$OUT" ] || fail "empty package enumeration must not emit a fake JSON package"
grep -q 'cannot enumerate installed packages' "$TMP/err" || fail "failure reason must be explicit"
echo "PASS: app picker fails closed instead of fabricating a target package"
