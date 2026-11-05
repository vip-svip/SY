#!/usr/bin/env python3
"""Publish the FX / third-party VPN coexistence verdict for the App and WebUI.

Requirement 3 wants the Android system VPN, a third-party VpnService app and the
FX kernel-level dataplane to coexist, with the outcome *visible* rather than
silently assumed. ``apply.sh`` already detects the outer tunnel and decides
whether FX must suspend interception, but it never persists that decision, so
neither the App nor the WebUI can tell the user what grade they are actually in.

This patch injects a status publisher immediately after the external-VPN
decision block, before the DNS-target logic. It:

* reuses the variables ``apply.sh`` already computed (``_PG_EXT_VPN_IF``,
  ``_PG_EXT_VPN_UID``, ``_PG_VPN_INTERCEPTION_BLOCKED``) instead of probing the
  network a second time;
* delegates the grade to ``scripts/fx-vpn-coexistence-arbiter.sh`` when it is
  present, so there is exactly one definition of the rules;
* falls back to a local, conservative grade when the arbiter is missing, and
  never upgrades the verdict to "parallel" without evidence;
* writes atomically to ``/data/adb/privacyguard/vpn-coexistence.json`` (0600)
  so a half-written file is never observed by the reader;
* is fail-open: a status write error must never break the user's network.
"""
from __future__ import annotations

import sys
from pathlib import Path

BEGIN = "# >>> fx-vpn-coexistence-status (managed by fx-patches/patch_vpn_coexistence_status.py)"
END = "# <<< fx-vpn-coexistence-status"
ANCHOR = "# ---------- 可信 DNS 目标（DNS 修复的核心）----------"

BLOCK = r'''
# >>> fx-vpn-coexistence-status (managed by fx-patches/patch_vpn_coexistence_status.py)
# FX 1.0.0：把「内核级数据面 / 第三方 VPN」共存等级发布为可读状态。
# 复用本脚本上方已算出的 _PG_EXT_VPN_IF / _PG_EXT_VPN_UID / _PG_VPN_INTERCEPTION_BLOCKED，
# 不重复探测网络，避免两套判定互相矛盾。任何失败都不得影响用户网络。
fx_coexist_status_write() {
  _fx_cs_dir=${FX_COEXIST_STATE_DIR:-/data/adb/privacyguard}
  _fx_cs_json="$_fx_cs_dir/vpn-coexistence.json"
  mkdir -p "$_fx_cs_dir" 2>/dev/null || return 0

  _fx_cs_if=${_PG_EXT_VPN_IF:-}
  _fx_cs_uid=${_PG_EXT_VPN_UID:-}
  case "$_fx_cs_uid" in ''|*[!0-9]*|0) _fx_cs_uid="" ;; esac
  _fx_cs_blocked=${_PG_VPN_INTERCEPTION_BLOCKED:-0}

  # 单一事实来源：优先让裁决器给等级，它同时检查端口冲突与槽位不变量。
  _fx_cs_verdict=""
  _fx_cs_grade=""
  _fx_cs_probe=""
  _fx_cs_route_probe="unverified"
  _fx_cs_slot="unknown"
  _fx_cs_dns_port=5353
  _fx_cs_dns_owner=unknown
  _fx_cs_filter_dns_port=53
  _fx_cs_filter_dns_owner=unknown
  _fx_cs_proxy_port=7890
  _fx_cs_proxy_owner=unknown
  # apply.sh 使用 MODDIR（不是 MODPATH）；MODDIR 未定义时必须留空而不是崩溃。
  _fx_cs_arb=${FX_COEXIST_ARBITER:-${MODDIR:-}/scripts/fx-vpn-coexistence-arbiter.sh}
  if [ -r "$_fx_cs_arb" ]; then
    _fx_cs_out=$(sh "$_fx_cs_arb" 2>/dev/null || true)
    _fx_cs_verdict=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"verdict":"\([a-z_]*\)".*/\1/p')
    _fx_cs_grade=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"grade_cn":"\([^"]*\)".*/\1/p')
    _fx_cs_probe=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"probe":"\([a-z_]*\)".*/\1/p')
    _fx_cs_route_probe=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"route_probe":"\([a-z_]*\)".*/\1/p')
    _fx_cs_slot=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"vpn_service_slot_used":\(true\|false\|null\)[,}].*/\1/p')
    _fx_cs_dns_port=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"dns":{"port":\([0-9][0-9]*\),"owner":"[a-z]*"}.*/\1/p')
    _fx_cs_dns_owner=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"dns":{"port":[0-9][0-9]*,"owner":"\([a-z]*\)".*/\1/p')
    _fx_cs_filter_dns_port=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"dns_filter":{"port":\([0-9][0-9]*\),"owner":"[a-z]*"}.*/\1/p')
    _fx_cs_filter_dns_owner=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"dns_filter":{"port":[0-9][0-9]*,"owner":"\([a-z]*\)".*/\1/p')
    _fx_cs_proxy_port=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"proxy":{"port":\([0-9][0-9]*\),"owner":"[a-z]*"}.*/\1/p')
    _fx_cs_proxy_owner=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"proxy":{"port":[0-9][0-9]*,"owner":"\([a-z]*\)".*/\1/p')
  fi

  _fx_cs_route_probe=${_fx_cs_route_probe:-unverified}
  case "$_fx_cs_slot" in
    true|false|null) _fx_cs_slot_json=$_fx_cs_slot ;;
    *) _fx_cs_slot="unknown"; _fx_cs_slot_json=null ;;
  esac
  case "$_fx_cs_dns_port" in ""|*[!0-9]*) _fx_cs_dns_port=5353 ;; esac
  case "$_fx_cs_filter_dns_port" in ""|*[!0-9]*) _fx_cs_filter_dns_port=53 ;; esac
  case "$_fx_cs_proxy_port" in ""|*[!0-9]*) _fx_cs_proxy_port=7890 ;; esac
  case "$_fx_cs_dns_owner" in free|other|unknown) ;; *) _fx_cs_dns_owner=unknown ;; esac
  case "$_fx_cs_filter_dns_owner" in free|other|unknown) ;; *) _fx_cs_filter_dns_owner=unknown ;; esac
  case "$_fx_cs_proxy_owner" in free|other|unknown) ;; *) _fx_cs_proxy_owner=unknown ;; esac

  # A readable path is not sufficient: only a complete arbiter record is the
  # authoritative source. Empty/partial output (for example an unreadable
  # executable or a stale helper) must be labelled local, not arbiter.
  _fx_cs_arb_valid=0
  if [ -n "$_fx_cs_verdict" ] && [ -n "$_fx_cs_grade" ] && [ -n "$_fx_cs_probe" ]; then
    case "$_fx_cs_slot" in true|false|null) _fx_cs_arb_valid=1 ;; esac
  fi

  # Local fallback stays conservative; the slot evidence check below will
  # downgrade it to unknown whenever the arbiter cannot certify the invariant.
  _fx_cs_source="local"
  if [ "$_fx_cs_arb_valid" = "1" ]; then
    _fx_cs_source="arbiter"
  else
    if [ "$_fx_cs_blocked" = "1" ] && [ -z "$_fx_cs_if" ]; then
      _fx_cs_verdict="unknown"; _fx_cs_grade="探测不可用"
    elif [ -z "$_fx_cs_if" ]; then
      _fx_cs_verdict="kernel_only"; _fx_cs_grade="内核级独立"
    else
      _fx_cs_verdict="partial"; _fx_cs_grade="部分兼容"
    fi
    _fx_cs_probe=${_fx_cs_probe:-unknown}
    _fx_cs_route_probe="unverified"
  fi

  # The published grade must agree with the slot evidence. A positive API
  # match is incompatible; absent/null slot evidence cannot certify kernel-only
  # or partial coexistence because the root dataplane invariant is unverified.
  case "$_fx_cs_slot" in
    true)
      _fx_cs_verdict="incompatible"
      _fx_cs_grade="不兼容"
      ;;
    false) : ;;
    *)
      _fx_cs_verdict="unknown"
      _fx_cs_grade="探测不可用"
      _fx_cs_probe=${_fx_cs_probe:-unknown}
      ;;
  esac

  _fx_cs_ext=false
  [ -n "$_fx_cs_if" ] && _fx_cs_ext=true

  # A private PID-scoped directory is atomically created under umask 077.
  # This avoids relying on mktemp implementations that differ across Android
  # and BusyBox; mkdir also refuses to reuse a stale or attacker-created path.
  _fx_cs_tmp_dir="$_fx_cs_json.tmp.$$"
  if ! ( umask 077; mkdir "$_fx_cs_tmp_dir" 2>/dev/null ); then
    return 0
  fi
  _fx_cs_tmp="$_fx_cs_tmp_dir/status"

  # noclobber prevents following a pre-existing file/symlink inside the new dir.
  # Never publish unless private mode, complete JSON and atomic replacement all
  # succeed; on failure retain the previous snapshot and clean only our temp.
  if ! (
    umask 077
    set -C
    printf '{"ok":1,"verdict":"%s","grade_cn":"%s","source":"%s","probe":"%s","route_probe":"%s","external_vpn":%s,"external_if":"%s","external_uid":"%s","dns":{"port":%s,"owner":"%s"},"dns_filter":{"port":%s,"owner":"%s"},"proxy":{"port":%s,"owner":"%s"},"interception_blocked":%s,"dataplane":"kernel","vpn_service_slot_used":%s}\n' \
      "$_fx_cs_verdict" "$_fx_cs_grade" "$_fx_cs_source" "$_fx_cs_probe" "$_fx_cs_route_probe" \
      "$_fx_cs_ext" "$_fx_cs_if" "$_fx_cs_uid" \
      "$_fx_cs_dns_port" "$_fx_cs_dns_owner" "$_fx_cs_filter_dns_port" "$_fx_cs_filter_dns_owner" \
      "$_fx_cs_proxy_port" "$_fx_cs_proxy_owner" \
      "$([ "$_fx_cs_blocked" = "1" ] && echo true || echo false)" "$_fx_cs_slot_json" > "$_fx_cs_tmp" &&
    chmod 0600 "$_fx_cs_tmp" &&
    [ -s "$_fx_cs_tmp" ] &&
    grep -q '"verdict":"' "$_fx_cs_tmp" &&
    mv -f "$_fx_cs_tmp" "$_fx_cs_json"
  ) 2>/dev/null; then
    rm -f "$_fx_cs_tmp" 2>/dev/null || :
  fi
  rmdir "$_fx_cs_tmp_dir" 2>/dev/null || :
  return 0
}

fx_coexist_status_write || :
# <<< fx-vpn-coexistence-status
'''


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
    apply_sh = root / "scripts/apply.sh"
    if not apply_sh.is_file():
        raise SystemExit("FX apply.sh is missing")

    text = apply_sh.read_text(encoding="utf-8")

    if BEGIN in text or END in text:
        if BEGIN not in text or END not in text:
            raise SystemExit("fx-vpn-coexistence-status markers are inconsistent; refusing to patch")
        start = text.index(BEGIN)
        end = text.index(END, start) + len(END)
        text = text[:start] + text[end:]

    if text.count(ANCHOR) != 1:
        raise SystemExit("apply.sh DNS-target anchor changed; refusing to patch")

    block = BLOCK.strip("\n")
    text = text.replace(ANCHOR, block + "\n\n" + ANCHOR, 1)
    apply_sh.write_text(text, encoding="utf-8")

    written = apply_sh.read_text(encoding="utf-8")
    for required in (BEGIN, END, "fx_coexist_status_write || :", ANCHOR):
        if required not in written:
            raise SystemExit(f"apply.sh coexistence status is incomplete: missing {required!r}")
    if written.count(BEGIN) != 1 or written.count(END) != 1:
        raise SystemExit("coexistence status block must appear exactly once")

    print("Patched fx-module/scripts/apply.sh with VPN coexistence status publication")


if __name__ == "__main__":
    main()
