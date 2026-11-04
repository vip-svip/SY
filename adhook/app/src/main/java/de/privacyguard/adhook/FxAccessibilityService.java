package de.privacyguard.adhook;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Optional user-enabled accessibility integration.
 * It forwards only foreground package names and volume-key direction metadata.
 * It never reads node trees/text, clicks controls, consumes keys or inspects passwords.
 */
public final class FxAccessibilityService extends AccessibilityService {
    public static final String ACTION_FOREGROUND_PACKAGE_CHANGED =
            "de.privacyguard.adhook.shield.FOREGROUND_PACKAGE_CHANGED";
    public static final String ACTION_VOLUME_KEY =
            "de.privacyguard.adhook.shield.VOLUME_KEY";
    private static volatile boolean connected;
    private String lastForegroundPackage = "";
    private final de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
            volumeTriggerSequence = new de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence();

    public static boolean isConnected() { return connected; }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        CharSequence packageName = event.getPackageName();
        if (packageName == null) return;
        String pkg = packageName.toString().trim();
        if (pkg.isEmpty() || pkg.equals(getPackageName()) || pkg.equals(lastForegroundPackage)) return;
        lastForegroundPackage = pkg;

        long now = System.currentTimeMillis();
        getSharedPreferences("fx_accessibility", MODE_PRIVATE).edit()
                .putString("last_foreground_package", pkg)
                .putLong("last_foreground_at", now).apply();
        Intent changed = new Intent(ACTION_FOREGROUND_PACKAGE_CHANGED);
        changed.setPackage(getPackageName());
        changed.putExtra("package_name", pkg);
        changed.putExtra("event_time", now);
        sendBroadcast(changed);
        de.privacyguard.adhook.imported.shield.FxYulongRiskScanDispatcher
                .onForegroundPackageChanged(this, pkg);
    }

    @Override public boolean onKeyEvent(KeyEvent event) {
        if (event == null) return false;
        int key = event.getKeyCode();
        if (key != KeyEvent.KEYCODE_VOLUME_UP && key != KeyEvent.KEYCODE_VOLUME_DOWN) return false;

        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
            int direction = key == KeyEvent.KEYCODE_VOLUME_UP ? 1 : -1;
            Intent changed = new Intent(ACTION_VOLUME_KEY);
            changed.setPackage(getPackageName());
            changed.putExtra("direction", direction);
            changed.putExtra("key_code", key);
            changed.putExtra("event_time", System.currentTimeMillis());
            sendBroadcast(changed);
        }

        if (event.getAction() == KeyEvent.ACTION_UP) {
            SharedPreferences shield = getSharedPreferences("shield_prefs", MODE_PRIVATE);
            if (!shield.getBoolean("volume_trigger_on", false)) {
                volumeTriggerSequence.resetSequence();
            } else {
                String configuredKey = shield.getString("volume_trigger_key", "down");
                int wantedDirection =
                        de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
                                .directionForPreference(configuredKey);
                int requiredCount =
                        de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
                                .normalizeCount(shield.getInt("volume_trigger_count", 3));
                int direction = key == KeyEvent.KEYCODE_VOLUME_UP
                        ? de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence.DIRECTION_UP
                        : de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence.DIRECTION_DOWN;
                if (volumeTriggerSequence.recordPress(direction, wantedDirection,
                        requiredCount, SystemClock.elapsedRealtime())) {
                    String keyLabel = direction == de.privacyguard.adhook.imported.shield
                            .FxYulongVolumeTriggerSequence.DIRECTION_UP ? "音量上键" : "音量下键";
                    de.privacyguard.adhook.imported.shield.FxYulongProtectionService.notifyRescue(
                            this, "连续按下" + keyLabel + " " + requiredCount
                                    + " 次，已触发安全护盾提醒。");
                }
            }
        }
        return false; // Preserve normal Android volume behavior.
    }

    @Override public void onInterrupt() {
        // Do not carry a partial volume-key sequence across service interruptions.
        volumeTriggerSequence.resetSequence();
    }

    @Override public boolean onUnbind(Intent intent) {
        volumeTriggerSequence.resetSequence();
        connected = false;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", false).remove("service_pid").apply();
        return super.onUnbind(intent);
    }

    @Override protected void onServiceConnected() {
        volumeTriggerSequence.resetSequence();
        super.onServiceConnected();
        connected = true;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", true)
                .putInt("service_pid", android.os.Process.myPid()).apply();
    }

    @Override public void onDestroy() {
        volumeTriggerSequence.resetSequence();
        connected = false;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", false).remove("service_pid").apply();
        super.onDestroy();
    }
}
