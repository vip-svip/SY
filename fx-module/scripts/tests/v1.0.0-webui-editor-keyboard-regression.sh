#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/webroot/index.html"
grep -Fq 'visualViewport.addEventListener(' "$H"
grep -Fq "root.classList.toggle('pg-keyboard-open',opened)" "$H"
grep -Fq "root.style.setProperty('--pg-keyboard-shift','0px')" "$H"
grep -Fq "nav.setAttribute('aria-hidden','false')" "$H"
grep -Fq "style.pointerEvents='auto'" "$H"
grep -Fq 'var timeout=new Promise(function(resolve){timer=setTimeout(function(){resolve({ok:false,err:lt(' "$H"
grep -Fq 'id="feRetryLoad"' "$H"
grep -Fq 'function feLoad(page)' "$H"
echo 'FX 1.0.0 editor loading / keyboard-nav regression: PASS'
