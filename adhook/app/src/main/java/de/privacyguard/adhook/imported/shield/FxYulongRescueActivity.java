package de.privacyguard.adhook.imported.shield;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.DateFormat;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.Set;

/** User-confirmed recovery actions for Yulong Shield inside the unified FX APK. */
public final class FxYulongRescueActivity extends Activity {
    private static final String PREFS = "shield_prefs";
    private SharedPreferences prefs;
    private String foregroundPackage = "";
    private TextView foregroundLabel;
    private TextView status;

    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView v = new TextView(this);
        v.setText(value); v.setTextSize(size); v.setTextColor(color);
        if (bold) v.setTypeface(null, android.graphics.Typeface.BOLD);
        v.setPadding(dp(4), dp(6), dp(4), dp(6));
        return v;
    }
    private Button button(String title, Runnable action) {
        Button b = new Button(this);
        b.setAllCaps(false); b.setText(title);
        b.setOnClickListener(v -> action.run());
        return b;
    }
    private void card(LinearLayout body, String title, String detail, View... controls) {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setPadding(dp(12), dp(8), dp(12), dp(8));
        p.setBackgroundColor(0xffeef2f6);
        p.addView(text(title, 15, 0xff17212b, true));
        p.addView(text(detail, 12, 0xff617080, false));
        for (View c : controls) p.addView(c);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(4), 0, dp(4));
        body.addView(p, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        foregroundPackage = lastForegroundPackage();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(10), dp(6));
        header.addView(button("‹ 返回安全护盾", () -> finish()));
        header.addView(text("安全护盾 · 救援中心", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(10), dp(4), dp(10), dp(22));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);

        foregroundLabel = text(formatForeground(), 13, 0xff17212b, true);
        card(body, "当前前台应用", "仅读取 Usage Access 的前台包名，不读取屏幕内容、输入内容或其他应用数据。",
                foregroundLabel,
                button("刷新前台应用", () -> {
                    foregroundPackage = lastForegroundPackage();
                    foregroundLabel.setText(formatForeground());
                    status.setText("已刷新前台应用信息。");
                }),
                button("打开当前应用信息", this::openApplicationInfo),
                button("打开系统卸载确认", this::confirmUninstall));

        status = text("救援操作只修改 FX 自己保存的安全护盾名单与开关。", 12, 0xff526170, false);
        card(body, "快速恢复", "用于误加入管控名单或误开启后台守护时恢复设置。",
                button("停止实时应用守护", () -> {
                    prefs.edit().putBoolean("protect_on", false).apply();
                    stopService(new Intent(this, FxYulongProtectionService.class));
                    status.setText("已关闭实时应用守护。");
                }),
                button("暂停音量键与摇动触发", () -> {
                    prefs.edit().putBoolean("volume_trigger_on", false)
                            .putBoolean("shake_trigger_on", false).apply();
                    Intent stop = new Intent(this, FxYulongProtectionService.class);
                    stop.setAction(FxYulongProtectionService.ACTION_START);
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(stop);
                    else startService(stop);
                    status.setText("已暂停音量键和摇动触发；其他守护设置未更改。");
                }),
                button("关闭悬浮救援入口", () -> {
                    prefs.edit().putBoolean("overlay_rescue_on", false).apply();
                    stopService(new Intent(this, FxYulongRescueOverlayService.class));
                    status.setText("已关闭悬浮救援入口。");
                }),
                status);

        card(body, "名单恢复", "以下操作需要明确点击；不会自动卸载、冻结或强制停止应用。",
                button("将当前应用加入白名单", () -> mutateList("whitelist_pkgs", true)),
                button("从管控黑名单移除当前应用", () -> mutateList("blacklist_pkgs", false)),
                button("清空全部管控名单", this::confirmClearBlacklist));

        card(body, "系统权限设置", "FX 不会自动打开或恢复系统权限；请由你在系统设置中手动处理。",
                button("使用情况访问权限", () -> openSettings(Settings.ACTION_USAGE_ACCESS_SETTINGS)),
                button("无障碍服务设置", () -> openSettings(Settings.ACTION_ACCESSIBILITY_SETTINGS)),
                button("悬浮窗权限设置", () -> {
                    try {
                        startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:" + getPackageName())));
                    } catch (Throwable e) {
                        status.setText("无法打开悬浮窗设置：" + e.getClass().getSimpleName());
                    }
                }),
                button("返回安全护盾主页", () ->
                        startActivity(new Intent(this, FxYulongShieldActivity.class))));
    }

    private String formatForeground() {
        if (foregroundPackage == null || foregroundPackage.isEmpty())
            return "未读取到最近前台应用。请确认 FX 已获得使用情况访问权限。";
        String label = foregroundPackage;
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(foregroundPackage, 0);
            label = String.valueOf(getPackageManager().getApplicationLabel(info));
        } catch (Throwable ignored) { }
        return label + "\n" + foregroundPackage;
    }

    private String lastForegroundPackage() {
        try {
            android.app.AppOpsManager appOps =
                    (android.app.AppOpsManager) getSystemService(APP_OPS_SERVICE);
            if (appOps == null || appOps.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), getPackageName())
                    != android.app.AppOpsManager.MODE_ALLOWED) return "";
            UsageStatsManager usage =
                    (UsageStatsManager) getSystemService(USAGE_STATS_SERVICE);
            if (usage == null) return "";
            long now = System.currentTimeMillis();
            UsageEvents events = usage.queryEvents(now - 10 * 60 * 1000L, now);
            if (events == null) return "";
            UsageEvents.Event event = new UsageEvents.Event();
            String latest = "";
            long latestTime = 0L;
            while (events.hasNextEvent()) {
                events.getNextEvent(event);
                int type = event.getEventType();
                boolean resumed = type == UsageEvents.Event.MOVE_TO_FOREGROUND;
                if (Build.VERSION.SDK_INT >= 29)
                    resumed = resumed || type == UsageEvents.Event.ACTIVITY_RESUMED;
                if (resumed && event.getTimeStamp() >= latestTime) {
                    latestTime = event.getTimeStamp();
                    latest = event.getPackageName();
                }
            }
            return latest == null ? "" : latest;
        } catch (Throwable ignored) { return ""; }
    }

    private void mutateList(String key, boolean add) {
        if (foregroundPackage == null || !foregroundPackage.matches(
                "[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
            status.setText("当前没有可处理的前台应用包名。");
            return;
        }
        LinkedHashSet<String> items = readPackages(key);
        if (add) items.add(foregroundPackage);
        else items.remove(foregroundPackage);
        prefs.edit().putString(key, join(items)).apply();
        status.setText((add ? "已加入白名单：" : "已从管控名单移除：") + foregroundPackage);
        String today = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
                .format(new Date());
        prefs.edit().putString("rescue_last_action_day", today)
                .putInt("rescue_action_count_today",
                        today.equals(prefs.getString("rescue_last_action_day", ""))
                                ? prefs.getInt("rescue_action_count_today", 0) + 1 : 1)
                .putString("rescue_last_action", key + (add ? ":add:" : ":remove:") + foregroundPackage)
                .putString("rescue_last_action_time",
                        DateFormat.getDateTimeInstance().format(new Date()))
                .apply();
        Toast.makeText(this, "名单已更新。", Toast.LENGTH_SHORT).show();
    }

    private void confirmClearBlacklist() {
        new AlertDialog.Builder(this).setTitle("清空管控名单")
                .setMessage("此操作会清空 FX 安全护盾保存的管控名单，不会卸载或修改任何应用。")
                .setNegativeButton("取消", null)
                .setPositiveButton("确认清空", (d, w) -> {
                    prefs.edit().putString("blacklist_pkgs", "").apply();
                    status.setText("管控名单已清空。");
                }).show();
    }

    private LinkedHashSet<String> readPackages(String key) {
        LinkedHashSet<String> items = new LinkedHashSet<>();
        String raw = prefs.getString(key, "");
        if (raw != null) for (String part : raw.split(",")) {
            String pkg = part.trim();
            if (pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) items.add(pkg);
        }
        return items;
    }

    private String join(Set<String> items) {
        StringBuilder b = new StringBuilder();
        for (String value : items) {
            if (b.length() > 0) b.append(',');
            b.append(value);
        }
        return b.toString();
    }

    private void openApplicationInfo() {
        if (foregroundPackage == null || foregroundPackage.isEmpty()) return;
        try {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + foregroundPackage)));
        } catch (Throwable error) {
            status.setText("无法打开应用信息：" + error.getClass().getSimpleName());
        }
    }

    private void confirmUninstall() {
        if (foregroundPackage == null || foregroundPackage.isEmpty()) return;
        new AlertDialog.Builder(this).setTitle("打开系统卸载确认")
                .setMessage("将打开 Android 系统卸载界面。FX 不会自动点击卸载确认按钮。")
                .setNegativeButton("取消", null)
                .setPositiveButton("继续", (d, w) -> {
                    try {
                        startActivity(new Intent(Intent.ACTION_DELETE,
                                Uri.parse("package:" + foregroundPackage)));
                    } catch (Throwable error) {
                        status.setText("无法打开卸载界面：" + error.getClass().getSimpleName());
                    }
                }).show();
    }

    private void openSettings(String action) {
        try { startActivity(new Intent(action)); }
        catch (Throwable error) { status.setText("无法打开系统设置：" + error.getClass().getSimpleName()); }
    }
}
