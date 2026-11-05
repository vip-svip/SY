#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
CONF="$ROOT/scripts/default.conf"
HOOK="$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java"
APPLY="$ROOT/scripts/apply.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'data-key="lsposed_enabled"' "$HTML" || fail 'LSPosed master switch missing from privacy UI'
grep -q '^lsposed_enabled=0' "$CONF" || fail 'LSPosed master switch must remain opt-in by default'
grep -Fq 'if (!"1".equals(master))' "$HOOK" || fail 'runtime master gate must fail closed unless explicitly enabled'
grep -Fq 'privacy hooks inactive: lsposed_enabled is not explicitly 1' "$HOOK" || fail 'runtime master gate must report disabled/malformed config'
grep -Fq 'data-key="hide_bl_status"' "$HTML" || fail 'bootloader property spoof switch missing'
grep -Fq '不能改变硬件 Key Attestation' "$HTML" || fail 'bootloader spoof must state hardware-attestation limitation'
grep -q '^hide_bl_status=0' "$CONF" || fail 'bootloader spoof must default off'
grep -Fq 'data-key="props_random"' "$HTML" || fail 'boot-time property randomization switch missing'
grep -Fq '开机时随机化序列号与构建时间属性' "$HTML" || fail 'property randomization scope must be explicit'
grep -Fq 'get props_random 0' "$ROOT/post-fs-data.sh" || fail 'property randomization startup backend missing'
grep -Fq 'if(sw.dataset.unavailable===\x271\x27)' "$HTML" || grep -Fq "if(sw.dataset.unavailable==='1')" "$HTML" || fail 'unavailable switch click must be blocked'
grep -Fq 'pgPersistNow().then(function(saved)' "$HTML" || fail 'editor must await config persistence'
grep -Fq "pgQueueAutoApply('隐私配置已保存，正在应用…',true)" "$HTML" || fail 'editor save must trigger apply'
grep -Fq "dns:'global_dns'" "$HTML" || fail 'DNS editor mapping must match the global_dns switch/backend section'
echo 'PASS: privacy runtime gate is user-accessible, unavailable features are blocked, and editor save applies config'
