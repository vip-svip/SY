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
import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Home-screen widget for the FX/Yulong ad-filter master switch. */
public final class FxYulongAdWidgetProvider extends AppWidgetProvider {
    public static final String ACTION_TOGGLE =
            "de.privacyguard.adhook.widget.YULONG_AD_TOGGLE";
    public static final String ACTION_REFRESH =
            "de.privacyguard.adhook.widget.YULONG_AD_REFRESH";
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();

    private static String shell(String action) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; "
                + "sh \"$MP/scripts/yulong-ad-control.sh\" " + action;
    }

    public static void refreshAll(Context context) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        WORKER.execute(() -> refreshFromRoot(app));
    }

    private static void refreshFromRoot(Context context) {
        RootAccess.Result result = RootAccess.execute(shell("list"), 30000L, 128 * 1024);
        boolean enabled = false;
        boolean valid = false;
        if (result.exitCode == 0 && result.output != null) {
            for (String line : result.output.split("\\r?\\n")) {
                if (line.startsWith("AD_MASTER|")) {
                    enabled = line.substring("AD_MASTER|".length()).trim().equals("1");
                    valid = true;
                    break;
                }
            }
        }
        String dailyCount = readTodayBlockedSamples();
        updateViews(context, enabled, valid, dailyCount);
    }

    private static String readTodayBlockedSamples() {
        RootAccess.Result logs = RootAccess.execute(shell("dns-log-tail"), 30000L, 512 * 1024);
        if (logs.exitCode != 0 || logs.output == null) return "今日拦截：日志读取失败";
        String raw = logs.output;
        if (raw.contains("FXDNSLOG_DISABLED")) return "今日拦截：查询日志未启用";
        if (raw.contains("FXDNSLOG_EMPTY")) return "今日拦截：暂无日志样本";
        long dayStart = java.time.LocalDate.now(java.time.ZoneId.systemDefault())
                .atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
        long now = System.currentTimeMillis();
        int today = 0, blocked = 0, unknown = 0;
        for (String line : raw.split("\\r?\\n")) {
            String value = line.trim();
            if (!value.startsWith("{")) continue;
            try {
                org.json.JSONObject item = new org.json.JSONObject(value);
                org.json.JSONObject result = item.optJSONObject("Result");
                boolean filtered = item.optBoolean("IsFiltered", false)
                        || (result != null && result.optBoolean("IsFiltered", false));
                String reason = result == null ? item.optString("reason", "")
                        : result.optString("Reason", item.optString("reason", ""));
                String logStatus = item.optString("status", "").toLowerCase(java.util.Locale.ROOT);
                if (logStatus.contains("block") || logStatus.contains("filter")
                        || reason.toLowerCase(java.util.Locale.ROOT).startsWith("filtered")) filtered = true;
                String timestamp = item.optString("T", item.optString("time", ""));
                long time = -1L;
                try { time = java.time.Instant.parse(timestamp).toEpochMilli(); } catch (Throwable ignored) { }
                if (time < 0) {
                    try { time = java.time.ZonedDateTime.parse(timestamp).toInstant().toEpochMilli(); }
                    catch (Throwable ignored) { }
                }
                if (time < 0) unknown++;
                else if (time >= dayStart && time <= now) {
                    today++;
                    if (filtered) blocked++;
                }
            } catch (Throwable ignored) { }
        }
        if (today == 0 && unknown > 0) return "今日拦截：日志时间无法解析";
        return "今日日志样本拦截：" + blocked + " / " + today + " 条";
    }

    private static void updateViews(Context context, boolean enabled, boolean valid) {
        updateViews(context, enabled, valid, "今日拦截：状态未知");
    }

    private static void updateViews(Context context, boolean enabled, boolean valid, String dailyCount) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, FxYulongAdWidgetProvider.class);
        int[] ids = manager.getAppWidgetIds(provider);
        if (ids == null || ids.length == 0) return;
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.fx_yulong_ad_widget);
        views.setTextViewText(R.id.fx_yulong_widget_status,
                !valid ? "Root 状态不可用" : (enabled ? "广告过滤已开启" : "广告过滤已关闭"));
        views.setTextViewText(R.id.fx_yulong_widget_count, dailyCount);
        views.setTextViewText(R.id.fx_yulong_widget_toggle,
                !valid ? "刷新状态" : (enabled ? "关闭过滤" : "开启过滤"));
        views.setViewVisibility(R.id.fx_yulong_widget_status,
                valid ? android.view.View.VISIBLE : android.view.View.VISIBLE);

        Intent toggle = new Intent(context, FxYulongAdWidgetProvider.class);
        toggle.setAction(ACTION_TOGGLE);
        PendingIntent togglePending = PendingIntent.getBroadcast(context, 5101, toggle,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_IMMUTABLE : 0));
        views.setOnClickPendingIntent(R.id.fx_yulong_widget_toggle, togglePending);

        Intent open = new Intent(context, FxYulongAdActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        open.putExtra("suite_page", "首页与防护");
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
        if (!ACTION_TOGGLE.equals(action)) return;

        final PendingResult pending = goAsync();
        WORKER.execute(() -> {
            int current = readEnabled(context);
            if (current < 0) {
                updateViews(context, false, false);
                pending.finish();
                return;
            }
            int wanted = current == 1 ? 0 : 1;
            RootAccess.Result applied = RootAccess.execute(
                    shell("ad-master " + wanted), 90000L, 128 * 1024);
            if (applied.exitCode == 0) {
                refreshFromRoot(context);
            } else {
                updateViews(context, current == 1, false);
            }
            pending.finish();
        });
    }

    private static int readEnabled(Context context) {
        RootAccess.Result result = RootAccess.execute(shell("list"), 30000L, 128 * 1024);
        if (result.exitCode != 0 || result.output == null) return -1;
        for (String line : result.output.split("\\r?\\n")) {
            if (line.startsWith("AD_MASTER|")) {
                return line.substring("AD_MASTER|".length()).trim().equals("1") ? 1 : 0;
            }
        }
        return -1;
    }
}
