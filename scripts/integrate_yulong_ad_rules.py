#!/usr/bin/env python3
"""Wire Yulong 7.0.1 DNS-safe rules into FX's existing Hosts/AdGuard pipeline.

This intentionally adds no VpnService and never writes the data to [list:fx],
which is reserved for FX anti-fraud/96110 rules.
"""
from pathlib import Path
import sys

ENTRY = "builtin://Yulong_AdBlock.txt|【游龙广告插件 7.0.1】内置广告与追踪 DNS/Hosts 域名规则|1"
RULE_MARKER = "[list:rule]\n"
UTIL_MARKER = "  # v1.0.0 cosmetic subset re-added by explicit product request: install once for\n"
UTIL_INSERT = r'''  # Yulong Ad Plugin 7.0.1 bundled DNS/hosts rule source.
  # Existing enable/disable state is preserved across upgrades.
  _mg_yulong_entry='builtin://Yulong_AdBlock.txt|【游龙广告插件 7.0.1】内置广告与追踪 DNS/Hosts 域名规则|1'
  if ! awk -F'|' -v key='builtin://Yulong_AdBlock.txt' '
    /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
    /^\[/ {inrule=0}
    inrule && $1==key {found=1}
    END {exit !found}
  ' "$CONF" 2>/dev/null; then
    _mg_yulong_tmp="$PG/cache/migrate-yulong-ad-rule.$$.tmp"
    if awk -v entry="$_mg_yulong_entry" '
      /^\[list:rule\][[:space:]]*$/ && !added {print; print entry; added=1; inrule=1; next}
      /^\[/ {inrule=0}
      {print}
      END {if (!added) {print ""; print "[list:rule]"; print entry}}
    ' "$CONF" > "$_mg_yulong_tmp" 2>/dev/null && mv -f "$_mg_yulong_tmp" "$CONF" 2>/dev/null; then
      pg_log 'migrate: registered Yulong 7.0.1 DNS-safe rule source' 2>/dev/null || true
    else
      pg_log 'migrate: Yulong 7.0.1 source registration failed; retry on next apply' 2>/dev/null || true
    fi
    rm -f "$_mg_yulong_tmp" 2>/dev/null || true
    chmod 600 "$CONF" 2>/dev/null || true
  fi

'''
AGH_MARKER = '  [ -n "$_rules" ] || { _pg_log \'no safe anti-fraud domain rules to load\'; return 1; }\n'
AGH_INSERT = r'''  # Ad-domain rules stay in [list:rule], separate from FX's 96110 anti-fraud section.
  # Stream the large file; never capture 200k+ rules in a shell variable.
  _yulong_enabled=$(awk -F'|' '
    /^\[list:rule\][[:space:]]*$/ {inrule=1; next}
    /^\[/ {inrule=0}
    inrule && $1=="builtin://Yulong_AdBlock.txt" && $3=="1" {enabled=1}
    END {print enabled+0}
  ' "$PG/settings.conf" 2>/dev/null)
  _yulong_file=""
  if [ "$_yulong_enabled" = 1 ]; then
    _yulong_file="$PG/rulefiles-user/Yulong_AdBlock.txt"
    [ -r "$_yulong_file" ] || _yulong_file="$MODDIR/rulefiles/Yulong_AdBlock.txt"
    [ -r "$_yulong_file" ] || _yulong_file=""
    if [ -z "$_yulong_file" ]; then
      _pg_log 'Yulong ad-domain source enabled but rulefile missing; FX anti-fraud rules remain active'
    fi
  fi
  # User-managed Yulong allow/block domains flow into AdGuard Home user_rules.
  # Domain rows are validated and kept separate from FX's reserved [list:fx] data.
  _yulong_custom_rules=$(
    {
      pg_list domain 2>/dev/null | awk -F'|' '
        function valid(d) {
          return d ~ /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?([.][A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/
        }
        $1 !~ /^[[:space:]]*#/ && valid($1) && (NF<3 || $3=="1") {
          print "@@||" tolower($1) "^"
        }
      '
      pg_list block 2>/dev/null | awk -F'|' '
        function valid(d) {
          return d ~ /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?([.][A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/
        }
        $1 !~ /^[[:space:]]*#/ && valid($1) && (NF<3 || $3=="1") {
          print "||" tolower($1) "^"
        }
      '
    } | awk '!seen[$0]++'
  )
'''
AGH_USER_RULES_MARKER = "user_rules:\n$_rules\nquerylog:\n  enabled: false\n"
AGH_USER_RULES_REPLACEMENT = r'''user_rules:
$_rules
EOF_CFG
  if [ -n "$_yulong_file" ]; then
    awk '
      /^[[:space:]]*#/ || NF < 2 {next}
      $1 != "0.0.0.0" && $1 != "127.0.0.1" {next}
      {
        d=tolower($2)
        if (d ~ /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/ && d !~ /\.\./)
          print "  - \"||" d "^\""
      }
    ' "$_yulong_file" | awk '!seen[$0]++'
  fi
  if [ -n "$_yulong_custom_rules" ]; then
    printf '%s\n' "$_yulong_custom_rules"
  fi
  cat <<EOF_CFG
querylog:
  enabled: false
'''

def replace_once(path: Path, old: str, new: str):
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one stable patch anchor, found {count}: {old[:90]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")

def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: integrate_yulong_ad_rules.py <fx-module-root>")
    root = Path(sys.argv[1])
    rules = root / "rulefiles/Yulong_AdBlock.txt"
    cosmetic = root / "rulefiles/Yulong_AdBlock_Cosmetic.txt"
    default = root / "scripts/default.conf"
    util = root / "scripts/util.sh"
    agh = root / "scripts/adguardhome.sh"
    test_source = root.parent / "scripts/tests/fx-yulong-ad-rule-import-regression.sh"
    test_target = root / "scripts/tests/fx-yulong-ad-rule-import-regression.sh"
    for path in (rules, cosmetic, default, util, agh, test_source):
        if not path.is_file():
            raise SystemExit(f"required FX input missing: {path}")
    if rules.stat().st_size < 1_000_000:
        raise SystemExit("Yulong domain file is unexpectedly small; refusing partial rule import")

    if "builtin://Yulong_AdBlock.txt|" not in default.read_text(encoding="utf-8"):
        replace_once(default, RULE_MARKER, RULE_MARKER + ENTRY + "\n")
    util_text = util.read_text(encoding="utf-8")
    if "_mg_yulong_entry=" not in util_text:
        replace_once(util, UTIL_MARKER, UTIL_INSERT + UTIL_MARKER)
    agh_text = agh.read_text(encoding="utf-8")
    if "_yulong_enabled=$(awk -F'|'" not in agh_text:
        replace_once(agh, AGH_MARKER, AGH_MARKER + AGH_INSERT)
    agh_text = agh.read_text(encoding="utf-8")
    if 'if [ -n "$_yulong_file" ]; then' not in agh_text:
        replace_once(agh, AGH_USER_RULES_MARKER, AGH_USER_RULES_REPLACEMENT)

    config = default.read_text(encoding="utf-8")
    fx = config.split("[list:fx]", 1)[1] if "[list:fx]" in config else ""
    fx = fx.split("\n[", 1)[0]
    if "Yulong_AdBlock" in fx:
        raise SystemExit("Yulong general ad rules leaked into the protected FX anti-fraud section")

    test_target.parent.mkdir(parents=True, exist_ok=True)
    test_target.write_text(test_source.read_text(encoding="utf-8"), encoding="utf-8")
    test_target.chmod(0o755)
    print("PASS: Yulong rules registered in Hosts/AdGuard DNS; FX anti-fraud rules remain separate")

if __name__ == "__main__":
    main()
