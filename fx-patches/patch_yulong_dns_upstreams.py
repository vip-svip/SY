#!/usr/bin/env python3
"""Patch the bundled AdGuard Home renderer to use FX-owned DNS upstream settings."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_yulong_dns_upstreams.py FX_MODULE_DIR")

module = Path(sys.argv[1])
target = module / "scripts" / "adguardhome.sh"
if not target.is_file():
    raise SystemExit(f"AdGuard Home lifecycle script is missing: {target}")

source = target.read_text(encoding="utf-8")
if "FX_YULONG_UPSTREAMS_BEGIN" not in source:
    old = """  upstream_dns:
  - 127.0.0.1:5353
"""
    new = r'''  upstream_dns:
EOF_CFG
  # FX_YULONG_UPSTREAMS_BEGIN
  # Use custom DoH/DoT/DoQ/plain endpoints only after explicit opt-in.
  # Default remains the device-local Unbound recursive resolver.
  _settings="$PG/settings.conf"
  _custom_enabled=$(awk -F= '$1=="custom_dns"{v=$2} END{print v}' "$_settings" 2>/dev/null)
  _global_enabled=$(awk -F= '$1=="global_dns"{v=$2} END{print v}' "$_settings" 2>/dev/null)
  _custom_primary=$(awk -F'[[:space:]]+' '
    $0=="[conf:custom_dns]" {inside=1; next}
    /^\[/ {inside=0}
    inside && $1=="nameserver" && NF>=2 {print $2}
  ' "$_settings" 2>/dev/null)
  _global_primary=$(awk -F'[[:space:]]+' '
    $0=="[conf:global_dns]" {inside=1; next}
    /^\[/ {inside=0}
    inside && $1=="nameserver" && NF>=2 {print $2}
  ' "$_settings" 2>/dev/null)
  if [ "$_global_enabled" = "1" ]; then
    [ -n "$_global_primary" ] || { echo "global DNS is enabled but its upstream list is empty" >&2; return 1; }
    _primary=$_global_primary
  elif [ "$_custom_enabled" = "1" ]; then
    [ -n "$_custom_primary" ] || { echo "custom DNS is enabled but its upstream list is empty" >&2; return 1; }
    _primary=$_custom_primary
  else
    _primary=
  fi
  if [ -n "$_primary" ]; then
    while IFS= read -r _server; do
      [ -n "$_server" ] && printf '  - "%s"\n' "$_server"
    done <<EOF_PRIMARY
$_primary
EOF_PRIMARY
    _fallback=$(awk -F'[[:space:]]+' '
      $0=="[conf:yulong_dns_fallback]" {inside=1; next}
      /^\[/ {inside=0}
      inside && $1=="nameserver" && NF>=2 {print $2}
    ' "$_settings" 2>/dev/null)
    if [ -n "$_fallback" ]; then
      printf '  fallback_dns:\n'
      while IFS= read -r _server; do
        [ -n "$_server" ] && printf '  - "%s"\n' "$_server"
      done <<EOF_FALLBACK
$_fallback
EOF_FALLBACK
    else
      # Without an explicit user fallback, use FX's local recursive resolver.
      printf '  fallback_dns:\n  - 127.0.0.1:5353\n'
    fi
    # Bootstrap lookups for encrypted upstream hostnames stay inside FX.
    # The local recursive Unbound resolver avoids fixed public DNS dependencies.
    if printf '%s\n' "$_primary" | grep -Eq '^(https://|tls://|quic://)'; then
      printf '  bootstrap_dns:\n  - 127.0.0.1:5353\n'
    fi
  else
    printf '  - 127.0.0.1:5353\n'
    printf '  fallback_dns: []\n'
  fi
  # FX_YULONG_UPSTREAMS_END
  cat <<EOF_CFG
'''
    if source.count(old) != 1:
        raise SystemExit(
            "expected exactly one stock Unbound upstream block in adguardhome.sh; "
            "refusing an ambiguous patch"
        )
    source = source.replace(old, new, 1)

if "FX_YULONG_DNS_RESPONSE_BEGIN" not in source:
    old_response = """  blocked_response_ttl: 10
"""
    new_response = r'''  blocked_response_ttl: 10
EOF_CFG
  # FX_YULONG_DNS_RESPONSE_BEGIN
  _response_mode=$(awk -F= '
    $0=="[conf:yulong_dns_response]" {inside=1; next}
    /^\[/ {inside=0}
    inside && $1=="mode" {value=$2}
    END {print value}
  ' "$PG/settings.conf" 2>/dev/null)
  case "$_response_mode" in
    refused|custom_ip) : ;;
    *) _response_mode=nxdomain ;;
  esac
  printf '  blocking_mode: %s\n' "$_response_mode"
  if [ "$_response_mode" = "custom_ip" ]; then
    printf '  blocking_ipv4: "0.0.0.0"\n  blocking_ipv6: "::"\n'
  fi
  # FX_YULONG_DNS_RESPONSE_END
  cat <<EOF_CFG
'''
    if source.count(old_response) != 1:
        raise SystemExit(
            "expected exactly one stock blocked_response_ttl line in adguardhome.sh; "
            "refusing an ambiguous response-mode patch"
        )
    source = source.replace(old_response, new_response, 1)

target.write_text(source, encoding="utf-8")
print("Patched AdGuard Home custom DNS upstreams and blocking response mode")
