#!/usr/bin/env python3
"""Reapply the Yulong Root DNS Proxy after the FX Release archive is restored."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".").resolve()

source = repo / "fx-module/scripts/yulong-root-proxy.sh"
target = module / "scripts/yulong-root-proxy.sh"
if not source.is_file() or source.stat().st_size < 8000:
    raise SystemExit("Yulong Root Proxy source is missing or incomplete")
target.parent.mkdir(parents=True, exist_ok=True)
# In the normal CI invocation (fx-module .), source and target resolve to
# the same tracked file. Avoid shutil.SameFileError while still supporting
# separate staged module directories.
if source.resolve() != target.resolve():
    shutil.copy2(source, target)
runtime_text = target.read_text(encoding="utf-8")
if "\\$" in runtime_text:
    raise SystemExit("Yulong Root Proxy contains escaped shell variable references")
target.chmod(0o755)

# The published module archive is restored before this patcher runs. Re-stage
# the canonical controller so Tile, Widget and Tasker share Root Proxy-aware
# start/stop/status behavior rather than carrying an older release copy.
vpn_control_source = repo / "scripts/yulong-vpn-control.sh"
vpn_control_target = module / "scripts/yulong-vpn-control.sh"
if not vpn_control_source.is_file() or vpn_control_source.stat().st_size < 5000:
    raise SystemExit("canonical Yulong VPN controller source is missing or incomplete")
vpn_control_target.parent.mkdir(parents=True, exist_ok=True)
if vpn_control_source.resolve() != vpn_control_target.resolve():
    shutil.copy2(vpn_control_source, vpn_control_target)
vpn_control_target.chmod(0o755)

def replace_once(path, old, new, label):
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit("%s: expected one patch anchor, found %d" % (label, count))
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

# Pin recursive Unbound queries to the active VPN's validated IPv4 address.
# In this mode Unbound sends upstream DNS over IPv4, while clients may still
# query the local AdGuard Home front end over IPv4 or IPv6.
unbound_path = module / "scripts/unbound.sh"
unbound = unbound_path.read_text(encoding="utf-8")
start = unbound.find("_render_config() {")
end = unbound.find("\n}\n_maybe_refresh_anchor", start)
if start < 0 or end < 0:
    raise SystemExit("unbound.sh _render_config() was not found")
fn = unbound[start:end + 2]
if "unbound-vpn-egress-ip" not in fn:
    fn = fn.replace(
        "  cat <<EOF_CFG\n",
        '''  _FX_OUT_IP=""
  _FX_DO_IP6=yes
  _FX_OUT_IP_FILE="$PG/unbound-vpn-egress-ip"
  if [ -s "$_FX_OUT_IP_FILE" ]; then
    _FX_OUT_IP=$(tr -d '\\r\\n' < "$_FX_OUT_IP_FILE")
    if ! printf '%s\\n' "$_FX_OUT_IP" | awk -F. '
      NF != 4 {ok=0; exit}
      {
        ok=1
        for (i=1; i<=4; i++) {
          if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255 ||
              ($i != "0" && $i ~ /^0/)) ok=0
        }
        first=$1+0
        second=$2+0
        # Match the Root Proxy unicast tunnel-source policy. Reject unspecified,
        # loopback, link-local, multicast and reserved address space.
        if (first==0 || first==127 || first>=224 ||
            (first==169 && second==254)) ok=0
      }
      END {exit(ok ? 0 : 1)}
    '; then
      _log "invalid external VPN egress marker; refusing Unbound config"
      return 1
    fi
    _FX_DO_IP6=no
  fi
  cat <<EOF_CFG
''', 1)
    if "  do-ip6: yes\n" not in fn:
        raise SystemExit("unbound.sh do-ip6 setting anchor missing")
    fn = fn.replace("  do-ip6: yes\n", "  do-ip6: $_FX_DO_IP6\n", 1)
    cat_anchor = "  cat <<EOF_CFG\n"
    cat_start = fn.find(cat_anchor)
    if cat_start < 0:
        raise SystemExit("unbound.sh config heredoc opener missing")
    terminator = fn.find("\nEOF_CFG\n", cat_start + len(cat_anchor))
    if terminator < 0:
        raise SystemExit("unbound.sh config heredoc terminator missing")
    # Insert shell code after the closing delimiter, not after the opener.
    # A plain replace("EOF_CFG\n", ...) matches the opener first and leaks
    # shell source into the generated Unbound config on every run.
    closing_token = terminator + 1
    fn = fn[:closing_token] + fn[closing_token:].replace(
        "EOF_CFG\n",
        """EOF_CFG
  if [ -n "$_FX_OUT_IP" ]; then
    printf '  outgoing-interface: %s\\n' "$_FX_OUT_IP"
  fi
""",
        1,
    )
    unbound = unbound[:start] + fn + unbound[end + 2:]
    unbound_path.write_text(unbound, encoding="utf-8")

# In direct mode, clear any stale external-VPN redirect before starting the
# ordinary local resolver. In external-VPN mode, start the Root Proxy only if
# Android VPN state, interface, owner UID and the user compatibility switch
# are all unambiguous. Its own route and DNS probes are an additional gate.
apply_path = module / "scripts/apply.sh"
apply_text = apply_path.read_text(encoding="utf-8")
direct_anchor = '    if sh "$MODDIR/scripts/adguardhome.sh" ensure "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then'
if 'yulong-root-proxy.sh" stop' not in apply_text:
    replace_once(
        apply_path, direct_anchor,
        '    if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ]; then\n'
        '      sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :\n'
        '    fi\n' + direct_anchor,
        "apply.sh direct DNS branch"
    )
    apply_text = apply_path.read_text(encoding="utf-8")

external_anchor = (
    '  sh "$MODDIR/scripts/adguardhome.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :\n'
    '  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then'
)
external_insert = (
    '  sh "$MODDIR/scripts/adguardhome.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :\n'
    '  if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ] && [ -n "$_PG_EXT_VPN_IF" ] && '
    '[ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "0" ] && [ -n "$VPN_EXTERNAL_UID" ] && '
    '[ "$VPN_EXTERNAL_COMPAT" = "1" ]; then\n'
    '    if sh "$MODDIR/scripts/yulong-root-proxy.sh" ensure "$MODDIR" "$PG" "$_PG_EXT_VPN_IF" "$VPN_EXTERNAL_UID" >> "$PG/boot.log" 2>&1; then\n'
    '      DNS_SAFE="127.0.0.1"\n'
    '      DNS_AGH_ACTIVE=1\n'
    '      pg_log "dns: Yulong Root Proxy validated; AdGuard DNS filtering enabled over the existing third-party VPN"\n'
    '    else\n'
    '      sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :\n'
    '      pg_log "dns: Yulong Root Proxy could not prove its VPN egress; preserved external VPN DNS (fail-open)"\n'
    '    fi\n'
    '  else\n'
    '    sh "$MODDIR/scripts/yulong-root-proxy.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :\n'
    '  fi\n'
    '  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then'
)
if 'yulong-root-proxy.sh" ensure' not in apply_text:
    replace_once(apply_path, external_anchor, external_insert, "apply.sh external VPN DNS branch")

# Uninstall cleanup runs before the generic AdGuard Home/Unbound stop path.
uninstall_path = module / "uninstall.sh"
uninstall = uninstall_path.read_text(encoding="utf-8")
if 'yulong-root-proxy.sh" uninstall' not in uninstall:
    replace_once(
        uninstall_path,
        "_DNS_ENGINE_STOP_OK=1\n",
        'if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ]; then\n'
        '  if ! sh "$MODDIR/scripts/yulong-root-proxy.sh" uninstall "$MODDIR" "$PG" >/dev/null 2>&1; then\n'
        '    PG_KEEP_DATA=1\n'
        '    _mitm_warn "could not confirm removing Yulong Root Proxy DNS rules; preserving $PG for safe retry"\n'
        '  fi\n'
        'fi\n'
        "_DNS_ENGINE_STOP_OK=1\n",
        "uninstall.sh DNS cleanup"
    )

# Preserve the original rule pipeline: Yulong DNS domains are already merged by
# integrate_yulong_ad_rules.py into AdGuardHome user_rules, not FX's 96110 list.
print("Applied Yulong Root Proxy lifecycle, VPN-bound Unbound configuration and uninstall cleanup.")
