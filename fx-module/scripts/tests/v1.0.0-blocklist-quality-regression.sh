#!/system/bin/sh
# The blacklist tab is intentionally empty. Check the preserved legacy ruleset separately.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
RULES="$ROOT/rulefiles/privacy_ad_domains.txt"
TMP="${TMPDIR:-/tmp}/fx-legacy-rule-quality.$$"
trap 'rm -f "$TMP" "$TMP.sorted"' EXIT HUP INT TERM
awk '/^\[list:block\][[:space:]]*$/{inside=1;next} /^\[/{inside=0} inside && $0 !~ /^[[:space:]]*#/ && NF {bad=1} END{exit bad}' "$CONF" || { echo 'FAIL: blacklist must start empty' >&2; exit 1; }
awk '$1=="0.0.0.0" && NF==2 {print $2}' "$RULES" > "$TMP"
[ -s "$TMP" ] || { echo 'FAIL: no preserved legacy rules in optional set' >&2; exit 1; }
while IFS= read -r d; do
  case "$d" in *[!a-z0-9.-]*|.*|*..*|*.) echo "FAIL: malformed domain: $d" >&2; exit 1 ;; esac
  [ "${#d}" -le 253 ] || { echo "FAIL: overlong domain: $d" >&2; exit 1; }
  oldifs=$IFS; IFS=.; set -- $d; IFS=$oldifs
  for label do [ -n "$label" ] && [ "${#label}" -le 63 ] || { echo "FAIL: malformed label in $d" >&2; exit 1; }; case "$label" in -*|*-) echo "FAIL: invalid label edge in $d" >&2; exit 1;; esac; done
done < "$TMP"
sort "$TMP" > "$TMP.sorted"
[ "$(wc -l < "$TMP")" -eq "$(uniq "$TMP.sorted" | wc -l)" ] || { echo 'FAIL: duplicate legacy domains' >&2; exit 1; }
for d in exoclick.com trafficjunky.net juicyads.com popads.net propellerads.com hilltopads.net trafficstars.com ero-advertising.com adsterra.com adnium.com plugrush.com; do
  grep -Fx "$d" "$TMP" >/dev/null || { echo "FAIL: legacy domain was lost during migration: $d" >&2; exit 1; }
done
for d in acquire.lupplovh.cc google.com apple.com microsoft.com; do
  if grep -Fx "$d" "$TMP" >/dev/null; then echo "FAIL: broad/site domain must not be blocked: $d" >&2; exit 1; fi
done
echo 'PASS: empty blacklist and preserved optional blocklist syntax/quality'
