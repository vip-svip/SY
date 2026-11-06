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

# The package workflow stages the canonical Root controller before this patcher.
# Never package a modern renderer with a stale controller or silently retain
# the pre-FX hard-coded upstream/response template from an older Release ZIP.
root_control = module / "scripts" / "yulong-ad-control.sh"
if not root_control.is_file():
    raise SystemExit(f"FX DNS Root controller is missing: {root_control}")
root_source = root_control.read_text(encoding="utf-8")
required_root_contract = (
    "dns-rewrites-get",
    "dns-rewrites-set",
    "dns-rewrites-yaml",
    "dns-response-get",
    "dns-response-config-set",
    "RESPONSE_IPV4",
    "RESPONSE_IPV6",
    "RESPONSE_TTL",
    "DNS_REWRITES",
    "dns-querylog-runtime-get",
    "dns-querylog-ignored-get",
    "dns-statistics-get",
    "dns-statistics-config-set",
    "dns-runtime-get",
    "dns-diagnose",
)
missing_root = [item for item in required_root_contract if item not in root_source]
if missing_root:
    raise SystemExit(
        "FX DNS Root controller is stale or incomplete; refusing to package: "
        + ", ".join(missing_root)
    )
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

has_root_response_adapter = (
    "dns-response-get" in source
    and "_dns_response_output=" in source
    and "_dns_blocking_ipv4=" in source
    and "_dns_blocking_ipv6=" in source
    and "_dns_blocked_response_ttl=" in source
)
if "FX_YULONG_DNS_RESPONSE_BEGIN" not in source and not has_root_response_adapter:
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

# Package only the integrated FX renderer. A marker on its own is not proof
# that the complete runtime adapter survived a Release-source restore.
required_renderer_contract = (
    "FX_YULONG_UPSTREAMS_BEGIN",
    "_build_dns_upstreams",
    "_fallback_file",
    "_bootstrap_file",
    "dns-rewrites-yaml",
    "filtering:",
    "rewrites:",
    "rewrites_enabled:",
    "rewrites_enabled_count",
    "runtime_rewrites_enabled",
    "rewrite_has_enabled",
    "FX_YULONG_DNS_RESPONSE_BEGIN",
    "dns-response-get",
    "_dns_response_output=",
    "_dns_blocking_ipv4=",
    "_dns_blocking_ipv6=",
    "_dns_blocked_response_ttl=",
    "dns-querylog-runtime-get",
    "dns-querylog-ignored-get",
    "dns-statistics-get",
    "dns-runtime-get",
    "safe_search:",
    "blocked_hosts:",
)
missing_renderer = [item for item in required_renderer_contract if item not in source]
if missing_renderer:
    raise SystemExit(
        "AdGuard Home renderer is still a legacy/partial DNS implementation; "
        "refusing to package an incomplete FX 1.0.0 DNS stack: "
        + ", ".join(missing_renderer)
    )

runtime_template = module / "engines" / "adguardhome" / "AdGuardHome.yaml"
if not runtime_template.is_file():
    raise SystemExit(f"FX AdGuard Home runtime YAML is missing: {runtime_template}")
runtime_lines = runtime_template.read_text(encoding="utf-8").splitlines()
inside_filtering = False
filtering_sections = 0
rewrite_toggle_values = []
for line in runtime_lines:
    if line == "filtering:":
        filtering_sections += 1
        inside_filtering = True
        continue
    if line and not line.startswith(" "):
        inside_filtering = False
        continue
    if inside_filtering and line.startswith("  rewrites_enabled:"):
        rewrite_toggle_values.append(line.split(":", 1)[1].strip())
if filtering_sections != 1 or rewrite_toggle_values != ["true"]:
    raise SystemExit(
        "FX AdGuard Home runtime template must contain exactly one "
        "filtering.rewrites_enabled: true; refusing to package disabled DNS rewrites"
    )

target.write_text(source, encoding="utf-8")
print("Verified and preserved the complete FX DNS runtime contract; no legacy hard-coded DNS downgrade was applied.")
