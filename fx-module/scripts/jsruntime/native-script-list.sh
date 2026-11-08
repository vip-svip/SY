#!/system/bin/sh
# Compatibility entry point retained for older FX callers.
# Keep one canonical script-list implementation so imports, duplicate handling,
# transaction locking and file staging cannot drift between two stores.
set -u
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
[ -n "$SELF_DIR" ] && [ -x "$SELF_DIR/native-list.sh" ] || {
  echo "ERROR canonical native script list unavailable"
  exit 127
}
exec sh "$SELF_DIR/native-list.sh" "$@"
