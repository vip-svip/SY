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
  # apply.sh 使用 MODDIR（不是 MODPATH）；MODDIR 未定义时必须留空而不是崩溃。
  _fx_cs_arb=${FX_COEXIST_ARBITER:-${MODDIR:-}/scripts/fx-vpn-coexistence-arbiter.sh}
  if [ -r "$_fx_cs_arb" ]; then
    _fx_cs_out=$(sh "$_fx_cs_arb" 2>/dev/null || true)
    _fx_cs_verdict=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"verdict":"\([a-z_]*\)".*/\1/p')
    _fx_cs_grade=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"grade_cn":"\([^"]*\)".*/\1/p')
    _fx_cs_probe=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"probe":"\([a-z_]*\)".*/\1/p')
    _fx_cs_route_probe=$(printf '%s' "$_fx_cs_out" | sed -n 's/.*"route_probe":"\([a-z_]*\)".*/\1/p')
  fi

  # 本地保守兜底：绝不把未知说成并行。
  _fx_cs_source="local"
  if [ -n "$_fx_cs_verdict" ]; then
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

  _fx_cs_ext=false
  [ -n "$_fx_cs_if" ] && _fx_cs_ext=true

  _fx_cs_tmp="$_fx_cs_json.tmp.$$"
  ( umask 077
    printf '{"ok":1,"verdict":"%s","grade_cn":"%s","source":"%s","probe":"%s",' \
      "$_fx_cs_verdict" "$_fx_cs_grade" "$_fx_cs_source" "$_fx_cs_probe"
    printf '"external_vpn":%s,"external_if":"%s","external_uid":"%s",' \
      "$_fx_cs_ext" "$_fx_cs_if" "$_fx_cs_uid"
    printf '"interception_blocked":%s,"dataplane":"kernel","vpn_service_slot_used":false}\n' \
      "$([ "$_fx_cs_blocked" = "1" ] && echo true || echo false)"
  ) > "$_fx_cs_tmp" 2>/dev/null || { rm -f "$_fx_cs_tmp" 2>/dev/null; return 0; }

  # 回读校验后才替换，避免发布半截 JSON。
  if [ -s "$_fx_cs_tmp" ] && grep -q '"verdict":"' "$_fx_cs_tmp" 2>/dev/null; then
    chmod 0600 "$_fx_cs_tmp" 2>/dev/null || :
    mv -f "$_fx_cs_tmp" "$_fx_cs_json" 2>/dev/null || rm -f "$_fx_cs_tmp" 2>/dev/null
  else
    rm -f "$_fx_cs_tmp" 2>/dev/null
  fi
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
