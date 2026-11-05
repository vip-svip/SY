#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
C="$ROOT/scripts/default.conf"
U="$ROOT/scripts/util.sh"
G="$ROOT/mitm/cosmetic.go"
for needle in \
  'https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt' \
  'https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt' \
  'https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt' \
  'https://raw.githubusercontent.com/fenglingback/cxfllist/main/rules/cxfl-ublock.txt' \
  'https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt' \
  'https://raw.githubusercontent.com/yokoffing/filterlists/main/adult_annoyance_list.txt'; do
  grep -Fq "$needle" "$C" || { echo "FAIL: missing cosmetic upstream in default catalog: $needle" >&2; exit 1; }
  grep -Fq "$needle" "$U" || { echo "FAIL: missing cosmetic upstream upgrade migration: $needle" >&2; exit 1; }
done
# The shell compilers intentionally use a prefix guard: web-layer CSS and context-aware
# ABP request lists must never be flattened into /system/etc/hosts or global sing-box routes.
for file in "$ROOT/scripts/apply.sh" "$ROOT/scripts/vpnrule.sh"; do
  grep -Fq '*easylist_adult/*' "$file" || { echo "FAIL: EasyList adult web-layer sources lack the hosts/route exclusion guard: $file" >&2; exit 1; }
  grep -Fq '*yokoffing/filterlists/main/adult_annoyance_list.txt|' "$file" || { echo "FAIL: adult annoyance list lacks the hosts/route exclusion guard: $file" >&2; exit 1; }
done
grep -Fq 'func readVerifiedCosmeticCache' "$G"
grep -Fq 'cache digest mismatch' "$G"
grep -Fq 'parseCosmeticRules(b, seen' "$G"
grep -Fq 'cosmeticRuleLimit       = 12000' "$G"
grep -Fq 'cosmeticCSSLimit        = 1 << 20' "$G"
grep -Fq 'safeCosmeticSelector' "$G"
grep -Fq 'sanitizeCosmeticDeclarations' "$G"
grep -Fq 'exception' "$G"
grep -Fq 'splitCosmeticSelectorGroups' "$G"
grep -Fq 'cosmeticBodyLimit       = 4 << 20' "$G"
# Default-on sources are cosmetic overlays only; they are not added to the dedicated FX anti-fraud list.
awk '/^\[list:fx\][[:space:]]*$/{s=1;next} /^\[/{s=0} s && /RunningCheese|NoAppDownload|cxfl-ublock|AdultSite|Adblock_Watermark/{bad=1} END{exit bad}' "$C" || { echo 'FAIL: cosmetic sources leaked into FX special rules' >&2; exit 1; }
sh -n "$U"
printf '%s\n' 'PASS: upstream cosmetic lists are cataloged, checksum-verified, parsed, capped, and kept separate from FX anti-fraud rules'
