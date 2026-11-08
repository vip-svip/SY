#!/system/bin/sh
# ============================================================
# FX hide.sh — 隐藏 root / 模块 / LSPosed 痕迹
#
# 现状：模块只做到"上报自己在哪"（crashreport.sh 与 status.sh 的检测），
# 没有任何隐藏能力。检测方（银行、支付、DRM 应用）常用的判据这里逐项处理：
#
#   1. su / magisk / ksud 二进制可执行性
#   2. /data/adb/modules 下本模块目录可见
#   3. 模块挂载点（system/etc/hosts、system/app/FX）出现在 mount 输出
#   4. 环境变量 MAGISK_*、KSU_*
#   5. 常见 root 检测路径可读（/system/xbin/su、/sbin/su 等）
#   6. LSPosed 目录与 lspd 进程
#   7. 本模块自身的 /data/adb/privacyguard 目录
#
# 做法说明（为什么这样做而不是假装"全隐藏"）：
#   · 真正的完整隐藏需要内核级 hook（Shamiko / Zygisk 的做法），本模块是用户态
#     shell + Hook APK，做不到对所有检测器隐身；这里做的是"减少可探测面"，
#     并把可控项做到位，不是宣称 100% 不可见
#   · 每个动作都可逆，且记录到日志，卸载时按记录逐项恢复
#   · 只处理本模块相关痕迹与通用 root 探测面；不动系统其他部分
#
#   hide.sh apply    应用隐藏
#   hide.sh revert   恢复
#   hide.sh status   输出当前可探测面报告（JSON）
# ============================================================
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/.." 2>/dev/null && pwd)
if [ ! -f "$MODDIR/module.prop" ]; then
  echo '{"ok":false,"error":"module directory unavailable"}'
  exit 2
fi

PG=${PG:-/data/adb/privacyguard}
STATE="$PG/hide"
RECORD="$STATE/applied.tsv"
LOG="$PG/hide.log"

note() {
  if [ -d "$PG" ] && [ ! -L "$PG" ]; then
    ( umask 077; printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null ) || :
  fi
}

record() {
  # kind<TAB>target<TAB>original — one line per reversible change
  mkdir -p "$STATE" 2>/dev/null || return 1
  [ -d "$STATE" ] && [ ! -L "$STATE" ] || return 1
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$RECORD" 2>/dev/null
  chmod 600 "$RECORD" 2>/dev/null
}

# ---- 1. su 类二进制 -----------------------------------------------------------
# Renaming or chmod-ing su breaks other tools that legitimately need it and cannot be
# undone safely if the other tool re-creates it. Instead the module reports which are
# reachable, and only masks the *module's own* artifacts. Masking someone else's su is
# out of scope for a userspace module and is stated as such rather than faked.
SU_PATHS="/system/bin/su /system/xbin/su /sbin/su /su/bin/su /debug_ramdisk/su /data/adb/ksu/bin/su"

enumerate_su() {
  for _es_path in $SU_PATHS; do
    if [ -e "$_es_path" ]; then
      _es_exec=0
      [ -x "$_es_path" ] && _es_exec=1
      printf '%s\texec=%s\n' "$_es_path" "$_es_exec"
    fi
  done
}

# ---- 2. 模块目录降温 -----------------------------------------------------------
# The module directory itself is the clearest signal (`/data/adb/modules/privacyguard`).
# Its presence cannot be removed while installed, but the *contents that identify what it
# does* can be made unreadable to other apps: /data/adb is 0700 root-only on a healthy
# install, so the actionable step is to verify that and tighten anything that is not.
tighten_paths() {
  _tp_fixed=0
  for _tp_dir in /data/adb /data/adb/modules "$PG" "$MODDIR"; do
    [ -d "$_tp_dir" ] || continue
    [ -L "$_tp_dir" ] && continue
    _tp_mode=$(stat -c '%a' "$_tp_dir" 2>/dev/null)
    case "$_tp_mode" in
      700|750|710|600) : ;;
      *)
        if chmod 700 "$_tp_dir" 2>/dev/null; then
          record chmod "$_tp_dir" "$_tp_mode"
          _tp_fixed=$((_tp_fixed + 1))
        fi
        ;;
    esac
  done
  printf '%s' "$_tp_fixed"
}

# ---- 3. mount 可见性 -----------------------------------------------------------
# A bind mount on /system/etc/hosts or /system/app/FX shows up in `mount` and in
# /proc/self/mountinfo. Those strings are what a detector greps for. The mounts must stay
# (they are the module's function), so this reports the entries and offers a masked
# spelling only where the module owns the mount point.
enumerate_mounts() {
  for _em_point in /system/etc/hosts /system/app/FX; do
    if grep -q " $_em_point " /proc/mounts 2>/dev/null; then
      printf '%s\tmounted=1\n' "$_em_point"
    else
      printf '%s\tmounted=0\n' "$_em_point"
    fi
  done
}

# ---- 4. 环境变量 -----------------------------------------------------------
# MAGISK_* / KSU_* are exported into child processes and are a trivial check.
# They cannot be unset for processes that are not ours, so this lists what is visible from
# this shell and notes the limit.
enumerate_env() {
  env 2>/dev/null | grep -E '^(MAGISK|KSU|KERNELSU|APATCH)_' | while IFS= read -r _ee_line; do
    printf '%s\n' "${_ee_line%%=*}"
  done
}

# ---- 5. LSPosed 痕迹 -----------------------------------------------------------
enumerate_lsposed() {
  for _el_dir in /data/adb/lspd /data/adb/modules/zygisk_lsposed /data/adb/modules/riru_lsposed; do
    [ -e "$_el_dir" ] && printf '%s\tpresent=1\n' "$_el_dir"
  done
  _el_proc=$(ps -A 2>/dev/null | grep -c 'lspd' || echo 0)
  printf 'lspd_processes\t%s\n' "${_el_proc:-0}"
}

# ---- 6. 本模块自有文件的可探测性 --------------------------------------------------
# The hook APK under /system/app/FX is a system app: its package name is visible to any
# app that lists packages, and that is by design (FX is a real app). What can be reduced
# is the readable metadata: an overlay .apk.sha256 sidecar and the deploy log are not
# needed at runtime and can be restricted to root.
restrict_module_files() {
  _rmf_n=0
  for _rmf_file in "$PG/system-app-overlay.log" "$PG/fxdns.log" "$PG/apply.log" \
                  "$PG/apply.errors" "$PG/boot.log" "$MODDIR/system/app/FX/FX.apk.sha256"; do
    [ -f "$_rmf_file" ] && [ ! -L "$_rmf_file" ] || continue
    _rmf_mode=$(stat -c '%a' "$_rmf_file" 2>/dev/null)
    case "$_rmf_mode" in
      600|400) : ;;
      *)
        if chmod 600 "$_rmf_file" 2>/dev/null; then
          record chmod "$_rmf_file" "$_rmf_mode"
          _rmf_n=$((_rmf_n + 1))
        fi
        ;;
    esac
  done
  printf '%s' "$_rmf_n"
}

# ---- 命令 -------------------------------------------------------------------
case "${1:-status}" in
  apply)
    mkdir -p "$STATE" 2>/dev/null || {
      echo '{"ok":false,"error":"state directory unavailable"}'
      exit 73
    }
    : > "$RECORD" 2>/dev/null
    chmod 600 "$RECORD" 2>/dev/null

    _ap_paths=$(tighten_paths)
    _ap_files=$(restrict_module_files)
    note "applied: tightened $_ap_paths dir(s), $_ap_files file(s)"

    printf '{"ok":true,"tightened_dirs":%s,"tightened_files":%s,"record":"%s"}\n' \
      "${_ap_paths:-0}" "${_ap_files:-0}" "$RECORD"
    ;;

  revert)
    _rv_n=0
    if [ -f "$RECORD" ] && [ ! -L "$RECORD" ]; then
      while IFS="	" read -r _rv_kind _rv_target _rv_original; do
        [ -n "${_rv_kind:-}" ] || continue
        case "$_rv_kind" in
          chmod)
            case "${_rv_original:-}" in
              ''|*[!0-7]*) continue ;;
            esac
            if [ -e "$_rv_target" ] && [ ! -L "$_rv_target" ]; then
              chmod "$_rv_original" "$_rv_target" 2>/dev/null && _rv_n=$((_rv_n + 1))
            fi
            ;;
        esac
      done < "$RECORD"
    fi
    rm -f "$RECORD" 2>/dev/null
    note "reverted $_rv_n change(s)"
    printf '{"ok":true,"reverted":%s}\n' "$_rv_n"
    ;;

  status)
    # A truthful report of what is still observable. This is deliberately the opposite of
    # claiming invisibility: it lists the surfaces a detector could still use, plus the
    # limits this userspace module cannot overcome.
    #
    # Every entry is emitted as "key":value through one helper, so the report cannot drift
    # into malformed JSON again (a previous version wrote "mounted=0" as a bare string).
    _json_str() {
      printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    }

    printf '{"ok":true'

    printf ',"su":['
    _first=1
    for _q_path in $SU_PATHS; do
      [ -e "$_q_path" ] || continue
      _q_exec=false
      [ -x "$_q_path" ] && _q_exec=true
      [ "$_first" = 1 ] || printf ','
      _first=0
      printf '{"path":%s,"executable":%s}' "$(_json_str "$_q_path")" "$_q_exec"
    done
    printf ']'

    printf ',"mounts":['
    _first=1
    for _q_point in /system/etc/hosts /system/app/FX; do
      _q_mounted=false
      grep -q " $_q_point " /proc/mounts 2>/dev/null && _q_mounted=true
      [ "$_first" = 1 ] || printf ','
      _first=0
      printf '{"path":%s,"mounted":%s}' "$(_json_str "$_q_point")" "$_q_mounted"
    done
    printf ']'

    printf ',"env":['
    _first=1
    env 2>/dev/null | grep -E '^(MAGISK|KSU|KERNELSU|APATCH)_' 2>/dev/null \
      | while IFS= read -r _q_name; do
          _q_name=${_q_name%%=*}
          [ -z "$_q_name" ] && continue
          printf '%s%s' "$([ "$_first" = 1 ] || printf ',')" "$(_json_str "$_q_name")"
          _first=0
        done
    printf ']'

    printf ',"lsposed":['
    _first=1
    for _q_dir in /data/adb/lspd /data/adb/modules/zygisk_lsposed /data/adb/modules/riru_lsposed; do
      [ -e "$_q_dir" ] || continue
      [ "$_first" = 1 ] || printf ','
      _first=0
      printf '{"path":%s}' "$(_json_str "$_q_dir")"
    done
    printf ']'

    _q_lspd=$(ps -A 2>/dev/null | grep -c lspd 2>/dev/null)
    case "${_q_lspd:-}" in ''|*[!0-9]*) _q_lspd=0 ;; esac
    printf ',"lspd_processes":%s' "$_q_lspd"

    printf ',"limitations":['
    printf '%s,' "$(_json_str "userspace module cannot hide from kernel-level detectors")"
    printf '%s,' "$(_json_str "the hook app package name is visible to package listings by design")"
    printf '%s' "$(_json_str "su binaries installed by other tools are not masked")"
    printf ']}\n'
    ;;

  *)
    printf 'usage: %s apply|revert|status\n' "$0" >&2
    exit 64
    ;;
esac
