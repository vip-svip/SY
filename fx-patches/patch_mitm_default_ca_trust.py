#!/usr/bin/env python3
"""Enable local MITM CA trust by default while preserving per-CA user intent."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
customize = root / "customize.sh"
certmgr = root / "scripts/certmgr.sh"
service = root / "service.sh"
postfs = root / "post-fs-data.sh"
markerlib = root / "scripts/certmarker.sh"
ui = root / "webroot/index.html"

for p in (customize, certmgr, service, postfs, markerlib, ui):
    if not p.is_file():
        raise SystemExit(f"required FX source missing: {p}")

def once(src, old, new, label):
    if new in src:
        return src
    if old not in src:
        raise SystemExit(f"{label}: anchor not found")
    return src.replace(old, new, 1)

# Install: snapshot the legacy child state before release replaces that directory.
s = customize.read_text(encoding="utf-8")
start_marker = 'ui_print "- 初始化独立 CA 子模块..."'
end_marker = "# 不分发静态共享 CA 私钥"
if start_marker in s and end_marker in s:
    a, b = s.index(start_marker), s.index(end_marker, s.index(start_marker))
    block = r'''ui_print "- 初始化并配置 MITM 系统 CA..."
if [ -f "$MODPATH/scripts/certmgr.sh" ]; then
  _pg_ca_state_dir=/data/adb/privacyguard
  _pg_ca_install_log="$_pg_ca_state_dir/ca-install.log"
  mkdir -p "$_pg_ca_state_dir" 2>/dev/null
  _pg_mitm_preexisting_disabled=0
  [ -f /data/adb/modules/pg_mitm_ca/disable ] && _pg_mitm_preexisting_disabled=1
  if sh "$MODPATH/scripts/certmgr.sh" builtin release "$MODPATH/certs" >>"$_pg_ca_install_log" 2>&1; then
    if [ -f "$_pg_ca_state_dir/ca-mitm-user-removed" ] || [ -f /data/adb/modules/pg_mitm_ca/remove ]; then
      ui_print "  检测到用户曾移除 MITM CA；尊重移除选择，不自动恢复"
    elif [ -f "$_pg_ca_state_dir/ca-mitm-user-disabled" ] || [ "$_pg_mitm_preexisting_disabled" = 1 ]; then
      : > "$_pg_ca_state_dir/ca-mitm-user-disabled" 2>/dev/null || :
      ui_print "  检测到用户曾禁用 MITM CA（含旧版状态）；尊重禁用选择，不自动恢复"
    elif sh "$MODPATH/scripts/mitm-engine.sh" trust-ca >>"$_pg_ca_install_log" 2>&1; then
      ui_print "  [✓] 已生成/恢复本机独立 MITM CA 并启用系统信任（不写入用户证书区）"
      ui_print "      HTTPS 流量重定向仍保持关闭；配置主机白名单后再手动启用"
    else
      ui_print "  [!] MITM CA 默认信任初始化失败；HTTPS 重定向保持关闭，详情见 ca-install.log"
    fi
  else
    ui_print "  [!] CA 子模块释放/迁移失败；HTTPS 重定向保持关闭，详情见 ca-install.log"
  fi
else
  ui_print "  [!] 未找到 certmgr.sh，未安装 MITM CA"
fi
'''
    s = s[:a] + block + s[b:]
elif 'mitm-engine.sh" trust-ca' not in s:
    raise SystemExit("customize CA bootstrap block missing")
customize.write_text(s, encoding="utf-8")

# Make lifecycle comments reflect the actual default install transaction.
c = certmgr.read_text(encoding="utf-8")
old_header = "# certmgr.sh — 内置系统级 CA 管理（自签 CA，默认不信任，仅用于受控 MITM 检测实验）"
new_header = "# certmgr.sh — 内置系统级 CA 管理（首次安装默认启用设备本地 MITM CA；备用 HTTPS CA 默认关闭）"
c = once(c, old_header, new_header, "certmgr default trust header")
old_enable_comment = "# 用户明确启用 → 记录 opt-in 标记: 以后升级/重装保持启用；失败时恢复原标记。"
new_enable_comment = "# CA 启用事务提交标记：首次安装由 MITM 引擎调用；后续用户操作也复用此路径。失败时恢复原标记。"
c = once(c, old_enable_comment, new_enable_comment, "certmgr enable transaction comment")
certmgr.write_text(c, encoding="utf-8")


# certmgr resolves the active module using its own script location, not a stale
# live-module path (KernelSU's install staging directory can differ on upgrades).
c = certmgr.read_text(encoding="utf-8")
old = '''MDIR_CERTS=/data/adb/modules/privacyguard/certs
[ -d "$MDIR_CERTS" ] || MDIR_CERTS=/data/mod/certs'''
new = r'''_THIS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
_THIS_MODULE_DIR=$(CDPATH= cd -- "$_THIS_SCRIPT_DIR/.." 2>/dev/null && pwd)
if [ -f "$_THIS_MODULE_DIR/module.prop" ] && [ -f "$_THIS_MODULE_DIR/certs/ca-index" ]; then
  MDIR_CERTS="$_THIS_MODULE_DIR/certs"
elif [ -d /data/adb/modules/privacyguard/certs ]; then
  MDIR_CERTS=/data/adb/modules/privacyguard/certs
else
  MDIR_CERTS=/data/mod/certs
fi'''
c = once(c, old, new, "active-module certificate source")

old = '''          id=$(basename "$tmpl")
          dest="$SM/$id"
          # 用户曾用管理器删除该子模块 → 尊重，不复活'''
new = '''          id=$(basename "$tmpl")
          dest="$SM/$id"
          case "$id" in
            pg_mitm_ca) [ -f "$PG/ca-mitm-user-removed" ] && { SKIP=$((SKIP+1)); continue; } ;;
            pg_https_ca) [ -f "$PG/ca-https-user-removed" ] && { SKIP=$((SKIP+1)); continue; } ;;
          esac
          # 用户曾用管理器删除该子模块 → 尊重，不复活'''
c = once(c, old, new, "persistent MITM removal guard")

old = '''          # 默认禁用；仅在用户明确 opt-in 且原子替换成功后保留启用状态。
          DIS=1
          [ -f "$PG/ca-trust-optin" ] && [ ! -f "$dest/disable" ] && DIS=0'''
new = '''          # Child CA state is independent. The legacy global opt-in marker never enables siblings.
          DIS=1
          if [ -d "$dest" ] && [ ! -f "$dest/disable" ]; then DIS=0; fi
          case "$id" in
            pg_mitm_ca)
              [ -f "$PG/ca-mitm-user-disabled" ] && DIS=1
              [ -f "$PG/ca-mitm-user-enabled" ] && [ ! -f "$PG/ca-mitm-user-disabled" ] && DIS=0
              ;;
            pg_https_ca)
              [ -f "$PG/ca-https-user-disabled" ] && DIS=1
              [ -f "$PG/ca-https-user-enabled" ] && [ ! -f "$PG/ca-https-user-disabled" ] && DIS=0
              ;;
          esac'''
c = once(c, old, new, "per-CA release state")

old_policy_comment = "        # 安装时被 customize.sh 调用: certs/submodules/* → /data/adb/modules/pg_*_ca\n        # 信任策略: 默认【不启用】。UI/README 一直写“默认不信任”, 且两张自签 CA 的\n        # 私钥随模块公开分发, 安装即全系统信任会让安全软件/银行类 App 把设备判为\n        # “存在自定义根证书/风险证书”, 这也是“装完模块就弹证书警告”的常见来源。\n        # 用户只要在 WebUI『根证书管理』点过“启用”, 就写 $PG/ca-trust-optin;\n        # 之后升级/重装保持启用; 其它情况一律释放为禁用状态(可一键启用)。"
new_policy_comment = "        # 安装时由 customize.sh 调用：释放独立 CA 子模块，并为每张 CA 保留独立状态。\n        # 首次安装会在设备本机生成 MITM CA 私钥/证书，验证系统信任同步后启用 pg_mitm_ca。\n        # pg_https_ca 备用根默认禁用；ca-trust-optin 仅是开机信任同步标记，不能用于\n        # 推断任一子模块是否应启用。升级时依照子模块 disable 和 ca-*-user-* 标记恢复。\n        # CA 私钥不随模块分发；系统信任不会自动开启 HTTPS 流量重定向。"
c = once(c, old_policy_comment, new_policy_comment, "certmgr trust-policy comments")

old = '''          else
            rm -rf "$_en_prev" 2>/dev/null
            printf '{"ok":true,"detail":"已启用 %s — 关键系统/Conscrypt 信任视图已同步并验证；个别应用命名空间可能需重启，证书固定应用不保证可用"}\\n' "$(idx "$id" 1)"
          fi'''
new = '''          else
            _state_enabled=""
            _state_disabled=""
            _state_removed=""
            _en_had_user_disabled=0
            _en_had_user_removed=0
            case "$id" in
              pg_mitm_ca)
                _state_enabled=ca-mitm-user-enabled
                _state_disabled=ca-mitm-user-disabled
                _state_removed=ca-mitm-user-removed
                ;;
              pg_https_ca)
                _state_enabled=ca-https-user-enabled
                _state_disabled=ca-https-user-disabled
                _state_removed=ca-https-user-removed
                ;;
            esac
            [ -f "$PG/$_state_disabled" ] && _en_had_user_disabled=1
            [ -f "$PG/$_state_removed" ] && _en_had_user_removed=1
            if ! ca_state_remove "$_state_disabled" "$_state_removed"; then
              _pg_cm_rc=1
              # Restore durable preferences first, then restore the original
              # child module, and only then reconcile system/APEX trust views.
              [ "$_en_had_user_disabled" = 1 ] && ca_state_write "$_state_disabled" || :
              [ "$_en_had_user_removed" = 1 ] && ca_state_write "$_state_removed" || :
              if [ "$_en_replaced" = 1 ]; then
                rm -rf "$_en_dest" 2>/dev/null
                if [ -d "$_en_prev" ]; then
                  mv "$_en_prev" "$_en_dest" 2>/dev/null || echo "cert: ERROR enable rollback could not restore previous submodule; backup retained at $_en_prev" >&2
                fi
              elif [ "$_en_had_dir" = 1 ]; then
                if [ "$_en_had_disable" = 1 ] || [ "$_en_had_user_disabled" = 1 ]; then
                  : > "$_en_dest/disable" 2>/dev/null || echo "cert: ERROR enable rollback could not restore disable flag for $id" >&2
                else
                  rm -f "$_en_dest/disable" 2>/dev/null || :
                fi
              else
                rm -rf "$_en_dest" 2>/dev/null
              fi
              [ "$_en_had_optin" = 1 ] || rm -f "$PG/ca-trust-optin" 2>/dev/null
              ca_sync >/dev/null 2>&1 || echo "cert: ERROR enable rollback trust resync incomplete" >&2
              printf '{"ok":false,"detail":"无法清除旧 CA 用户状态标记；已先恢复原状态再同步信任视图"}\\n'
            else
              # The child module state is authoritative if the auxiliary marker
              # cannot be published; release() also preserves its disable bit.
              _state_write_error=0
              if ! ca_state_write "$_state_enabled"; then
                _pg_cm_rc=1
                _state_write_error=1
                echo "cert: ERROR unable to persist $_state_enabled; the trust marker is not durable" >&2
              fi
              rm -rf "$_en_prev" 2>/dev/null
              if [ "$_state_write_error" = 1 ]; then
                printf '{"ok":false,"detail":"当前已启用 %s，但无法保存跨升级状态；请检查 /data/adb/privacyguard 写入权限和空间"}\\n' "$(idx "$id" 1)"
              else
                printf '{"ok":true,"detail":"已启用 %s — 系统/Conscrypt 信任视图与跨升级用户状态均已保存"}\\n' "$(idx "$id" 1)"
              fi
            fi
          fi'''
c = once(c, old, new, "enable state persistence")

old = '''          else
            printf '{"ok":true,"detail":"已禁用 %s — 本模块拥有的系统/Conscrypt 信任视图已同步；个别应用缓存需重启，系统原生同指纹 CA 不会被本模块删除"}\\n' "$(idx "$id" 1)"
          fi'''
new = '''          else
            _state_disabled=""
            _state_enabled=""
            case "$id" in
              pg_mitm_ca) _state_disabled=ca-mitm-user-disabled; _state_enabled=ca-mitm-user-enabled ;;
              pg_https_ca) _state_disabled=ca-https-user-disabled; _state_enabled=ca-https-user-enabled ;;
            esac
            # The child disable bit is durable too; fail visibly if the preference
            # marker cannot be committed instead of silently claiming full persistence.
            _state_write_error=0
            _state_cleanup_error=0
            if ! ca_state_write "$_state_disabled"; then
              _pg_cm_rc=1
              _state_write_error=1
              echo "cert: ERROR unable to persist $_state_disabled; current child disable bit remains active" >&2
            fi
            if ! ca_state_remove "$_state_enabled"; then
              _pg_cm_rc=1
              _state_cleanup_error=1
              echo "cert: WARN unable to clear stale enabled marker for $id; disabled marker takes precedence" >&2
            fi
            if [ "$_state_write_error" = 1 ]; then
              printf '{"ok":false,"detail":"当前已禁用 %s，但无法保存跨升级禁用选择；当前子模块 disable 标记仍有效"}\\n' "$(idx "$id" 1)"
            elif [ "$_state_cleanup_error" = 1 ]; then
              printf '{"ok":false,"detail":"当前已禁用 %s，禁用选择已保存，但旧启用标记清理不完整；禁用标记优先"}\\n' "$(idx "$id" 1)"
            else
              printf '{"ok":true,"detail":"已禁用 %s — 系统/Conscrypt 信任视图与跨升级禁用选择均已保存"}\\n' "$(idx "$id" 1)"
            fi
          fi'''
c = once(c, old, new, "disable state persistence")

old = '''          else
            rm -rf "$_rm_backup" 2>/dev/null
            printf '{"ok":true,"detail":"已移除子模块 %s — 系统信任已即时摘除, 升级不会自动复活(重启后管理器清理残留目录)"}\\n' "$id"
          fi'''
new = '''          else
            _state_removed=""
            _state_enabled=""
            _state_disabled=""
            case "$id" in
              pg_mitm_ca)
                _state_removed=ca-mitm-user-removed
                _state_enabled=ca-mitm-user-enabled
                _state_disabled=ca-mitm-user-disabled
                ;;
              pg_https_ca)
                _state_removed=ca-https-user-removed
                _state_enabled=ca-https-user-enabled
                _state_disabled=ca-https-user-disabled
                ;;
            esac
            if ! ca_state_write "$_state_removed"; then
              _pg_cm_rc=1
              _rm_restore=$(mktemp -d "$SM/.$id.restore.XXXXXX" 2>/dev/null) || _rm_restore=""
              if [ -n "$_rm_restore" ] && cp -R "$_rm_backup/." "$_rm_restore/" 2>/dev/null &&
                 rm -rf "$SM/$id" 2>/dev/null && mv "$_rm_restore" "$SM/$id" 2>/dev/null; then
                ca_sync >/dev/null 2>&1 || echo "cert: ERROR remove-marker rollback resync incomplete" >&2
                rm -rf "$_rm_backup" 2>/dev/null
              else
                [ -n "$_rm_restore" ] && rm -rf "$_rm_restore" 2>/dev/null
                echo "cert: ERROR remove-marker rollback failed; recovery backup retained at $_rm_backup" >&2
              fi
              printf '{"ok":false,"detail":"无法持久保存 CA 移除选择；已尝试恢复原子模块，升级后不会静默复活"}\\n'
            else
              ca_state_remove "$_state_enabled" "$_state_disabled" || echo "cert: WARN stale enabled/disabled state cleanup incomplete for $id" >&2
              rm -rf "$_rm_backup" 2>/dev/null
              printf '{"ok":true,"detail":"已移除子模块 %s — 系统信任已摘除，用户移除选择已原子持久化"}\\n' "$id"
            fi
          fi'''
c = once(c, old, new, "remove state persistence")

old = '''        if ca_sync; then
          printf '{"ok":true,"detail":"已移除 %d 个 CA 子模块；信任同步流程完成，仍需核实实际挂载状态"}\\n' "$N"'''
new = '''        if ca_sync; then
          if ca_state_remove ca-mitm-user-enabled ca-mitm-user-disabled ca-mitm-user-removed ca-https-user-enabled ca-https-user-disabled ca-https-user-removed ca-trust-optin; then
            printf '{"ok":true,"detail":"已移除 %d 个 CA 子模块并清理用户状态"}\\n' "$N"
          else
            _pg_cm_rc=1
            printf '{"ok":false,"detail":"CA 已移除，但偏好标记清理不完整；请检查 /data/adb/privacyguard"}\\n'
          fi'''
c = once(c, old, new, "purge state cleanup")
certmgr.write_text(c, encoding="utf-8")

# CA user preferences are durable state, not best-effort log hints. Publish them
# through a private same-directory temp file and an atomic rename.
markerlib_text = markerlib.read_text(encoding="utf-8")
if "ca_state_write()" not in markerlib_text:
    markerlib_text += r'''

# Atomically persist one of the known per-CA lifecycle preferences.
ca_state_write() {
  _csw_name="$1"
  case "$_csw_name" in
    ca-mitm-user-enabled|ca-mitm-user-disabled|ca-mitm-user-removed|ca-https-user-enabled|ca-https-user-disabled|ca-https-user-removed) ;;
    *) echo "cert: ERROR refusing unknown CA state marker: $_csw_name" >&2; return 1 ;;
  esac
  [ -n "$PG" ] || return 1
  mkdir -p "$PG" 2>/dev/null || return 1
  _csw_tmp=$(umask 077; mktemp "$PG/.$_csw_name.tmp.XXXXXX" 2>/dev/null) || return 1
  [ -n "$_csw_tmp" ] || return 1
  if ! printf '1\n' > "$_csw_tmp"; then rm -f "$_csw_tmp"; return 1; fi
  if ! mv -f "$_csw_tmp" "$PG/$_csw_name" 2>/dev/null; then
    rm -f "$_csw_tmp" 2>/dev/null
    return 1
  fi
  [ -f "$PG/$_csw_name" ] && [ "$(cat "$PG/$_csw_name" 2>/dev/null)" = 1 ]
}

# Remove only known state markers; report an incomplete cleanup to callers.
ca_state_remove() {
  for _csr_name in "$@"; do
    case "$_csr_name" in
      ca-mitm-user-enabled|ca-mitm-user-disabled|ca-mitm-user-removed|ca-https-user-enabled|ca-https-user-disabled|ca-https-user-removed|ca-trust-optin) ;;
      *) echo "cert: ERROR refusing unknown CA state marker removal: $_csr_name" >&2; return 1 ;;
    esac
    rm -f "$PG/$_csr_name" 2>/dev/null || return 1
    [ ! -e "$PG/$_csr_name" ] || return 1
  done
  return 0
}
'''
markerlib.write_text(markerlib_text, encoding="utf-8")



for rel, old_line, new_line in (
    ("scripts/tests/v1.0.0-js-mitm-runtime-controls-regression.sh", 'HTML="$ROOT/webroot/index.html"', 'HTML=${FX_UI_SOURCE:-$ROOT/webroot/index.html}'),
    ("scripts/tests/v1.0.0-cert-apex-namespace-ui-truth-regression.sh", 'UI="$ROOT/webroot/index.html"', 'UI=${FX_UI_SOURCE:-$ROOT/webroot/index.html}'),
):
    p = root / rel
    if p.is_file():
        t = p.read_text(encoding="utf-8")
        if old_line in t:
            t = t.replace(old_line, new_line, 1)
        elif new_line not in t:
            raise SystemExit("UI regression source selector anchor missing: " + rel)
        p.write_text(t, encoding="utf-8")

# No-OpenSSL fixture: make its fake module root discoverable by the real resolver.
collision = root / "scripts/tests/v1.0.0-cert-collision-no-openssl-regression.sh"
if collision.is_file():
    t = collision.read_text(encoding="utf-8")
    if ': > "$MOD/module.prop"' not in t:
        t, n = re.subn(
            r'(?m)^(mkdir -p "\$MOD/scripts"[^\n]*)$',
            lambda m: m.group(1) + '\n: > "$MOD/module.prop"',
            t, count=1,
        )
        if n != 1:
            raise SystemExit("no-OpenSSL fake module root setup line not found")
    collision.write_text(t, encoding="utf-8")


sv = service.read_text(encoding="utf-8")
sv = once(sv, "# Android 14+: wait for Conscrypt/zygote to exist, then reconcile CA trust into\n# init + zygote and visible app mount namespaces before ordinary boot completion.\n# We never promote a CA unless the user has the explicit ca-trust-optin marker.", "# Android 14+: wait for Conscrypt/zygote to exist, then reconcile an already\n# committed CA trust transaction into init + zygote and visible app namespaces.\n# First install commits the local MITM CA by default; the marker gates sync only.", "service CA trust comments")
service.write_text(sv, encoding="utf-8")

sv = service.read_text(encoding="utf-8")
sv = once(sv, "# Restore only CA trust that the user explicitly enabled in WebUI.\n# Android 14+ uses the Conscrypt APEX trust view, which is not restored by the\n# ordinary KernelSU /system module mount. Never enable a CA just because files\n# exist: the opt-in marker is written by an explicit builtin CA enable action.", "# Restore only CA trust transactions that were committed by certmgr.\n# First install commits the device-local pg_mitm_ca by default through the MITM\n# engine; pg_https_ca remains disabled. This marker gates boot reconciliation\n# and never enables a newly released sibling CA by itself.", "service trust policy comment")
service.write_text(sv, encoding="utf-8")

pf = postfs.read_text(encoding="utf-8")
pf = once(pf, "# CA trust remains opt-in. For Android 13 and earlier, synchronize an explicitly\n# authorized CA overlay before zygote initializes trust managers. On Android 14+\n# Conscrypt APEX requires a live zygote namespace, so service.sh performs the\n# verified namespace-aware sync as soon as zygote is available.", "# Synchronize only CA modules whose trust transaction has committed. The first\n# install commits the device-local MITM CA by default; the HTTPS fallback CA remains\n# disabled. Android 13 and earlier sync before zygote; Android 14+ is synchronized\n# in service.sh after a live Conscrypt/zygote namespace is available.", "post-fs-data CA trust comments")
postfs.write_text(pf, encoding="utf-8")

# Native APK UI and module description.
html = ui.read_text(encoding="utf-8")
old_ui = "模块内置 CA（默认不启用；启用后为系统级信任。MITM 专用 CA 必须通过下方 MITM 管理完成初始化/信任；实验结束请禁用或移除）"
new_ui = "模块内置 CA（MITM 专用 CA 首次安装默认初始化并启用系统级信任；用户主动禁用/移除后保留其选择。证书固定应用或自带信任库仍可能拒绝 MITM）"
if old_ui in html:
    html = html.replace(old_ui, new_ui, 1)
elif new_ui not in html:
    raise SystemExit("MITM CA UI label anchor missing")
old_hint = "Android 14+ 会在系统启动完成后，依据已明确启用的 CA 子模块同步 Conscrypt APEX 信任视图。安装默认关闭；CA 信任本身不会自动启用 HTTPS 流量重定向。"
new_hint = "Android 14+ 会在系统启动完成后同步 Conscrypt APEX 信任视图，并验证 zygote/App 命名空间。首次安装默认启用 MITM 专用系统 CA；CA 信任本身不会自动启用 HTTPS 流量重定向。若系统命名空间验证失败，状态会显示未确认，不会谎报受信任。"
if old_hint in html:
    html = html.replace(old_hint, new_hint, 1)
elif new_hint not in html:
    raise SystemExit("MITM CA UI trust hint anchor missing")

old_status_ui = "    if(state==='enabled'){badge.textContent='已启用';detail.textContent='IPv4 重定向已挂载 · 引擎 '+(listener||'状态未知')+' · IPv6 未接管。';}\n    else if(state==='disabled'){badge.textContent='已关闭';detail.textContent='未发现已启用的 IPv4 HTTPS 重定向；引擎状态：'+(listener||'未知')+'。';}\n    else {badge.textContent='状态异常/未知';detail.textContent=String((j&&j.error)||(r&&r.out)||'无法确认真实防火墙状态').slice(0,500);}"
new_status_ui = "    if(state==='enabled'&&j.health==='ok'&&listener==='running'){badge.textContent='已启用';detail.textContent='IPv4 重定向已挂载 · 引擎监听正常 · IPv6 未接管。';}\n    else if(state==='enabled'){badge.textContent='已降级/异常';detail.textContent='警告：IPv4 重定向仍在，但 MITM 监听器未确认健康（'+(listener||'未知')+'）。流量可能被送入不可用端口；请立即关闭重定向并检查 engine.log。';}\n    else if(state==='disabled'){badge.textContent='已关闭';detail.textContent='未发现已启用的 IPv4 HTTPS 重定向；引擎状态：'+(listener||'未知')+'。';}\n    else {badge.textContent='状态异常/未知';detail.textContent=String((j&&j.error)||(r&&r.out)||'无法确认真实防火墙状态').slice(0,500);}"
html = once(html, old_status_ui, new_status_ui, "MITM UI degraded-listener status")
ui.write_text(html, encoding="utf-8")

mitm_prop = root / "certs/submodules/pg_mitm_ca/module.prop"
if mitm_prop.is_file():
    lines = mitm_prop.read_text(encoding="utf-8").splitlines()
    lines = [
        "description=FX 首次安装默认初始化并启用本机独立系统 MITM CA；用户可在主应用中禁用/移除。HTTPS 流量重定向仍需显式启用。"
        if line.startswith("description=") else line for line in lines
    ]
    mitm_prop.write_text("\n".join(lines) + "\n", encoding="utf-8")

runtime_readme = root / "scripts/jsruntime/README-zh-CN.md"
if runtime_readme.is_file():
    d = runtime_readme.read_text(encoding="utf-8")
    d = d.replace("用户仍需明确启用 MITM、安装并信任 FX CA；",
                  "首次安装已自动初始化并信任 MITM 专用系统 CA；用户仍需配置主机白名单并手动启用 HTTPS 流量重定向；")
    d = d.replace("安装默认关闭", "安装默认启用 MITM 专用系统 CA（HTTPS 流量重定向仍需手动启用）")
    runtime_readme.write_text(d, encoding="utf-8")

readme = root / "README.md"
if readme.is_file():
    d = readme.read_text(encoding="utf-8")
    d = re.sub(r"(?m)^- 内置根证书子模块管理.*$",
               "- 内置根证书子模块管理（首次安装默认生成并启用设备本地 MITM 系统 CA；备用 HTTPS CA 默认禁用；用户可主动禁用/移除）", d, count=1)
    d = re.sub(r"(?m)^- 根证书管理：.*$",
               "- 根证书管理：首次安装默认初始化并启用设备本地 MITM 系统 CA；备用 HTTPS CA 默认禁用。证书固定、自带信任库或安全策略仍可能拒绝 MITM。", d, count=1)
    d = re.sub(r"(?m)^## 内置根证书子模块.*$",
               "## 内置根证书子模块（FX 1.0.0；MITM 专用系统 CA 首次安装默认启用）", d, count=1)
    d = re.sub(r"(?m)^模块自带两张自签根 CA.*$",
               "模块内有两个独立 CA 子模块。首次安装会为 pg_mitm_ca 生成设备本地私钥和 CA 证书，并在验证通过后加入 /system/etc/security/cacerts；Android 14+ 还会同步 Conscrypt APEX 信任视图并检查 zygote/App 命名空间。pg_https_ca 备用根仍默认禁用。MITM CA 的用户禁用/移除选择会在升级时保留。设备私钥不会随 ZIP 分发，也不会写入用户证书区。系统 CA 信任不会自动开启 HTTPS 流量重定向。", d, count=1)
    d = re.sub(r"(?m)^\| PrivacyGuard MITM Detection CA \|.*$",
               "| PrivacyGuard MITM Detection CA | pg_mitm_ca | 设备本机动态生成 | 仅供 FX MITM 引擎签发白名单主机的叶子证书 |", d, count=1)
    d = re.sub(r"(?m)^v1\.10\.4 起按以下顺序排查.*$",
               "按以下顺序排查（首次安装默认启用设备本地 MITM 系统 CA；但这不会自动启用 HTTPS 流量重定向）：", d, count=1)
    d = d.replace("（本版默认不启用系统 CA，不会主动留下自定义根证书）。",
                  "（首次安装默认启用设备本地 MITM 系统 CA；HTTPS 流量重定向需单独手动启用）。")
    d = d.replace("- 内置 CA 默认不启用；启用后 Android 14+ 依赖 APEX bind-mount",
                  "- MITM 专用 CA 首次安装默认启用；Android 14+ 依赖 Conscrypt APEX 信任同步")
    readme.write_text(d, encoding="utf-8")

# Fail-closed regression for default trust, independent CA states, upgrade/remove
# persistence, script-relative paths, UI copy and the explicit traffic gate.
test_lines = [
    "#!/system/bin/sh", "set -eu",
    'ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)',
    'CUSTOM="$ROOT/customize.sh"', 'CERT="$ROOT/scripts/certmgr.sh"',
    'SERVICE="$ROOT/service.sh"', 'POST="$ROOT/post-fs-data.sh"',
    'REDIRECT="$ROOT/scripts/mitm-redirect.sh"', 'ENGINE="$ROOT/scripts/mitm-engine.sh"',
    'UI="$ROOT/webroot/index.html"',
    'fail(){ echo "FAIL: $*" >&2; exit 1; }',
    'UI_TMP=""',
    'if ! grep -Fq "function pgMitmTrafficAction" "$UI" && [ -s "$ROOT/optional/FXUnifiedHook.apk" ] && command -v unzip >/dev/null 2>&1; then',
    '  UI_TMP=$(mktemp /tmp/fx-mitm-ui.XXXXXX) || fail "cannot create temporary APK UI extraction file"',
    '  unzip -p "$ROOT/optional/FXUnifiedHook.apk" assets/webroot/index.html > "$UI_TMP" || fail "cannot extract APK embedded MITM UI"',
    '  UI="$UI_TMP"',
    '  trap "rm -f $UI_TMP" EXIT HUP INT TERM',
    'fi',
    'for f in "$CUSTOM" "$CERT" "$SERVICE" "$POST" "$REDIRECT" "$ENGINE" "$UI"; do [ -s "$f" ] || fail "missing $f"; done',
    'grep -Fq \'mitm-engine.sh" trust-ca\' "$CUSTOM" || fail "first-install MITM CA bootstrap missing"',
    'grep -Fq "_pg_mitm_preexisting_disabled" "$CUSTOM" || fail "legacy disabled-state migration missing"',
    'grep -Fq "ca-mitm-user-disabled" "$CUSTOM" || fail "persistent MITM disable preference missing"',
    'grep -Fq "ca-mitm-user-removed" "$CUSTOM" || fail "persistent MITM removal preference missing"',
    'grep -Fq "_THIS_MODULE_DIR/certs" "$CERT" || fail "active module path resolution missing"',
    'grep -Fq "首次安装会在设备本机生成 MITM CA" "$CERT" || fail "certmgr policy comments are stale"',
    'grep -Fq "First install commits the local MITM CA by default" "$SERVICE" || fail "service CA sync comments are stale"',
    'grep -Fq "the HTTPS fallback CA remains" "$POST" || fail "post-fs-data CA sync comments are stale"',
    'if grep -Fq "默认不信任，仅用于受控 MITM" "$CERT"; then fail "certmgr header still claims MITM CA is default-off"; fi',
    'if grep -Fq "用户明确启用" "$CERT"; then fail "certmgr enable comment still describes opt-in-only behavior"; fi',
    'if grep -Fq "explicitly enabled in WebUI" "$SERVICE"; then fail "service comment still describes opt-in-only behavior"; fi',
    'grep -Fq "First install commits the device-local pg_mitm_ca by default" "$SERVICE" || fail "service boot policy comment missing"',
    'grep -Fq \'if [ -d "$dest" ] && [ ! -f "$dest/disable" ]; then DIS=0; fi\' "$CERT" || fail "per-child CA state is not preserved"',
    'grep -Fq "ca-mitm-user-enabled" "$CERT" || fail "MITM enable preference is not persisted"',
    'grep -Fq "ca-mitm-user-disabled" "$CERT" || fail "MITM disable preference is not persisted"',
    'grep -Fq "ca-mitm-user-removed" "$CERT" || fail "MITM remove preference is not persisted"',
    'grep -Fq "ca_state_write()" "$ROOT/scripts/certmarker.sh" || fail "atomic CA state marker writer missing"',
    'grep -Fq "mktemp" "$ROOT/scripts/certmarker.sh" || fail "CA marker writer has no unique temp-file creation"',
    'grep -Fq "ca_state_remove()" "$ROOT/scripts/certmarker.sh" || fail "safe CA state marker remover missing"',
    'grep -Fq "_en_had_user_disabled" "$CERT" || fail "enable rollback does not snapshot prior disabled state"',
    'grep -Fq "_en_had_user_removed" "$CERT" || fail "enable rollback does not snapshot prior removed state"',
    'grep -Fq "无法保存跨升级状态" "$CERT" || fail "enable status does not disclose marker persistence failures"',
    'grep -Fq "无法保存跨升级禁用选择" "$CERT" || fail "disable status does not disclose marker persistence failures"',
    'grep -Fq "enable rollback trust resync incomplete" "$CERT" || fail "enable rollback does not resync after restoring original state"',
    'grep -Fq "mktemp -d" "$CERT" || fail "remove rollback does not use a unique restore directory"',
    'grep -Fq \'pg_https_ca) [ -f "$PG/ca-https-user-removed" ]\' "$CERT" || fail "HTTPS CA removal preference is not honored during release"',
    'grep -Fq \'[ -f "$PG/ca-trust-optin" ]\' "$SERVICE" || fail "boot CA sync guard missing"',
    'grep -Fq \'[ -f "$PG/ca-trust-optin" ]\' "$POST" || fail "early boot CA sync guard missing"',
    'grep -Fq "MITM hostname allowlist is empty" "$REDIRECT" || fail "empty hostname allowlist is not rejected"',
    'grep -Fq "MITM CA is not confirmed active in the system trust store" "$REDIRECT" || fail "trust preflight missing"',
    'grep -Fq "function pgMitmTrafficAction" "$UI" || fail "native MITM traffic controls missing"',
    'grep -Fq "首次安装默认初始化并启用系统级信任" "$UI" || fail "native UI still says CA is opt-in"',
    'grep -Fq "j.health===\'ok\'&&listener===\'running\'" "$UI" || fail "MITM UI treats an unhealthy listener as enabled"',
    'grep -Fq "已降级/异常" "$UI" || fail "MITM UI has no degraded redirect state"',
    'grep -Fq \'chmod 700 "$DIR"\' "$ENGINE" || fail "MITM private runtime directory is not restricted to root"',
    '_private_file=$(find "$ROOT" -type f \\( -iname "*.key" -o -iname "*.p12" -o -iname "*.pfx" -o -iname "*.jks" -o -iname "*.keystore" \\) -print -quit)',
    '[ -z "$_private_file" ] || fail "private key/keystore file must not be shipped in the FX package"',
    'for _f in $(find "$ROOT" -type f); do if grep -I -q -E -- "-----BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY-----" "$_f" 2>/dev/null; then fail "private key material found in package: $_f"; fi; done',
    'if grep -Fq "mitm-redirect.sh enable" "$CUSTOM"; then fail "installer must not auto-enable HTTPS interception"; fi',
    'if grep -Fq "mitm-redirect.sh enable" "$SERVICE"; then fail "boot must not auto-enable HTTPS interception"; fi',
    'sh -n "$CUSTOM"; sh -n "$CERT"; sh -n "$SERVICE"; sh -n "$POST"; sh -n "$REDIRECT"; sh -n "$ENGINE"',
    'echo "PASS: default device-local MITM CA trust; per-CA user choices persist; traffic interception stays explicit and fail-closed"',
]
(root / "scripts/tests").mkdir(parents=True, exist_ok=True)
test_text = "\n".join(test_lines) + "\n"
(root / "scripts/tests/v1.0.0-mitm-default-ca-trust-regression.sh").write_text(test_text, encoding="utf-8")
(root / "scripts/tests/v1.0.0-ca-mitm-lifecycle-integration-regression.sh").write_text(test_text, encoding="utf-8")
# Give each HTTP bridge call a unique request file prefix even when one script
# issues several synchronous requests within the same millisecond.
host = root / "scripts/jsruntime/host.js"
if not host.is_file():
    raise SystemExit("QuickJS host prelude missing")
host_text = host.read_text(encoding="utf-8")
old_http_tmp = "    const tmp=_fxStateDir+'/http-'+_fxOS.getpid()+'-'+Date.now();"
new_http_tmp = "    const tmp=_fxStateDir+'/http-'+_fxOS.getpid()+'-'+(++_fxHttpSequence)+'-'+Date.now();"
if old_http_tmp in host_text:
    host_text = host_text.replace(old_http_tmp, new_http_tmp, 1)
elif new_http_tmp not in host_text:
    raise SystemExit("QuickJS HTTP temp-name anchor missing")
host_anchor = "  function _fxRequest(options,cb) {"
if "let _fxHttpSequence = 0;" not in host_text:
    if host_anchor not in host_text:
        raise SystemExit("QuickJS HTTP sequence insertion anchor missing")
    host_text = host_text.replace(host_anchor, "  let _fxHttpSequence = 0;\n" + host_anchor, 1)
host.write_text(host_text, encoding="utf-8")

http_test = root / "scripts/tests/v1.0.0-js-http-bridge-unique-request-temp-regression.sh"
http_test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HOST="$ROOT/scripts/jsruntime/host.js"
BRIDGE="$ROOT/scripts/jsruntime/http.sh"
grep -Fq 'let _fxHttpSequence = 0;' "$HOST" || {
  echo 'FAIL: HTTP call sequence counter missing' >&2; exit 1;
}
grep -Fq "++_fxHttpSequence" "$HOST" || {
  echo 'FAIL: each HTTP bridge call does not get a unique sequence number' >&2; exit 1;
}
grep -Fq "_fxOS.getpid()+'-'+(++_fxHttpSequence)+'-'+Date.now()" "$HOST" || {
  echo 'FAIL: HTTP temp-file prefix is not unique per script call' >&2; exit 1;
}
sh -n "$BRIDGE"
echo 'PASS: HTTP bridge temp files are unique for repeated calls in one QuickJS process'
''', encoding="utf-8")

marker_test = root / "scripts/tests/v1.0.0-ca-state-marker-atomic-regression.sh"
marker_test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LIB="$ROOT/scripts/certmarker.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
PG="$TMP/state"
mkdir -p "$PG"
. "$LIB"
ca_state_write ca-mitm-user-removed
[ -f "$PG/ca-mitm-user-removed" ] || { echo 'FAIL: marker was not committed' >&2; exit 1; }
[ "$(cat "$PG/ca-mitm-user-removed")" = 1 ] || { echo 'FAIL: marker content is invalid' >&2; exit 1; }
mode=$(stat -c '%a' "$PG/ca-mitm-user-removed" 2>/dev/null || stat -f '%Lp' "$PG/ca-mitm-user-removed")
[ "$mode" = 600 ] || { echo "FAIL: marker mode is $mode, expected 600" >&2; exit 1; }

# Concurrent writers must use distinct private temp files and publish complete markers.
_pids=""
_i=0
while [ "$_i" -lt 12 ]; do
  (ca_state_write ca-mitm-user-removed) &
  _pids="$_pids $!"
  _i=$((_i+1))
done
for _p in $_pids; do wait "$_p" || { echo "FAIL: concurrent marker write failed" >&2; exit 1; }; done
[ "$(cat "$PG/ca-mitm-user-removed")" = 1 ] || { echo 'FAIL: concurrent writes corrupted marker' >&2; exit 1; }

ca_state_write ca-https-user-disabled
[ -f "$PG/ca-https-user-disabled" ] || { echo 'FAIL: second marker was not committed' >&2; exit 1; }
if ca_state_write '../outside'; then
  echo 'FAIL: marker traversal accepted' >&2; exit 1
fi
if ca_state_remove '../outside'; then
  echo 'FAIL: marker removal traversal accepted' >&2; exit 1
fi
ca_state_remove ca-mitm-user-removed ca-https-user-disabled
[ ! -e "$PG/ca-mitm-user-removed" ] && [ ! -e "$PG/ca-https-user-disabled" ] || {
  echo 'FAIL: marker removal did not complete' >&2; exit 1;
}
echo 'PASS: CA preference markers are atomic, private, path-restricted and concurrency-safe'
''', encoding="utf-8")

print("Patched MITM default trust, per-CA lifecycle state, module-relative cert path, UI/docs, and regression tests.")
