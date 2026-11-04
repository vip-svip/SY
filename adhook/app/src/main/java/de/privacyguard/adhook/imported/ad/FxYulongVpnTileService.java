package de.privacyguard.adhook.imported.ad;

import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import de.privacyguard.adhook.RootAccess;
import org.json.JSONObject;
import java.util.Arrays;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Migrated Yulong network-protection Quick Settings toggle.
 *
 * FX owns one canonical network route; this tile never starts the original
 * AdBlockVpnService or RootProxyService. The ad-filter master remains a
 * separate Quick Settings tile.
 */
public final class FxYulongVpnTileService extends TileService {
    private static final String[] MODES = {"direct", "global", "rule", "tun"};
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> {
                Thread thread = new Thread(r, "fx-yulong-vpn-tile");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());
    private final AtomicBoolean refreshPending = new AtomicBoolean(false);
    private final AtomicBoolean togglePending = new AtomicBoolean(false);
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean destroyed;

    private static final class VpnState {
        final boolean running;
        final String mode;
        final boolean rootProxy;
        VpnState(boolean running, String mode, boolean rootProxy) {
            this.running = running;
            this.mode = mode;
            this.rootProxy = rootProxy;
        }
        boolean protectedNow() {
            return rootProxy || (running && !"direct".equals(mode));
        }
    }

    private String vpnCommand(String action) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; "
                + "PG=/data/adb/privacyguard; "
                + "sh \"$MP/scripts/yulong-vpn-control.sh\" \"$MP\" \"$PG\" " + action;
    }

    private VpnState readState() {
        RootAccess.Result result = RootAccess.execute(vpnCommand("status"), 30000L, 128 * 1024);
        if (result.exitCode != 0 || result.output == null || result.output.trim().isEmpty()) {
            return null;
        }
        try {
            JSONObject status = new JSONObject(result.output.trim());
            Object runningValue = status.opt("vpn_on");
            Object modeValue = status.opt("vpn_mode");
            Object rootProxyValue = status.opt("root_proxy_on");
            Object rootProxyKnownValue = status.opt("root_proxy_known");
            if (!(runningValue instanceof Boolean) || !(modeValue instanceof String)
                    || !(rootProxyValue instanceof Boolean) || !Boolean.TRUE.equals(rootProxyKnownValue))
                return null;
            String mode = ((String) modeValue).trim();
            if (!Arrays.asList(MODES).contains(mode)) return null;
            return new VpnState((Boolean) runningValue, mode, (Boolean) rootProxyValue);
        } catch (Exception invalidStatus) {
            return null;
        }
    }

    private String describe(VpnState state) {
        if (state == null) return "Root 状态不可用";
        if (!state.protectedNow()) return "直连 · VPN 已关闭";
        if (state.rootProxy) return "保护中 · 第三方 VPN / Root DNS";
        switch (state.mode) {
            case "global": return "保护中 · 全局模式";
            case "rule": return "保护中 · 规则模式";
            case "tun": return "保护中 · TUN 模式";
            default: return "保护状态未知";
        }
    }

    private void applyTile(VpnState state, String override) {
        Tile tile = getQsTile();
        if (tile == null) return;
        int tileState = state == null ? Tile.STATE_UNAVAILABLE
                : state.protectedNow() ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE;
        String subtitle = override == null ? describe(state) : override;
        tile.setState(tileState);
        tile.setLabel("FX VPN");
        if (Build.VERSION.SDK_INT >= 29) tile.setSubtitle(subtitle);
        if (Build.VERSION.SDK_INT >= 30) tile.setContentDescription("FX VPN 快速切换；" + subtitle);
        tile.updateTile();
    }

    private void refreshAsync() {
        if (destroyed || !refreshPending.compareAndSet(false, true)) return;
        try {
            worker.execute(() -> {
                try {
                    VpnState state = readState();
                    main.post(() -> { if (!destroyed) applyTile(state, null); });
                } catch (Throwable failure) {
                    main.post(() -> { if (!destroyed) applyTile(null, "VPN 状态读取失败"); });
                } finally {
                    refreshPending.set(false);
                }
            });
        } catch (RejectedExecutionException full) {
            refreshPending.set(false);
            applyTile(null, "后台任务繁忙，请重试");
        }
    }

    @Override public void onStartListening() {
        super.onStartListening();
        refreshAsync();
    }

    @Override public void onClick() {
        super.onClick();
        if (destroyed || !togglePending.compareAndSet(false, true)) {
            applyTile(null, "正在切换…");
            return;
        }
        applyTile(null, "正在读取 VPN 状态…");
        try {
            worker.execute(() -> {
                try {
                    // A failed status read is not "off": never mutate an unknown route.
                    VpnState before = readState();
                    if (before == null) {
                        main.post(() -> { if (!destroyed) applyTile(null, "Root 状态不可用，未更改"); });
                        return;
                    }
                    String action = before.protectedNow() ? "stop" : "start";
                    RootAccess.Result result = RootAccess.execute(
                            vpnCommand(action), 120000L, 128 * 1024);
                    VpnState after = readState();
                    boolean confirmed = after != null
                            && (("stop".equals(action) && !after.protectedNow())
                                || ("start".equals(action) && after.protectedNow()));
                    String override = null;
                    if (result.exitCode != 0) {
                        String output = result.output == null ? "" : result.output;
                        if (output.contains("VPN_NO_NODE_SELECTED")) {
                            override = "尚未选择节点，请先打开 FX VPN 页面";
                        } else if (result.denied) {
                            override = "Root 权限被拒绝";
                        } else {
                            override = "VPN " + ("start".equals(action) ? "启动" : "停止") + "失败";
                        }
                    } else if (!confirmed) {
                        override = "已提交操作，但实际状态未确认";
                    }
                    String finalOverride = override;
                    main.post(() -> { if (!destroyed) applyTile(after, finalOverride); });
                } catch (Throwable failure) {
                    main.post(() -> { if (!destroyed) applyTile(null, "VPN 操作失败，状态未知"); });
                } finally {
                    togglePending.set(false);
                }
            });
        } catch (RejectedExecutionException full) {
            togglePending.set(false);
            applyTile(null, "后台任务繁忙，请重试");
        }
    }

    @Override public void onDestroy() {
        destroyed = true;
        worker.shutdownNow();
        super.onDestroy();
    }
}
