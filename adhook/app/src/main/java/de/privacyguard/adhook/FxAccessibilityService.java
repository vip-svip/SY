package de.privacyguard.adhook;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

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

    /**
     * Called after the user changes local GKD rules. The existing service owns
     * the single Accessibility lifecycle; this only invalidates its in-memory
     * compiled-rule cache and never starts another service.
     */
    public static void requestReconfigure(Context context) {
        if (context == null) return;
        FxGkdAutomationRuntime.invalidateRules();
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null) return;
        final int eventType = event.getEventType();
        final boolean foregroundChanged = eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED;
        final boolean automationEvent = foregroundChanged
                || eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                || eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED;
        if (!automationEvent) return;

        CharSequence packageName = event.getPackageName();
        if (packageName == null) return;
        String pkg = packageName.toString().trim();
        if (pkg.isEmpty() || pkg.equals(getPackageName())) return;

        if (foregroundChanged && !pkg.equals(lastForegroundPackage)) {
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

        // The GKD master switch is OFF by default. Only a locally configured,
        // enabled rule for this exact installed package may read an Accessibility
        // tree and execute its user-authored action.
        if (!FxGkdRuleStore.hasEnabledRule(this, pkg)) return;
        AccessibilityNodeInfo root = null;
        try {
            root = getRootInActiveWindow();
            if (root == null) return;
            CharSequence rootPackage = root.getPackageName();
            if (rootPackage == null || !pkg.equals(rootPackage.toString())) {
                try { root.recycle(); } catch (RuntimeException ignored) {}
                return;
            }
            // process() takes ownership of and recycles this root on every path.
            FxGkdAutomationRuntime.process(this, pkg, root);
            root = null;
        } catch (RuntimeException unavailable) {
            // Accessibility providers can detach a window between the event and
            // root lookup. Do not crash the shared FX service.
        } finally {
            if (root != null) {
                try { root.recycle(); } catch (RuntimeException ignored) {}
            }
        }
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
