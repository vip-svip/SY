#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SRC="$ROOT/fxrules/anti_fraud_96110.txt"
CANDIDATE="$ROOT/fxrules/96110_candidate.txt"
CONF="$ROOT/scripts/default.conf"
[ -s "$SRC" ] || { echo 'FAIL: bundled FX source missing' >&2; exit 1; }
# The current FX source is intentionally narrow: anti-fraud domains, the official
# app package, and source-labelled anti-fraud /32 addresses only. Never mix general
# ad lists, OEM security apps, broad government domains, or unverified carrier endpoints.
awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  {
    if ($0 ~ /^DOMAIN(-SUFFIX)?,[A-Za-z0-9.-]+,REJECT$/) { domains++; next }
    if ($0 == "PACKAGE-NAME,com.hicorenational.antifraud,REJECT") { packages++; next }
    if ($0 ~ /^IP-CIDR,[0-9.]+\/32,REJECT$/) {
      split($0,fields,","); ip=fields[2]; sub(/\/32$/, "", ip); n=split(ip,oct,".");
      if (n!=4) bad=1;
      for(i=1;i<=n;i++) if (oct[i]!~/^[0-9]+$/ || oct[i]+0>255 || length(oct[i])>3) bad=1;
      ips++; next
    }
    bad=1
  }
  END {
    if (bad || domains!=5 || packages!=1 || ips<1) {
      printf "FAIL: FX source scope invalid (domains=%d packages=%d /32s=%d bad=%d)\n",domains,packages,ips,bad > "/dev/stderr"; exit 1
    }
  }
' "$SRC"
if grep -Eq 'com\.android\.packageinstaller|com\.oplus\.safecenter|DOMAIN(-SUFFIX)?,(mps\.gov\.cn|miit\.gov\.cn)|96110\.[A-Za-z0-9.-]+' "$SRC"; then
  echo 'FAIL: broad system/government rule or unverified 96110 host leaked into the verified FX source' >&2
  exit 1
fi
[ -s "$CANDIDATE" ] || { echo 'FAIL: separate 96110 candidate source missing' >&2; exit 1; }
grep -Fq 'sultan1sa/rules' "$CANDIDATE" || { echo 'FAIL: 96110 candidate provenance missing' >&2; exit 1; }
grep -Fxq 'DOMAIN,prpr.96110.cn.com,REJECT' "$CANDIDATE" || { echo 'FAIL: exact community 96110 candidate missing' >&2; exit 1; }
[ "$(grep -Ec '^(DOMAIN|DOMAIN-SUFFIX|IP-CIDR|PACKAGE-NAME),' "$CANDIDATE")" -eq 1 ] || { echo 'FAIL: candidate source must remain a single exact host rule' >&2; exit 1; }
# The settings default registers the narrow bundled source, while generic rule import
# destinations are separately tested by v1.0.0-rule-import-block-action-regression.sh.
awk '
  /^\[list:fx\][[:space:]]*$/ { section=1; next }
  /^\[/ { section=0 }
  section && !/^[[:space:]]*#/ && NF {
    if ($0 ~ /^fxfile:\/\/anti_fraud_96110\|/) { main=1; rows++; next }
    if ($0 ~ /^fxfile:\/\/96110_candidate\|/ && $0 ~ /\|0$/) { candidate=1; rows++; next }
    bad=1
  }
  END { if (bad || rows!=2 || !main || !candidate) exit 1 }
' "$CONF" || { echo 'FAIL: default [list:fx] must contain only the anti-fraud source and separately disabled 96110 candidate' >&2; exit 1; }
printf 'PASS: verified FX anti-fraud source stays narrow; disputed 96110 candidate is isolated as a separate exact-host toggle\n'
