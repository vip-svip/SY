#!/system/bin/sh
# ============================================================
# PrivacyGuard fileedit.sh — 大文件「分页查看 + 行级编辑」后端（v1.10.9）
#
# 设计要点（为什么这是「完美解决办法」）：
#   WebView 里把几 MB 文本塞进 textarea/pre 必然卡（布局/滚动/输入事件都在主线程），
#   桥层一条 JSON 回传超大字符串还会被截断（用户看到的「大文件加载失败」）。
#   所以：正文永远只在 shell 侧，前端一次只拿「一页」（≤200 行 / ≤64KB base64）。
#   编辑不是整篇重写，而是行级操作（改写/删除/插入），单次只回一行 JSON。
#   整篇编辑仅允许小文件（≤64KB）；大文件请用行操作或导出后替换。
#
# 用法（spec 形如 sub:<key> / builtin:<id> / fx:<id> / hosts）：
#   fileedit.sh stat   <spec>
#   fileedit.sh page   <spec> <start> <count> [maxBytes]
#   fileedit.sh find   <spec> <pattern> [max]
#   fileedit.sh edit   <spec> <n> <tmpfile>   # 用 tmpfile 内容替换第 n 行
#   fileedit.sh ins    <spec> <n> <tmpfile>   # 在第 n 行前插入（n=0 行首；n=总行数+1 追加）
#   fileedit.sh del    <spec> <n>
#   fileedit.sh put    <spec> <tmpfile>       # 整篇替换（≤16MB）
#   fileedit.sh cat    <spec>                 # 整篇 base64（≤300KB，仅小文件/导出用）
#   fileedit.sh reset  <spec>                 # 内置：删除用户副本，恢复随模块版本
#   fileedit.sh export <spec>
#
# 输出：单行 JSON {"ok":1,...} / {"ok":0,"err":"..."}
# ============================================================
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2"); _pg_n=$((_pg_n+1))
  done
fi
. "$MODDIR/scripts/util.sh"

# 用法：fileedit.sh <op> <spec> [args...]
op="$1"; spec="$2"
case "$spec" in
  sub:*)
    key=${spec#sub:}
    case "$key" in ''|*[!A-Za-z0-9_.-]*) echo '{"ok":0,"err":"bad key"}'; exit 0 ;; esac
    base="$PG/subs/$key.txt"; ov=""; name="PrivacyGuard-sub-$key.txt" ;;
  builtin:*)
    id=${spec#builtin:}
    case "$id" in ''|*[!A-Za-z0-9_.-]*|*..*|.*) echo '{"ok":0,"err":"bad id"}'; exit 0 ;; esac
    case "$id" in *.txt) _idfile="$id" ;; *) _idfile="$id.txt" ;; esac
    base="$MODDIR/rulefiles/$_idfile"; ov="$PG/rulefiles-user/$_idfile"; name="PrivacyGuard-rule-$id" ;;
  fx:*)
    id=${spec#fx:}
    case "$id" in ''|*[!A-Za-z0-9_.-]*|*..*|.*) echo '{"ok":0,"err":"bad id"}'; exit 0 ;; esac
    case "$id" in *.txt) _idfile="$id" ;; *) _idfile="$id.txt" ;; esac
    base="$MODDIR/fxrules/$_idfile"; ov="$PG/fxrules-user/$_idfile"; name="PrivacyGuard-fx-$id" ;;
  hosts)
    # Editable local Android hosts-format text. Keep this source separate from both
    # downloaded subscriptions and the generated/bind-mounted effective system file.
    base="$PG/local/hosts"; ov=""; name="hosts" ;;
  system-hosts)
    # Live system view: the exact path apps/resolver see. It is read-only because
    # direct writes may replace a bind-mounted inode or overwrite generated layers.
    base="/system/etc/hosts"; ov=""; name="hosts" ;;
  *)
    echo '{"ok":0,"err":"bad spec"}'; exit 0 ;;
esac

# Remote subscription bodies are display/cache copies, not the active rule source.
# Editing them here used to report success while apply.sh continued consuming the URL
# entry and its own validated cache. The live system hosts path is also read-only here:
# all durable manual edits must go through the separate local hosts source.
case "$spec" in
  sub:*|system-hosts)
    case "$op" in
      edit|ins|del|put|replacepage|reset|import-external)
        echo '{"ok":0,"err":"read-only source: edit the active rule/source instead"}'
        exit 0 ;;
    esac ;;
esac

# 本地 hosts 是独立的无扩展名文本源；首次访问时迁移旧 hosts.local，
# 若不存在则建立空文件。它不是 /system/etc/hosts 的 bind-mount 目标。
if [ "$spec" = hosts ]; then
  mkdir -p "$PG/local" 2>/dev/null
  if [ ! -f "$base" ] && [ -f "$PG/hosts.local" ]; then
    cp -p "$PG/hosts.local" "$base" 2>/dev/null || { echo '{"ok":0,"err":"cannot migrate local hosts"}'; exit 0; }
  fi
  if [ ! -f "$base" ]; then : > "$base" 2>/dev/null || { echo '{"ok":0,"err":"cannot create local hosts"}'; exit 0; }; chmod 600 "$base" 2>/dev/null; fi
fi

eff() {
  if [ -n "$ov" ] && [ -f "$ov" ]; then printf '%s' "$ov"; else printf '%s' "$base"; fi
}
is_override() { [ -n "$ov" ] && [ -f "$ov" ] && echo 1 || echo 0; }
ensure_dir() { [ -n "$ov" ] && mkdir -p "${ov%/*}" 2>/dev/null; }

lines_of() { awk 'END{print NR}' "$1" 2>/dev/null; }
size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }
num() { case "$1" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
strip_bom() { # 防御：前端若用带 BOM 的 UTF-8 写临时文件，去掉首部 BOM
  [ -f "$1" ] || return 0
  _m=$(od -An -tx1 -N3 "$1" 2>/dev/null | tr -d ' \n')
  if [ "$_m" = "efbbbf" ]; then
    tail -c +4 "$1" > "$1.nobom" 2>/dev/null && mv -f "$1.nobom" "$1" 2>/dev/null
  fi
}

# 写入目标：有 override 能力 → 先复制内置为副本再改；备份 .bak（只保留一份）
target_file() {
  if [ -n "$ov" ]; then
    if [ ! -f "$ov" ]; then
      ensure_dir || { echo '{"ok":0,"err":"cannot create override directory"}'; exit 0; }
      if [ -f "$base" ]; then
        cp "$base" "$ov" 2>/dev/null || { echo '{"ok":0,"err":"cannot create override"}'; exit 0; }
      elif [ "$spec" != hosts ] && [ "${spec#fx:}" != "$spec" ]; then
        # A missing bundled FX source can still be a user-owned local source.
        # Create an empty override only on explicit editor/write access; never
        # fabricate a bundled list or silently claim it contains active rules.
        (umask 077; : > "$ov") 2>/dev/null || { echo '{"ok":0,"err":"cannot create empty FX override"}'; exit 0; }
      else
        echo '{"ok":0,"err":"cannot create override: bundled source missing"}'; exit 0
      fi
      chmod 600 "$ov" 2>/dev/null
    fi
    printf '%s' "$ov"
  else
    [ -f "$base" ] || { : > "$base" 2>/dev/null; chmod 600 "$base" 2>/dev/null; }
    printf '%s' "$base"
  fi
}
# Missing bundled FX source: make the paged editor usable for a user-owned source.
# This is deliberately limited to explicit stat/page requests for fx:<id>;
# parser/runtime paths still skip missing bundled files until this user copy exists.
if [ -n "$ov" ] && [ "${spec#fx:}" != "$spec" ] && [ ! -f "$base" ] && [ ! -f "$ov" ]; then
  case "$op" in
    stat|page)
      ensure_dir || { echo '{"ok":0,"err":"cannot create FX override directory"}'; exit 0; }
      (umask 077; : > "$ov") 2>/dev/null || { echo '{"ok":0,"err":"cannot initialize empty FX override"}'; exit 0; }
      chmod 600 "$ov" 2>/dev/null
      ;;
  esac
fi

write_tmp_to() { # $1=dest $2=tmp; verified backup + same-directory atomic replace
  _w_dst="$1"; _w_src="$2"
  [ -f "$_w_src" ] || { echo '{"ok":0,"err":"tmp missing"}'; exit 0; }
  [ -f "$_w_dst" ] || { echo '{"ok":0,"err":"destination missing"}'; exit 0; }
  _w_dir=${_w_dst%/*}; [ "$_w_dir" = "$_w_dst" ] && _w_dir=.
  _w_tag=".fx-fileedit.$$.${_w_dst##*/}"
  _w_bak_tmp="$_w_dir/$_w_tag.bak.tmp"
  _w_new_tmp="$_w_dir/$_w_tag.new"
  # Never overwrite the last known-good backup until its replacement is verified.
  if ! cp -p "$_w_dst" "$_w_bak_tmp" 2>/dev/null || ! cmp -s "$_w_dst" "$_w_bak_tmp" 2>/dev/null; then
    rm -f "$_w_bak_tmp" "$_w_new_tmp" 2>/dev/null
    echo '{"ok":0,"err":"backup failed; original preserved"}'
    exit 0
  fi
  if ! cp "$_w_src" "$_w_new_tmp" 2>/dev/null || ! cmp -s "$_w_src" "$_w_new_tmp" 2>/dev/null; then
    rm -f "$_w_bak_tmp" "$_w_new_tmp" 2>/dev/null
    echo '{"ok":0,"err":"staging failed; original preserved"}'
    exit 0
  fi
  chmod 600 "$_w_new_tmp" 2>/dev/null
  # Commit verified backup first; then rename staged data over destination.
  if ! mv -f "$_w_bak_tmp" "$_w_dst.bak" 2>/dev/null; then
    rm -f "$_w_bak_tmp" "$_w_new_tmp" 2>/dev/null
    echo '{"ok":0,"err":"backup commit failed; original preserved"}'
    exit 0
  fi
  if mv -f "$_w_new_tmp" "$_w_dst" 2>/dev/null; then
    rm -f "$_w_src" 2>/dev/null
    _sz=$(num "$(size_of "$_w_dst")"); _nl=$(num "$(lines_of "$_w_dst")")
    printf '{"ok":1,"size":%s,"lines":%s,"override":%s}\n' "$_sz" "$_nl" "$(is_override)"
    exit 0
  fi
  # If the final rename fails, retain the verified .bak and attempt immediate recovery.
  if cp "$_w_dst.bak" "$_w_new_tmp" 2>/dev/null && cmp -s "$_w_dst.bak" "$_w_new_tmp" 2>/dev/null; then
    mv -f "$_w_new_tmp" "$_w_dst" 2>/dev/null
  fi
  rm -f "$_w_src" "$_w_new_tmp" 2>/dev/null
  echo '{"ok":0,"err":"write failed; verified backup retained"}'
  exit 0
}

case "$op" in
  stat)
    _f=$(eff); [ -f "$_f" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _sz=$(num "$(size_of "$_f")"); _nl=$(num "$(lines_of "$_f")")
    printf '{"ok":1,"size":%s,"lines":%s,"override":%s,"base":%s}\n' "$_sz" "$_nl" "$(is_override)" "$([ -f "$base" ] && echo 1 || echo 0)"
    exit 0 ;;
  page)
    _f=$(eff); [ -f "$_f" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _start=$(num "$3"); [ "$_start" -lt 1 ] && _start=1
    _count=$(num "$4"); [ "$_count" -lt 1 ] && _count=200; [ "$_count" -gt 400 ] && _count=400
    _maxb=$(num "$5"); [ "$_maxb" -lt 4096 ] && _maxb=65536; [ "$_maxb" -gt 262144 ] && _maxb=262144
    _total=$(num "$(lines_of "$_f")")
    _sel="$PG/cache/.fe.$$.page.sel"; _tmp="$PG/cache/.fe.$$.page"
    mkdir -p "$PG/cache" 2>/dev/null
    # Keep the selected page separate from the byte-limited response. This lets
    # the API report when maxBytes cut the payload, rather than silently
    # presenting a partial final line as a complete page.
    tail -n +"$_start" "$_f" 2>/dev/null | head -n "$_count" > "$_sel" 2>/dev/null
    _sel_sz=$(num "$(size_of "$_sel")")
    _byte_trunc=0; [ "$_sel_sz" -gt "$_maxb" ] && _byte_trunc=1
    head -c "$_maxb" "$_sel" > "$_tmp" 2>/dev/null
    _pl=$(num "$(lines_of "$_tmp")")
    _b64=$(base64 < "$_tmp" 2>/dev/null | tr -d '\n')
    rm -f "$_tmp" "$_sel" 2>/dev/null
    _trunc=0
    [ "$_pl" -ge "$_count" ] && { _next=$((_start + _pl)); [ "$_next" -le "$_total" ] && _trunc=1; }
    [ "$_byte_trunc" -eq 1 ] && _trunc=1
    printf '{"ok":1,"size":%s,"total":%s,"start":%s,"lines":%s,"trunc":%s,"byteTrunc":%s,"override":%s,"b64":"%s"}\n' \
      "$(num "$(size_of "$_f")")" "$_total" "$_start" "$_pl" "$_trunc" "$_byte_trunc" "$(is_override)" "$_b64"
    exit 0 ;;
  find)
    _f=$(eff); [ -f "$_f" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _pat="${3}"; [ -z "$_pat" ] && { echo '{"ok":0,"err":"no pattern"}'; exit 0; }
    _max=$(num "$4"); [ "$_max" -lt 1 ] && _max=100; [ "$_max" -gt 300 ] && _max=300
    _tmp="$PG/cache/.fe.$$.find"; mkdir -p "$PG/cache" 2>/dev/null
    # Distinguish a valid no-match result (grep rc=1) from malformed regex or
    # an actual read/grep error (rc>1). Previously both cases were reported as
    # a successful empty search, hiding bad patterns and inaccessible files.
    if grep -n -i -m "$_max" -- "$_pat" "$_f" > "$_tmp" 2>/dev/null; then
      _grep_rc=0
    else
      _grep_rc=$?
    fi
    if [ "$_grep_rc" -gt 1 ]; then
      rm -f "$_tmp" 2>/dev/null
      echo '{"ok":0,"err":"search failed (invalid pattern or read error)"}'
      exit 0
    fi
    _n=0; _out=""; _hit_tmp="$PG/cache/.fe.$$.hit"
    _out_bytes=0; _hits_trunc=0; _out_limit=32768
    while IFS= read -r _ln; do
      _no=${_ln%%:*}
      _tx=${_ln#*:}
      case "$_no" in ''|*[!0-9]*) continue ;; esac
      # Bound each match and the aggregate response. Search still runs against
      # full source content, but returned JSON is capped to avoid UI/OOM spikes.
      _tx_sz=$(num "$(printf '%s' "$_tx" | wc -c 2>/dev/null | tr -d ' ')")
      _remain=$((_out_limit - _out_bytes))
      [ "$_remain" -gt 0 ] || { _hits_trunc=1; break; }
      _emit_sz=$_tx_sz; _hit_cut=0
      [ "$_emit_sz" -gt 4096 ] && { _emit_sz=4096; _hit_cut=1; }
      if [ "$_emit_sz" -gt "$_remain" ]; then _emit_sz=$_remain; _hit_cut=1; _hits_trunc=1; fi
      printf '%s' "$_tx" | head -c "$_emit_sz" > "$_hit_tmp" 2>/dev/null
      _actual_sz=$(num "$(size_of "$_hit_tmp")")
      [ "$_actual_sz" -lt "$_tx_sz" ] && _hit_cut=1
      _b=$(base64 < "$_hit_tmp" 2>/dev/null | tr -d '\n')
      _n=$((_n+1)); _out_bytes=$((_out_bytes + _actual_sz))
      _out="$_out${_out:+,}{\"n\":$_no,\"t\":\"$_b\",\"cut\":$_hit_cut}"
      [ "$_hits_trunc" -eq 1 ] && break
    done < "$_tmp"
    rm -f "$_tmp" "$_hit_tmp" 2>/dev/null
    printf '{"ok":1,"total":%s,"hitsTrunc":%s,"hits":[%s]}\n' "$_n" "$_hits_trunc" "$_out"
    exit 0 ;;
  edit)
    _n=$(num "$3"); [ "$_n" -lt 1 ] && { echo '{"ok":0,"err":"bad line"}'; exit 0; }
    _src="$4"; [ -f "$_src" ] || { echo '{"ok":0,"err":"tmp missing"}'; exit 0; }
    strip_bom "$_src"
    # Validate against the effective file before creating a user override.
    _cur=$(eff); [ -f "$_cur" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _total=$(num "$(lines_of "$_cur")")
    [ "$_n" -le "$_total" ] || { echo '{"ok":0,"err":"line out of range"}'; exit 0; }
    # Transform from the effective source first; do not create an override until
    # the transformation has succeeded.
    _tmp="$PG/cache/.fe.$$.edit"; mkdir -p "$PG/cache" 2>/dev/null
    if ! awk -v n="$_n" -v repl="$_src" '
      BEGIN { rn=0; while((getline l < repl)>0) { rep[++rn]=l } }
      NR==n {
        if (rn==0) print ""; else for(i=1;i<=rn;i++) print rep[i]
        next
      }
      { print }
    ' "$_cur" > "$_tmp" 2>/dev/null; then
      rm -f "$_tmp" 2>/dev/null
      echo '{"ok":0,"err":"edit transform failed; original preserved"}'
      exit 0
    fi
    _dst=$(target_file)
    write_tmp_to "$_dst" "$_tmp" ;;
  del)
    _n=$(num "$3"); [ "$_n" -lt 1 ] && { echo '{"ok":0,"err":"bad line"}'; exit 0; }
    # Validate against the effective file before creating a user override.
    _cur=$(eff); [ -f "$_cur" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _total=$(num "$(lines_of "$_cur")")
    [ "$_n" -le "$_total" ] || { echo '{"ok":0,"err":"line out of range"}'; exit 0; }
    # Transform the effective source before target_file() can create an override.
    _tmp="$PG/cache/.fe.$$.del"; mkdir -p "$PG/cache" 2>/dev/null
    if ! awk -v n="$_n" 'NR!=n { print }' "$_cur" > "$_tmp" 2>/dev/null; then
      rm -f "$_tmp" 2>/dev/null
      echo '{"ok":0,"err":"delete transform failed; original preserved"}'
      exit 0
    fi
    _dst=$(target_file)
    write_tmp_to "$_dst" "$_tmp" ;;
  ins)
    # Validate against the effective file before target_file() creates an override.
    # Accepted positions are 0 (prepend) through total+1 (append).
    case "$3" in ''|*[!0-9]*) echo '{"ok":0,"err":"bad line"}'; exit 0 ;; esac
    _n="$3"
    _src="$4"; [ -f "$_src" ] || { echo '{"ok":0,"err":"tmp missing"}'; exit 0; }
    strip_bom "$_src"
    _cur=$(eff); [ -f "$_cur" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _total=$(num "$(lines_of "$_cur")")
    _max=$((_total + 1))
    [ "$_n" -le "$_max" ] || { echo '{"ok":0,"err":"line out of range"}'; exit 0; }
    # Build the candidate from the effective source before creating an override.
    _tmp="$PG/cache/.fe.$$.ins"; mkdir -p "$PG/cache" 2>/dev/null
    if ! awk -v n="$_n" -v repl="$_src" '
      BEGIN { rn=0; while((getline l < repl)>0) { rep[++rn]=l } }
      NR==1 && n<=0 { for(i=1;i<=rn;i++) print rep[i] }
      NR==n && n>0 { for(i=1;i<=rn;i++) print rep[i] }
      { print }
      END { if (n>NR || (NR==0 && n<=0)) for(i=1;i<=rn;i++) print rep[i] }
    ' "$_cur" > "$_tmp" 2>/dev/null; then
      rm -f "$_tmp" 2>/dev/null
      echo '{"ok":0,"err":"insert transform failed; original preserved"}'
      exit 0
    fi
    _dst=$(target_file)
    write_tmp_to "$_dst" "$_tmp" ;;
  put)
    _src="$3"; [ -f "$_src" ] || { echo '{"ok":0,"err":"tmp missing"}'; exit 0; }
    strip_bom "$_src"
    _sz=$(num "$(size_of "$_src")"); [ "$_sz" -gt 16777216 ] && { echo '{"ok":0,"err":"too large"}'; exit 0; }
    _dst=$(target_file)
    cp "$_src" "$PG/cache/.fe.$$.put" 2>/dev/null || { echo '{"ok":0,"err":"copy failed"}'; exit 0; }
    write_tmp_to "$_dst" "$PG/cache/.fe.$$.put" ;;
  replacepage)
    _start=$(num "$3"); _count=$(num "$4"); _src="$5"
    [ "$_start" -ge 1 ] || { echo '{"ok":0,"err":"bad page start"}'; exit 0; }
    [ "$_count" -le 400 ] || { echo '{"ok":0,"err":"page too large"}'; exit 0; }
    [ -f "$_src" ] || { echo '{"ok":0,"err":"tmp missing"}'; exit 0; }
    strip_bom "$_src"
    _cur=$(eff); [ -f "$_cur" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _total=$(num "$(lines_of "$_cur")")
    [ "$_start" -le $((_total + 1)) ] || { echo '{"ok":0,"err":"page start out of range"}'; exit 0; }
    [ "$((_start + _count - 1))" -le "$_total" ] || { [ "$_count" -eq 0 ] || { echo '{"ok":0,"err":"page range changed; reload before saving"}'; exit 0; }; }
    _tmp="$PG/cache/.fe.$$.replacepage"; mkdir -p "$PG/cache" 2>/dev/null
    if ! awk -v start="$_start" -v count="$_count" -v repl="$_src" '
      BEGIN { rn=0; while((getline l < repl)>0) rep[++rn]=l }
      NR < start { print; next }
      NR == start { for(i=1;i<=rn;i++) print rep[i]; next }
      NR < start + count { next }
      { print }
      END { if(start > NR) for(i=1;i<=rn;i++) print rep[i] }
    ' "$_cur" > "$_tmp" 2>/dev/null; then
      rm -f "$_tmp" 2>/dev/null
      echo '{"ok":0,"err":"page transform failed; original preserved"}'
      exit 0
    fi
    _dst=$(target_file)
    write_tmp_to "$_dst" "$_tmp" ;;
  cat)
    _f=$(eff); [ -f "$_f" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    _sz=$(num "$(size_of "$_f")"); [ "$_sz" -gt 307200 ] && { echo '{"ok":0,"err":"too large for cat","size":'"$_sz"'}'; exit 0; }
    _b64=$(base64 < "$_f" 2>/dev/null | tr -d '\n')
    printf '{"ok":1,"size":%s,"lines":%s,"override":%s,"b64":"%s"}\n' "$_sz" "$(num "$(lines_of "$_f")")" "$(is_override)" "$_b64"
    exit 0 ;;
  reset)
    [ -z "$ov" ] && { echo '{"ok":0,"err":"not overridable"}'; exit 0; }
    rm -f "$ov" 2>/dev/null
    _nl=$(num "$(lines_of "$base")")
    printf '{"ok":1,"lines":%s,"override":0}\n' "$_nl"
    exit 0 ;;
  export)
    _f=$(eff); [ -f "$_f" ] || { echo '{"ok":0,"err":"missing"}'; exit 0; }
    mkdir -p /sdcard/Download/FX-External 2>/dev/null || { echo '{"ok":0,"err":"cannot create external workspace"}'; exit 0; }
    _safe_name=$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_.-')
    [ -n "$_safe_name" ] || _safe_name=rules.txt
    _ext="/sdcard/Download/FX-External/${_safe_name}"
    _base_hash=$(sha256sum "$_f" 2>/dev/null | awk '{print $1}')
    [ -n "$_base_hash" ] || { echo '{"ok":0,"err":"cannot fingerprint source"}'; exit 0; }
    _copy_tmp="${_ext}.fx-tmp.$$"
    if cp "$_f" "$_copy_tmp" 2>/dev/null && cmp -s "$_f" "$_copy_tmp" 2>/dev/null && mv -f "$_copy_tmp" "$_ext" 2>/dev/null; then
      chmod 600 "$_ext" 2>/dev/null
      printf '{"ok":1,"path":"%s","baseHash":"%s","size":%s}\n' "$_ext" "$_base_hash" "$(num "$(size_of "$_ext")")"
    else
      rm -f "$_copy_tmp" 2>/dev/null
      echo '{"ok":0,"err":"export failed; source preserved"}'
    fi
    exit 0 ;;
  import-external)
    _ext="$3"; _expected="$4"
    case "$_ext" in /sdcard/Download/FX-External/*) ;; *) echo '{"ok":0,"err":"external path rejected"}'; exit 0 ;; esac
    _ext_rel=${_ext#/sdcard/Download/FX-External/}
    case "$_ext_rel" in ''|*/*|*..*) echo '{"ok":0,"err":"external path rejected"}'; exit 0 ;; esac
    case "$_expected" in ''|*[!0-9a-fA-F]*) echo '{"ok":0,"err":"bad source fingerprint"}'; exit 0 ;; esac
    [ -f "$_ext" ] && [ ! -L "$_ext" ] || { echo '{"ok":0,"err":"external file missing or unsafe"}'; exit 0; }
    _dst=$(eff); [ -f "$_dst" ] || { echo '{"ok":0,"err":"active source missing"}'; exit 0; }
    _current=$(sha256sum "$_dst" 2>/dev/null | awk '{print $1}')
    [ "$_current" = "$_expected" ] || { echo '{"ok":0,"err":"source changed in FX; external import blocked to prevent overwrite conflict"}'; exit 0; }
    _ext_size=$(num "$(size_of "$_ext")")
    [ "$_ext_size" -le 16777216 ] || { echo '{"ok":0,"err":"external file exceeds 16MB limit"}'; exit 0; }
    _tmp="$PG/cache/.fe.$$.external"
    mkdir -p "$PG/cache" 2>/dev/null
    cp "$_ext" "$_tmp" 2>/dev/null && cmp -s "$_ext" "$_tmp" 2>/dev/null || { rm -f "$_tmp"; echo '{"ok":0,"err":"external copy verification failed"}'; exit 0; }
    _dst=$(target_file)
    write_tmp_to "$_dst" "$_tmp" ;;
  *)
    echo '{"ok":0,"err":"bad op"}' ;;
esac
