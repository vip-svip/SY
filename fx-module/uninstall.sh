#!/system/bin/sh
# KernelSU uninstall hook: remove only Hook APKs explicitly owned by FX.
MODDIR=${MODDIR:-$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)}
STATE_DIR=/data/adb/privacyguard
REMOVER="$MODDIR/scripts/remove_adhook_app.sh"
if [ -f "$REMOVER" ]; then
  sh "$REMOVER" "$MODDIR" "$STATE_DIR"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    echo "FX uninstall: one or more FX-owned Hook packages could not be removed; see $STATE_DIR/adhook-install.log" >&2
  fi
  exit "$_rc"
fi
echo "FX uninstall: Hook remover missing; leaving installed packages untouched" >&2
exit 0
