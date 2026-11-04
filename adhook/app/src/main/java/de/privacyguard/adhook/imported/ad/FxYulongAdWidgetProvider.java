package de.privacyguard.adhook.imported.ad;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.widget.RemoteViews;

import de.privacyguard.adhook.MainActivity;
import de.privacyguard.adhook.R;
import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Original Yulong home-screen VPN widget migrated to FX's one canonical route. */
public final class FxYulongAdWidgetProvider extends AppWidgetProvider {
    // Preserve the existing action so widgets created by older app versions remain functional.
    public static final String ACTION_TOGGLE = "app.pwhs.blockads.widget.TOGGLE_VPN";
    public static final String ACTION_REFRESH = "de.privacyguard.adhook.widget.YULONG_AD_REFRESH";

    private static final ThreadPoolExecutor WORKER = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> { Thread t = new Thread(r, "fx-yulong-vpn-widget"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private static final AtomicBoolean REFRESH_PENDING = new AtomicBoolean(false);
    private static final AtomicBoolean TOGGLE_PENDING = new AtomicBoolean(false);

    private static String shell(String operation) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; "
                + "sh \"$MP/scripts/yulong-vpn-control.sh\" \"$MP\" /data/adb/privacyguard " + operation;
    }

    private static final class VpnState {
        final boolean valid;
        final boolean running;
        final boolean hasNode;
        final String mode;
        final String detail;
        final boolean rootProxy;

        VpnState(boolean valid, boolean running, boolean hasNode, String mode, String detail,
                 boolean rootProxy) {
            this.valid = valid;
            this.running = running;
            this.hasNode = hasNode;
            this.mode = mode == null ? "direct" : mode;
            this.detail = detail == null ? "" : detail;
            this.rootProxy = rootProxy;
        }
        boolean protectedNow() { return running || rootProxy; }
    }

    private static VpnState readState() {
        RootAccess.Result result = RootAccess.execute(shell("status"), 30000L, 256 * 1024);
        if (result.exitCode != 0 || result.output == null) {
            return new VpnState(false, false, false, "direct",
                    result.output == null ? "Root 状态不可用" : result.output.trim(), false);
        }
        try {
            org.json.JSONObject json = new org.json.JSONObject(result.output.trim());
            Object proxyOn = json.opt("root_proxy_on");
            Object proxyKnown = json.opt("root_proxy_known");
            if (!(proxyOn instanceof Boolean) || !Boolean.TRUE.equals(proxyKnown)) {
                return new VpnState(false, false, false, "direct",
                        "Root Proxy 状态不可用，拒绝显示网络保护已关闭", false);
            }
            return new VpnState(true, json.optBoolean("vpn_on", false),
                    !json.optString("vpn_node", "").isEmpty(),
                    json.optString("vpn_mode", "direct"), "", (Boolean) proxyOn);
        } catch (Exception invalid) {
            return new VpnState(false, false, false, "direct",
                    "status.sh 返回无效状态：" + invalid.getClass().getSimpleName(), false);
        }
    }

    public static void refreshAll(Context context) {
        if (context == null || !REFRESH_PENDING.compareAndSet(false, true)) return;
        Context app = context.getApplicationContext();
        try {
            WORKER.execute(() -> {
                try {
                    updateViews(app, readState(), "");
                } catch (Throwable failure) {
                    updateViews(app, new VpnState(false, false, false, "direct",
                            failure.getClass().getSimpleName(), false), "");
                } finally {
                    REFRESH_PENDING.set(false);
                }
            });
        } catch (RejectedExecutionException full) {
            REFRESH_PENDING.set(false);
        }
    }

    private static void updateViews(Context context, VpnState state, String message) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, FxYulongAdWidgetProvider.class));
        if (ids == null || ids.length == 0) return;

        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.fx_yulong_ad_widget);
        String status;
        String button;
        if (!state.valid) {
            status = "VPN 状态不可用";
            button = "刷新状态";
        } else if (state.rootProxy) {
            status = "网络保护已启用 · 第三方 VPN / Root DNS";
            button = "停止防护";
        } else if (state.running) {
            status = "VPN 已启用 · " + state.mode;
            button = "停止 VPN";
        } else if ("direct".equals(state.mode)) {
            status = "直连 · 网络保护已关闭";
            button = "启动防护";
        } else {
            status = "已配置 " + state.mode + " · 后端未运行";
            button = "重试启动";
        }
        views.setTextViewText(R.id.fx_yulong_widget_status, status);
        views.setTextViewText(R.id.fx_yulong_widget_count,
                !message.isEmpty() ? message : state.hasNode ? "节点：已配置" : "节点：未选择");
        views.setTextViewText(R.id.fx_yulong_widget_toggle, button);
        views.setViewVisibility(R.id.fx_yulong_widget_status, android.view.View.VISIBLE);

        Intent toggle = new Intent(context, FxYulongAdWidgetProvider.class);
        toggle.setAction(ACTION_TOGGLE);
        PendingIntent togglePending = PendingIntent.getBroadcast(context, 5101, toggle,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_IMMUTABLE : 0));
        views.setOnClickPendingIntent(R.id.fx_yulong_widget_toggle, togglePending);

        Intent open = new Intent(context, MainActivity.class);
        open.setAction(Intent.ACTION_MAIN);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent openPending = PendingIntent.getActivity(context, 5102, open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_IMMUTABLE : 0));
        views.setOnClickPendingIntent(R.id.fx_yulong_widget_open, openPending);
        manager.updateAppWidget(ids, views);
    }

    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        super.onUpdate(context, manager, ids);
        refreshAll(context);
    }

    @Override public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (intent == null) return;
        String action = intent.getAction();
        if (ACTION_REFRESH.equals(action)) {
            refreshAll(context);
            return;
        }
        if (!ACTION_TOGGLE.equals(action) || !TOGGLE_PENDING.compareAndSet(false, true)) return;

        final PendingResult pending;
        try {
            pending = goAsync();
        } catch (RuntimeException unavailable) {
            TOGGLE_PENDING.set(false);
            updateViews(context, new VpnState(false, false, false, "direct", "无法启动后台任务", false), "");
            return;
        }

        try {
            WORKER.execute(() -> {
                try {
                    VpnState current = readState();
                    if (!current.valid) {
                        updateViews(context, current, "Root 状态不可用，未更改");
                        return;
                    }
                    String operation = current.protectedNow() ? "stop" : "start";
                    RootAccess.Result result = RootAccess.execute(shell(operation), 150000L, 512 * 1024);
                    VpnState actual = readState();
                    updateViews(context, actual, result.exitCode == 0 ? ""
                            : "操作失败（退出码 " + result.exitCode + "）");
                } catch (Throwable failure) {
                    updateViews(context, new VpnState(false, false, false, "direct",
                            failure.getClass().getSimpleName(), false), "VPN 操作失败，未确认状态");
                } finally {
                    TOGGLE_PENDING.set(false);
                    pending.finish();
                }
            });
        } catch (RejectedExecutionException full) {
            TOGGLE_PENDING.set(false);
            try {
                updateViews(context, new VpnState(false, false, false, "direct", "后台任务繁忙", false), "请稍后重试");
            } finally {
                pending.finish();
            }
        }
    }
}
