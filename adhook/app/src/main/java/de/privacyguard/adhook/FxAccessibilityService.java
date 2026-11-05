package de.privacyguard.adhook;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * FX owns one optional AccessibilityService for foreground detection, YouLong
 * safety helpers and explicitly enabled local GKD rules. GKD node access is
 * gated by the user's separate master switch and exact per-app rule scope.
 */
public final class FxAccessibilityService extends AccessibilityService {
    public static final String ACTION_FOREGROUND_PACKAGE_CHANGED =
            "de.privacyguard.adhook.shield.FOREGROUND_PACKAGE_CHANGED";
    public static final String ACTION_VOLUME_KEY =
            "de.privacyguard.adhook.shield.VOLUME_KEY";
    public static final String ACTION_GKD_CONFIG_CHANGED =
            "de.privacyguard.adhook.GKD_CONFIG_CHANGED";

    private static volatile boolean connected;
    private String lastForegroundPackage = "";
    private boolean gkdConfigReceiverRegistered;
    private final AtomicBoolean gkdWorkPending = new AtomicBoolean(false);
    private final ExecutorService gkdExecutor = Executors.newSingleThreadExecutor(r -> {
        Thread worker = new Thread(r, "fx-gkd-accessibility");
        worker.setDaemon(true);
        return worker;
    });
    private final de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
            volumeTriggerSequence = new de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence();

    private final BroadcastReceiver gkdConfigReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!ACTION_GKD_CONFIG_CHANGED.equals(intent == null ? null : intent.getAction())) return;
            FxGkdAutomationRuntime.invalidateRules();
            applyGkdEventSubscription();
        }
    };

    public static boolean isConnected() { return connected; }

    /** Request an in-process service configuration refresh after user rule changes. */
    public static void requestReconfigure(Context context) {
        if (context == null) return;
        Intent changed = new Intent(ACTION_GKD_CONFIG_CHANGED);
        changed.setPackage(context.getPackageName());
        context.sendBroadcast(changed);
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null) return;
        final int eventType = event.getEventType();
        final CharSequence packageName = event.getPackageName();
        if (packageName == null) return;
        final String pkg = packageName.toString().trim();
        if (pkg.isEmpty() || pkg.equals(getPackageName())) return;

        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                && !pkg.equals(lastForegroundPackage)) {
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

        if (!isGkdEventType(eventType) || !FxGkdRuleStore.hasEnabledRule(this, pkg)) return;
        enqueueGkdScan(pkg);
    }

    private boolean isGkdEventType(int eventType) {
        return eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                || eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                || eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED;
    }

    private void enqueueGkdScan(String eventPackage) {
        if (!gkdWorkPending.compareAndSet(false, true)) return;

        AccessibilityNodeInfo root;
        try {
            root = getRootInActiveWindow();
        } catch (RuntimeException unavailable) {
            gkdWorkPending.set(false);
            return;
        }
        if (root == null) {
            gkdWorkPending.set(false);
            return;
        }

        CharSequence rootPackage;
        try {
            rootPackage = root.getPackageName();
        } catch (RuntimeException staleNode) {
            recycleQuietly(root);
            gkdWorkPending.set(false);
            return;
        }
        if (rootPackage == null || !eventPackage.contentEquals(rootPackage)) {
            recycleQuietly(root);
            gkdWorkPending.set(false);
            return;
        }

        try {
            gkdExecutor.execute(() -> {
                try {
                    FxGkdAutomationRuntime.process(this, eventPackage, root);
                } catch (RuntimeException failure) {
                    // A stale or vendor-specific node must not terminate the only
                    // Accessibility event worker. No screen text is logged.
                    recycleQuietly(root);
                } finally {
                    gkdWorkPending.set(false);
                }
            });
        } catch (RejectedExecutionException stopped) {
            recycleQuietly(root);
            gkdWorkPending.set(false);
        }
    }

    private static void recycleQuietly(AccessibilityNodeInfo node) {
        if (node == null) return;
        try {
            node.recycle();
        } catch (RuntimeException ignored) {
            // AccessibilityNodeInfo may already have been recycled by snapshot cleanup.
        }
    }

    private void registerGkdConfigReceiver() {
        if (gkdConfigReceiverRegistered) return;
        IntentFilter filter = new IntentFilter(ACTION_GKD_CONFIG_CHANGED);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(gkdConfigReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(gkdConfigReceiver, filter);
        }
        gkdConfigReceiverRegistered = true;
    }

    private void applyGkdEventSubscription() {
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) return;
        int wantedEvents = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED;
        int wantedFlags = info.flags;
        boolean gkdEnabled = FxGkdRuleStore.isEnabled(this)
                && FxGkdRuleStore.getRules(this).stream().anyMatch(FxGkdRule::getEnabled);
        if (gkdEnabled) {
            wantedEvents |= AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                    | AccessibilityEvent.TYPE_VIEW_SCROLLED;
            // GKD selectors may target resource IDs (id/vid). Request those IDs
            // only while the user's GKD master switch and at least one rule are on.
            wantedFlags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        } else {
            wantedFlags &= ~AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        }
        if (info.eventTypes != wantedEvents || info.flags != wantedFlags) {
            info.eventTypes = wantedEvents;
            info.flags = wantedFlags;
            setServiceInfo(info);
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
        volumeTriggerSequence.resetSequence();
        FxGkdAutomationRuntime.invalidateRules();
    }

    @Override public boolean onUnbind(Intent intent) {
        volumeTriggerSequence.resetSequence();
        FxGkdAutomationRuntime.invalidateRules();
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
        registerGkdConfigReceiver();
        applyGkdEventSubscription();
    }

    @Override public void onDestroy() {
        volumeTriggerSequence.resetSequence();
        FxGkdAutomationRuntime.invalidateRules();
        if (gkdConfigReceiverRegistered) {
            try {
                unregisterReceiver(gkdConfigReceiver);
            } catch (IllegalArgumentException ignored) { }
            gkdConfigReceiverRegistered = false;
        }
        gkdExecutor.shutdownNow();
        connected = false;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", false).remove("service_pid").apply();
        super.onDestroy();
    }
}
