#!/usr/bin/env python3
"""Fix uninstall warning helper ordering and point installer guidance at native Hook UI."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
uninstall = root / "uninstall.sh"
customize = root / "customize.sh"
if not uninstall.is_file() or not customize.is_file():
    raise SystemExit("FX uninstall.sh or customize.sh is missing")

source = uninstall.read_text(encoding="utf-8")
helper = '''_mitm_warn() {
  _msg="PrivacyGuard uninstall warning: $*"
  echo "$_msg" >&2
  if command -v log >/dev/null 2>&1; then log -p w -t PrivacyGuardUninstall "$_msg" 2>/dev/null; fi
}
'''
if source.count(helper) != 1:
    raise SystemExit("uninstall warning helper does not match the reviewed source")
source = source.replace(helper, "", 1)
anchor = "PG_CLEANUP_INCOMPLETE=0\n"
if source.count(anchor) != 1:
    raise SystemExit("uninstall initialization anchor changed; refusing to move helper")
source = source.replace(anchor, anchor + helper, 1)
first_call = source.find('_mitm_warn "scheduler PID')
definition = source.find("_mitm_warn() {")
if first_call < 0 or definition < 0 or definition > first_call:
    raise SystemExit("uninstall warning helper is not defined before the scheduler cleanup path")
uninstall.write_text(source, encoding="utf-8")

ui = customize.read_text(encoding="utf-8")
# Release ZIPs may contain older customize.sh revisions whose wording differs
# from the exact source strings. Normalize the whole guidance lines instead of
# silently leaving stale split-WebUI/FXAdHook instructions behind.
import re
stale_patterns = (
    r"FX\s*WebUI.*Hook",
    r"Hook.*目标应用.*管理界面",
    r"FXAdHook\s*APK",
    r"FX\s*Ad\s*Hook",
    r"PrivacyGuardHook",
)
lines = ui.splitlines()
normalized = []
guidance = 'ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"'
for line in lines:
    if line.lstrip().startswith("ui_print") and any(
        re.search(pattern, line, re.IGNORECASE) for pattern in stale_patterns
    ):
        # Replace each stale output line in place. Removing one can leave an
        # otherwise empty if/then block and make customize.sh unparseable.
        indent = line[:len(line) - len(line.lstrip())]
        normalized.append(indent + guidance)
    else:
        normalized.append(line)
ui = "\n".join(normalized) + ("\n" if ui.endswith("\n") else "")
if any(
    re.search(pattern, line, re.IGNORECASE)
    for line in ui.splitlines() if line.lstrip().startswith("ui_print")
    for pattern in stale_patterns
):
    raise SystemExit("installer still advertises the retired WebUI/split Hook entry")
customize.write_text(ui, encoding="utf-8")

# settings.conf can contain subscription bearer URLs. The first-install copy in
# customize.sh bypasses service.sh's "file absent" chmod branch, so explicitly
# harden it after migration and again on every boot (including upgrades).
customize_text = customize.read_text(encoding="utf-8")
customize_block = '''if [ -f /data/adb/privacyguard/settings.conf ]; then
  chown 0:0 /data/adb/privacyguard/settings.conf 2>/dev/null || true
  if ! chmod 600 /data/adb/privacyguard/settings.conf 2>/dev/null; then
    ui_print "  [!] 无法将 settings.conf 权限收紧为 600；请检查 /data/adb/privacyguard/settings.conf"
  fi
fi
'''
customize_anchor = 'ui_print "- 清理历史版本残留的证书覆盖层/暂存区(如有)..."'
if customize_block not in customize_text:
    if customize_text.count(customize_anchor) != 1:
        raise SystemExit("customize.sh settings permission insertion anchor changed")
    customize_text = customize_text.replace(customize_anchor, customize_block + customize_anchor, 1)
customize.write_text(customize_text, encoding="utf-8")

service_text = service.read_text(encoding="utf-8")
service_block = '''# Protect subscription URLs and other private configuration on every boot.
if [ -f "$PG/settings.conf" ]; then
  chown 0:0 "$PG/settings.conf" 2>/dev/null || :
  if ! chmod 600 "$PG/settings.conf" 2>/dev/null; then
    echo "[$(date '+%m-%d %H:%M:%S')] WARNING: unable to restrict settings.conf permissions to 0600" >> "$PG/boot.log"
  fi
fi
'''
service_anchor = '# Restore only CA trust that the user explicitly enabled in WebUI.'
if service_block not in service_text:
    if service_text.count(service_anchor) != 1:
        raise SystemExit("service.sh settings permission insertion anchor changed")
    service_text = service_text.replace(service_anchor, service_block + service_anchor, 1)
service.write_text(service_text, encoding="utf-8")
print("Fixed uninstall warning order, native Hook installer guidance, and private settings.conf permissions.")
