#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'save.setOnClickListener(v -> {' "$UI" || fail "native Hook save action missing"
grep -Fq 'publishConfig();' "$UI" || fail "native Hook save does not use the single publisher"
grep -Fq 'private void publishConfig()' "$UI" || fail "native Hook publisher missing"
grep -Fq 'if (hookPublisherThread != null && hookPublisherThread.isAlive())' "$UI" || fail "duplicate concurrent publishes are not rejected"
grep -Fq 'Thread publisher = new Thread(() -> {' "$UI" || fail "native Hook publication is not off the UI thread"
echo "PASS: per-app Hook actions use a single persistence/apply pipeline"
