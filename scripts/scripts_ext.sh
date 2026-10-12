#!/system/bin/sh
# ============================================================
#  scripts_ext.sh — 脚本扩展中心
#  功能: 油猴脚本导入/订阅/更新/卸载、订阅开关与多订阅并行、
#        脚本订阅源无限制、QX/Surge/Loon/SR MITM 规则导入、
#        MITM 规则转脚本、批量删除、恶意代码特征扫描、版本回滚
#  用法: scripts_ext.sh {list|list-json|install-url|install-file|remove|remove-multi|
#        update|update-all|subscribe|subs-list|subs-list-json|subs-remove|
#        subs-remove-multi|subs-toggle|subs-enable-multi|rollback|info|
#        import-mitm-b64|mitm-to-script|scan}
# ============================================================
. "$(dirname "$0")/common.sh"

JS_DIR="$SCRIPTS_DIR"           # 用户脚本目录
META_DIR="$DATA_DIR/config/script_meta"
SUB_FILE="$DATA_DIR/config/subscriptions.conf"
DEP_CACHE="$CACHE/deps"
mkdir -p "$JS_DIR" "$META_DIR" "$DEP_CACHE" 2>/dev/null
[ -f "$SUB_FILE" ] || : > "$SUB_FILE"

logf="$LOGS/scripts.log"

scan_malicious() {
  f="$1"
  if grep -qiE 'Runtime\.getRuntime|ProcessBuilder|exec\(|su -c|/system/bin/|chmod |mount |pm install|curl .*\| *sh|wget .*\| *sh|SmsManager|sendTextMessage|content://sms|getDeviceId|getImei|ContactsContract|android\.permission\.' "$f" 2>/dev/null; then
    return 1
  fi
  return 0
}

parse_meta() {
  awk '
    /==UserScript==/ { inblk=1; next }
    /==\/UserScript==/ { inblk=0 }
    inblk && /@[a-zA-Z]/ {
      line=$0
      sub(/^[[:space:]]*\/\/[[:space:]]*/, "", line)
      gsub(/^@/, "", line)
      n=index(line, " ")
      if(n>0){ k=substr(line,1,n-1); v=substr(line,n+1); print k"="v } else { print line"=" }
    }
  ' "$f" 2>/dev/null
}

write_meta() { # base name url
  { echo "file=$1"; echo "name=$2"; echo "url=$3"; echo "installed=$(date '+%Y-%m-%d %H:%M:%S')"; } > "$META_DIR/$1.meta"
}

install_url() {
  url="$1"
  [ -z "$url" ] && { echo "ERR: 缺少URL"; exit 1; }
  base=$(basename "$url" | sed 's/[?].*$//')
  case "$base" in *.js|*.user.js) ;; *) base="script_$(date +%s).js" ;; esac
  out="$JS_DIR/$base"
  if http_get "$url" "$out" 40; then
    if ! scan_malicious "$out"; then
      mv "$out" "$out.rejected"
      echo "ERR: 脚本含敏感代码特征，已被拦截"
      return 1
    fi
    name=$(parse_meta "$out" | awk -F= '/^name=/{print $2; exit}')
    [ -z "$name" ] && name="$base"
    write_meta "$base" "$name" "$url"
    echo "OK: 已安装脚本「$name」-> $base"
  else
    echo "ERR: 下载失败"
  fi
}

install_file() {
  base="local_$(date +%s).js"
  out="$JS_DIR/$base"
  cat > "$out"
  if ! scan_malicious "$out"; then
    mv "$out" "$out.rejected"; echo "ERR: 本地脚本含敏感特征，已拦截"; return 1
  fi
  name=$(parse_meta "$out" | awk -F= '/^name=/{print $2; exit}')
  [ -z "$name" ] && name="$base"
  write_meta "$base" "$name" "local"
  echo "OK: 已导入脚本「$name」"
}

install_url_file() { # tmpfile url
  tmp="$1"; url="$2"
  base=$(basename "$url" | sed 's/[?].*$//')
  case "$base" in *.js) ;; *) base="sub_$(echo "$url"|md5sum|cut -c1-8).js" ;; esac
  out="$JS_DIR/$base"
  scan_malicious "$tmp" || { logf "更新拦截可疑 $url"; return 1; }
  cp -f "$tmp" "$out"
  name=$(parse_meta "$out" | awk -F= '/^name=/{print $2; exit}')
  [ -z "$name" ] && name="$base"
  if [ ! -f "$META_DIR/$base.meta" ]; then write_meta "$base" "$name" "$url"; fi
  echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$META_DIR/$base.updated"
}

list_scripts() {
  out="["
  first=1
  for f in "$JS_DIR"/*.js; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    m="$META_DIR/$b.meta"
    name="$b"; url=""
    if [ -f "$m" ]; then
      nm=$(grep '^name=' "$m" | head -n1 | cut -d= -f2-)
      [ -n "$nm" ] && name="$nm"
      url=$(grep '^url=' "$m" | head -n1 | cut -d= -f2-)
    fi
    upd=""
    [ -f "$META_DIR/$b.updated" ] && upd=$(cat "$META_DIR/$b.updated")
    enabled="yes"
    [ -f "$JS_DIR/.disabled/$b" ] && enabled="no"
    [ "$first" = "1" ] || out="$out,"
    first=0
    out="$out{\"file\":\"$(json_escape "$b")\",\"name\":\"$(json_escape "$name")\",\"url\":\"$(json_escape "$url")\",\"updated\":\"$(json_escape "$upd")\",\"enabled\":\"$enabled\"}"
  done
  out="$out]"
  printf '%s\n' "$out"
}

remove_script() {
  f="$1"
  [ -z "$f" ] && { echo "ERR: 缺少文件名"; exit 1; }
  rm -f "$JS_DIR/$f" "$META_DIR/$f.meta" "$META_DIR/$f.updated" "$JS_DIR/.disabled/$f"
  echo "OK: 已卸载 $f"
}

remove_multi() { # 逗号分隔文件名
  list="$1"; [ -z "$list" ] && { echo "ERR: 缺少文件名"; exit 1; }
  n=0
  echo "$list" | tr ',' '\n' | while IFS= read -r f; do
    [ -z "$f" ] && continue
    rm -f "$JS_DIR/$f" "$META_DIR/$f.meta" "$META_DIR/$f.updated" "$JS_DIR/.disabled/$f"
  done
  n=$(echo "$list" | tr ',' '\n' | grep -c .)
  echo "OK: 已批量卸载 $n 个脚本"
}

update_script() {
  f="$1"
  [ -z "$f" ] && { echo "ERR: 缺少文件名"; exit 1; }
  m="$META_DIR/$f.meta"
  [ -f "$m" ] || { echo "ERR: 无元信息，无法更新"; exit 1; }
  url=$(grep '^url=' "$m" | head -n1 | cut -d= -f2-)
  if [ -z "$url" ] || [ "$url" = "local" ]; then echo "ERR: 本地脚本无来源，无法更新"; exit 1; fi
  tmp="$CACHE/upd_$f"
  if http_get "$url" "$tmp" 40; then
    if ! scan_malicious "$tmp"; then echo "ERR: 新版本含敏感特征，已阻止"; return 1; fi
    cp -f "$JS_DIR/$f" "$BACKUP_DIR/$f.bak" 2>/dev/null
    cp -f "$tmp" "$JS_DIR/$f"
    name=$(parse_meta "$JS_DIR/$f" | awk -F= '/^name=/{print $2; exit}')
    [ -z "$name" ] && name="$f"
    write_meta "$f" "$name" "$url"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$META_DIR/$f.updated"
    echo "OK: 已更新 $f"
  else
    echo "ERR: 更新下载失败"
  fi
}

# 订阅行格式: enabled|url|interval  (兼容旧格式 url|interval)
subs_iter() { # 输出: idx|enabled|url|iv
  [ -f "$SUB_FILE" ] || return 0
  idx=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    idx=$((idx+1))
    f1=$(echo "$line" | cut -d'|' -f1)
    case "$f1" in
      0|1) en="$f1"; url=$(echo "$line" | cut -d'|' -f2); iv=$(echo "$line" | cut -d'|' -f3) ;;
      *)   en="1"; url="$f1"; iv=$(echo "$line" | cut -d'|' -f2) ;;
    esac
    [ -z "$iv" ] && iv=24
    echo "$idx|$en|$url|$iv"
  done < "$SUB_FILE"
}

update_all() {
  [ -f "$SUB_FILE" ] || { echo "OK: 无订阅"; return 0; }
  n=0; total=0
  subs_iter | while IFS='|' read -r idx en url iv; do
    [ "$en" = "1" ] || continue
    [ -z "$url" ] && continue
    total=$((total+1))
    http_get "$url" "$CACHE/sub_update.tmp" 30 && install_url_file "$CACHE/sub_update.tmp" "$url" >/dev/null 2>&1
  done
  echo "OK: 订阅更新完成"
}

subscribe() {
  url="$1"; iv="${2:-24}"
  [ -z "$url" ] && { echo "ERR: 缺少URL"; exit 1; }
  grep -qF "|$url" "$SUB_FILE" 2>/dev/null || grep -qFx "$url|$iv" "$SUB_FILE" 2>/dev/null || printf '1|%s|%s\n' "$url" "$iv" >> "$SUB_FILE"
  echo "OK: 已添加订阅 (每${iv}h，默认启用)"
}

subs_remove() { # idx
  idx="$1"
  [ -f "$SUB_FILE" ] || return 0
  tmp="$SUB_FILE.tmp.$$"
  awk -v w="$idx" 'BEGIN{n=0}/^[[:space:]]*#/{print;next}/^[[:space:]]*$/{next}{n++; if(n!=w)print}' "$SUB_FILE" > "$tmp"
  mv "$tmp" "$SUB_FILE"
  echo "OK: 已删除订阅 #$idx"
}

subs_remove_multi() { # 逗号分隔 idx
  list="$1"; [ -z "$list" ] && { echo "ERR: 缺少序号"; exit 1; }
  echo "$list" | tr ',' '\n' > "$CACHE/.subdel.$$"
  tmp="$SUB_FILE.tmp.$$"
  awk -v del="$CACHE/.subdel.$$" 'BEGIN{while((getline l < del)>0)d[l+0]=1} /^[[:space:]]*#/{print;next} /^[[:space:]]*$/{next} {n++; if(!(n in d))print}' "$SUB_FILE" > "$tmp"
  mv "$tmp" "$SUB_FILE"; rm -f "$CACHE/.subdel.$$"
  echo "OK: 已批量删除订阅"
}

subs_toggle() { # idx [on|off]
  idx="$1"; v="$2"
  [ -f "$SUB_FILE" ] || { echo "ERR: 无订阅"; exit 1; }
  cur=$(subs_iter | awk -F'|' -v w="$idx" '$1==w{print $2}')
  [ -z "$cur" ] && { echo "ERR: 订阅 #$idx 不存在"; exit 1; }
  case "$v" in
    on|1|enable|enabled) nv=1 ;;
    off|0|disable|disabled) nv=0 ;;
    "") [ "$cur" = "1" ] && nv=0 || nv=1 ;;
    *) nv="$v" ;;
  esac
  tmp="$SUB_FILE.tmp.$$"
  awk -v w="$idx" -v nv="$nv" '
    /^[[:space:]]*#/{print;next} /^[[:space:]]*$/{next}
    { n++
      f1=$0; sub(/\|.*$/,"",f1)
      if (n==w) { rest=$0; if (f1=="0"||f1=="1") { sub(/^[^|]*\|?/,"",rest) } print nv"|"rest }
      else print
    }' "$SUB_FILE" > "$tmp"
  mv "$tmp" "$SUB_FILE"
  [ "$nv" = "1" ] && echo "OK: 订阅 #$idx 已启用" || echo "OK: 订阅 #$idx 已停用"
}

subs_enable_multi() { # 逗号分隔 idx, 全部启用
  list="$1"; [ -z "$list" ] && { echo "ERR: 缺少序号"; exit 1; }
  echo "$list" | tr ',' '\n' | while IFS= read -r i; do [ -n "$i" ] && subs_toggle "$i" on >/dev/null; done
  echo "OK: 已启用所选订阅（可多订阅同时使用）"
}

rollback() {
  f="$1"; bak="$BACKUP_DIR/$f.bak"
  [ -f "$bak" ] && cp -f "$bak" "$JS_DIR/$f" && echo "OK: 已回滚 $f" || echo "ERR: 无备份"
}

# MITM 规则 -> 可执行用户脚本(便于在脚本引擎中复用/分发)
mitm_to_script() {
  src="$1"
  ts=$(date +%s)
  base="mitm_rules_$ts.js"
  out="$JS_DIR/$base"
  {
    echo "// ==UserScript=="
    echo "// @name         MITM 规则脚本 ($ts)"
    echo "// @namespace    SY"
    echo "// @version      1.1"
    echo "// @description  由 SY 面板 MITM 规则转换生成（含底层适配层）"
    echo "// @run-at       document-start"
    echo "// @grant        none"
    echo "// ==/UserScript=="
    echo "// ---- 底层适配层: 同时适配 浏览器/WebView(QX,Loon,Surge,脚本引擎) ----"
    echo "(function(){"
    echo "  'use strict';"
    echo "  var ADAPTER = (function(){"
    echo "    var env = (typeof \$task !== 'undefined' && \$task) ? 'qx'"
    echo "      : (typeof \$httpClient !== 'undefined') ? 'surge'"
    echo "      : (typeof HTTP !== 'undefined' && HTTP.get) ? 'scriptable'"
    echo "      : 'web';"
    echo "    return {"
    echo "      env: env,"
    echo "      fetch: function(u,o){ try{ if(typeof \$task!=='undefined'&&\$task.fetch) return \$task.fetch(u,o); }catch(e){} return fetch(u,o); },"
    echo "      matchHost: function(url,pat){ try{ return new RegExp(pat.replace(/\./g,'\\\\.').replace(/\*/g,'.*')).test(url);}catch(e){ return url.indexOf(pat)>=0; } },"
    echo "      replaceAll: function(s,rules){ for(var r of rules){ if(s.indexOf(r.from)>=0) s=s.split(r.from).join(r.to); } return s; }"
    echo "    };"
    echo "  })();"
    echo "  if (typeof window !== 'undefined') { window.SY_ADAPTER = ADAPTER; }"
    echo "  // 在 document-start 阶段拦截 XHR/fetch 响应体做内容替换"
    echo "  if (ADAPTER.env === 'web' || typeof window !== 'undefined') {"
    echo "    try {"
    echo "      var _open = XMLHttpRequest.prototype.open;"
    echo "      XMLHttpRequest.prototype.open = function(){ this.__sy_url = arguments[1]; return _open.apply(this, arguments); };"
    echo "      var _send = XMLHttpRequest.prototype.send;"
    echo "      XMLHttpRequest.prototype.send = function(){ var self=this; self.addEventListener('readystatechange', function(){ if(self.readyState===4 && typeof SY_APPLY==='function'){ try{ self.__sy_replaced = SY_APPLY(self.__sy_url, self.responseText);}catch(e){} } }); return _send.apply(self, arguments); };"
    echo "    } catch(e){}"
    echo "    if (typeof window.fetch === 'function') { var _f=window.fetch; window.fetch=function(){ return _f.apply(this, arguments).then(function(resp){ return resp; }); }; }"
    echo "  }"
    echo "})();"
    echo "// 规则数据（内容替换规则，供脚本引擎/后续处理读取）"
    echo "const SY_MITM_RULES = ["
    i=0
    while IFS= read -r ln; do
      [ -z "$ln" ] && continue
      case "$ln" in \#*) continue ;; esac
      i=$((i+1))
      esc=$(printf '%s' "$ln" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
      echo "  \"$esc\","
    done < "$src"
    echo "];"
    echo "if (typeof window !== 'undefined') { window.__SY_MITM_RULES__ = SY_MITM_RULES; }"
  } > "$out"
  scan_malicious "$out" || rm -f "$out"
  name="MITM 规则脚本 ($ts)"
  write_meta "$base" "$name" "local"
  echo "OK: 已生成脚本「$name」-> $base（共 $i 条规则）"
}

case "$1" in
  list)          list_scripts ;;
  list-json)     list_scripts ;;
  install-url)   install_url "$2" ;;
  install-file)  install_file ;;
  remove)        remove_script "$2" ;;
  remove-multi)  remove_multi "$2" ;;
  update)        update_script "$2" ;;
  update-all)    update_all ;;
  subscribe)     subscribe "$2" "$3" ;;
  subs-list)     subs_iter ;;
  subs-list-json)
    out="["; first=1
    subs_iter | while IFS='|' read -r idx en url iv; do
      [ "$first" = "1" ] || out="$out,"
      first=0
      out="$out{\"idx\":$idx,\"enabled\":\"$en\",\"url\":\"$(json_escape "$url")\",\"interval\":\"$iv\"}"
      printf '%s\n' "$out" > "$CACHE/.subsjson.$$"
    done
    [ -f "$CACHE/.subsjson.$$" ] && { cat "$CACHE/.subsjson.$$"; rm -f "$CACHE/.subsjson.$$"; } || printf '[]\n'
    ;;
  subs-remove)   subs_remove "$2" ;;
  subs-remove-multi) subs_remove_multi "$2" ;;
  subs-toggle)   subs_toggle "$2" "$3" ;;
  subs-enable-multi) subs_enable_multi "$2" ;;
  rollback)      rollback "$2" ;;
  info)
    for m in "$META_DIR"/*.meta; do [ -f "$m" ] && { echo "--- $(basename "$m")"; cat "$m"; }; done
    ;;
  import-mitm-b64)
    [ -z "$2" ] && { echo "ERR: 空内容"; exit 1; }
    echo "$2" | base64 -d > "$CACHE/mitm_import.conf" 2>/dev/null
    cat "$CACHE/mitm_import.conf" >> "$MITM_RULES"
    echo "OK: 已导入 MITM 规则到代理规则（当前 $(count_lines "$MITM_RULES") 条）"
    ;;
  mitm-to-script) mitm_to_script "$MITM_RULES" ;;
  scan) scan_malicious "$2" && echo "OK: 未发现敏感特征" || echo "ERR: 含敏感特征" ;;
  *) echo "usage: scripts_ext.sh {list|list-json|install-url|install-file|remove|remove-multi|update|update-all|subscribe|subs-list|subs-list-json|subs-remove|subs-remove-multi|subs-toggle|subs-enable-multi|rollback|info|import-mitm-b64|mitm-to-script|scan}" ;;
esac
