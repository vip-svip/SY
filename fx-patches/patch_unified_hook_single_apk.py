#!/usr/bin/env python3
"""Collapse FX's dual LSPosed APK deployment to the API-101 FX Hook package.

The retired API-82 entry only concealed VPN-related packages from PackageManager.
That concealment is intentionally not migrated. Existing FX-owned legacy installs
are removed only after the modern APK is installed successfully and only when
the ownership marker proves FX originally installed them.
"""
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
installer = root / "scripts/install_adhook_app.sh"
remover = root / "scripts/remove_adhook_app.sh"
regression = root / "scripts/tests/adhook-app-installer-regression.sh"
apk = root / "optional/FXAdHook.apk"
legacy_apk = root / "optional/PrivacyGuardHook.apk"
legacy_hash = root / "optional/PrivacyGuardHook.apk.sha256"

for p in (installer, remover, regression, apk):
    if not p.is_file():
        raise SystemExit(f"required single-Hook input missing: {p}")
with zipfile.ZipFile(apk) as z:
    names = set(z.namelist())
    if "META-INF/xposed/java_init.list" not in names:
        raise SystemExit("FXAdHook.apk does not contain the libxposed entrypoint")
    init = z.read("META-INF/xposed/java_init.list").decode("utf-8", "strict").strip()
    if init != "de.privacyguard.adhook.AdVisibilityHook":
        raise SystemExit("unexpected FX Hook entrypoint; refusing single-APK packaging")

installer.write_text(r'''#!/system/bin/sh
# Install the one unified libxposed API-101 FX Hook package.
set -u
MODDIR=${1:-}
if [ -z "$MODDIR" ]; then
  _d=$(dirname "$0" 2>/dev/null)
  MODDIR=$(cd "$_d/.." 2>/dev/null && pwd)
fi
STATE_DIR=${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}
TMP_DIR=${FX_ADHOOK_TMP_DIR:-/data/local/tmp}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
mkdir -p "$STATE_DIR" "$TMP_DIR" 2>/dev/null || :
log_msg() {
  _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) install_adhook_app: $*"
  printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :
  printf '%s\n' "$*"
}
package_present() { pm path "$1" 2>/dev/null | grep -q '^package:'; }
remove_legacy_if_fx_owned() {
  _pkg=de.privacyguard.hook
  _marker="$STATE_DIR/adhook-apk-privacyguardhook.sha256"
  _owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  [ -s "$_marker" ] || return 0
  if [ ! -s "$_owned" ]; then
    log_msg "legacy package ownership is unproven; preserving it: $_pkg"
    rm -f "$_marker" 2>/dev/null
    return 0
  fi
  if package_present "$_pkg"; then
    if pm uninstall "$_pkg" >> "$LOG" 2>&1; then
      log_msg "removed retired FX-owned API-82 package after API-101 install: $_pkg"
    else
      log_msg "WARN: could not remove retired FX-owned API-82 package: $_pkg"
      return 1
    fi
  fi
  rm -f "$_marker" "$_owned" 2>/dev/null
  return 0
}
APK="$MODDIR/optional/FXAdHook.apk"
PKG=de.privacyguard.adhook
SLUG=fxadhook
MARKER="$STATE_DIR/adhook-apk-$SLUG.sha256"
OWNED="$STATE_DIR/adhook-apk-$SLUG.fx-owned"
if [ ! -s "$APK" ]; then log_msg "ERROR: unified FX Hook APK missing: $APK"; exit 1; fi
if ! command -v pm >/dev/null 2>&1; then log_msg "WARN: pm command unavailable; cannot install $PKG"; exit 1; fi
ACTUAL=$(sha256sum "$APK" 2>/dev/null | awk 'NR==1 {print $1}')
if [ -z "$ACTUAL" ]; then log_msg "ERROR: cannot compute APK digest"; exit 1; fi
if [ -s "$APK.sha256" ]; then
  EXPECTED=$(awk 'NR==1 {print $1}' "$APK.sha256" 2>/dev/null)
  if [ -n "$EXPECTED" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
    log_msg "ERROR: unified APK checksum mismatch; refusing install"; exit 1
  fi
fi
PRIOR=$(cat "$MARKER" 2>/dev/null)
WAS_PRESENT=0
package_present "$PKG" && WAS_PRESENT=1
if [ "$WAS_PRESENT" = 1 ] && [ "$PRIOR" = "$ACTUAL" ]; then
  log_msg "unified FX Hook already installed and unchanged"
  remove_legacy_if_fx_owned || exit 1
  exit 0
fi
STAGE="$TMP_DIR/.fx-unified-hook-$$.apk"
rm -f "$STAGE" 2>/dev/null
if ! cp "$APK" "$STAGE" 2>/dev/null; then log_msg "ERROR: cannot stage unified APK"; exit 1; fi
chmod 0644 "$STAGE" 2>/dev/null || :
chown shell:shell "$STAGE" 2>/dev/null || :
command -v restorecon >/dev/null 2>&1 && restorecon "$STAGE" 2>/dev/null || :
command -v chcon >/dev/null 2>&1 && chcon u:object_r:shell_data_file:s0 "$STAGE" 2>/dev/null || :
ATTEMPT=1
INSTALLED=0
while [ "$ATTEMPT" -le 3 ]; do
  if [ -f "$LOG" ]; then LOG_LINES=$(wc -l < "$LOG" 2>/dev/null || echo 0); else LOG_LINES=0; fi
  if pm install -r "$STAGE" >> "$LOG" 2>&1 && package_present "$PKG"; then
    if [ "$WAS_PRESENT" = 0 ]; then
      OWNED_TMP="$OWNED.tmp.$$"
      (umask 077; printf 'fx-managed-v1\n' > "$OWNED_TMP") &&
        chmod 0600 "$OWNED_TMP" 2>/dev/null && mv -f "$OWNED_TMP" "$OWNED" 2>/dev/null ||
        log_msg "WARN: ownership marker could not be persisted for $PKG"
    fi
    MARKER_TMP="$MARKER.tmp.$$"
    (umask 077; printf '%s\n' "$ACTUAL" > "$MARKER_TMP") &&
      chmod 0600 "$MARKER_TMP" 2>/dev/null && mv -f "$MARKER_TMP" "$MARKER" 2>/dev/null
    INSTALLED=1
    break
  fi
  if tail -n "+$((LOG_LINES + 1))" "$LOG" 2>/dev/null | grep -Eqi 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|signing certificate'; then
    log_msg "ERROR: unified APK signing certificate differs; existing package and data preserved"
    rm -f "$STAGE" 2>/dev/null
    exit 1
  fi
  log_msg "WARN: PackageManager install attempt $ATTEMPT/3 failed for $PKG"
  ATTEMPT=$((ATTEMPT + 1))
  [ "$ATTEMPT" -le 3 ] && sleep 2
done
rm -f "$STAGE" 2>/dev/null
[ "$INSTALLED" = 1 ] || { log_msg "ERROR: unable to install unified FX Hook"; exit 1; }
if [ ! -s "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$ACTUAL" ]; then
  log_msg "WARN: installed unified APK but checksum state marker could not be persisted"
fi
remove_legacy_if_fx_owned || exit 1
log_msg "unified FX Hook installed; enable its single LSPosed module/scope and reboot"
exit 0
''', encoding="utf-8")

remover.write_text(r'''#!/system/bin/sh
# Remove only Hook packages proven to have been installed and owned by FX.
set -u
STATE_DIR=${2:-${FX_ADHOOK_STATE_DIR:-/data/adb/privacyguard}}
LOG=${FX_ADHOOK_LOG:-$STATE_DIR/adhook-install.log}
log_msg() {
  _msg="$(date '+%m-%d %H:%M:%S' 2>/dev/null) remove_adhook_app: $*"
  printf '%s\n' "$_msg" >> "$LOG" 2>/dev/null || :
}
[ -d "$STATE_DIR" ] || exit 0
command -v pm >/dev/null 2>&1 || exit 0
RESULT=0
for PAIR in 'de.privacyguard.adhook fxadhook' 'de.privacyguard.hook privacyguardhook'; do
  set -- $PAIR
  PKG=$1
  SLUG=$2
  MARKER="$STATE_DIR/adhook-apk-$SLUG.sha256"
  OWNED="$STATE_DIR/adhook-apk-$SLUG.fx-owned"
  [ -s "$MARKER" ] || continue
  if [ ! -s "$OWNED" ]; then
    log_msg "leaving pre-existing or ownership-unknown package untouched: $PKG"
    rm -f "$MARKER" 2>/dev/null
    continue
  fi
  PATHS=$(pm path "$PKG" 2>/dev/null)
  if [ -z "$PATHS" ]; then rm -f "$MARKER" "$OWNED" 2>/dev/null; continue; fi
  case "$PATHS" in
    *:/system/*|*:/product/*|*:/vendor/*)
      log_msg "system-overlay package will disappear with module unmount: $PKG"
      rm -f "$MARKER" "$OWNED" 2>/dev/null
      ;;
    *)
      if pm uninstall "$PKG" >> "$LOG" 2>&1; then
        log_msg "removed FX-managed package: $PKG"
        rm -f "$MARKER" "$OWNED" 2>/dev/null
      else
        log_msg "WARN: could not remove FX-managed package: $PKG"
        RESULT=1
      fi
      ;;
  esac
done
exit "$RESULT"
''', encoding="utf-8")

# Update the host-side installer regression to model one APK and legacy migration.
regression.write_text(r'''#!/bin/sh
# Host regression for the single-APK FX Hook installer and safe API-82 migration.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"
REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] || fail "unified installer missing"
[ -s "$REMOVER" ] || fail "unified remover missing"
PACKAGED_INSTALLER="$ROOT/fx-module/scripts/install_adhook_app.sh"
[ -s "$PACKAGED_INSTALLER" ] || fail "packaged installer missing"
cmp -s "$INSTALLER" "$PACKAGED_INSTALLER" || fail "packaged installer drifted"
TMP="${TMPDIR:-/tmp}/fx-unified-hook-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'fake unified apk payload\n' > "$TMP/mod/optional/FXAdHook.apk"
sha256sum "$TMP/mod/optional/FXAdHook.apk" > "$TMP/mod/optional/FXAdHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
STATE=$FX_ADHOOK_FAKE_PM_STATE
mkdir -p "$STATE"
case "$1" in
  path)
    grep -Fxq "$2" "$STATE/installed" 2>/dev/null && { echo "package:/data/app/$2/base.apk"; exit 0; }
    exit 1
    ;;
  install)
    [ "$2" = "-r" ] || exit 2
    [ -s "$3" ] || exit 3
    if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then
      echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2
      exit 1
    fi
    grep -Fxv de.privacyguard.adhook "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo de.privacyguard.adhook >> "$STATE/installed"
    echo install >> "$STATE/calls"
    ;;
  uninstall)
    grep -Fxv "$2" "$STATE/installed" > "$STATE/installed.tmp" 2>/dev/null || :
    mv "$STATE/installed.tmp" "$STATE/installed"
    echo "$2" >> "$STATE/uninstalls"
    ;;
  *) exit 9 ;;
esac
PM
chmod 0755 "$TMP/bin/pm"
export PATH="$TMP/bin:$PATH"
export FX_ADHOOK_FAKE_PM_STATE="$TMP/pm"
export FX_ADHOOK_STATE_DIR="$TMP/state"
export FX_ADHOOK_TMP_DIR="$TMP/tmp"
export FX_ADHOOK_LOG="$TMP/state/install.log"
# Simulate a legacy FX-owned package. Migration removes it only after API-101 succeeds.
printf '%s\n' de.privacyguard.hook > "$TMP/pm/installed"
printf 'legacy-digest\n' > "$TMP/state/adhook-apk-privacyguardhook.sha256"
printf 'fx-managed-v1\n' > "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "unified install or legacy migration failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified API-101 package not installed"
! grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "FX-owned legacy package not migrated away"
[ "$(wc -l < "$TMP/pm/calls" | tr -d ' ')" = 1 ] || fail "installer must install exactly one APK"
[ -s "$TMP/state/adhook-apk-fxadhook.fx-owned" ] || fail "new package ownership marker missing"
[ ! -e "$TMP/state/adhook-apk-privacyguardhook.fx-owned" ] || fail "legacy ownership marker not cleared"
# Idempotent retry must not reinstall.
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/calls" | tr -d ' ')" = 1 ] || fail "unchanged APK was reinstalled"
# Signature mismatch preserves the current installed package and does not uninstall.
printf 'changed fake apk payload\n' >> "$TMP/mod/optional/FXAdHook.apk"
sha256sum "$TMP/mod/optional/FXAdHook.apk" > "$TMP/mod/optional/FXAdHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch should fail"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed on signature mismatch"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
# User-owned legacy package without ownership marker must never be removed.
printf '%s\n' de.privacyguard.hook >> "$TMP/pm/installed"
printf 'legacy-digest\n' > "$TMP/state/adhook-apk-privacyguardhook.sha256"
rm -f "$TMP/state/adhook-apk-privacyguardhook.fx-owned"
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "unified cleanup failed"
! grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "FX-owned unified package not removed"
grep -Fxq de.privacyguard.hook "$TMP/pm/installed" || fail "pre-existing legacy package was incorrectly removed"
grep -q 'de.privacyguard.hook' "$TMP/state/install.log" || fail "legacy migration was not logged"
if grep -Eqi 'iptables|ip6tables|dns_hijack|vpn_mode|setprop net\.' "$INSTALLER" "$REMOVER"; then
  fail "Hook package installer unexpectedly mutates networking"
fi
echo "PASS: one API-101 Hook APK installs, migrates only FX-owned legacy package, and safely uninstalls"
''', encoding="utf-8")

# Legacy APK is deliberately excluded from new KernelSU payloads.
legacy_apk.unlink(missing_ok=True)
legacy_hash.unlink(missing_ok=True)

# Keep repository-side deployment scripts byte-identical to the packaged scripts.
repo = root.parent
(repo / "scripts/install_adhook_app.sh").write_text(installer.read_text(encoding="utf-8"), encoding="utf-8")
(repo / "scripts/remove_adhook_app.sh").write_text(remover.read_text(encoding="utf-8"), encoding="utf-8")
(repo / "scripts/tests/adhook-app-installer-regression.sh").write_text(regression.read_text(encoding="utf-8"), encoding="utf-8")

# Update the old package regression: only the modern single APK is expected now.
for test_path in (
    root / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh",
    repo / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh",
):
    if test_path.is_file():
        test = test_path.read_text(encoding="utf-8")
        old_checks = '''[ -s "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "legacy Hook APK missing from optional app payload"
[ -s "$ROOT/optional/PrivacyGuardHook.apk.sha256" ] || fail "legacy Hook APK checksum missing"
[ "$(sha256sum "$ROOT/optional/PrivacyGuardHook.apk" | awk '{print $1}')" = "$(awk 'NR==1 {print $1}' "$ROOT/optional/PrivacyGuardHook.apk.sha256")" ] || fail "legacy Hook APK checksum mismatch"
'''
        test = test.replace(old_checks, '''[ ! -e "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "retired API-82 APK must not be packaged"
[ ! -e "$ROOT/optional/PrivacyGuardHook.apk.sha256" ] || fail "retired API-82 checksum must not be packaged"
''')
        test = test.replace("PASS: FXAdHook APK archive, entrypoint, features, checksum, and ordinary-app deployment", "PASS: single FX Hook APK archive, entrypoint, features, checksum, and ordinary-app deployment")
        test_path.write_text(test, encoding="utf-8")

# Replace the historical dual-APK audit assertions with executable single-APK acceptance.
audit_test = r'''#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" ] || fail "single APK merge audit missing"
grep -q "唯一 API-101" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "single API-101 architecture not documented"
grep -q "de.privacyguard.adhook" "$ROOT/adhook/app/build.gradle" || fail "unified package identity missing"
grep -q "io.github.libxposed:api:101.0.1" "$ROOT/adhook/app/build.gradle" || fail "modern API dependency missing"
grep -q "de.privacyguard.adhook.AdVisibilityHook" "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "single runtime entrypoint missing"
grep -q "de.privacyguard.adhook" "$ROOT/scripts/install_adhook_app.sh" || fail "unified APK install missing"
! grep -q "install_one de.privacyguard.hook" "$ROOT/scripts/install_adhook_app.sh" || fail "retired API-82 package is still installed"
grep -q "remove_legacy_if_fx_owned" "$ROOT/scripts/install_adhook_app.sh" || fail "ownership-safe legacy migration missing"
grep -q "签名不兼容时不卸载" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "upgrade safety acceptance missing"
echo "PASS: one API-101 package, one entrypoint, ownership-safe API-82 migration"
'''
for test_path in (
    root / "scripts/tests/v1.0.0-fxhook-single-apk-merge-audit-regression.sh",
    repo / "scripts/tests/v1.0.0-fxhook-single-apk-merge-audit-regression.sh",
):
    if test_path.is_file():
        test_path.write_text(audit_test, encoding="utf-8")

# Replace the old blocker-only audit with the implemented migration result and explicit exclusions.
audit = """# FX Hook 单 APK 合并结果 — FX 1.0.0

状态：源码与安装包迁移已实现；CI/打包回归待本次工作流完成；OnePlus 12 真机升级验证仍待执行。

## 统一架构

- 唯一安装包：optional/FXAdHook.apk
- 唯一 applicationId：de.privacyguard.adhook
- 唯一 API-101 运行时：libxposed
- 唯一入口：de.privacyguard.adhook.AdVisibilityHook
- 唯一配置通道：LSPosed Remote Files fx-hook-targets.conf
- API-82 PrivacyGuardHook.apk 不再打入新的 FX ZIP，也不再由安装器安装。

## 旧模块迁移边界

旧 MainHook 的实际功能是从 PackageManager 查询结果中隐藏一组 VPN/系统应用。它没有可迁移的普通隐私策略或独立配置功能。该应用隐匿逻辑不移植到统一运行时；不伪称旧模块的应用隐藏功能仍然存在。

新安装器先安装并确认 API-101 APK 成功，再根据旧版 FX 所有权标记清理 API-82 包。若缺少 .fx-owned 所有权标记，则保留该包，避免卸载用户原有应用。签名不兼容时不强制卸载，也不清除应用数据。

## 已迁移并保留的 API-101 功能

广告视图观察/过滤、按目标应用配置的隐私策略、剪贴板进程隔离、EXIF 脱敏、传感器/麦克风/相机/位置访问策略、Wi-Fi 扫描和通知相关隐私策略，以及只读会员/计费诊断仍由统一 API-101 模块提供。购买结果、会员权益和服务端授权状态不会被伪造或改写。

## 验收状态

- [x] 单 APK / 单 applicationId / 单 libxposed API-101 入口。
- [x] 新 ZIP 不再包含 API-82 APK。
- [x] 安装器只安装一个 APK。
- [x] 仅清理有 FX 所有权标记的旧 API-82 安装。
- [x] 卸载时保留所有权不明或用户预先安装的应用。
- [x] 固定版本 1.0.0。
- [ ] 本次 GitHub Actions 完成单 APK 构建和回归测试。
- [ ] OnePlus 12 + KernelSU + LSPosed 真机安装、scope、升级、卸载与回滚验证。

签名不兼容时不卸载用户现有包，不删除用户数据。未完成真机验证前，不宣称设备端整合已验证。
"""
for doc_path in (root / "docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md", repo / "docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md"):
    if doc_path.parent.is_dir():
        doc_path.write_text(audit, encoding="utf-8")

print("Applied single-APK FX Hook packaging and ownership-safe API-82 migration.")
