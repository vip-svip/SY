package de.privacyguard.adhook;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Optional user-enabled accessibility integration.
 * It records only service availability; it does not read text, click controls,
 * inspect passwords, or automate actions in other applications.
 */
public final class FxAccessibilityService extends AccessibilityService {
    // Process-local truth prevents a persisted PID marker from surviving a process restart.
    private static volatile boolean connected;

    public static boolean isConnected() { return connected; }
    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        // Intentionally observe no event payload. FX only needs service availability.
    }

    @Override public void onInterrupt() { }

    @Override public boolean onUnbind(Intent intent) {
        connected = false;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", false).remove("service_pid").apply();
        return super.onUnbind(intent);
    }

    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        connected = true;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", true)
                .putInt("service_pid", android.os.Process.myPid()).apply();
    }

    @Override public void onDestroy() {
        connected = false;
        getSharedPreferences("fx_accessibility", MODE_PRIVATE)
                .edit().putBoolean("service_connected", false).remove("service_pid").apply();
        super.onDestroy();
    }
}
