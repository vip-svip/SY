#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
H="$ROOT/scripts/jsruntime/host.js"
node --check "$H"
# Ensure vendor identifiers are selected from event configuration rather than
# falsely claiming that all clients are present simultaneously.
grep -Fq "_fxEvent.compatPlatform||_fxEvent.platform||'fx'" "$H"
grep -Fq "if(_fxIsSurge) globalThis.\$environment['surge-version']" "$H"
grep -Fq "if(_fxIsLoon) globalThis.\$environment['loon-version']" "$H"
grep -Fq "if(_fxIsStash) globalThis.\$environment['stash-version']" "$H"
grep -Fq "if(_fxIsQuanX) globalThis.\$environment['quantumult-x-version']" "$H"
! grep -Fq "globalThis.\$environment['surge-version']='FX-1.0.0'" "$H"
! grep -Fq "globalThis.\$environment['quantumult-x-version']='FX-1.0.0'" "$H"
echo 'FX compatibility profile regression: PASS'
