#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
GENERAL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
TASKER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java"
TILE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java"
WIDGET="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java"
GATE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdOperationGate.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACTIVITY" "$GENERAL" "$TASKER" "$TILE" "$WIDGET" "$GATE"; do
  [ -s "$file" ] || fail "missing shared ad operation gate source: $file"
done
python3 - "$ACTIVITY" "$GENERAL" "$TASKER" "$TILE" "$WIDGET" "$GATE" <<'PY'
from pathlib import Path
import sys

activity, general, tasker, tile, widget, gate = [Path(x).read_text(encoding="utf-8") for x in sys.argv[1:]]
start = activity.find("private void apply(")
if start < 0:
    raise SystemExit("FAIL: ad activity apply method missing")
end = activity.find("\n @Override protected void onCreate", start)
if end < 0:
    raise SystemExit("FAIL: ad activity apply method boundary missing")
apply = activity[start:end]
worker = apply.find("worker.execute(")
acquire = apply.find("gateToken=FxYulongAdOperationGate.tryAcquire()")
finally_release = apply.find("if(gateToken!=0L)FxYulongAdOperationGate.release(gateToken)")
reject = apply.find("catch(RejectedExecutionException full)")
if min(worker, acquire, finally_release, reject) < 0:
    raise SystemExit("FAIL: ad activity does not show the full queue/gate lifecycle")
if not worker < acquire < finally_release < reject:
    raise SystemExit("FAIL: ad activity must acquire/release only inside accepted worker execution")
reject_block = apply[reject:]
if "FxYulongAdOperationGate.release()" in reject_block:
    raise SystemExit("FAIL: rejected Activity task releases a gate it never acquired")
if "后台任务繁忙，请稍后重试。" not in reject_block:
    raise SystemExit("FAIL: rejected Activity task no longer reports queue saturation")

# The Tile acquires in its accepted worker and releases only when gateAcquired.
tile_click = tile[tile.find("@Override public void onClick()"):]
tile_worker = tile_click.find("worker.execute(")
tile_acquire = tile_click.find("gateToken = FxYulongAdOperationGate.tryAcquire()")
tile_release = tile_click.find("if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken)")
if min(tile_worker, tile_acquire, tile_release) < 0 or not tile_worker < tile_acquire < tile_release:
    raise SystemExit("FAIL: Quick Settings tile gate is not acquired/released in its worker finally")
tile_reject = tile_click.find("catch (RejectedExecutionException full)")
if tile_reject < 0 or "FxYulongAdOperationGate.release()" in tile_click[tile_reject:]:
    raise SystemExit("FAIL: rejected Tile task must not release an unacquired gate")

# The migrated Yulong home-screen Widget controls the unified VPN route,
# not the ad-master setting. It must use its own controller lock and must never
# acquire the ad settings transaction gate.
widget_receive = widget[widget.find("@Override public void onReceive("):]
widget_pending = widget_receive.find("TOGGLE_PENDING.compareAndSet(false, true)")
go_async = widget_receive.find("goAsync()")
worker_submit = widget_receive.find("WORKER.execute(")
if min(widget_pending, go_async, worker_submit) < 0 or not widget_pending < go_async < worker_submit:
    raise SystemExit("FAIL: VPN Widget must serialize before goAsync and submit accepted work asynchronously")
if "FxYulongAdOperationGate" in widget_receive:
    raise SystemExit("FAIL: VPN Widget must not acquire the separate ad-settings transaction gate")
if "yulong-vpn-control.sh" not in widget or "TOGGLE_PENDING.set(false);" not in widget_receive:
    raise SystemExit("FAIL: VPN Widget must use canonical VPN control and release its pending state")
if "OWNER_TOKEN.compareAndSet(0L, token)" not in gate or "OWNER_TOKEN.compareAndSet(token, 0L)" not in gate:
    raise SystemExit("FAIL: operation gate does not enforce exact-token ownership")
all_callers = "\\n".join((activity, general, tasker, tile, widget))
if "FxYulongAdOperationGate.release()" in all_callers:
    raise SystemExit("FAIL: a caller still uses unsafe ownerless release API")
if "gateToken = FxYulongAdOperationGate.tryAcquire()" not in general or "release(gateToken)" not in general:
    raise SystemExit("FAIL: General settings import does not carry its lease token")
if "final long gateToken = adFilterAction ? FxYulongAdOperationGate.tryAcquire() : 0L;" not in tasker:
    raise SystemExit("FAIL: Tasker must acquire the ad transaction gate only for AD_FILTER actions")
if tasker.count("release(gateToken)") != 3:
    raise SystemExit("FAIL: Tasker does not preserve and release its conditional ad lease token")
if "yulong-vpn-control.sh" not in tasker or "module-side yulong-vpn-control.sh lock" not in tasker:
    raise SystemExit("FAIL: legacy Tasker VPN aliases must use the canonical separate VPN lock")

root_start = activity.find("private void root(")
root_end = activity.find("private String safe(", root_start)
if root_start < 0 or root_end < 0:
    raise SystemExit("FAIL: Yulong read-only Root helper boundary missing")
root = activity[root_start:root_end]
root_submit = root.find("worker.execute(task)")
root_catch = root.find("catch(RejectedExecutionException full)")
if min(root_submit, root_catch) < 0 or not root_submit < root_catch:
    raise SystemExit("FAIL: Yulong read-only Root helper does not guard bounded queue submission")
if "RootAccess.failure(125" not in root or "后台任务繁忙，请稍后重试。" not in root:
    raise SystemExit("FAIL: rejected read-only Root task does not surface an explicit busy result")
if "if(cb!=null)cb.accept(busy)" not in root:
    raise SystemExit("FAIL: rejected read-only Root task does not notify its operation callback")

print("PASS: ad Activity/General/Tile callers retain exact-token leases; VPN Widget and Tasker VPN aliases use their separate canonical route lock")
PY
