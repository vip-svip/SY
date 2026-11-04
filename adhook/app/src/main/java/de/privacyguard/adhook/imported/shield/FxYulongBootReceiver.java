package de.privacyguard.adhook.imported.shield;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.provider.Settings;

/**
 * Restores only Shield services that the user explicitly enabled before reboot.
 * No background permission is granted or changed automatically.
 */
public final class FxYulongBootReceiver extends BroadcastReceiver {

    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                && !"android.intent.action.QUICKBOOT_POWERON".equals(action)
                && !"com.htc.intent.action.QUICKBOOT_POWERON".equals(action)) return;

        final Context app = context.getApplicationContext();
        android.content.SharedPreferences prefs =
                app.getSharedPreferences("shield_prefs", Context.MODE_PRIVATE);

        if (prefs.getBoolean("protect_on", false) || prefs.getBoolean("shake_trigger_on", false)) {
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

        if (prefs.getBoolean("overlay_rescue_on", false)) {
            if (Settings.canDrawOverlays(app)) {
                try {
                    Intent overlay = new Intent(app, FxYulongRescueOverlayService.class);
                    if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(overlay);
                    else app.startService(overlay);
                } catch (Throwable failure) {
                    prefs.edit().putString("overlay_restore_error",
                            failure.getClass().getSimpleName()).apply();
                }
            } else {
                // A revoked overlay permission must not be silently re-enabled.
                prefs.edit().putBoolean("overlay_rescue_on", false)
                        .putString("overlay_restore_error", "overlay permission revoked").apply();
            }
        }

        // Recompute only after permission degradation has updated the persisted
        // feature flags; otherwise a revoked overlay permission leaves a stale alarm.
        FxYulongKeepAliveReceiver.refreshSchedule(app);
    }
}
