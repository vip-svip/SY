#!/system/bin/sh
# Local core port remains freely configurable but uses numeric input hints and strict range validation.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
grep -Fq "if(cfg.key==='local_port'){bodyEl.setAttribute('inputmode','numeric');bodyEl.setAttribute('maxlength','5')" "$HTML"
grep -Fq "! /^[0-9]{1,5}$/.test(port)" "$HTML" 2>/dev/null && exit 1 || true
grep -Fq "if(!/^[0-9]{1,5}$/.test(port)||Number(port)<1||Number(port)>65535)" "$HTML"
grep -Fq "secSet(cfg.sec,cfg.key,String(Number(port)))" "$HTML"
grep -Fq "removeAttribute('inputmode')" "$HTML"
echo 'PASS: local port numeric input hints, 1..65535 validation, normalized persistence, and editor cleanup'
