#!/system/bin/sh
# ============================================================
#  ruleset.sh — 外置规则库同步 (SY-Rules)
#  模块不再内置任何拦截规则，全部从规则仓库拉取。
#  用法: ruleset.sh {sync|status|set-repo <owner/repo>|set-branch <b>
#                    |set-mirror <url>|append-repo <owner/repo>|list-repos}
#  作者: vip-svip
# ============================================================
. "$(dirname "$0")/common.sh"

DEF_REPO="vip-svip/SY-Rules"
REPO=$(cfg_get RULES_REPO "$DEF_REPO")
BRANCH=$(cfg_get RULES_BRANCH "main")
MIRROR=$(cfg_get RULES_MIRROR "")
RDIR="$DATA_DIR/rules/remote"
mkdir -p "$RDIR"

_raw() { # relpath -> url
  u="https://raw.githubusercontent.com/$REPO/$BRANCH/$1"
  if [ -n "$MIRROR" ]; then printf '%s/%s' "${MIRROR%/}" "$u"; else printf '%s' "$u"; fi
}

_fetch() { # relpath outfile ; 0 on success
  http_get "$(_raw "$1")" "$2" 40
}

sync() {
  # 断网优化：无网时明确告知并沿用上次缓存，不空等超时
  # （旧行为是逐个 url 等 40s 超时，用户看到"卡住"，且不知道是没网）
  if [ -f "$(dirname "$0")/offline.sh" ]; then
    sh "$(dirname "$0")/offline.sh" need "同步规则库（$REPO）" "$RDIR/block.txt" || {
      echo "提示：DNS 拦截会继续使用本地已缓存的规则，功能不受影响。"
      return 0
    }
  fi
  [ -z "$REPO" ] && { echo "ERR: 未配置规则仓库"; return 1; }
  ok=0; bad=0
  for pair in \
      "rules/block.txt|$RDIR/block.txt" \
      "rules/upstream.txt|$RDIR/upstream.txt" \
      "rules/whitelist.txt|$RDIR/whitelist.txt" \
      "rules/mitm_rules.conf|$RDIR/mitm_rules.conf" \
      "rules/splash_rules.conf|$RDIR/splash_rules.conf" \
      "rules/notify_keywords.conf|$RDIR/notify_keywords.conf" \
      "manifest.json|$RDIR/manifest.json" ; do
    p="${pair%%|*}"; o="${pair##*|}"
    if _fetch "$p" "$o"; then ok=$((ok+1)); log "ruleset: 拉取 $p OK"; else
      bad=$((bad+1)); log "ruleset: 拉取 $p 失败(保留旧缓存)"
      [ -s "$o" ] || : > "$o"
    fi
  done
  log "ruleset: sync repo=$REPO ok=$ok bad=$bad"
  # 将远端规则落到各功能实际读取的工作配置路径
  for pair in "whitelist.txt|whitelist.conf" "mitm_rules.conf|mitm_rules.conf" \
              "splash_rules.conf|splash_rules.conf" "notify_keywords.conf|notify_keywords.conf"; do
    rf="$RDIR/${pair%%|*}"; cf="$DATA_DIR/config/${pair##*|}"
    [ -s "$rf" ] && { mkdir -p "$DATA_DIR/config"; cp -f "$rf" "$cf"; }
  done
  # 拉取成功后应用: 重建 DNS 规则
  sh "$(dirname "$0")/dns.sh" update >/dev/null 2>&1
  echo "OK: 规则同步完成 (成功 $ok 项, 失败 $bad 项, 规则库=$REPO@$BRANCH)"
}

status() {
  bf="$RDIR/block.txt"; up="$RDIR/upstream.txt"; wl="$RDIR/whitelist.txt"
  printf '{"repo":"%s","branch":"%s","mirror":"%s","block_lines":%s,"upstream_lines":%s,"whitelist_lines":%s,"dir":"%s"}\n' \
    "$(json_escape "$REPO")" "$(json_escape "$BRANCH")" "$(json_escape "$MIRROR")" \
    "$(count_lines "$bf")" "$(count_lines "$up")" "$(count_lines "$wl")" "$RDIR"
}

# ---------- 订阅源管理 ----------
sources_json() {
  out=""; cur="$REPO"
  if [ -f "$SOURCES" ]; then
    while IFS= read -r line; do
      case "$line" in ""|\#*) continue ;; esac
      nm="${line%%|*}"; rp="${line##*|}"
      [ "$rp" = "$line" ] && rp="$nm"
      rp=$(printf '%s' "$rp" | tr -d '[:space:]')
      nm=$(printf '%s' "$nm" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$rp" ] && continue; [ -z "$nm" ] && nm="$rp"
      [ -n "$out" ] && out="$out,"
      act=0; [ "$rp" = "$cur" ] && act=1
      out="$out{\"name\":\"$(json_escape "$nm")\",\"repo\":\"$(json_escape "$rp")\",\"active\":$act}"
    done < "$SOURCES"
  fi
  [ -z "$out" ] && out="{\"name\":\"$(json_escape "$cur")\",\"repo\":\"$(json_escape "$cur")\",\"active\":1}"
  printf '[%s]\n' "$out"
}

use_source() {
  nm="$1"; [ -z "$nm" ] && { echo "ERR: 缺少订阅源名称"; return 1; }
  rp=""
  if [ -f "$SOURCES" ]; then
    rp=$(awk -F'|' -v n="$nm" '{nm=$1; rp=$2; if(rp=="")rp=nm; gsub(/[[:space:]]/,"",rp); gsub(/^[[:space:]]+|[[:space:]]+$/,"",nm); if(nm==n||rp==n){print rp; exit}}' "$SOURCES")
  fi
  [ -z "$rp" ] && { echo "ERR: 未找到订阅源 $nm"; return 1; }
  cfg_set RULES_REPO "$rp"
  echo "OK: 已选用规则源 $rp"
  sync
}

append_repo() {
  rp=$(printf '%s' "$1" | tr -d '[:space:]'); [ -z "$rp" ] && { echo "ERR: 缺少仓库(owner/repo)"; return 1; }
  if [ -f "$SOURCES" ] && grep -qF "$rp" "$SOURCES"; then echo "OK: 订阅源已存在"; return 0; fi
  echo "$rp|$rp" >> "$SOURCES"
  echo "OK: 已添加订阅源 $rp"
}

case "$1" in
  sync)       sync ;;
  set-repo)   cfg_set RULES_REPO "$2";   echo "OK: 规则仓库 -> $2" ;;
  set-branch) cfg_set RULES_BRANCH "$2"; echo "OK: 规则分支 -> ${2:-main}" ;;
  set-mirror) cfg_set RULES_MIRROR "$2"; echo "OK: 下载镜像 -> ${2:-无}" ;;
  get-repo)   echo "$REPO" ;;
  status)     status ;;
  serve-list) sources_json ;;
  use-source) use_source "$2" ;;
  append-repo) append_repo "$2" ;;
  *) echo "usage: ruleset.sh {sync|status|set-repo <owner/repo>|set-branch <b>|set-mirror <url>|get-repo}" ;;
esac
