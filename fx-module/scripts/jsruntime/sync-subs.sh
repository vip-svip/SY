#!/system/bin/sh
# Synchronize explicitly enabled JS subscription URLs into the MITM hook directory.
# Activate explicit FX metadata or supported HTTP(S) @match/@include/@url URL globs.
set -u
_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory not found"}' >&2; exit 2; }
. "$MODDIR/scripts/util.sh"
DEST="$PG/jsruntime/scripts"
mkdir -p "$DEST" "$PG/jsruntime" || exit 1
chmod 700 "$PG/jsruntime" "$DEST" 2>/dev/null || :

# A sync owns the complete active-script snapshot, including stale-file cleanup.
# Without a lock, concurrent manual refreshes / engine starts / the scheduler can
# delete each other's newly installed files or race on the same target + sidecar.
LOCK="$PG/jsruntime/sync-subs.lock"
umask 077
acquire_lock() {
  _tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    _owner=$(cat "$LOCK/pid" 2>/dev/null || true)
    case "$_owner" in
      ''|*[!0-9]*)
        # Give an owner time to publish its PID after mkdir before treating a
        # lock with a missing PID as stale.
        if [ "$_tries" -ge 30 ]; then
          _stale="$LOCK.stale.$$"
          if mv "$LOCK" "$_stale" 2>/dev/null; then rm -rf "$_stale"; fi
        else
          _tries=$((_tries + 1)); sleep 0.1
        fi
        ;;
      *)
        if kill -0 "$_owner" 2>/dev/null; then
          [ "$_tries" -lt 600 ] || return 1
          _tries=$((_tries + 1)); sleep 0.1
        else
          _stale="$LOCK.stale.$$"
          if mv "$LOCK" "$_stale" 2>/dev/null; then rm -rf "$_stale"; fi
        fi
        ;;
    esac
  done
  if ! printf '%s\n' "$$" > "$LOCK/pid"; then
    rmdir "$LOCK" 2>/dev/null || :
    return 1
  fi
  return 0
}
release_lock() {
  _owner=$(cat "$LOCK/pid" 2>/dev/null || true)
  [ "$_owner" = "$$" ] || return 0
  rm -f "$LOCK/pid" 2>/dev/null || :
  rmdir "$LOCK" 2>/dev/null || :
}
if ! acquire_lock; then
  printf '{"ok":false,"busy":true,"error":"another script subscription sync is still running"}\n'
  exit 75
fi
ACTIVE="$DEST/.active.$$"
: > "$ACTIVE" || { release_lock; exit 1; }
cleanup() { rm -f "$ACTIVE" "$DEST/.fetch.$$" "$DEST/.wrap.$$" "$DEST"/*.previous.$$ 2>/dev/null; release_lock; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
fetch_script_https() {
  # Scripts execute with module privileges; require curl so HTTPS redirects can be pinned.
  command -v curl >/dev/null 2>&1 || { pg_log "js-sub: curl required for HTTPS-only script downloads; refusing wget redirect downgrade risk"; return 1; }
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 6 --max-time 15 --max-filesize 1048576 -o "$2" "$1" 2>>"$PG/apply.log"
}
ok=0; skipped=0; failed=0
while IFS='|' read -r url note enabled; do
  case "$url" in ''|\#*) continue ;; esac
  [ "$enabled" = 1 ] || continue
  case "$url" in
    https://*) ;;
    http://*) pg_log "js-sub: refused insecure HTTP subscription: [subscription URL redacted]"; skipped=$((skipped+1)); continue ;;
    *) continue ;;
  esac
  # A module may reuse one script URL for many distinct request/response patterns.
  # Include trigger metadata in the cache key so each wrapper gets its own file;
  # URL-only keys caused later declarations to overwrite earlier hook metadata.
  key=$(printf '%s
%s' "$url" "$note" | cksum 2>/dev/null | awk '{print $1}')
  case "$key" in ''|*[!0-9]*) failed=$((failed+1)); continue ;; esac
  name="pgsub_${key}.js"
  printf '%s\n' "$name" >> "$ACTIVE"
  tmp="$DEST/.fetch.$$"
  if ! fetch_script_https "$url" "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    pg_log "js-sub: fetch failed; preserving last known good script $name"
    failed=$((failed+1)); continue
  fi
  size=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt 1048576 ] || [ "$size" -lt 16 ]; then
    rm -f "$tmp"; pg_log "js-sub: rejected invalid size for [subscription URL redacted] ($size bytes)"; failed=$((failed+1)); continue
  fi
  case "$note" in
    FXMETA_B64:*)
      meta=$(printf '%s' "${note#FXMETA_B64:}" | base64 -d 2>/dev/null) || meta=''
      meta_type=$(printf '%s\n' "$meta" | sed -n '1p')
      meta_match=$(printf '%s\n' "$meta" | sed -n '2p')
      meta_requires_body=$(printf '%s\n' "$meta" | sed -n '3p')
      meta_display_name=$(printf '%s\n' "$meta" | sed -n '4p')
      meta_env_json=$(printf '%s\n' "$meta" | sed -n '5p')
      meta_argument=$(printf '%s\n' "$meta" | sed -n '6p')
      meta_extra=$(printf '%s\n' "$meta" | sed -n '7,$p')
      case "$meta_type" in request|response|both) ;; *) meta_type='' ;; esac
      case "$meta_match" in ''|*"$(printf '\r')"*) meta_match='' ;; esac
      case "$meta_requires_body" in ''|0) meta_requires_body=0 ;; 1) ;; *) meta_requires_body='' ;; esac
      case "$meta_display_name" in *"$(printf '\r')"*) meta_display_name='' ;; esac
      meta_name_length=$(printf '%s' "$meta_display_name" | wc -c | tr -d ' ')
      case "$meta_name_length" in ''|*[!0-9]*) meta_display_name='' ;; esac
      [ "$meta_name_length" -le 512 ] 2>/dev/null || meta_display_name=''
      case "$meta_env_json" in *"$(printf '\r')"*) meta_env_json='' ;; esac
      meta_env_length=$(printf '%s' "$meta_env_json" | wc -c | tr -d ' ')
      case "$meta_env_length" in ''|*[!0-9]*) meta_env_json='' ;; esac
      if [ "$meta_env_length" -gt 2048 ] 2>/dev/null; then meta_env_json=''; fi
      if [ -n "$meta_env_json" ]; then
        case "$meta_env_json" in \{*\}) ;; *) meta_env_json='' ;; esac
      fi
      meta_argument_invalid=0
      meta_argument_length=$(printf '%s' "$meta_argument" | wc -c | tr -d ' ')
      case "$meta_argument_length" in ''|*[!0-9]*) meta_argument_invalid=1 ;; esac
      [ "$meta_argument_length" -le 512 ] 2>/dev/null || meta_argument_invalid=1
      case "$meta_argument" in *"$(printf '\r')"*) meta_argument_invalid=1 ;; esac
      if printf '%s' "$meta_argument" | LC_ALL=C grep -q '[[:cntrl:]]'; then meta_argument_invalid=1; fi
      [ -z "$meta_extra" ] || meta_argument_invalid=1
      # Stash's per-script argument is carried as field 6. Strip control bytes
      # before writing a source header so metadata cannot inject extra directives.
      meta_argument=$(printf '%s' "$meta_argument" | tr '\r\n' '  ' | sed 's/[[:cntrl:]]/ /g')
      meta_argument_length=$(printf '%s' "$meta_argument" | wc -c | tr -d ' ')
      case "$meta_argument_length" in ''|*[!0-9]*) meta_argument='' ;; esac
      [ "$meta_argument_length" -le 512 ] 2>/dev/null || meta_argument=''
      if [ -z "$meta_type" ] || [ -z "$meta_match" ] || [ -z "$meta_requires_body" ] || [ "$meta_argument_invalid" -eq 1 ]; then
        rm -f "$tmp"; pg_log "js-sub: invalid encoded trigger metadata for [subscription URL redacted]"; failed=$((failed+1)); continue
      fi
      wrapped="$DEST/.wrap.$$"
      if ! {
        printf '// FX-SCRIPT-TYPE: %s\n// FX-SCRIPT-MATCH: %s\n' "$meta_type" "$meta_match"
        if [ "$meta_requires_body" = 1 ]; then printf '// FX-SCRIPT-REQUIRES-BODY: 1\n'; fi
        if [ -n "$meta_display_name" ]; then printf '// FX-SCRIPT-NAME: %s\n' "$meta_display_name"; fi
        if [ -n "$meta_env_json" ]; then printf '// FX-SCRIPT-ENV-JSON: %s\n' "$meta_env_json"; fi
        if [ -n "$meta_argument" ]; then printf '// FX-SCRIPT-ARGUMENT: %s\n' "$meta_argument"; fi
        cat "$tmp"
      } > "$wrapped"; then
        rm -f "$tmp" "$wrapped"; failed=$((failed+1)); continue
      fi
      mv -f "$wrapped" "$tmp" || { rm -f "$tmp" "$wrapped"; failed=$((failed+1)); continue; }
      ;;
  esac
  _head=$(head -c 8192 "$tmp")
  explicit=$(printf '%s\n' "$_head" | grep -Eiq '^//[[:space:]]*FX-SCRIPT-TYPE:[[:space:]]*(request|response|both)[[:space:]]*$' && printf '%s\n' "$_head" | grep -Eiq '^//[[:space:]]*FX-SCRIPT-MATCH:[[:space:]]*[^[:space:]].*' && echo yes || echo no)
  if [ "$explicit" != yes ]; then
    # Also accept conventional userscript @match/@include/@url URL metadata.
    # The Go engine translates these URL globs conservatively; no arbitrary
    # regex or non-HTTP include syntax is activated.
    has_glob=$(printf '%s\n' "$_head" | grep -Eiq '^//[[:space:]]*@(match|include|url)[[:space:]]+https?://' && echo yes || echo no)
    has_type=$(printf '%s\n' "$_head" | grep -Eiq '^//[[:space:]]*FX-SCRIPT-TYPE:[[:space:]]*(request|response|both)[[:space:]]*$' && echo yes || echo no)
    if [ "$has_glob" != yes ]; then
      rm -f "$tmp"; pg_log "js-sub: rejected script without supported FX or userscript URL metadata: [subscription URL redacted]"; skipped=$((skipped+1)); continue
    fi
    if [ "$has_type" != yes ]; then
      wrapped="$DEST/.wrap.$$"
      if ! { printf '// FX-SCRIPT-TYPE: both\n'; cat "$tmp"; } > "$wrapped"; then
        rm -f "$tmp" "$wrapped"; failed=$((failed+1)); continue
      fi
      mv -f "$wrapped" "$tmp" || { rm -f "$tmp" "$wrapped"; failed=$((failed+1)); continue; }
    fi
  fi
  size=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt 1048576 ]; then rm -f "$tmp"; pg_log "js-sub: metadata-wrapped script exceeds 1 MiB: [subscription URL redacted]"; failed=$((failed+1)); continue; fi
  # SHA-256 records the exact accepted bytes; verify the committed file before reporting success.
  hashline=$(sha256sum "$tmp" 2>/dev/null) || { rm -f "$tmp"; failed=$((failed+1)); continue; }
  hash=${hashline%% *}
  case "$hash" in *[!0-9a-fA-F]*|'') rm -f "$tmp"; failed=$((failed+1)); continue ;; esac
  target="$DEST/$name"
  backup="$target.previous.$$"
  sidebackup="$target.sha256.previous.$$"
  had_old=0; had_side=0
  if [ -f "$target" ]; then cp -p "$target" "$backup" || { rm -f "$tmp"; failed=$((failed+1)); continue; }; had_old=1; fi
  if [ -f "$target.sha256" ]; then cp -p "$target.sha256" "$sidebackup" || { rm -f "$tmp" "$backup"; failed=$((failed+1)); continue; }; had_side=1; fi
  if ! mv -f "$tmp" "$target"; then rm -f "$tmp" "$backup" "$sidebackup"; failed=$((failed+1)); continue; fi
  chmod 600 "$target" 2>/dev/null || :
  gotline=$(sha256sum "$target" 2>/dev/null) || gotline=''
  got=${gotline%% *}
  if [ "$got" != "$hash" ]; then
    if [ "$had_old" -eq 1 ] && [ -f "$backup" ]; then mv -f "$backup" "$target"; else rm -f "$target"; fi
    if [ "$had_side" -eq 1 ] && [ -f "$sidebackup" ]; then mv -f "$sidebackup" "$target.sha256"; else rm -f "$target.sha256"; fi
    pg_log "js-sub: SHA-256 post-commit verification failed for $name; rolled back to last-known-good script"
    failed=$((failed+1)); continue
  fi
  if ! printf '%s  %s\n' "$hash" "$name" > "$target.sha256.tmp" || ! mv -f "$target.sha256.tmp" "$target.sha256"; then
    rm -f "$target.sha256.tmp"
    if [ "$had_old" -eq 1 ] && [ -f "$backup" ]; then mv -f "$backup" "$target"; else rm -f "$target"; fi
    if [ "$had_side" -eq 1 ] && [ -f "$sidebackup" ]; then mv -f "$sidebackup" "$target.sha256"; else rm -f "$target.sha256"; fi
    failed=$((failed+1)); continue
  fi
  rm -f "$backup" "$sidebackup"
  chmod 600 "$target.sha256" 2>/dev/null || :
  ok=$((ok+1))
  pg_log "js-sub: installed $name sha256=$hash"
done <<EOF_LIST
$(pg_list script)
EOF_LIST
# Remove only files owned by this synchronizer when their subscription is no longer enabled.
for f in "$DEST"/pgsub_*.js; do
  [ -f "$f" ] || continue
  base=${f##*/}
  if ! grep -Fxq "$base" "$ACTIVE"; then rm -f "$f" "$f.sha256"; pg_log "js-sub: removed disabled subscription $base"; fi
done
printf '{"ok":%s,"installed":%s,"skipped":%s,"failed":%s}\n' "$([ "$failed" -eq 0 ] && echo true || echo false)" "$ok" "$skipped" "$failed"
[ "$failed" -eq 0 ]
