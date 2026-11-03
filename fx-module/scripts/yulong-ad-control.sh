#!/system/bin/sh
# Native Yulong AdBlock 7.0.1 control backend, hosted by the FX KernelSU module.
# It uses FX's existing settings.conf and apply pipeline; it never starts VpnService.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
MP=${SCRIPT_DIR%/scripts}
PG=/data/adb/privacyguard
CONF=$PG/settings.conf
[ -s "$MP/module.prop" ] && [ -s "$MP/scripts/util.sh" ] || { echo "FX module files are missing" >&2; exit 20; }
mkdir -p "$PG"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf is missing or unsafe" >&2; exit 22; }
. "$MP/scripts/util.sh"

valid_state() { [ "$1" = 0 ] || [ "$1" = 1 ]; }
valid_text() {
  max=512; [ "$#" -lt 2 ] || max=$2
  case "$1" in *'|'*) return 1 ;; esac
  size=$(printf '%s' "$1" | wc -c | tr -d ' ')
  [ "$size" -le "$max" ] || return 1
  ! printf '%s' "$1" | grep -q '[[:cntrl:]]'
}
valid_ipv4() {
  printf '%s\n' "$1" | awk -F. 'NF!=4{ok=0;exit}{ok=1;for(i=1;i<=4;i++)if($i!~/^[0-9]+$/||length($i)>3||($i+0)>255)ok=0}END{exit(ok?0:1)}'
}
valid_domain() {
  size=$(printf '%s' "$1" | wc -c | tr -d ' '); [ "$size" -le 253 ] || return 1
  printf '%s\n' "$1" | grep -Eqi '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' || return 1
  case "$1" in *..*|.*|*.) return 1 ;; esac
}
apply_fast() { sh "$MP/scripts/apply.sh" fast >> "$PG/boot.log" 2>&1; }
read_vpn_value() { pg_conf vpn | awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1);exit}'; }

rewrite_section() {
  kind=$1; name=$2; body_file=$3
  [ -f "$body_file" ] || return 1
  body=$(cat "$body_file")
  tmp="$CONF.yulong-ad-section.$$"
  awk -v target="[$kind:$name]" -v body="$body" '
    BEGIN{n=split(body,lines,"\n");inside=0;written=0}
    $0==target{if(!written){print;for(i=1;i<=n;i++)if(lines[i]!="")print lines[i];written=1}inside=1;next}
    /^\[/âžÈ{H§²'^ìm¦¸§´CC‰ü+ŠÛ^žšâžÚkŠ{mj¸µú+‹X