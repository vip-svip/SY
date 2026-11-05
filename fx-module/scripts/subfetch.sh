#!/system/bin/sh
# ============================================================
# PrivacyGuard subfetch.sh — 订阅拉取 + 本地落盘（v1.10.2 重写）
#
# 为什么重写：
#   旧版把订阅正文塞进 JSON 字符串从 stdout 回传（最大 2MB）。
#   2MB 正文要走 shell → JSON 转义 → 桥层 → JS 字符串 → textarea，
#   每一跳都是一次全量拷贝，真机上必然卡死。
#   现在正文只落盘，stdout 只回一行很小的元数据，走 subread.sh 分块读。
#
# 用法:
#   subfetch.sh <url>            有本地缓存就用缓存；没有才联网
#   subfetch.sh <url> --force    强制联网刷新，覆盖本地缓存
#   subfetch.sh <url> --local    只读本地缓存，绝不联网
#     subfetch.sh <url> --view     通用文本预览（脚本/规则/hosts）；不用于 VPN 节点导入
#
# 输出（单行 JSON，KB 级以下，与正文大小无关）:
#   {"ok":1,"key":"k123","size":4567,"lines":89,"cached":1,"fetched":0,"path":"..."}
#   {"ok":0,"err":"..."}
# ============================================================
# >>> pg-moddir (auto)
# 兼容相对路径/软链/su 调用：先尝试按 $0 推导，失败再逐级向上找 module.prop
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
PG_MODDIR=$MODDIR
# <<< pg-moddir
. "$MODDIR/scripts/util.sh"

url="$1"
mode="$2"
if [ -z "$url" ]; then
  echo '{"ok":0,"err":"no url"}'
  exit 0
fi
# Remote subscriptions and script/rule previews must use HTTP(S) only. Passing
# arbitrary schemes to curl/wget can turn a URL field into a local-file or other
# protocol reader. Local cached content is still available through --local.
case "$url" in
  http://*|https://*) ;;
  *) echo '{"ok":0,"err":"unsupported URL scheme (use http:// or https://)"}'; exit 0 ;;
esac
# Reject control whitespace before hashing or handing the URL to curl/wget.
# Build an actual newline portably (printf '\\nX' then strip sentinel X).
_fx_nl=$(printf '\nX')
_fx_nl=${_fx_nl%X}
_fx_cr=$(printf '\r')
_fx_tab=$(printf '\t')
case "$url" in
  *"$_fx_nl"*|*"${_fx_cr}"*|*"${_fx_tab}"*|*' '*) echo '{"ok":0,"err":"invalid URL characters"}'; exit 0 ;;
esac

SUBDIR="$PG/subs"
mkdir -p "$SUBDIR" 2>/dev/null
[ -d "$SUBDIR" ] || { echo '{"ok":0,"err":"cannot create subs dir"}'; exit 0; }

# 稳定的短键：URL 的 cksum。同一 URL 永远落在同一文件，便于复用与清理。
_key=$(printf '%s' "$url" | cksum 2>/dev/null | awk '{print $1}')
[ -n "$_key" ] || _key=$(printf '%s' "$url" | md5sum 2>/dev/null | cut -c1-10)
[ -n "$_key" ] || _key=$(printf '%s' "$url" | sed 's/[^A-Za-z0-9]/_/g' | cut -c1-40)
FILE="$SUBDIR/$_key.txt"
META="$SUBDIR/$_key.meta"

# Commit cache metadata atomically. The body is already atomically replaced;
# writing META in-place could leave an empty/partial sidecar if the process is
# killed during the write. A same-directory temp file keeps rename atomic.
_pg_sub_hash() {
  _sh_file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$_sh_file" 2>/dev/null | awk 'NR==1 {print $1}'
  elif command -v toybox >/dev/null 2>&1 && toybox sha256sum "$_sh_file" >/dev/null 2>&1; then
    toybox sha256sum "$_sh_file" 2>/dev/null | awk 'NR==1 {print $1}'
  else
    _sh_sum=$(cksum "$_sh_file" 2>/dev/null) || return 1
    set -- $_sh_sum
    printf 'cksum:%s:%s\n' "$1" "$2"
  fi
}

_pg_sub_write_meta() {
  _sm_size=$1 _sm_lines=$2 _sm_time=$3 _sm_hash=${4:-}
  _sm_tmp="$META.tmp.$$"
  if ! { printf 'size=%s\nlines=%s\ntime=%s\nhash=%s\n' "$_sm_size" "$_sm_lines" "$_sm_time" "$_sm_hash" > "$_sm_tmp"; } 2>/dev/null; then
    rm -f "$_sm_tmp" 2>/dev/null || :
    return 1
  fi
  chmod 600 "$_sm_tmp" 2>/dev/null || :
  if ! mv -f "$_sm_tmp" "$META" 2>/dev/null; then
    rm -f "$_sm_tmp" 2>/dev/null || :
    return 1
  fi
  return 0
}

# Serialize operations for the same URL. Without this lock, two forced refreshes
# could both download, replace the body in different orders, and leave metadata
# (size/line count/time) describing the other process's body. A per-key mkdir lock
# is atomic on Android/Linux filesystems; stale owners are reclaimed conservatively.
LOCK="$SUBDIR/.lock.$_key"
LOCK_HELD=0
subfetch_unlock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  _sl_owner=$(cat "$LOCK/pid" 2>/dev/null)
  if [ "$_sl_owner" = "$$" ]; then rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null || :; fi
  LOCK_HELD=0
}
trap 'subfetch_unlock' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
_sl_try=0
while ! mkdir "$LOCK" 2>/dev/null; do
  _sl_owner=$(cat "$LOCK/pid" 2>/dev/null)
  case "$_sl_owner" in
    ''|*[!0-9]*) ;;
    *) if ! kill -0 "$_sl_owner" 2>/dev/null; then
         # Recheck ownership, then atomically move the stale directory out of
         # the contested name. Never unlink LOCK/pid and rmdir LOCK separately:
         # another waiter could recreate LOCK between those operations and have
         # its live lock deleted by this stale-lock reaper.
         _sl_again=$(cat "$LOCK/pid" 2>/dev/null)
         if [ "$_sl_again" = "$_sl_owner" ]; then
           _sl_stale="$SUBDIR/.stale-lock.$_key.$$.$_sl_try"
           if [ ! -e "$_sl_stale" ] && mv "$LOCK" "$_sl_stale" 2>/dev/null; then
             # The PID may have changed between the last read and rename. Only
             # delete the quarantined directory if it still belongs to the dead
             # owner we observed. Otherwise preserve it and restore it if no new
             # canonical lock has appeared; never delete an unverified owner.
             _sl_moved_owner=$(cat "$_sl_stale/pid" 2>/dev/null)
             if [ "$_sl_moved_owner" = "$_sl_owner" ] && ! kill -0 "$_sl_moved_owner" 2>/dev/null; then
               rm -rf "$_sl_stale" 2>/dev/null || :
             else
               # Preserve an unverified quarantine instead of moving it back to
               # LOCK. A check-then-mv is racy: another waiter can create LOCK
               # after the check, and POSIX mv may nest the quarantine inside
               # that new live lock directory. The canonical lock name stays
               # untouched; a later invocation can retry after this waiter exits.
               :
             fi
           fi
         fi
       fi ;;
  esac
  _sl_try=$((_sl_try+1))
  if [ "$_sl_try" -ge 100 ]; then
    printf '{"ok":0,"err":"subscription cache busy for 30 seconds; retry later","key":"%s"}\n' "$_key"
    exit 0
  fi
  sleep 0.1
 done
LOCK_HELD=1
printf '%s\n' "$$" > "$LOCK/pid" || { rmdir "$LOCK" 2>/dev/null || :; LOCK_HELD=0; echo '{"ok":0,"err":"cannot record cache lock owner"}'; exit 0; }

# 只有显式 --local 才允许「没缓存就报错」；默认行为是「有缓存用缓存，没有才联网」
if [ "$mode" = "--local" ] && [ ! -f "$FILE" ]; then
  echo '{"ok":0,"err":"no local copy yet","key":"'"$_key"'","size":0,"lines":0,"cached":0,"fetched":0}'
  exit 0
fi

# ---- 读取元数据（size/lines/mtime 都以此为准，避免每次重算大文件）----
_meta_size=0; _meta_lines=0; _meta_time=0; _meta_hash=""
if [ -f "$META" ]; then
  _meta_size=$(sed -n 's/^size=//p' "$META" 2>/dev/null | head -1)
  _meta_lines=$(sed -n 's/^lines=//p' "$META" 2>/dev/null | head -1)
  _meta_time=$(sed -n 's/^time=//p' "$META" 2>/dev/null | head -1)
  _meta_hash=$(sed -n 's/^hash=//p' "$META" 2>/dev/null | head -1)
fi
case "$_meta_size" in ''|*[!0-9]*) _meta_size=0 ;; esac
case "$_meta_lines" in ''|*[!0-9]*) _meta_lines=0 ;; esac
case "$_meta_time" in ''|*[!0-9]*) _meta_time=0 ;; esac
# Recover a usable cache whose metadata is missing/stale (e.g. interrupted old-version upgrade).
# The body itself is written atomically, so a non-empty cache file is safer than failing import.
if [ -f "$FILE" ]; then
  _actual_size=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
  case "$_actual_size" in ''|*[!0-9]*) _actual_size=0 ;; esac
  if [ "$_actual_size" -gt 0 ] && [ "$_actual_size" -le 8388608 ]; then
    # Size alone cannot detect a crash between body and sidecar commits when
    # the old and new subscription happen to have equal byte length. Verify a
    # digest and rebuild metadata whenever the sidecar is stale or legacy.
    _actual_hash=$(_pg_sub_hash "$FILE" 2>/dev/null) || _actual_hash=""
    if [ "$_actual_size" != "$_meta_size" ] || [ -z "$_meta_hash" ] || [ -z "$_actual_hash" ] || [ "$_actual_hash" != "$_meta_hash" ]; then
      _meta_size=$_actual_size
      _meta_lines=$(awk 'END{print NR}' "$FILE" 2>/dev/null)
      case "$_meta_lines" in ''|*[!0-9]*) _meta_lines=0 ;; esac
      _meta_time=$(date +%s 2>/dev/null); case "$_meta_time" in ''|*[!0-9]*) _meta_time=0 ;; esac
      _meta_hash=$_actual_hash
      if _pg_sub_write_meta "$_meta_size" "$_meta_lines" "$_meta_time" "$_meta_hash"; then
      pg_log "subfetch: recovered cache metadata for key $_key"
    else
        pg_log "subfetch: warning — could not atomically recover metadata for key $_key"
      fi
    fi
  fi
fi

# Validate subscription content before replacing a previously working cache.
# Return 0 for supported formats, 2 for HTML/verification pages, 1 for unknown bodies.
_pg_sub_body_type() {
  _sv_file="$1"; _sv_depth="${2:-0}"
  [ -s "$_sv_file" ] || return 1
  if grep -Eiq '<!doctype[[:space:]]+html|<html([[:space:]>]|$)|cloudflare|captcha|login required|verify you are human|access denied' "$_sv_file" 2>/dev/null; then return 2; fi
  _sv_bom=$(printf '\357\273\277')
  if grep -Eiq "^[[:space:]]*(${_sv_bom})?(vmess|vless|trojan|ss|ssr|hysteria2?|tuic|anytls|socks5?)://" "$_sv_file" 2>/dev/null; then return 0; fi
  if grep -Eiq "^[[:space:]]*(${_sv_bom})?proxies[[:space:]]*:" "$_sv_file" 2>/dev/null &&
     grep -Eiq 'type[[:space:]]*:[[:space:]]*(vmess|vless|trojan|ss|ssr|shadowsocks|shadowsocksr|hysteria2?|hy2|tuic|anytls|socks5?|socks)' "$_sv_file" 2>/dev/null &&
     grep -Eiq 'server[[:space:]]*:' "$_sv_file" 2>/dev/null &&
     grep -Eiq 'port[[:space:]]*:' "$_sv_file" 2>/dev/null; then return 0; fi
  if grep -Eiq '"outbounds"[[:space:]]*:' "$_sv_file" 2>/dev/null &&
     grep -Eiq '"type"[[:space:]]*:[[:space:]]*"(vmess|vless|trojan|shadowsocks|shadowsocksr|hysteria2?|hy2|tuic|anytls|socks|socks5)"' "$_sv_file" 2>/dev/null &&
     grep -Eiq '"server"[[:space:]]*:' "$_sv_file" 2>/dev/null; then return 0; fi
  # Some providers Base64-wrap the actual URI list or Clash YAML.
  if [ "$_sv_depth" = 0 ] && command -v base64 >/dev/null 2>&1; then
    _sv_dec="$SUBDIR/.validate.$$"
    if base64 -d "$_sv_file" > "$_sv_dec" 2>/dev/null && [ -s "$_sv_dec" ]; then
      _pg_sub_body_type "$_sv_dec" 1; _sv_rc=$?
      rm -f "$_sv_dec" 2>/dev/null
      return "$_sv_rc"
    fi
    rm -f "$_sv_dec" 2>/dev/null
  fi
  return 1
}

_cache_valid=0
if [ -s "$FILE" ]; then
  if [ "$mode" = "--view" ] || [ "$mode" = "--view-force" ]; then
    # Generic editor view accepts plain-text rule/script modules, but never HTML/login challenges.
    if ! grep -Eiq '<!doctype[[:space:]]+html|<html([[:space:]>]|$)|cloudflare|captcha|login required|verify you are human|access denied' "$FILE" 2>/dev/null; then _cache_valid=1; fi
  elif [ "$(_pg_sub_body_type "$FILE" 0; echo $?)" = 0 ]; then _cache_valid=1; fi
fi

_out_ok() {
  printf '{"ok":1,"key":"%s","size":%s,"lines":%s,"cached":%s,"fetched":%s,"path":"%s"}\n' \
    "$_key" "$1" "$2" "$3" "$4" "$SUBDIR/$_key.txt"
}

# ---- 只用本地 ----
if [ "$mode" = "--local" ]; then
  if [ "$_cache_valid" != 1 ]; then
    echo '{"ok":0,"err":"本地订阅缓存不是可识别的代理订阅正文"}'
    exit 0
  fi
  if [ "$_meta_size" -eq 0 ]; then
    _meta_size=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
    case "$_meta_size" in ''|*[!0-9]*) _meta_size=0 ;; esac
  fi
  _out_ok "$_meta_size" "$_meta_lines" 1 0
  exit 0
fi

# ---- 有缓存且非强制刷新：直接返回，零网络 ----
if [ "$_cache_valid" = 1 ] && [ "$mode" != "--force" ] && [ "$mode" != "--view-force" ] && [ "$_meta_size" -gt 0 ]; then
  _out_ok "$_meta_size" "$_meta_lines" 1 0
  exit 0
fi

# ---- 联网拉取 ----
tmp="$SUBDIR/.fetch.$$"
# Enforce the byte cap while streaming, including chunked responses without
# Content-Length. The helper writes at most 8 MiB + one overflow sentinel byte.
_fr=1
if [ -f "$MODDIR/scripts/subfetch-download.sh" ]; then
  if pg_have timeout; then
    timeout 20 sh "$MODDIR/scripts/subfetch-download.sh" "$url" "$tmp" >/dev/null 2>&1 && _fr=0
  else
    sh "$MODDIR/scripts/subfetch-download.sh" "$url" "$tmp" >/dev/null 2>&1 && _fr=0
  fi
else
  pg_log "subfetch: bounded download helper missing; refusing unbounded fetch"
fi

if [ "$_fr" -ne 0 ] || [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  # 拉取失败但本地有旧缓存 → 退回缓存，不让界面变空
  if [ "$_cache_valid" = 1 ] && [ "$_meta_size" -gt 0 ]; then
    _out_ok "$_meta_size" "$_meta_lines" 1 0
    exit 0
  fi
  echo '{"ok":0,"err":"fetch failed (network or url)"}'
  exit 0
fi

_sz=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
if [ "$_sz" -eq 0 ]; then
  rm -f "$tmp"
  echo '{"ok":0,"err":"empty response"}'
  exit 0
fi
# 体积上限放宽到 8MB：正文不再经过 stdout，落盘即可，不会撑爆桥层
if [ "$_sz" -gt 8388608 ]; then
  rm -f "$tmp"
  echo '{"ok":0,"err":"subscription too large (>8MB)"}'
  exit 0
fi

# HTTP 200 can still be a login page, anti-bot challenge or error document.
# Reject it before atomic replacement so a failed refresh cannot poison the working cache.
_pg_sub_body_type "$tmp" 0
_sv_type=$?
if [ "$_sv_type" -ne 0 ] && ! { ( [ "$mode" = "--view" ] || [ "$mode" = "--view-force" ] ) && [ "$_sv_type" = 1 ]; }; then
  rm -f "$tmp"
  if [ "$_cache_valid" = 1 ] && [ "$_meta_size" -gt 0 ]; then
    _out_ok "$_meta_size" "$_meta_lines" 1 0
    exit 0
  fi
  if [ "$_sv_type" = 2 ]; then
    echo '{"ok":0,"err":"服务器返回了网页/登录验证页，不是有效订阅；未覆盖本地缓存"}'
  else
    echo '{"ok":0,"err":"服务器响应不是可识别的代理订阅（支持 URI/Base64、Clash YAML、sing-box JSON）；未覆盖本地缓存"}'
  fi
  exit 0
fi

# 断言式覆盖：先写临时文件再 mv，避免读到半个文件
mv -f "$tmp" "$FILE" 2>/dev/null || { rm -f "$tmp"; echo '{"ok":0,"err":"cannot save local copy"}'; exit 0; }
chmod 600 "$FILE" 2>/dev/null

# 统计行数（大文件也只扫一遍，且不在 stdout 输出内容）
_sz=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
_nl=$(awk 'END{print NR}' "$FILE" 2>/dev/null)
case "$_nl" in ''|*[!0-9]*) _nl=0 ;; esac
_now=$(date +%s 2>/dev/null)
case "$_now" in ''|*[!0-9]*) _now=0 ;; esac

_hash=$(_pg_sub_hash "$FILE" 2>/dev/null) || _hash=""
if ! _pg_sub_write_meta "$_sz" "$_nl" "$_now" "$_hash"; then
  # Keep the newly committed body, but report metadata failure clearly. The
  # next invocation can reconstruct the sidecar from the valid body.
  pg_log "subfetch: warning — body committed but metadata sidecar update failed for key $_key"
fi

_out_ok "$_sz" "$_nl" 1 1
exit 0