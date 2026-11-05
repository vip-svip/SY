#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -Fq "e.preventDefault();e.stopImmediatePropagation();" "$HTML" || fail 'editor save must suppress stale bubbling stub handlers'
grep -Fq 'pgPersistNow().then(function(saved)' "$HTML" || fail 'editor save must await transactional config commit'
grep -Fq "pgQueueAutoApply('隐私配置已保存，正在应用…',true)" "$HTML" || fail 'saved privacy editor config must trigger apply'
grep -Fq "dns:'global_dns'" "$HTML" || fail 'global DNS editor must write to backend-consumed global_dns section'
grep -Fq 'if(!sec){e.preventDefault();e.stopImmediatePropagation();toast(' "$HTML" || fail 'editor must block custom editors without a runtime parser'
grep -Fq 'Config saved and applying; verify runtime logs for effective status' "$HTML" || fail 'editor must distinguish save from verified runtime effect'
! grep -Fq '示例编辑器未接入后端：内容未保存' "$HTML" || fail 'stale false-negative editor message remains'
echo 'PASS: privacy editor saves transactionally, applies config, and reports status honestly'
