package de.privacyguard.adhook.imported.shield;

import android.app.AppOpsManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;

import java.text.DateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.Set;

/**
 * User-controlled Yulong Shield ProtectService migration.
 *
 * Reads only the foreground package name from Usage Access and applies the
 * original blacklist/whitelist preference lists. It warns the user but never
 * force-stops, disables, freezes, uninstalls apps, changes accessibility
 * settings, or restarts itself.
 */
public final class FxYulongProtectionService extends Service {
    public static final String ACTION_START = "de.privacyguard.adhook.shield.START";
    public static final String ACTION_STOP = "de.privacyguard.adhook.shield.STOP";
    private static final String PREFS = "shield_prefs";
    private static final String CHANNEL = "fx_yulong_protection";
    private static final String ALERT_CHANNEL = "fx_yulong_protection_alert";
    private static final int ONGOING_ID = 0x594d;
    private static final long POLL_MS = 2500L;
    private static final long ALERT_COOLDOWN_MS = 120000L;

    private HandlerThread thread;
    private Handler handler;
    private UsageStatsManager usage;
    private volatile boolean running;

    private final Runnable poll = new Runnable() {
        @Override public void run() {
            if (!running) return;
            try {
                SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
                if (!prefs.getBoolean("protect_on", false) || !hasUsageAccess()) {
                    stopFromPolicy();
                    return;
                }
                String foreground = readForegroundPackage(System.currentTimeMillis() - 8000L);
                if (foreground != null) evaluateForeground(foreground, prefs);
            } catch (Throwable ignored) {
                // One Usage Access/PackageManager failure must not crash the service.
            }
            if (running && handler != null) handler.postDelayed(this, POLL_MS);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        thread = new HandlerThread("fx-yulong-protection");
        thread.start();
        handler = new Handler(thread.getLooper());
        usage = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        createChannels();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("protect_on", false).apply();
            stopSelf();
            return START_NOT_STICKY;
        }
        if (!hasUsageAccess()) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("protect_on", false).apply();
            stopSelf();
            return START_NOT_STICKY;
        }

        startForeground(ONGOING_ID, buildOngoingNotification());
        running = true;
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("protect_service_running", true)
                .putString("protect_service_started_at", DateFormat.getDateTimeInstance().format(new Date()))
                .apply();
        handler.removeCallbacks(poll);
        handler.post(poll);
        return START_NOT_STICKY;
    }

    private boolean hasUsageAccess() {
        try {
            AppOpsManager appOps = (AppOpsManager) getSystemService(APP_OPS_SERVICE);
            return appOps != null && appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), getPackageName())
                    == AppOpsManager.MODE_ALLOWED;
        } catch (Throwable ignored) { return false; }
    }

    private String readForegroundPackage(long since) {
        if (usage == null) return null;
        UsageEvents events = usage.queryEvents(since, System.currentTimeMillis());
        if (events == null) return null;
        UsageEvents.Event event = new UsageEvents.Event();
        String latest = null;
        long latestTime = since;
        while (events.hasNextEvent()) {
            events.getNextEvent(event);
            int type = event.getEventType();
            boolean foreground = type == UsageEvents.Event.MOVE_TO_FOREGROUND;
            if (Build.VERSION.SDK_INT >= 29)
                foreground = foreground || type == UsageEvents.Event.ACTIVITY_RESUMED;
            if (foreground && event.getTimeStamp() >= latestTime) {
                latestTime = event.getTimeStamp();
                latest = event.getPackageName();
            }
        }
        return latest;
    }

    private void evaluateForeground(String packageName, SharedPreferences prefs) {
        if (packageName == null || packageName.isEmpty() || packageName.equals(getPackageName())) return;
        Set<String> blacklist = split(prefs.getString("blacklist_pkgs", ""));
        Set<String> whitelist = split(prefs.getString("whitelist_pkgs", ""));
        if (!blacklist.contains(packageName) || whitelist.contains(packageName)) return;

        long now = System.currentTimeMillis();
        String key = "protect_alert_last_" + Integer.toHexString(packageName.hashCode());
        long last = prefs.getLong(key, 0L);
        if (now - last < ALERT_COOLDOWN_MS) return;

        String label = packageName;
        try {
            label = String.valueOf(getPackageManager().getApplicationLabel(
                    getPackageManager().getApplicationInfo(packageName, 0)));
        } catch (Throwable ignored) { }

        String message = "检测到管控名单应用正在前台：" + label + "（" + packageName + "）。请确认是否为预期操作。";
        prefs.edit().putLong(key, now)
                .putInt("protect_warn_count", prefs.getInt("protect_warn_count", 0) + 1)
                .putString("protect_last_warn_package", packageName)
                .putString("protect_last_warn_time", DateFormat.getDateTimeInstance().format(new Date()))
                .putString("protect_last_warn_message", message)
                .apply();
        showWarning(packageName, label, message);
    }

    private Set<String> split(String values) {
        Set<String> out = new HashSet<>();
        if (values == null || values.trim().isEmpty()) return out;
        for (String value : values.split(",")) {
            String pkg = value.trim();
            if (pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) out.add(pkg);
        }
        return out;
    }

    private void createChannels() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (manager == null) return;
        NotificationChannel ongoing = new NotificationChannel(
                CHANNEL, "游龙安全护盾实时守护", NotificationManager.IMPORTANCE_LOW);
        ongoing.setDescription("用户主动开启的前台应用名单监测");
        manager.createNotificationChannel(ongoing);
        NotificationChannel alerts = new NotificationChannel(
                ALERT_CHANNEL, "游龙安全护盾管控提醒", NotificationManager.IMPORTANCE_HIGH);
        alerts.setDescription("当管控名单应用进入前台时提醒用户");
        manager.createNotificationChannel(alerts);
    }

    private Notification buildOngoingNotification() {
        Intent open = new Intent(this, FxYulongShieldActivity.class);
        PendingIntent content = PendingIntent.getActivity(this, 9023, open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Intent stop = new Intent(this, FxYulongProtectionService.class);
        stop.setAction(ACTION_STOP);
        PendingIntent stopPending = PendingIntent.getService(this, 9024, stop,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        Notification.Builder configured = builder.setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setContentTitle("FX 游龙安全护盾正在守护")
                .setContentText("仅监测用户配置的前台应用名单；不会自动停止应用。")
                .setOngoing(true).setOnlyAlertOnce(true).setContentIntent(content);
        if (Build.VERSION.SDK_INT >= 16) configured.addAction(
                android.R.drawable.ic_menu_close_clear_cancel, "停止守护", stopPending);
        return configured.build();
    }

    private void showWarning(String packageName, String label, String message) {
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (manager == null) return;
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return;
        Intent open = new Intent(this, FxYulongShieldActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent content = PendingIntent.getActivity(this, packageName.hashCode(), open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, ALERT_CHANNEL) : new Notification.Builder(this);
        Notification notification = builder.setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("检测到管控名单应用")
                .setContentText(label + " 正在前台")
                .setStyle(new Notification.BigTextStyle().bigText(message))
                .setContentIntent(content).setAutoCancel(true).build();
        manager.notify(0x5950 ^ packageName.hashCode(), notification);
    }

    private void stopFromPolicy() {
        running = false;
        stopSelf();
    }

    @Override public void onDestroy() {
        running = false;
        if (handler != null) handler.removeCallbacksAndMessages(null);
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("protect_service_running", false).apply();
        if (thread != null) thread.quitSafely();
        stopForeground(true);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
