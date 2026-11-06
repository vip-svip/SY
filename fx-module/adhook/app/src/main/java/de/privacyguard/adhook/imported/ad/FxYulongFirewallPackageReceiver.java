package de.privacyguard.adhook.imported.ad;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;

import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * Rebuilds the Yulong per-app firewall after package lifecycle changes.
 * Only runs after the user has enabled the firewall in its native settings page.
 */
public final class FxYulongFirewallPackageReceiver extends BroadcastReceiver {
    private static final String PREFS = "yulong_app_firewall";
    private static final String PREF_MASTER = "master_enabled";

    private static final ThreadPoolExecutor EXECUTOR = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            runnable -> {
                Thread thread = new Thread(runnable, "fx-yulong-firewall-package");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();
        boolean added = Intent.ACTION_PACKAGE_ADDED.equals(action);
        boolean removed = Intent.ACTION_PACKAGE_REMOVED.equals(action)
                || Intent.ACTION_PACKAGE_FULLY_REMOVED.equals(action);
        boolean replaced = Intent.ACTION_PACKAGE_REPLACED.equals(action);
        if (!added && !removed && !replaced) return;

        // Package updates emit a remove/add pair before PACKAGE_REPLACED.
        // Ignore that intermediate pair and reconcile once the new UID exists.
        if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                && (added || removed)) return;

        Uri data = intent.getData();
        String packageName = data == null ? null : data.getSchemeSpecificPart();
        if (packageName == null || packageName.trim().isEmpty()
                || packageName.equals(context.getPackageName())
                || "android".equals(packageName)) return;

        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        final boolean firewallEnabled = prefs.getBoolean(PREF_MASTER, false);

        final PendingResult pending = goAsync();
        try {
            EXECUTOR.execute(() -> {
                try {
                    RootAccess.Result result = RootAccess.execute(packageLifecycleCommand(firewallEnabled),
                            15000L, 96 * 1024);
                    if (result.exitCode != 0) {
                        android.util.Log.w("FXYulongFirewall",
                                "Package-change firewall reconcile failed (exit "
                                        + result.exitCode + "): " + safe(result.output));
                    }
                } catch (Throwable error) {
                    android.util.Log.w("FXYulongFirewall",
                            "Package-change firewall reconcile threw", error);
                } finally {
                    try { pending.finish(); } catch (RuntimeException ignored) { }
                }
            });
        } catch (RejectedExecutionException full) {
            android.util.Log.w("FXYulongFirewall",
                    "Package-change reconcile queue is full; next package event or boot will retry");
            try { pending.finish(); } catch (RuntimeException ignored) { }
        }
    }

    private static String packageLifecycleCommand(boolean firewallEnabled) {
        return "MP=''; for d in /data/adb/modules/privacyguard "
                + "/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard "
                + "/data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -qx 'id=privacyguard' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; _rc=0; "
                + (firewallEnabled
                    ? "sh \"$MP/scripts/yulong-app-firewall.sh\" apply-event || _rc=$?; "
                    : "")
                // Prune both independent bypass lists when module settings are present.
                + "if [ -f /data/adb/privacyguard/settings.conf ]; then "
                + "sh \"$MP/scripts/yulong-app-whitelist.sh\" prune || _rc=$?; fi; "
                // Root Proxy combines its own DNS whitelist prune and route reconcile.
                + "sh \"$MP/scripts/yulong-root-proxy.sh\" package-event || _rc=$?; "
                + "exit \"$_rc\"";
    }

    private static String safe(String value) {
        if (value == null || value.trim().isEmpty()) return "no output";
        String text = value.trim();
        return text.length() > 500 ? text.substring(0, 500) + "…" : text;
    }
}
