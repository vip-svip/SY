#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SERVICE="$ROOT/fx-module/service.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -s "$SERVICE" ] || fail "FX boot service source missing"

T=$(mktemp -d "${TMPDIR:-/tmp}/fx-service-state.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM

awk '
  /^# >>> fx-service-state-dir-guard$/ { capture=1; next }
  /^# <<< fx-service-state-dir-guard$/ { capture=0; found=1; next }
  capture { print }
  END { if (!found) exit 2 }
' "$SERVICE" > "$T/guard.sh" || fail "state-directory guard markers missing"
[ -s "$T/guard.sh" ] || fail "state-directory guard extraction empty"
sh -n "$T/guard.sh" || fail "extracted guard shell syntax invalid"
. "$T/guard.sh"

mkdir -p "$T/root/data/adb"
SAFE="$T/root/data/adb/privacyguard"
pg_ensure_state_dir "$SAFE" || fail "safe absent state directory was not created"
[ -d "$SAFE" ] && [ ! -L "$SAFE" ] || fail "safe state directory has wrong type"
pg_ensure_state_dir "$SAFE" || fail "existing real state directory is not idempotent"

mkdir -p "$T/real-target"
ln -s "$T/real-target" "$T/root/data/adb/final-link"
if pg_ensure_state_dir "$T/root/data/adb/final-link"; then
  fail "final-component symlink was accepted"
fi
[ -z "$(find "$T/real-target" -mindepth 1 -print -quit)" ] || fail "symlink target was modified"

mkdir -p "$T/real-parent"
ln -s "$T/real-parent" "$T/root/data/adb/parent-link"
if pg_ensure_state_dir "$T/root/data/adb/parent-link/child"; then
  fail "parent-component symlink was accepted"
fi
[ ! -e "$T/real-parent/child" ] || fail "parent symlink target was modified"

printf 'not a directory\n' > "$T/root/data/adb/not-a-directory"
if pg_ensure_state_dir "$T/root/data/adb/not-a-directory"; then
  fail "regular file at state path was accepted"
fi
if pg_ensure_state_dir "$T/root/data/adb/../traversal"; then
  fail "parent traversal path was accepted"
fi
if pg_ensure_state_dir "relative/state"; then
  fail "relative state path was accepted"
fi

grep -Fq 'if ! pg_ensure_state_dir "$PG"; then' "$SERVICE" || fail "boot service does not enforce the guard before state writes"
! grep -Fq 'mkdir -p "$PG"' "$SERVICE" || fail "unguarded mkdir -p remains in boot service"

echo "PASS: FX boot state directory creation is absolute, idempotent, and rejects symlink/traversal/file paths"
