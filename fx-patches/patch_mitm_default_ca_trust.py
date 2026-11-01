#!/usr/bin/env python3
"""Make the per-device MITM CA trusted by default without auto-enabling traffic interception."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
customize = root / "customize.sh"
certmgr = root / "scripts/certmgr.sh"
tests = root / "scripts/tests/v1.0.0-mitm-default-ca-trust-regression.sh"

for p in (customize, certmgr):
    if not p.is_file():
        raise SystemExit(f"required FX source missing: {p}")

s = customize.read_text(encoding="utf-8")
start_marker = 'ui_print "- 初始化独立 CA 子模块..."'
end_marker = '# 不分发静态共享 CA 私钥'
if start_marker not in s or end_marker not in s:
    raise SystemExit("customize.sh CA initialization block does not match reviewed source")
start = s.index(start_marker)
end = s.index(end_marker, start)
new_block = r'''ui_print "- 初始化并配置 MITM 系统 CA..."
# 首次安装默认创建本机独立 MITM CA，并部署到 Android 系统/Conscrypt 信任库。
# 已存在 ca-trust-optin 表示用户此前管理过 CA：升级时保留每张 CA 的启用/禁用状态。
# 已明确移除 MITM CA 的用户选择通过独立标记持久化，升级时不会自动复活。
if [ -f "$MODPATH/scripts/certmgr.sh" ]; then
  _pg_ca_state_dir=/data/adb/privacyguard
  _pg_ca_install_log="$_pg_ca_state_dir/ca-install.log"
  mkdir -p "$_pg_ca_state_dir" 2>/dev/null
  if sh "$MODPATH/scripts/certmgr.sh" builtin release "$MODPATH/certs" >>"$_pg_ca_install_log" 2>&1; then
    if [ -f "$_pg_ca_state_dir/ca-trust-optin" ]; then
      ui_print "  检测到已有 CA 管理记录；保留用户当前启用/禁用状态"
    elif [ -f "$_pg_ca_state_dir/ca-mitm-user-removed" ] || [ -f /data/adb/modules/pg_mitm_ca/remove ]; then
      ui_print "  检测到用户曾移除 MITM CA；尊重移除选择，不自动恢复"
    elif sh "$MODPATH/scripts/mitm-engine.sh" trust-ca >>"$_pg_ca_install_log" 2>&1; then
      ui_print "  [✓] 已生成本机独立 MITM CA 并启用系统信任（不写入用户证书区）"
      ui_print "      HTTPS 流量重定向仍保持关闭；需配置 MITM 主机白名单后手动启用"
    else
      ui_print "  [!] MITM CA 默认信任初始化失败；未启用 HTTPS 重定向，详情见 ca-install.log"
    fi
  else
    ui_print "  [!] CA 子模块释放/迁移失败；未启用 HTTPS 重定向，详情见 ca-install.log"
  fi
else
  ui_print "  [!] 未找到 certmgr.sh，未安装 MITM CA"
fi
'''
s = s[:start] + new_block + s[end:]
customize.write_text(s, encoding="utf-8")

c = certmgr.read_text(encoding="utf-8")
old = '''          id=$(basename "$tmpl")
          dest="$SM/$id"
          # 用户曾用管理器删除该子模块 → 尊重，不复活
'''
new = '''          id=$(basename "$tmpl")
          dest="$SM/$id"
          # Persist an explicit user removal across KernelSU cleanup/reinstall.
          if [ "$id" = "pg_mitm_ca" ] && [ -f "$PG/ca-mitm-user-removed" ]; then SKIP=$((SKIP+1)); continue; fi
          # 用户曾用管理器删除该子模块 → 尊重，不复活
'''
if old in c:
    c = c.replace(old, new, 1)
elif 'ca-mitm-user-removed' not in c:
    raise SystemExit("certmgr release insertion anchor not found")

old = '''          else
            rm -rf "$_en_prev" 2>/dev/null
            printf '{"ok":true,"detail":"已启用 %s — 关键系统/Conscrypt 信任视图已同步并验证；个别应用命名空间可能需重启，证书固定应用不保证可用"}\\n' "$(idx "$id" 1)"
          fi
'''
new = '''          else
            rm -rf "$_en_prev" 2>/dev/null
            if [ "$id" = "pg_mitm_ca" ]; then rm -f "$PG/ca-mitm-user-removed" 2>/dev/null; fi
            printf '{"ok":true,"detail":"已启用 %s — 关键系统/Conscrypt 信任视图已同步并验证；个别应用命名空间可能需重启，证书固定应用不保证可用"}\\n' "$(idx "$id" 1)"
          fi
'''
if old in c:
    c = c.replace(old, new, 1)
elif 'rm -f "$PG/ca-mitm-user-removed"' not in c:
    raise SystemExit("certmgr enable success anchor not found")

old = '''          else
            rm -rf "$_rm_backup" 2>/dev/null
            printf '{"ok":true,"detail":"已移除子模块 %s — 系统信任已即时摘除, 升级不会自动复活(重启后管理器清理残留目录)"}\\n' "$id"
          fi
'''
new = '''          else
            if [ "$id" = "pg_mitm_ca" ]; then
              : > "$PG/ca-mitm-user-removed" 2>/dev/null || echo "cert: WARN unable to persist explicit MITM CA removal preference" >&2
              chmod 600 "$PG/ca-mitm-user-removed" 2>/dev/null || :
            fi
            rm -rf "$_rm_backup" 2>/dev/null
            printf '{"ok":true,"detail":"已移除子模块 %s — 系统信任已即时摘除，升级不会自动复活"}\\n' "$id"
          fi
'''
if old in c:
    c = c.replace(old, new, 1)
elif 'persist explicit MITM CA removal preference' not in c:
    raise SystemExit("certmgr remove success anchor not found")

certmgr.write_text(c, encoding="utf-8")

tests.parent.mkdir(parents=True, exist_ok=True)
tests.write_text(r'''#!/system/bin/sh
# Default MITM CA trust is installed, while traffic interception remains explicit.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CUSTOM="$ROOT/customize.sh"
CERT="$ROOT/scripts/certmgr.sh"
SERVICE="$ROOT/service.sh"
POST="$ROOT/post-fs-data.sh"
REDIRECT="$ROOT/scripts/mitm-redirect.sh"
ENGINE="$ROOT/scripts/mitm-engine.sh"
UI="$ROOT/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$CUSTOM" "$CERT" "$SERVICE" "$POST" "$REDIRECT" "$ENGINE" "$UI"; do
  [ -s "$f" ] || fail "missing required file: $f"
done
grep -Fq 'mitm-engine.sh" trust-ca' "$CUSTOM" || fail 'first-install default CA bootstrap missing'
grep -Fq 'ca-trust-optin' "$CUSTOM" || fail 'existing CA user choices are not preserved'
grep -Fq 'ca-mitm-user-removed' "$CUSTOM" || fail 'explicit MITM CA removal is not preserved'
grep -Fq 'ca-mitm-user-removed' "$CERT" || fail 'certmgr does not persist explicit MITM CA removal'
grep -Fq 'builtin sync' "$SERVICE" || fail 'post-boot Android 14+ trust sync missing'
grep -Fq 'builtin sync' "$POST" || fail 'pre-zygote trust sync missing for older Android'
! grep -Fq 'mitm-redirect.sh enable' "$CUSTOM" || fail 'installer must not enable traffic interception'
! grep -Fq 'mitm-redirect.sh enable' "$SERVICE" || fail 'boot must not enable traffic interception'
grep -Fq 'MITM hostname allowlist is empty' "$REDIRECT" || fail 'empty allowlist is not rejected'
grep -Fq 'MITM CA is not confirmed active in the system trust store' "$REDIRECT" || fail 'redirect trust preflight missing'
grep -Fq 'function pgMitmTrafficAction' "$UI" || fail 'native APK UI traffic control missing'
grep -Fq 'scripts/mitm-engine.sh trust-ca' "$UI" || fail 'native APK UI CA lifecycle missing'
sh -n "$CUSTOM"
sh -n "$CERT"
sh -n "$SERVICE"
sh -n "$POST"
sh -n "$REDIRECT"
sh -n "$ENGINE"
echo 'PASS: MITM CA defaults to per-device system trust; user removal/disable persists; HTTPS redirect remains explicit and fail-closed'
''', encoding="utf-8")
legacy_test = root / "scripts/tests/v1.0.0-ca-mitm-lifecycle-integration-regression.sh"
legacy_test.write_text(r'''#!/system/bin/sh
# CA trust defaults to the per-device MITM root; traffic redirection remains explicit.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CUSTOM="$ROOT/customize.sh"
SERVICE="$ROOT/service.sh"
APPLY="$ROOT/scripts/apply.sh"
UI="$ROOT/webroot/index.html"
ENGINE="$ROOT/scripts/mitm-engine.sh"
REDIRECT="$ROOT/scripts/mitm-redirect.sh"
CERT="$ROOT/scripts/certmgr.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -f "$CUSTOM" ] && [ -f "$SERVICE" ] && [ -f "$APPLY" ] && [ -f "$UI" ] || fail 'required source is missing'
grep -Fq 'mitm-engine.sh" trust-ca' "$CUSTOM" || fail 'first-install default MITM CA trust missing'
grep -Fq 'ca-trust-optin' "$CUSTOM" || fail 'existing CA opt-in state is not preserved'
grep -Fq 'ca-mitm-user-removed' "$CUSTOM" || fail 'explicit MITM CA removal is not preserved'
grep -Fq 'ca-mitm-user-removed' "$CERT" || fail 'persistent explicit CA removal marker missing'
grep -Fq '[ -f "$PG/ca-trust-optin" ]' "$SERVICE" || fail 'post-boot CA trust sync guard missing'
grep -Fq 'builtin sync' "$SERVICE" || fail 'post-boot CA trust sync missing'
if grep -Fq 'mitm-redirect.sh enable' "$CUSTOM"; then fail 'installer must not auto-enable HTTPS traffic interception'; fi
if grep -Fq 'mitm-redirect.sh enable' "$SERVICE"; then fail 'boot must not auto-enable HTTPS traffic interception'; fi
for marker in 'id="mitmTrafficCard"' 'id="mitmTrafficRefresh"' 'id="mitmTrafficEnable"' 'id="mitmTrafficDisable"' 'function pgMitmTrafficAction' 'scripts/mitm-redirect.sh status'; do
  grep -Fq "$marker" "$UI" || fail "MITM UI marker missing: $marker"
done
grep -Fq "scripts/mitm-engine.sh trust-ca" "$UI" || fail 'runtime CA trust integration missing'
grep -Fq "scripts/mitm-engine.sh untrust-ca" "$UI" || fail 'MITM CA untrust integration missing'
grep -Fq "scripts/mitm-redirect.sh disable" "$UI" || fail 'cleanup-before-CA-mutation integration missing'
grep -Fq 'trust-ca)' "$ENGINE" || fail 'runtime CA trust operation missing'
grep -Fq 'sync_runtime_cert_to_child' "$ENGINE" || fail 'runtime CA child synchronization missing'
grep -Fq 'enable)' "$REDIRECT" || fail 'explicit redirect enable operation missing'
grep -Fq 'MITM hostname allowlist is empty' "$REDIRECT" || fail 'empty allowlist must fail closed'
sh -n "$CUSTOM"; sh -n "$SERVICE"; sh -n "$APPLY"; sh -n "$ENGINE"; sh -n "$REDIRECT"; sh -n "$CERT"
echo 'PASS: default per-device MITM CA trust, upgrade/removal persistence, and explicit traffic UI/backend lifecycle'
''', encoding="utf-8")
print("Patched customize.sh/certmgr.sh and updated CA/MITM lifecycle regressions.")
