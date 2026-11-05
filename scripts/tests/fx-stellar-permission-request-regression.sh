#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/StellarPermissionRequestActivity.java"
SERVICE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/StellarAuthorizationService.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ACTIVITY" ] && [ -s "$SERVICE" ] || fail "Stellar permission confirmation sources missing"
python3 - "$ACTIVITY" "$SERVICE" "$MANIFEST" <<'PY'
from pathlib import Path
import sys
activity, service, manifest = (Path(p).read_text(encoding="utf-8") for p in sys.argv[1:])
assert 'value.replace("\\r", "").replace("\\n", " ")' in activity, "request text must remove CR and flatten line feeds"
assert 'value.replace("\\\\r", "").replace("\\\\n", " ")' not in activity, "request text must not search for literal backslash sequences"
assert 'label + "\\n" + sourcePackage' not in activity, "package identity card must render an actual line break"
assert 'permission + "\\n请求代码' not in activity, "permission details card must render an actual line break"
for token in ('getIntExtra("uid", -1)', 'getIntExtra("pid", -1)',
              'getIntExtra("requestCode", -1)', 'getStringExtra("sourcePackage")',
              'getStringExtra("permission")', 'replyMessenger.send(response)',
              'setResult(RESULT_OK, resultIntent)', 'RESPONSE_TIMEOUT_MS = 30000L',
              'if (!replied.compareAndSet(false, true)) return;'):
    assert token in activity, f"permission confirmation contract missing: {token}"
for key in ("stellar:request-permission-reply-allowed",
            "stellar:request-permission-reply-is-onetime",
            "stellar:request-permission-reply-permission"):
    assert key in activity and key in service, f"original permission reply key missing: {key}"
assert "packageBelongsToUid(sourcePackage, uid)" in service
assert "getPackagesForUid(uid)" in service
assert "POST_NOTIFICATIONS" in service and "NotificationManager.IMPORTANCE_HIGH" in service
assert "new ProcessBuilder" not in activity and "RootAccess.execute" not in activity,     "permission confirmation UI must not execute Shell or directly grant the permission"
assert "onBackPressed()" in activity and 'reply(false, true' in activity
assert "onDestroy()" in activity and "已默认拒绝" in activity
assert "MSG_PERMISSION_REQUEST = 5" in service and "MSG_PERMISSION_RESULT = 6" in service
assert "ACTION_COMMAND_GUARD" in service or "MSG_PERMISSION_REQUEST" in service
assert 'android:name="com.youlong.hd.intent.action.REQUEST_PERMISSION"' in manifest
print("PASS: Stellar permission request validates UID/package, preserves original reply Bundle, defaults to denial, and uses protected Messenger/Activity callbacks")
PY
