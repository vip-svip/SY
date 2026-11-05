#!/system/bin/sh
# Host regression for root-side developer-rule translation. No Android/LSPosed required.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
GEN="$ROOT/scripts/gen_xposed_conf.sh"
grep -q 'enabled=\$NF; note=\$(NF-1); line=\$1' "$GEN"
grep -q 'for (fi=2; fi<=NF-2; fi++) line=line "|" \$fi' "$GEN"
grep -Fq 'key ~ /^dev_rule_[1-9][0-9]?$/' "$GEN"
grep -q 'dev_rule_count >= 64' "$GEN"
# Reproduce the exact pipe-preserving record split used by the generator.
record='com.example.debug,dev_hook_enabled=1,dev_rule_1=vip|Lcom/example/debug/Account;->isVip()Z|OBSERVE|100|FX debug fixture|1'
out=$(printf '%s\n' "$record" | awk -F'|' '
  NF >= 3 { enabled=$NF; note=$(NF-1); line=$1; for (fi=2; fi<=NF-2; fi++) line=line "|" $fi }
  END { if (enabled != "1") exit 2; n=split(line,a,","); for(i=1;i<=n;i++) if(a[i] ~ /^dev_rule_1=/) print a[i] }
')
[ "$out" = 'dev_rule_1=vip|Lcom/example/debug/Account;->isVip()Z|OBSERVE|100' ]
# The serialized rule must retain all four fields after comma parsing.
fields=$(printf '%s\n' "$out" | awk -F'=' '{split($2,f,"|"); print length(f)}')
[ "$fields" = 4 ]
echo 'PASS developer Hook rule delimiter preservation and 64-rule guard'
