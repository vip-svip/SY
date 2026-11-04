#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarManagerActivity.java"
SERVICE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/StellarAuthorizationService.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
ROOT_ACCESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java"
[ -s "$SOURCE" ] || { echo "FAIL: Stellar manager Activity source missing" >&2; exit 1; }
python3 - "$SOURCE" "$SERVICE" "$MANIFEST" "$ROOT_ACCESS" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

root_start = source.index("private void root(")
root_end = source.index("private String appLabel", root_start)
root = source[root_start:root_end]
assert "MAX_PENDING_ROOT_REQUESTS = 16" in source, "Activity request queue must stay bounded"
assert "rootQueue.size()+rootCallbacks.size()>=MAX_PENDING_ROOT_REQUESTS" in root, "Activity must reject excess pending Root requests"
assert "RootAccess.failure(75," in root, "queue saturation must be surfaced as an explicit failure result"
assert "flushRootRequests();" in root, "accepted requests must be forwarded to the private Binder queue"


load_start = source.index("private void loadApplications()")
load_end = source.index("private void updateTargetLabel()", load_start)
load = source[load_start:load_end]
assert "worker.execute(()->{" in load, "application inventory must run on the background worker"
assert "getInstalledApplications(0)" in load, "installed application inventory must not be replaced by a stub"
assert "loaded.sort(Comparator.comparing" in load, "application label sorting must remain available"
assert "runOnUiThread(()->{" in load, "application inventory may only update views on the UI thread"

create_start = source.index("@Override protected void onCreate")
create_end = source.index("private void render()", create_start)
create = source[create_start:create_end]
assert "getInstalledApplications" not in create, "onCreate must not enumerate packages on the main thread"
assert "loadApplications();" in create, "onCreate must schedule asynchronous inventory loading"
assert 'saved.getString("stellar_target_package","")' in create, "selected target package must be restored"

save_start = source.index("protected void onSaveInstanceState")
save_end = source.index("private void render()", save_start)
save = source[save_start:save_end]
assert 'out.putString("stellar_target_package",target)' in save, "selected target package must survive Activity recreation"
assert "worker.shutdownNow()" in source, "worker must be stopped with Activity lifecycle"
assert 'addSwitch("安全设置写入（高权限）","SECURE_SETTINGS_WRITE",true);' in source, \
       "SECURE_SETTINGS_WRITE has no user-accessible high-privilege grant switch"
secure_card = source.split('addCard("安全设置写入"', 1)[1].split('addCard("AppOps 管理"', 1)[0]
assert "SECURE_SETTINGS_WRITE" in secure_card and 'confirmManaged("secure-setting ' in secure_card, \
       "secure-setting actions must require the dedicated scope and explicit confirmation"

service = Path(sys.argv[2]).read_text(encoding="utf-8")
manifest = Path(sys.argv[3]).read_text(encoding="utf-8")
root_access = Path(sys.argv[4]).read_text(encoding="utf-8")
create_start = source.index("@Override protected void onCreate")
create_end = source.index("private void render()", create_start)
create = source[create_start:create_end]
assert "bindService(" in create and "Context.BIND_AUTO_CREATE" in create, "Activity must bind the private Binder service"
assert "StellarAuthorizationService.MSG_HELLO" in source, "Activity must negotiate Binder protocol"
assert "StellarAuthorizationService.MSG_EXECUTE" in source and "StellarAuthorizationService.MSG_RESULT" in source, "request and response messages must be distinct"
assert "rootCallbacks.remove(id)" in source, "responses must resolve the matching pending callback"
assert "unbindService(stellarConnection)" in source, "Activity must unbind with its lifecycle"
assert "RootAccess.execute(" not in source, "Activity must not bypass Binder and invoke Root directly"
assert "extends Service" in service and "new Messenger(incoming)" in service, "transport must be a real Android Messenger Binder service"
assert "new ArrayBlockingQueue<>(16)" in service, "Binder command queue must be bounded"
assert "commands.execute(" in service and "RootAccess.execute(" in service, "service must execute asynchronously and return actual backend results"
assert "MAX_SHELL_ARGS = 8192" in service and "OUTPUT_LIMIT = 256 * 1024" in service, "Binder request/output sizes must be capped"
assert "KEY_EXIT_CODE" in service and "KEY_OUTPUT" in service and "KEY_DENIED" in service, "response must preserve result metadata"

assert "MSG_PERMISSION_REQUEST = 5" in service and "MSG_PERMISSION_RESULT = 6" in service
assert "handlePermissionRequest(message)" in service
assert "getPackagesForUid(uid)" in service and "packageBelongsToUid(sourcePackage, uid)" in service
assert "POST_NOTIFICATIONS" in service and "NotificationManager.IMPORTANCE_HIGH" in service
assert "Notification.CATEGORY_PERMISSION" not in service, "Android has no CATEGORY_PERMISSION constant; permission prompt must use supported notification metadata"
assert '.setContentTitle("应用请求 Stellar 权限")' in service and ".setContentIntent(content)" in service, "permission request notification must retain its title and decision action"
for key in ("REPLY_ALLOWED", "REPLY_ONE_TIME", "REPLY_PERMISSION"):
    assert key in service, f"original permission response Bundle key missing: {key}"
assert 'android:name="roro.stellar.manager.authorization.StellarPermissionRequestActivity"' in manifest
permission_activity = manifest.split('android:name="roro.stellar.manager.authorization.StellarPermissionRequestActivity"',1)[1].split("</activity>",1)[0]
assert 'android:exported="true"' in permission_activity
assert 'android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"' in permission_activity
assert 'android:name="com.youlong.hd.intent.action.REQUEST_PERMISSION"' in permission_activity
authorization_service = manifest.split('android:name="roro.stellar.manager.authorization.StellarAuthorizationService"',1)[1].split("/>",1)[0]
assert 'android:exported="true"' in authorization_service
assert 'android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"' in authorization_service

assert "android:name=\"roro.stellar.manager.authorization.StellarAuthorizationService\"" in manifest, "Binder service must be registered"
svc = manifest.split('android:name="roro.stellar.manager.authorization.StellarAuthorizationService"',1)[1].split("/>",1)[0]
assert 'android:exported="true"' in svc, "Root broker must expose its signature-protected Messenger endpoint"
assert 'android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"' in svc, \
       "exported Stellar broker must remain protected by the Android signature permission"
assert "public Result(int code, String text, boolean wasDenied)" in root_access, "Binder response result must be publicly constructible"

guard = Path(sys.argv[1]).with_name("FxStellarCommandGuardActivity.java").read_text(encoding="utf-8")
assert "ACTION_COMMAND_GUARD" in guard and 'getLongExtra("id", -1L)' in guard
assert "REQUEST_TIMEOUT_MS = 30000L" in guard and 'submitDecision("DENY")' in guard
for decision in ('"ALLOW"', '"DENY"', '"ALWAYS_ALLOW"'):
    assert decision in guard, f"command guard response token missing: {decision}"
assert '"/data/local/tmp/stellar_guard"' in guard and '".resp"' in guard
assert "mktemp" in guard and "chmod 600" in guard and "mv -f" in guard
assert "RootAccess.execute(" in guard and "responseCommand(decision)" in guard
assert "new ProcessBuilder" not in guard and "Runtime.getRuntime()" not in guard, \
    "incoming commands must only be displayed and never executed by this confirmation Activity"
guard_manifest = manifest.split('android:name="roro.stellar.manager.authorization.FxStellarCommandGuardActivity"', 1)[1].split("</activity>", 1)[0]
assert 'android:exported="true"' in guard_manifest
assert 'android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"' in guard_manifest
assert 'android:name="com.youlong.hd.intent.action.COMMAND_GUARD"' in guard_manifest


print("PASS: Stellar manager app inventory is off-main-thread, Root work is bounded, target selection is restorable, and secure-settings scope is grantable")
PY
