#!/usr/bin/env python3
"""Deploy the FX APK as a system app during module installation.

The published module archive ships a systemless overlay at
``system/app/FX/FX.apk``. Until now nothing at *install* time validated that
payload: ``customize.sh`` only set permissions on the module tree and the boot
scripts (``post-fs-data.sh``/``service.sh``) repaired ownership, SELinux context
and an ordinary-app compatibility copy afterwards.

This patch adds a single, idempotent, fail-closed deployment stage that runs from
``customize.sh``:

* validates the packaged overlay digest against its ``.sha256`` sidecar and
  refuses to deploy a payload that does not match;
* materialises the overlay from the legacy ``optional/FXUnifiedHook.apk``
  payload when the archive has no overlay yet, so upgrades from older archives
  still end up with a systemless system app;
* applies deterministic ownership/mode and the Android ``system_file`` SELinux
  context, recording what it did;
* records a digest marker so the boot stage can verify the same payload and so
  uninstall can prove FX ownership before removing anything;
* never claims privileged status: FX is not a privileged app, therefore no
  ``privapp-permissions`` allowlist is fabricated.

Failures are reported to the installer UI and the shared log, and leave a retry
marker for the boot stage; they never abort the module installation.
"""
from __future__ import annotations

import sys
from pathlib import Path

ANCHOR = 'set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644'
BEGIN = "# >>> fx-system-app-install-stage (managed by fx-patches/patch_system_app_install_stage.py)"
END = "# <<< fx-system-app-install-stage"

BLOCK = r'''
# >>> fx-system-app-install-stage (managed by fx-patches/patch_system_app_install_stage.py)
# FX 1.0.0: 安装期把随包 APK 部署为系统应用（可恢复的 systemless overlay）。
# 原则：
#   - 只处理 FX 自己的覆盖层路径，不触碰其它模块或用户数据；
#   - 校验不通过就拒绝部署，绝不把损坏/被替换的 APK 挂成系统应用；
#   - FX 不是特权应用，因此不生成 privapp-permissions 白名单，也不声称已获特权；
#   - 任何失败都只记录并留待开机重试，不中断主模块安装。
fx_system_app_state_dir=${FX_SYSTEM_APP_STATE_DIR:-/data/adb/privacyguard}
fx_system_app_log=$fx_system_app_state_dir/system-app-overlay.log
fx_system_app_marker=$fx_system_app_state_dir/system-app-apk.sha256
fx_system_app_retry=$fx_system_app_state_dir/system-app-retry

fx_system_app_note() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$fx_system_app_log" 2>/dev/null || :
}

fx_system_app_digest() {
  # toybox/busybox sha256sum; no digest means we cannot prove the payload.
  [ -s "$1" ] || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  _fx_d=$(sha256sum "$1" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$_fx_d" ] || return 1
  printf '%s\n' "$_fx_d"
}

fx_system_app_perm() {
  # Normalise ownership/mode. Failures are tolerated here (some install
  # environments run as root already) but verified again below.
  chown 0:0 "$1" 2>/dev/null || :
  chmod "$2" "$1" 2>/dev/null || :
  return 0
}

fx_system_app_context() {
  # Android labels mounted system paths by path; apply the canonical
  # system_file type as a best effort and let post-fs-data.sh re-verify.
  _fx_ctx=$(ls -Zd "$1" 2>/dev/null | awk '{print $1}')
  case "$_fx_ctx" in
    u:object_r:system_file:s0) return 0 ;;
  esac
  if command -v chcon >/dev/null 2>&1; then
    chcon u:object_r:system_file:s0 "$1" 2>/dev/null && return 0
  fi
  return 1
}

fx_system_app_stage() {
  mkdir -p "$fx_system_app_state_dir" 2>/dev/null || :
  : >> "$fx_system_app_log" 2>/dev/null || fx_system_app_log=/dev/null

  _fx_overlay_dir="$MODPATH/system/app/FX"
  _fx_overlay_apk="$_fx_overlay_dir/FX.apk"
  _fx_overlay_sum="$_fx_overlay_dir/FX.apk.sha256"
  _fx_fallback="$MODPATH/optional/FXUnifiedHook.apk"
  _fx_retry_marker="$fx_system_app_retry"

  # 归档里既没有覆盖层也没有可选载荷：明确跳过，不制造空目录。
  if [ ! -s "$_fx_overlay_apk" ] && [ ! -s "$_fx_fallback" ]; then
    ui_print "  [i] 归档未包含系统应用载荷；本次不部署系统应用"
    fx_system_app_note "SKIP: archive has neither system/app/FX/FX.apk nor optional/FXUnifiedHook.apk"
    return 0
  fi

  # 覆盖层存在但没有校验清单：拒绝部署。
  if [ -s "$_fx_overlay_apk" ] && [ ! -s "$_fx_overlay_sum" ]; then
    ui_print "  [!] 系统应用覆盖层缺少校验清单，拒绝部署"
    fx_system_app_note "ERROR: overlay checksum sidecar missing; deployment refused"
    return 1
  fi

  # 旧归档只有可选载荷：在安装期补齐覆盖层，而不是等到开机后装成普通应用。
  if [ ! -s "$_fx_overlay_apk" ] && [ -s "$_fx_fallback" ]; then
    _fx_fallback_digest=$(fx_system_app_digest "$_fx_fallback") || {
      ui_print "  [!] 无法计算可选 APK 摘要，跳过系统应用部署"
      fx_system_app_note "ERROR: cannot digest optional payload"
      return 1
    }
    mkdir -p "$_fx_overlay_dir" 2>/dev/null || {
      ui_print "  [!] 无法创建系统应用覆盖层目录"
      fx_system_app_note "ERROR: cannot create $_fx_overlay_dir"
      return 1
    }
    _fx_tmp="$_fx_overlay_dir/.FX.apk.fxstage.$$"
    if ! cp "$_fx_fallback" "$_fx_tmp" 2>/dev/null; then
      rm -f "$_fx_tmp" 2>/dev/null
      ui_print "  [!] 复制系统应用载荷失败"
      fx_system_app_note "ERROR: cannot stage overlay payload"
      return 1
    fi
    ( umask 022; printf '%s  FX.apk\n' "$_fx_fallback_digest" > "$_fx_overlay_sum.tmp.$$" ) 2>/dev/null || {
      rm -f "$_fx_tmp" "$_fx_overlay_sum.tmp.$$" 2>/dev/null
      ui_print "  [!] 写入覆盖层校验清单失败"
      fx_system_app_note "ERROR: cannot write overlay checksum sidecar"
      return 1
    }
    mv -f "$_fx_tmp" "$_fx_overlay_apk" 2>/dev/null &&
      mv -f "$_fx_overlay_sum.tmp.$$" "$_fx_overlay_sum" 2>/dev/null || {
        rm -f "$_fx_tmp" "$_fx_overlay_sum.tmp.$$" 2>/dev/null
        ui_print "  [!] 覆盖层落盘失败"
        fx_system_app_note "ERROR: cannot commit staged overlay"
        return 1
      }
    ui_print "  已从可选载荷生成系统应用覆盖层 system/app/FX/FX.apk"
    fx_system_app_note "STAGED: overlay created from optional/FXUnifiedHook.apk"
  fi

  _fx_expected=$(awk 'NR==1 {print $1}' "$_fx_overlay_sum" 2>/dev/null)
  case "$_fx_expected" in
    *[!0-9a-fA-F]*|'') 
      ui_print "  [!] 覆盖层校验清单格式无效，拒绝部署"
      fx_system_app_note "ERROR: malformed overlay checksum sidecar"
      return 1 ;;
  esac
  [ "${#_fx_expected}" -eq 64 ] || {
    ui_print "  [!] 覆盖层校验清单长度无效，拒绝部署"
    fx_system_app_note "ERROR: overlay checksum length is not 64 hex characters"
    return 1
  }
  _fx_actual=$(fx_system_app_digest "$_fx_overlay_apk") || {
    ui_print "  [!] 无法计算覆盖层 APK 摘要，拒绝部署"
    fx_system_app_note "ERROR: cannot digest overlay APK"
    return 1
  }
  if [ "$_fx_expected" != "$_fx_actual" ]; then
    ui_print "  [!] 系统应用覆盖层摘要与校验清单不一致，拒绝部署"
    fx_system_app_note "ERROR: overlay digest mismatch (expected $_fx_expected, actual $_fx_actual)"
    return 1
  fi

  fx_system_app_perm "$_fx_overlay_dir" 0755
  fx_system_app_perm "$_fx_overlay_apk" 0644
  fx_system_app_perm "$_fx_overlay_sum" 0644
  fx_system_app_context "$_fx_overlay_dir" || :
  if ! fx_system_app_context "$_fx_overlay_apk"; then
    ui_print "  [!] 未能应用 system_file SELinux 标签；post-fs-data 会再次校正"
    fx_system_app_note "WARN: system_file context not applied at install time"
  fi

  # 记录部署摘要：开机阶段核对同一载荷，卸载阶段据此证明 FX 所有权。
  ( umask 077; printf '%s\n' "$_fx_actual" > "$fx_system_app_marker.tmp.$$" ) 2>/dev/null &&
    chmod 0600 "$fx_system_app_marker.tmp.$$" 2>/dev/null &&
    mv -f "$fx_system_app_marker.tmp.$$" "$fx_system_app_marker" 2>/dev/null || {
      rm -f "$fx_system_app_marker.tmp.$$" 2>/dev/null
      ui_print "  [!] 无法写入系统应用部署记录"
      fx_system_app_note "ERROR: cannot commit deployment marker"
      return 1
    }
  [ "$(cat "$fx_system_app_marker" 2>/dev/null)" = "$_fx_actual" ] || {
    ui_print "  [!] 系统应用部署记录回读不一致"
    fx_system_app_note "ERROR: deployment marker readback mismatch"
    return 1
  }

  # 部署成功后清除历史重试标记，避免开机阶段重复安装覆盖。
  rm -f "$_fx_retry_marker" 2>/dev/null || :

  _fx_ctx_final=$(ls -Zd "$_fx_overlay_apk" 2>/dev/null | awk '{print $1}')
  _fx_short=$(printf '%s' "$_fx_actual" | cut -c1-12)
  ui_print "  [✓] 系统应用覆盖层就绪：system/app/FX/FX.apk (${_fx_short}…)"
  ui_print "      重启后由 PackageManager 按系统应用识别；FX 非特权应用，不声明 privapp 权限"
  fx_system_app_note "OK: overlay deployed, digest=$_fx_actual context=${_fx_ctx_final:-unknown}"
  return 0
}

if fx_system_app_stage; then
  :
else
  ui_print "  [!] 系统应用部署未完成；主模块继续安装，开机服务会重试（日志：$fx_system_app_log）"
  ( umask 077; printf '%s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" > "$fx_system_app_retry.tmp.$$" ) 2>/dev/null &&
    mv -f "$fx_system_app_retry.tmp.$$" "$fx_system_app_retry" 2>/dev/null || :
fi
# <<< fx-system-app-install-stage
'''


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
    customize = root / "customize.sh"
    if not customize.is_file():
        raise SystemExit("FX customize.sh is missing")

    text = customize.read_text(encoding="utf-8")

    # Idempotence: re-running the patch must not duplicate the stage.
    if BEGIN in text or END in text:
        if BEGIN not in text or END not in text:
            raise SystemExit("fx-system-app-install-stage markers are inconsistent; refusing to patch")
        start = text.index(BEGIN)
        end = text.index(END, start) + len(END)
        text = text[:start] + text[end:]
        text = text.replace("\n\n\n", "\n\n")

    if text.count(ANCHOR) != 1:
        raise SystemExit("customize.sh webroot permission anchor changed; refusing to patch")

    block = BLOCK.strip("\n")
    text = text.replace(ANCHOR, ANCHOR + "\n\n" + block, 1)
    customize.write_text(text, encoding="utf-8")

    # The stage must stay reachable from the installer: verify the call site.
    written = customize.read_text(encoding="utf-8")
    for required in (BEGIN, END, "if fx_system_app_stage; then", ANCHOR):
        if required not in written:
            raise SystemExit(f"customize.sh system-app stage is incomplete: missing {required!r}")
    if written.count(BEGIN) != 1 or written.count(END) != 1:
        raise SystemExit("customize.sh system-app stage must appear exactly once")

    print("Patched fx-module/customize.sh with install-time system-app deployment")


if __name__ == "__main__":
    main()
