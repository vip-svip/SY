package de.privacyguard.adhook.imported.ad;

import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import de.privacyguard.adhook.RootAccess;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Quick Settings toggle bound to the FX ad-filter master key. */
public final class FxYulongAdTileService extends TileService {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-yulong-tile"), new ThreadPoolExecutor.AbortPolicy());
    private final AtomicBoolean refreshPending = new AtomicBoolean(false);
    private final AtomicBoolean togglePending = new AtomicBoolean(false);
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean destroyed;
    private String command(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; "
                + "[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" " + args;
    }
    private int readState() {
        RootAccess.Result r=RootAccess.execute(command("list"),30000L,128*1024);
        if(r.exitCode!=0||r.output==null)return Tile.STATE_UNAVAILABLE;
        for(String line:r.output.split("\\r?\\n"))
            if(line.startsWith("AD_MASTER|"))return line.endsWith("|1")?Tile.STATE_ACTIVE:Tile.STATE_INACTIVE;
        return Tile.STATE_INACTIVE;
    }
    private void applyTile(int state,String subtitle) {
        Tile tile=getQsTile();if(tile==null)return;
        tile.setState(state);tile.setLabel("FX 广告过滤");tile.setSubtitle(subtitle);tile.updateTile();
    }
    private void refreshAsync() {
        if (destroyed || !refreshPending.compareAndSet(false, true)) return;
        try {
            worker.execute(() -> {
                try {
                    int state = readState();
                    main.post(() -> {
                        if (!destroyed) applyTile(state, state == Tile.STATE_ACTIVE ? "已开启"
                                : state == Tile.STATE_INACTIVE ? "已关闭" : "Root 不可用");
                    });
                } catch (Throwable failure) {
                    main.post(() -> { if (!destroyed) applyTile(Tile.STATE_UNAVAILABLE, "状态读取失败"); });
                } finally {
                    refreshPending.set(false);
                }
            });
        } catch (RejectedExecutionException full) {
            refreshPending.set(false);
        }
    }

    @Override public void onStartListening() {
        super.onStartListening();
        refreshAsync();
    }

    @Override public void onClick() {
        super.onClick();
        if (destroyed || !togglePending.compareAndSet(false, true)) {
            applyTile(Tile.STATE_UNAVAILABLE, "正在应用…");
            return;
        }
        applyTile(Tile.STATE_UNAVAILABLE, "正在应用…");
        try {
            worker.execute(() -> {
                long gateToken = 0L;
                try {
                    gateToken = FxYulongAdOperationGate.tryAcquire();
                    if (gateToken == 0L) {
                        main.post(() -> { if (!destroyed) applyTile(Tile.STATE_UNAVAILABLE, "另一入口正在修改广告过滤"); });
                        return;
                    }
                    int current = readState();
                    // Unknown Root/service state must never be interpreted as "off";
                    // doing so would turn a failed read into an unconditional enable.
                    if (current == Tile.STATE_UNAVAILABLE) {
                        main.post(() -> { if (!destroyed) applyTile(Tile.STATE_UNAVAILABLE, "Root 状态不可用，未更改"); });
                        return;
                    }
                    int next = current == Tile.STATE_ACTIVE ? 0 : 1;
                    RootAccess.Result result = RootAccess.execute(command("ad-master " + next),
                            90000L, 128 * 1024);
                    int state = result.exitCode == 0 ? readState() : Tile.STATE_UNAVAILABLE;
                    if (result.exitCode == 0) FxYulongAdWidgetProvider.refreshAll(this);
                    main.post(() -> {
                        if (destroyed) return;
                        String subtitle = result.exitCode != 0 ? "Root 应用失败"
                                : state == Tile.STATE_ACTIVE ? "已开启"
                                : state == Tile.STATE_INACTIVE ? "已关闭" : "已应用，但无法核实状态";
                        applyTile(state, subtitle);
                    });
                } catch (Throwable failure) {
                    main.post(() -> { if (!destroyed) applyTile(Tile.STATE_UNAVAILABLE, "Root 操作失败"); });
                } finally {
                    if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);
                    togglePending.set(false);
                }
            });
        } catch (RejectedExecutionException full) {
            togglePending.set(false);
            applyTile(Tile.STATE_UNAVAILABLE, "后台任务繁忙，请重试");
        }
    }

    @Override public void onDestroy() {
        destroyed = true;
        worker.shutdownNow();
        super.onDestroy();
    }
}
