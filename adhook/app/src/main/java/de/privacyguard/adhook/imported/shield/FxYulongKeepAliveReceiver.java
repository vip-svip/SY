package de.privacyguard.adhook.imported.shield;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.provider.Settings;

/**
 * Low-frequency, user-opted-in recovery tick replacing the original aggressive
 * two-minute KeepAliveAlarm. It restarts only FX-owned Shield services and
 * never changes permissions or acts on other applications.
 */
public final class FxYulongKeepAliveReceiver extends BroadcastReceiver {
    static final String ACTION_KEEPALIVE = "de.privacyguard.adhook.shield.KEEPALIVE";
    private static final long INTERVAL_MS = 15L * 60L * 1000L;
    private static final int REQUEST_CODE = 0x5963;

    public static void refreshSchedule(Context context) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        android.content.SharedPreferences prefs =
                app.getSharedPreferences("shield_prefs", Context.MODE_PRIVATE);
        boolean enabled = prefs.getBoolean("protect_on", false)
                || prefs.getBoolean("overlay_rescue_on", false);
        android.app.AlarmManager alarms =
                (android.app.AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
        if (alarms == null) return;
        Intent tick = new Intent(app, FxYulongKeepAliveReceiver.class);
        tick.setAction(ACTION_KEEPALIVE);
        android.app.PendingIntent pending = android.app.PendingIntent.getBroadcast(app,
                REQUEST_CODE, tick, android.app.PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= 23 ? android.app.PendingIntent.FLAG_IMMUTABLE : 0));
        alarms.cancel(pending);
        if (!enabled) return;
        long next = android.os.SystemClock.elapsedRealtime() + INTERVAL_MS;
        if (Build.VERSION.SDK_INT >= 23)
            alarms.setAndAllowWhileIdle(android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pending);
        else
            alarms.set(android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pending);
    }

    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null || !ACTION_KEEPALIVE.equals(intent.getAction())) return;
        Context app = context.getApplicationContext();
        android.content.SharedPreferences prefs =
                app.getSharedPreferences("shield_prefs", Context.MODE_PRIVATE);

        if (prefs.getBoolean("protect_on", false)) {
            Intent monitor = new Intent(app, FxYulongProtectionService.class);
            monitor.setAction(FxYulongProtectionService.ACTION_START);
            try {
                if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(monitor);
                else app.startService(monitor);
            } catch (Throwable failure) {
                prefs.edit().putBoolean("protect_service_running", false)
                        .putString("protect_restore_error",
                                failure.getClass().getSimpleName()).apply();
            }
        }
        if (prefs.getBoolean("overlay_rescue_on", false) && Settings.canDrawOverlays(app)) {
            try {
                Intent overlay = new Intent(app, FxYulongRescueOverlayService.class);
                if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(overlay);
                else app.startService(overlay);
            } catch (Throwable failure) {
                prefs.edit().putString("overlay_restore_error",
                        failure.getClass().getSimpleName()).apply();
            }
        }
        refreshSchedule(app);
    }
}
