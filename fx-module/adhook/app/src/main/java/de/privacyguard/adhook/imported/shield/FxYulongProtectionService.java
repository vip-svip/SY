package de.privacyguard.adhook.imported.shield;

import android.app.AppOpsManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;
import android.os.SystemClock;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;


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
public final class FxYulongProtectionService extends Service implements SensorEventListener {
    public static final String ACTION_START = "de.privacyguard.adhook.shield.START";
    public static final String ACTION_STOP = "de.privacyguard.adhook.shield.STOP";
    private static final String PREFS = "shield_prefs";
    private static final String CHANNEL = "fx_yulong_protection";
    private static final String ALERT_CHANNEL = "fx_yulong_protection_alert";
    private static final int ONGOING_ID = 0x594d;
    private static final long POLL_FALLBACK_MS = 5000L;
    private static final long POLL_ACCESSIBILITY_BACKUP_MS = 15000L;
    private static final long ALERT_COOLDOWN_MS = 120000L;

    private HandlerThread thread;
    private Handler handler;
    private UsageStatsManager usage;
    private SensorManager sensorManager;
    private Sensor accelerometer;
    private long lastShakeAlert;
    private boolean shakeRegistered;
    private volatile boolean running;
    private volatile long lastForegroundSignalAt;

    private boolean foregroundReceiverRegistered;
    private final BroadcastReceiver foregroundChangeReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null || !running) return;
            String packageName = intent.getStringExtra("package_name");
            if (packageName == null || packageName.isEmpty() || handler == null) return;
            lastForegroundSignalAt = SystemClock.elapsedRealtime();
            handler.post(() -> {
                if (!running) return;
                SharedPreferences current = getSharedPreferences(PREFS, MODE_PRIVATE);
                if (current.getBoolean("protect_on", false)) evaluateForeground(packageName, current);
            });
        }
    };

    private final Runnable poll = new Runnable() {
        @Override public void run() {
            if (!running) return;
            try {
                SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
                boolean protectEnabled = prefs.getBoolean("protect_on", false);
                boolean shakeEnabled = prefs.getBoolean("shake_trigger_on", false);
                if (!protectEnabled && !shakeEnabled) {
                    stopFromPolicy();
                    return;
                }
                if (protectEnabled && !hasUsageAccess()) {
                    prefs.edit().putBoolean("protect_on", false).apply();
                    protectEnabled = false;
                    if (!shakeEnabled) {
                        stopFromPolicy();
                        return;
                    }
                }
                if (protectEnabled) {
                    String foreground = readForegroundPackage(System.currentTimeMillis() - 8000L);
                    if (foreground != null) evaluateForeground(foreground, prefs);
                }
            } catch (Throwable ignored) {
                // One Usage Access/PackageManager failure must not crash the service.
            }
            syncShakeSensor();
            if (running && handler != null) handler.postDelayed(this, nextPollDelay());
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        thread = new HandlerThread("fx-yulong-protection");
        thread.start();
        handler = new Handler(thread.getLooper());
        usage = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
        sensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);
        accelerometer = sensorManager == null ? null : sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
        createChannels();
        IntentFilter foregroundFilter = new IntentFilter(
                de.privacyguard.adhook.FxAccessibilityService.ACTION_FOREGROUND_PACKAGE_CHANGED);
        try {
            if (Build.VERSION.SDK_INT >= 33)
                registerReceiver(foregroundChangeReceiver, foregroundFilter, Context.RECEIVER_NOT_EXPORTED);
            else registerReceiver(foregroundChangeReceiver, foregroundFilter);
            foregroundReceiverRegistered = true;
        } catch (Throwable ignored) {
            foregroundReceiverRegistered = false;
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("protect_on", false)
                    .putBoolean("shake_trigger_on", false)
                    .putBoolean("volume_trigger_on", false)
                    .putBoolean("protect_service_running", false)
                    .putString("protect_restore_error", "notification permission revoked")
                    .apply();
            FxYulongKeepAliveReceiver.refreshSchedule(this);
            stopSelf();
            return START_NOT_STICKY;
        }

        if (ACTION_STOP.equals(action)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("protect_on", false)
                    .putBoolean("shake_trigger_on", false)
                    .putBoolean("volume_trigger_on", false)
                    .apply();
            FxYulongKeepAliveReceiver.refreshSchedule(this);
            stopSelf();
            return START_NOT_STICKY;
        }
        SharedPreferences startupPrefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        boolean protectEnabled = startupPrefs.getBoolean("protect_on", false);
        boolean shakeEnabled = startupPrefs.getBoolean("shake_trigger_on", false);
        if (!protectEnabled && !shakeEnabled) {
            startupPrefs.edit().putBoolean("protect_service_running", false).apply();
            FxYulongKeepAliveReceiver.refreshSchedule(this);
            stopSelf();
            return START_NOT_STICKY;
        }
        if (protectEnabled && !hasUsageAccess()) {
            startupPrefs.edit().putBoolean("protect_on", false).apply();
            protectEnabled = false;
            if (!shakeEnabled) {
                startupPrefs.edit().putBoolean("protect_service_running", false).apply();
                FxYulongKeepAliveReceiver.refreshSchedule(this);
                stopSelf();
                return START_NOT_STICKY;
            }
        }

        startForeground(ONGOING_ID, buildOngoingNotification());
        FxYulongKeepAliveReceiver.refreshSchedule(this);
        running = true;
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("protect_service_running", true)
                .putString("protect_service_started_at", DateFormat.getDateTimeInstance().format(new Date()))
                .apply();
        syncShakeSensor();
        handler.removeCallbacks(poll);
        handler.post(poll);
        // User opt-in is persisted in shield_prefs; sticky restart is allowed only
        // while protect_on and Usage Access remain valid in onStartCommand().
        return START_STICKY;
    }

    private long nextPollDelay() {
        // Accessibility foreground-change broadcasts are immediate. Once the
        // bridge has delivered a signal, retain only a slower UsageStats
        // fallback; without the bridge, keep a bounded 5-second fallback.
        return lastForegroundSignalAt > 0L
                ? POLL_ACCESSIBILITY_BACKUP_MS : POLL_FALLBACK_MS;
    }

    private void syncShakeSensor() {
        if (sensorManager == null || accelerometer == null) return;
        boolean enabled = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean("shake_trigger_on", false);
        if (enabled && !shakeRegistered) {
            shakeRegistered = sensorManager.registerListener(
                    this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL, handler);
        } else if (!enabled && shakeRegistered) {
            sensorManager.unregisterListener(this);
            shakeRegistered = false;
        }
    }

    @Override public void onSensorChanged(SensorEvent event) {
        if (event == null || event.values == null || event.values.length < 3) return;
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        if (!prefs.getBoolean("shake_trigger_on", false)) return;
        float x = event.values[0], y = event.values[1], z = event.values[2];
        double magnitude = Math.sqrt(x * x + y * y + z * z);
        long now = SystemClock.elapsedRealtime();
        if (magnitude > 22.5d && now - lastShakeAlert > 12000L) {
            lastShakeAlert = now;
            notifyRescue(this, "检测到强烈摇动，已触发安全护盾提醒。");
        }
    }

    @Override public void onAccuracyChanged(Sensor sensor, int accuracy) { }

    public static void notifyRescue(Context context, String message) {
        if (context == null) return;
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return;
        NotificationManager manager = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE);
        String today = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
                .format(new Date());
        int todayCount = today.equals(prefs.getString("rescue_trigger_day", ""))
                ? prefs.getInt("rescue_trigger_count_today", 0) : 0;
        prefs.edit().putString("rescue_trigger_day", today)
                .putInt("rescue_trigger_count_today", todayCount + 1)
                .putInt("rescue_trigger_count", prefs.getInt("rescue_trigger_count", 0) + 1)
                .putString("rescue_trigger_last_time", DateFormat.getDateTimeInstance().format(new Date()))
                .putString("rescue_trigger_last_message", message)
                .apply();
        String channelId = "fx_yulong_protection_alert";
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    channelId, "游龙安全护盾救援提醒", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("由用户手动开启的音量键/摇动触发提醒");
            manager.createNotificationChannel(channel);
        }
        Intent open = new Intent(context, FxYulongRescueActivity.class);
        open.putExtra(FxYulongRescueActivity.EXTRA_OPENED_FROM_NOTIFICATION, true);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent content = PendingIntent.getActivity(context, 9025, open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, channelId) : new Notification.Builder(context);
        manager.notify(0x5960, builder.setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("FX 安全护盾救援提醒")
                .setContentText(message)
                .setContentIntent(content)
                .setAutoCancel(true).build());
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
        Set<String> blacklist = split(prefs);
        // Manual scans, automatic risk dispatch and real-time foreground warnings
        // must all use the same bounded, fail-open user whitelist policy.
        Set<String> whitelist = FxYulongWhitelistPolicy.load(this);
        if (!blacklist.contains(packageName) || whitelist.contains(packageName)) return;

        long now = System.currentTimeMillis();
        String key = "protect_alert_last_" + packageName;
        long last = prefs.getLong(key, 0L);
        if (now - last < ALERT_COOLDOWN_MS) return;

        String label = packageName;
        try {
            label = String.valueOf(getPackageManager().getApplicationLabel(
                    getPackageManager().getApplicationInfo(packageName, 0)));
        } catch (Throwable ignored) { }

        String message = "检测到管控名单应用正在前台：" + label + "（" + packageName + "）。请确认是否为预期操作。";
        String today = new java.text.SimpleDateFormat("yyyy-MM-dd",
                java.util.Locale.ROOT).format(new Date());
        int dailyWarnings = today.equals(prefs.getString("protect_warn_day", ""))
                ? prefs.getInt("protect_warn_count_today", 0) : 0;
        prefs.edit().putLong(key, now)
                .putInt("protect_warn_count", prefs.getInt("protect_warn_count", 0) + 1)
                .putString("protect_warn_day", today)
                .putInt("protect_warn_count_today", dailyWarnings + 1)
                .putString("protect_last_warn_package", packageName)
                .putString("protect_last_warn_time", DateFormat.getDateTimeInstance().format(new Date()))
                .putString("protect_last_warn_message", message)
                .apply();
        showWarning(packageName, label, message);
    }

    private Set<String> split(SharedPreferences prefs) {
        // A malformed/oversized legacy list or a preference type error is rejected
        // atomically. The service fails open instead of partially enforcing it.
        try {
            return FxYulongBlacklistPolicy.parse(prefs.getString("blacklist_pkgs", ""));
        } catch (RuntimeException corruptPreference) {
            android.util.Log.w("FX-YulongShield",
                    "Cannot read blacklist preference; foreground warnings are disabled for this poll.",
                    corruptPreference);
            return java.util.Collections.emptySet();
        }
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
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
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
                .setContentText("仅运行用户启用的前台名单监测或摇动触发；不会自动停止应用。")
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
        Intent open = new Intent(this, FxYulongWarningActivity.class);
        open.putExtra("package_name", packageName);
        open.putExtra("app_label", label);
        open.putExtra("reason", message);
        open.putExtra("severity", "BLACKLIST");
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        open.setData(Uri.parse("fx-shield-risk://" + Uri.encode(packageName)));
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Intent uninstallIntent = new Intent(this,
                FxYulongUninstallReceiver.class);
        uninstallIntent.putExtra("target_pkg", packageName);
        uninstallIntent.setData(Uri.parse("fx-shield-uninstall://" + Uri.encode(packageName)));
        PendingIntent uninstallAction = PendingIntent.getBroadcast(
                this, 0, uninstallIntent,
                PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, ALERT_CHANNEL) : new Notification.Builder(this);
        Notification notification = builder.setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("检测到管控名单应用")
                .setContentText(label + " 正在前台")
                .setStyle(new Notification.BigTextStyle().bigText(message))
                .addAction(android.R.drawable.ic_menu_delete, "系统卸载确认", uninstallAction)
                .setContentIntent(content).setAutoCancel(true).build();
        manager.notify("fx-shield-risk:" + packageName, 0x5950, notification);
    }

    private void stopFromPolicy() {
        running = false;
        FxYulongKeepAliveReceiver.refreshSchedule(this);
        stopSelf();
    }

    @Override public void onDestroy() {
        running = false;
        if (handler != null) handler.removeCallbacksAndMessages(null);
        if (sensorManager != null) sensorManager.unregisterListener(this);
        shakeRegistered = false;
        if (foregroundReceiverRegistered) {
            try { unregisterReceiver(foregroundChangeReceiver); } catch (Throwable ignored) { }
            foregroundReceiverRegistered = false;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("protect_service_running", false).apply();
        if (thread != null) thread.quitSafely();
        FxYulongKeepAliveReceiver.refreshSchedule(this);
        stopForeground(true);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
