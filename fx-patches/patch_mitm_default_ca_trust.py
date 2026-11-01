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
  # Capture the old per-module state before release replaces the child directory.
  _pg_mitm_preexisting_disabled=0
  [ -f /data/adb/modules/pg_mitm_ca/disable ] && _pg_mitm_preexisting_disabled=1
  if sh "$MODPATH/scripts/certmgr.sh" builtin release "$MODPATH/certs" >>"$_pg_ca_install_log" 2>&1; then
    if [ -f "$_pg_ca_state_dir/ca-mitm-user-removed" ] || [ -f /data/adb/modules/pg_mitm_ca/remove ]; then
      ui_print "  检测到用户曾移除 MITM CA；尊重移除选择，不自动恢复"
    elif [ -f "$_pg_ca_state_dir/ca-mitm-user-disabled" ] || [ "$_pg_mitm_preexisting_disabled" = 1 ]; then
      : > "$_pg_ca_state_dir/ca-mitm-user-disabled" 2>/dev/null || :
      ui_print "  检测到用户曾禁用 MITM CA（含旧版状态）；尊重禁用选择，不自动恢复"
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
c = c.replace("# certmgr.sh — 内置系统级 CA 管理（自签 CA，默认不信任，仅用于受控 MITM 检测实验）", "# certmgr.sh — 内置系统级 CA 管理；安装器首次安装默认信任设备本地 MITM CA，备用 HTTPS CA 默认关闭。HTTPS 流量重定向始终单独授权。", 1)
old_release_comment = """        # 安装时被 customize.sh 调用: certs/submodules/* → /data/adb/modules/pg_*_ca
        # 信任策略: 默认【不启用】。UI/README 一直写“默认不信任”, 且两张自签 CA 的
        # 私钥随模块公开分发, 安装即全系统信任会让安全软件/银行类 App 把设备判为
        # “存在自定义根证书/风险证书”, 这也是“装完模块就弹证书警告”的常见来源。
        # 用户只要在 WebUI『根证书管理』点过“启用”, 就写 $PG/ca-trust-optin;
        # 之后升级/重装保持启用; 其它情况一律释放为禁用状态(可一键启用)。"""
new_release_comment = """        # 安装时被 customize.sh 调用: certs/submodules/* → /data/adb/modules/pg_*_ca
        # release 阶段先原子释放子模块；首次安装随后由 customize.sh 生成本机
        # MITM CA 并只启用 pg_mitm_ca。pg_https_ca 备用根仍保持默认禁用。
        # 本机 CA 私钥不随模块分发；系统信任与 HTTPS 流量重定向是两个独立状态。
        # ca-trust-optin 是历史全局兼容标记，升级时还需结合各子模块 disable
        # 标记和 per-MITM 用户状态恢复选择，不能单独用它推断 MITM 应否启用。"""
if old_release_comment in c:
    c = c.replace(old_release_comment, new_release_comment, 1)
elif "release 阶段先原子释放子模块" not in c:
    raise SystemExit("certmgr release-policy comment anchor not found")

old_release_state = '''          # 默认禁用；仅在用户明确 opt-in 且原子替换成功后保留启用状态。
          DIS=1
          [ -f "$PG/ca-trust-optin" ] && [ ! -f "$dest/disable" ] && DIS=0'''
new_release_state = '''          # The legacy opt-in marker is global. Preserve trust only for an existing
          # child module that was already enabled; never enable a newly added CA
          # because another CA once received user consent.
          DIS=1
          if [ "$id" = "pg_mitm_ca" ] && [ -f "$PG/ca-mitm-user-disabled" ]; then
            DIS=1
          elif [ -f "$PG/ca-trust-optin" ] && [ -d "$dest" ] && [ ! -f "$dest/disable" ]; then
            DIS=0
          fi'''
if old_release_state in c:
    c = c.replace(old_release_state, new_release_state, 1)
elif 'legacy opt-in marker is global. Preserve trust only for an existing' not in c:
    raise SystemExit("certmgr release state block anchor not found")
old_paths = "MDIR_CERTS=/data/adb/modules/privacyguard/certs\n[ -d \"$MDIR_CERTS\" ] || MDIR_CERTS=/data/mod/certs"
new_paths = r'''_THIS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
_THIS_MODULE_DIR=$(CDPATH= cd -- "$_THIS_SCRIPT_DIR/.." 2>/dev/null && pwd)
if [ -f "$_THIS_MODULE_DIR/module.prop" ] && [ -f "$_THIS_MODULE_DIR/certs/ca-index" ]; then
  MDIR_CERTS="$_THIS_MODULE_DIR/certs"
elif [ -d /data/adb/modules/privacyguard/certs ]; then
  MDIR_CERTS=/data/adb/modules/privacyguard/certs
else
  MDIR_CERTS=/data/mod/certs
fi'''
if old_paths in c:
    c = c.replace(old_paths, new_paths, 1)
elif '_THIS_MODULE_DIR/certs' not in c:
    raise SystemExit("certmgr active-module path anchor not found")
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


# Persist explicit per-MITM-CA disable separately from the global opt-in marker.
disable_line = next((line for line in c.splitlines() if "已禁用 %s" in line and "printf" in line), None)
if disable_line is None:
    raise SystemExit("certmgr explicit MITM CA disable anchor not found")
disable_insert = """            if [ "$id" = "pg_mitm_ca" ]; then
              : > "$PG/ca-mitm-user-disabled" 2>/dev/null || echo "cert: WARN unable to persist explicit MITM CA disable preference" >&2
              chmod 600 "$PG/ca-mitm-user-disabled" 2>/dev/null || :
              rm -f "$PG/ca-mitm-user-removed" 2>/dev/null
            fi
"""
c = c.replace(disable_line, disable_insert + disable_line, 1)
c = c.replace('rm -f "$PG/ca-mitm-user-removed" 2>/dev/null; fi', 'rm -f "$PG/ca-mitm-user-removed" "$PG/ca-mitm-user-disabled" 2>/dev/null; fi', 1)
c = c.replace('chmod 600 "$PG/ca-mitm-user-removed" 2>/dev/null || :', 'chmod 600 "$PG/ca-mitm-user-removed" 2>/dev/null || :\n              rm -f "$PG/ca-mitm-user-disabled" 2>/dev/null', 1)

certmgr.write_text(c, encoding="utf-8")

# Keep the no-OpenSSL integration fixture isolated after MDIR_CERTS became
# dynamically derived from this script's active module directory.
collision_test = root / "scripts/tests/v1.0.0-cert-collision-no-openssl-regression.sh"
if collision_test.is_file():
    test_text = collision_test.read_text(encoding="utf-8")
    test_text = test_text.replace('  -e "s|^MDIR_CERTS=/data/adb/modules/privacyguard/certs$|MDIR_CERTS=$MOD/certs|" \\\n', '')
    import re
    # Match the fixture setup command structurally; archive whitespace/order may vary.
    if 'cp "$ROOT/module.prop" "$MOD/module.prop"' not in test_text:
        pattern = r'(?m)^(?P<mkdir>mkdir -p "\$MOD/scripts".*)$'
        test_text, count = re.subn(
            pattern,
            lambda m: m.group("mkdir") + chr(10) + 'cp "$ROOT/module.prop" "$MOD/module.prop"',
            test_text,
            count=1,
        )
        if count != 1:
            raise SystemExit("no-OpenSSL fixture module-root setup command not found")
    collision_test.write_text(test_text, encoding="utf-8")

# Keep the app UI and documentation consistent with the new default.
ui = root / "webroot/index.html"
if not ui.is_file():
    raise SystemExit("FX WebUI source missing before MITM trust-default patch")
html = ui.read_text(encoding="utf-8")
old_ui = "模块内置 CA（默认不启用；启用后为系统级信任。MITM 专用 CA 必须通过下方 MITM 管理完成初始化/信任；实验结束请禁用或移除）"
new_ui = "模块内置 CA（MITM 专用 CA 首次安装默认初始化并启用系统级信任；用户主动禁用/移除后保留其选择。证书固定应用或自带信任库仍可能拒绝 MITM）"
if old_ui in html:
    html = html.replace(old_ui, new_ui, 1)
elif new_ui not in html:
    raise SystemExit("MITM CA default-off UI label anchor not found")
old_hint = "Android 14+ 会在系统启动完成后，依据已明确启用的 CA 子模块同步 Conscrypt APEX 信任视图。安装默认关闭；CA 信任本身不会自动启用 HTTPS 流量重定向。"
new_hint = "Android 14+ 会在系统启动完成后同步 Conscrypt APEX 信任视图，并验证 zygote/App 命名空间。首次安装默认启用 MITM 专用系统 CA；CA 信任本身不会自动启用 HTTPS 流量重定向。若系统命名空间验证失败，状态会显示未确认，不会谎报受信任。"
if old_hint in html:
    html = html.replace(old_hint, new_hint, 1)
elif new_hint not in html:
    raise SystemExit("MITM CA UI explanatory text anchor not found")
ui.write_text(html, encoding="utf-8")

mitm_prop = root / "certs/submodules/pg_mitm_ca/module.prop"
if mitm_prop.is_file():
    prop_lines = mitm_prop.read_text(encoding="utf-8").splitlines()
    prop_lines = [("description=FX 首次安装默认初始化并启用本机独立系统 CA；用户可在主应用中禁用/移除。HTTPS 流量重定向仍需显式启用。" if line.startswith("description=") else line) for line in prop_lines]
    mitm_prop.write_text("\\n".join(prop_lines) + "\\n", encoding="utf-8")

readme = root / "scripts/jsruntime/README-zh-CN.md"
if readme.is_file():
    doc = readme.read_text(encoding="utf-8")
    doc = doc.replace("安装默认关闭", "安装默认启用 MITM 专用系统 CA（HTTPS 流量重定向仍需手动启用）")
    doc = doc.replace("用户仍需明确启用 MITM、安装并信任 FX CA；", "首次安装已自动初始化并信任 MITM 专用系统 CA；用户仍需配置主机白名单并手动启用 HTTPS 流量重定向；")
root_readme = root / "README.md"
if root_readme.is_file():
    doc = root_readme.read_text(encoding="utf-8")
    replacements = [
        ("- 根证书管理：内置 CA 的启用/禁用/移除（WebUI pageAd「根证书管理」；默认不启用，避免浏览器/银行类 App 报“自定义根证书/风险证书”警告）", "- 根证书管理：首次安装默认初始化并启用设备本地 MITM 系统 CA；备用 HTTPS CA 默认禁用。用户可随时禁用/移除；证书固定、自带信任库或安全软件策略仍可能拒绝 MITM。"),
        ("## 内置根证书子模块（v1.7.0；v1.10.4 起默认不启用）", "## 内置根证书子模块（FX 1.0.0；MITM 专用系统 CA 首次安装默认启用）"),
        ("模块自带两张自签根 CA（2049 年到期，`BasicConstraints: cA=TRUE` + `KeyUsage: keyCertSign`），安装时以**独立子模块**释放到 `/data/adb/modules/`，但**默认不启用**（不写系统信任区，避免被安全软件/银行类 App 判为“存在自定义根证书”）。需要受控 MITM 检测实验时，在 WebUI『根证书管理』点『启用』，才会经 magic-mount 进入 `/system/etc/security/cacerts`；Android 14+ 另在开机早期（`post-fs-data`）bind-mount 覆盖 `/apex/com.android.conscrypt/cacerts`（Conscrypt 实际读取处），对之后启动的应用生效。启用状态会记住，升级/重装保持。", "模块内有两个独立 CA 子模块。首次安装会为 `pg_mitm_ca` 生成设备本地私钥和 CA 证书，并在验证通过后加入 `/system/etc/security/cacerts`；Android 14+ 还会同步 Conscrypt APEX 信任视图并检查 zygote/App 命名空间。`pg_https_ca` 备用根仍默认禁用。MITM CA 的用户禁用/移除选择会在升级时保留。设备私钥不会随 ZIP 分发，也不会写入用户证书区。系统 CA 信任不会自动开启 HTTPS 流量重定向。"),
        ("| PrivacyGuard MITM Detection CA | `pg_mitm_ca` | `3cd7fe0549eaae30` | 导入抓包工具签发叶子证书，配合模块自身的 MITM 检测做受控实验 |", "| PrivacyGuard MITM Detection CA | `pg_mitm_ca` | 设备本机动态生成 | 仅供 FX MITM 引擎签发白名单主机的叶子证书 |"),
        ("| PrivacyGuard HTTPS Root CA | `pg_https_ca` | `1a9960b9339b31a5` | 自签 HTTPS 站点证书备用根 |", "| PrivacyGuard HTTPS Root CA | `pg_https_ca` | 模板证书指纹 | 备用 HTTPS 根，默认禁用 |"),
        ("v1.10.4 起按以下顺序排查（本模块的系统 CA **默认不启用**）：", "按以下顺序排查（首次安装默认启用设备本地 MITM 系统 CA；但这不会自动启用 HTTPS 流量重定向）："),
        ("> 升级提示：装完打开 WebUI，在「VPN → 自动核心」点一次「启动核心」确认可拉起；证书如仍报错，按上文「浏览器/App 报证书错误怎么办」逐项检查（本版默认不启用系统 CA，不会主动留下自定义根证书）。", "> 升级提示：首次安装会自动初始化并启用设备本地 MITM 系统 CA；升级时保留用户此前明确禁用/移除的选择。HTTPS 流量重定向仍需配置主机白名单后手动启用。若应用仍报错，按上文检查 CA 系统信任状态、应用证书固定、自带信任库和 TLS 支持范围。"),
        ("- 内置 CA 默认不启用；启用后 Android 14+ 依赖 APEX bind-mount，个别 ROM 的 SELinux/挂载策略可能拒绝（`certmgr.sh builtin list` 的 `apex`/`live_apex` 与 `$PG/early.log` 可判断；覆盖层不完整时会拒绝挂载以保护公共信任链，不会把全局 HTTPS 弄坏）", "- MITM 专用 CA 首次安装默认启用；Android 14+ 依赖 Conscrypt APEX 信任同步，个别 ROM 的 SELinux/挂载策略可能拒绝（用 `certmgr.sh builtin list` 检查 `apex`/`apex_ns`/`live_apex`；命名空间验证失败时状态保持未确认，不会谎报信任成功）。备用 HTTPS CA 默认禁用。"),
    ]
    for old, new in replacements:
        if old not in doc:
            raise SystemExit("README current-state anchor not found: " + old[:100])
        doc = doc.replace(old, new, 1)
    root_readme.write_text(doc, encoding="utf-8")

# The no-OpenSSL sandbox now follows the real active-module path resolver.
no_openssl_test = root / "scripts/tests/v1.0.0-cert-collision-no-openssl-regression.sh"
if no_openssl_test.is_file():
    test_source = no_openssl_test.read_text(encoding="utf-8")
    fixture_anchor = 'mkdir -p "$MOD/scripts" "$MOD/certs/submodules" "$SM/pg_mitm_ca/system/etc/security/cacerts" "$SC" "$PG" "$TMP/bin"\n'
    fixture_replacement = fixture_anchor + ': > "$MOD/module.prop"\n'
    if fixture_anchor in test_source:
        test_source = test_source.replace(fixture_anchor, fixture_replacement, 1)
    elif ': > "$MOD/module.prop"' not in test_source:
        raise SystemExit("no-OpenSSL test fixture module-root anchor not found")
    no_openssl_test.write_text(test_source, encoding="utf-8")

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
grep -Fq 'ca-trust-optin' "$SERVICE" || fail 'post-boot sync is not gated by the explicit trust marker'
grep -Fq 'ca-trust-optin' "$POST" || fail 'pre-zygote sync is not gated by the explicit trust marker'
grep -Fq 'ca-mitm-user-removed' "$CUSTOM" || fail 'explicit MITM CA removal is not preserved'
grep -Fq '_pg_mitm_preexisting_disabled' "$CUSTOM" || fail 'legacy per-module MITM disable state is not migrated'
grep -Fq '首次安装默认初始化并启用系统级信任' "$UI" || fail 'native UI still describes MITM CA as opt-in'
grep -Fq '首次安装默认启用设备本地 MITM 系统 CA' "$ROOT/README.md" || fail 'README still describes default-off MITM CA'
grep -Fq '设备本机动态生成' "$ROOT/README.md" || fail 'README still documents a static MITM CA fingerprint'
grep -Fq 'ca-mitm-user-removed' "$CERT" || fail 'certmgr does not persist explicit MITM CA removal'
grep -Fq 'ca-mitm-user-disabled' "$CERT" || fail 'certmgr does not persist explicit MITM CA disable'
grep -Fq '[ -d "$dest" ]' "$CERT" || fail 'legacy global opt-in could enable a newly released unrelated CA'
grep -Fq 'legacy opt-in marker is global. Preserve trust only for an existing' "$CERT" || fail 'per-CA trust is not isolated during module release'
grep -Fq '_THIS_MODULE_DIR/certs' "$CERT" || fail 'certmgr does not resolve active staging module directory'
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
grep -Fq 'ca-trust-optin' "$SERVICE" || fail 'boot trust sync marker missing'
grep -Fq 'ca-trust-optin' "$POST" || fail 'early boot trust sync marker missing'
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

# Keep the app UI and documentation consistent with the new default.
ui = root / "webroot/index.html"
if not ui.is_file():
    raise SystemExit("FX WebUI source missing before MITM trust-default patch")
html = ui.read_text(encoding="utf-8")
old_ui = "模块内置 CA（默认不启用；启用后为系统级信任。MITM 专用 CA 必须通过下方 MITM 管理完成初始化/信任；实验结束请禁用或移除）"
new_ui = "模块内置 CA（MITM 专用 CA 首次安装默认初始化并启用系统级信任；用户主动禁用/移除后保留其选择。证书固定应用或自带信任库仍可能拒绝 MITM）"
if old_ui in html:
    html = html.replace(old_ui, new_ui, 1)
elif new_ui not in html:
    raise SystemExit("MITM CA default-off UI label anchor not found")
old_hint = "Android 14+ 会在系统启动完成后，依据已明确启用的 CA 子模块同步 Conscrypt APEX 信任视图。安装默认关闭；CA 信任本身不会自动启用 HTTPS 流量重定向。"
new_hint = "Android 14+ 会在系统启动完成后同步 Conscrypt APEX 信任视图，并验证 zygote/App 命名空间。首次安装默认启用 MITM 专用系统 CA；CA 信任本身不会自动启用 HTTPS 流量重定向。若系统命名空间验证失败，状态会显示未确认，不会谎报受信任。"
if old_hint in html:
    html = html.replace(old_hint, new_hint, 1)
elif new_hint not in html:
    raise SystemExit("MITM CA UI explanatory text anchor not found")
ui.write_text(html, encoding="utf-8")

mitm_prop = root / "certs/submodules/pg_mitm_ca/module.prop"
if mitm_prop.is_file():
    prop_lines = mitm_prop.read_text(encoding="utf-8").splitlines()
    prop_lines = [("description=FX 首次安装默认初始化并启用本机独立系统 CA；用户可在主应用中禁用/移除。HTTPS 流量重定向仍需显式启用。" if line.startswith("description=") else line) for line in prop_lines]
    mitm_prop.write_text("\\n".join(prop_lines) + "\\n", encoding="utf-8")

readme = root / "scripts/jsruntime/README-zh-CN.md"
if readme.is_file():
    doc = readme.read_text(encoding="utf-8")
    doc = doc.replace("安装默认关闭", "安装默认启用 MITM 专用系统 CA（HTTPS 流量重定向仍需手动启用）")
    doc = doc.replace("用户仍需明确启用 MITM、安装并信任 FX CA；", "首次安装已自动初始化并信任 MITM 专用系统 CA；用户仍需配置主机白名单并手动启用 HTTPS 流量重定向；")
root_readme = root / "README.md"
if root_readme.is_file():
    doc = root_readme.read_text(encoding="utf-8")
    replacements = [
        ("- 根证书管理：内置 CA 的启用/禁用/移除（WebUI pageAd「根证书管理」；默认不启用，避免浏览器/银行类 App 报“自定义根证书/风险证书”警告）", "- 根证书管理：首次安装默认初始化并启用设备本地 MITM 系统 CA；备用 HTTPS CA 默认禁用。用户可随时禁用/移除；证书固定、自带信任库或安全软件策略仍可能拒绝 MITM。"),
        ("## 内置根证书子模块（v1.7.0；v1.10.4 起默认不启用）", "## 内置根证书子模块（FX 1.0.0；MITM 专用系统 CA 首次安装默认启用）"),
        ("模块自带两张自签根 CA（2049 年到期，`BasicConstraints: cA=TRUE` + `KeyUsage: keyCertSign`），安装时以**独立子模块**释放到 `/data/adb/modules/`，但**默认不启用**（不写系统信任区，避免被安全软件/银行类 App 判为“存在自定义根证书”）。需要受控 MITM 检测实验时，在 WebUI『根证书管理』点『启用』，才会经 magic-mount 进入 `/system/etc/security/cacerts`；Android 14+ 另在开机早期（`post-fs-data`）bind-mount 覆盖 `/apex/com.android.conscrypt/cacerts`（Conscrypt 实际读取处），对之后启动的应用生效。启用状态会记住，升级/重装保持。", "模块内有两个独立 CA 子模块。首次安装会为 `pg_mitm_ca` 生成设备本地私钥和 CA 证书，并在验证通过后加入 `/system/etc/security/cacerts`；Android 14+ 还会同步 Conscrypt APEX 信任视图并检查 zygote/App 命名空间。`pg_https_ca` 备用根仍默认禁用。MITM CA 的用户禁用/移除选择会在升级时保留。设备私钥不会随 ZIP 分发，也不会写入用户证书区。系统 CA 信任不会自动开启 HTTPS 流量重定向。"),
        ("| PrivacyGuard MITM Detection CA | `pg_mitm_ca` | `3cd7fe0549eaae30` | 导入抓包工具签发叶子证书，配合模块自身的 MITM 检测做受控实验 |", "| PrivacyGuard MITM Detection CA | `pg_mitm_ca` | 设备本机动态生成 | 仅供 FX MITM 引擎签发白名单主机的叶子证书 |"),
        ("| PrivacyGuard HTTPS Root CA | `pg_https_ca` | `1a9960b9339b31a5` | 自签 HTTPS 站点证书备用根 |", "| PrivacyGuard HTTPS Root CA | `pg_https_ca` | 模板证书指纹 | 备用 HTTPS 根，默认禁用 |"),
        ("v1.10.4 起按以下顺序排查（本模块的系统 CA **默认不启用**）：", "按以下顺序排查（首次安装默认启用设备本地 MITM 系统 CA；但这不会自动启用 HTTPS 流量重定向）："),
        ("> 升级提示：装完打开 WebUI，在「VPN → 自动核心」点一次「启动核心」确认可拉起；证书如仍报错，按上文「浏览器/App 报证书错误怎么办」逐项检查（本版默认不启用系统 CA，不会主动留下自定义根证书）。", "> 升级提示：首次安装会自动初始化并启用设备本地 MITM 系统 CA；升级时保留用户此前明确禁用/移除的选择。HTTPS 流量重定向仍需配置主机白名单后手动启用。若应用仍报错，按上文检查 CA 系统信任状态、应用证书固定、自带信任库和 TLS 支持范围。"),
        ("- 内置 CA 默认不启用；启用后 Android 14+ 依赖 APEX bind-mount，个别 ROM 的 SELinux/挂载策略可能拒绝（`certmgr.sh builtin list` 的 `apex`/`live_apex` 与 `$PG/early.log` 可判断；覆盖层不完整时会拒绝挂载以保护公共信任链，不会把全局 HTTPS 弄坏）", "- MITM 专用 CA 首次安装默认启用；Android 14+ 依赖 Conscrypt APEX 信任同步，个别 ROM 的 SELinux/挂载策略可能拒绝（用 `certmgr.sh builtin list` 检查 `apex`/`apex_ns`/`live_apex`；命名空间验证失败时状态保持未确认，不会谎报信任成功）。备用 HTTPS CA 默认禁用。"),
    ]
    for old, new in replacements:
        if old not in doc:
            raise SystemExit("README current-state anchor not found: " + old[:100])
        doc = doc.replace(old, new, 1)
    root_readme.write_text(doc, encoding="utf-8")

# The no-OpenSSL sandbox now follows the real active-module path resolver.
no_openssl_test = root / "scripts/tests/v1.0.0-cert-collision-no-openssl-regression.sh"
if no_openssl_test.is_file():
    test_source = no_openssl_test.read_text(encoding="utf-8")
    fixture_anchor = 'mkdir -p "$MOD/scripts" "$MOD/certs/submodules" "$SM/pg_mitm_ca/system/etc/security/cacerts" "$SC" "$PG" "$TMP/bin"\n'
    fixture_replacement = fixture_anchor + ': > "$MOD/module.prop"\n'
    if fixture_anchor in test_source:
        test_source = test_source.replace(fixture_anchor, fixture_replacement, 1)
    elif ': > "$MOD/module.prop"' not in test_source:
        raise SystemExit("no-OpenSSL test fixture module-root anchor not found")
    no_openssl_test.write_text(test_source, encoding="utf-8")

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
grep -Fq 'ca-trust-optin' "$SERVICE" || fail 'post-boot sync is not gated by the explicit trust marker'
grep -Fq 'ca-trust-optin' "$POST" || fail 'pre-zygote sync is not gated by the explicit trust marker'
grep -Fq 'ca-mitm-user-removed' "$CUSTOM" || fail 'explicit MITM CA removal is not preserved'
grep -Fq '_pg_mitm_preexisting_disabled' "$CUSTOM" || fail 'legacy per-module MITM disable state is not migrated'
grep -Fq '首次安装默认初始化并启用系统级信任' "$UI" || fail 'native UI still describes MITM CA as opt-in'
grep -Fq '首次安装默认启用设备本地 MITM 系统 CA' "$ROOT/README.md" || fail 'README still describes default-off MITM CA'
grep -Fq '设备本机动态生成' "$ROOT/README.md" || fail 'README still documents a static MITM CA fingerprint'
grep -Fq 'ca-mitm-user-removed' "$CERT" || fail 'certmgr does not persist explicit MITM CA removal'
grep -Fq 'ca-mitm-user-disabled' "$CERT" || fail 'certmgr does not persist explicit MITM CA disable'
grep -Fq '_THIS_MODULE_DIR/certs' "$CERT" || fail 'certmgr does not resolve active staging module directory'
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
grep -Fq 'ca-trust-optin' "$SERVICE" || fail 'boot trust sync marker missing'
grep -Fq 'ca-trust-optin' "$POST" || fail 'early boot trust sync marker missing'
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
