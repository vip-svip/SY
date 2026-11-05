package de.privacyguard.adhook.imported.shield;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;

/** Install/update auto-risk scan hook migrated from Yulong Shield 9.9.60. */
public final class FxYulongInstallScanReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();
        if (!Intent.ACTION_PACKAGE_ADDED.equals(action)
                && !Intent.ACTION_PACKAGE_REPLACED.equals(action)) return;
        if (Intent.ACTION_PACKAGE_ADDED.equals(action)
                && intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return;
        Uri data = intent.getData();
        String packageName = data == null ? null : data.getSchemeSpecificPart();
        if (packageName == null || packageName.isEmpty()
                || packageName.equals(context.getPackageName())) return;
        final PendingResult pending = goAsync();
        FxYulongRiskScanDispatcher.onPackageInstalled(
                context.getApplicationContext(), packageName, pending::finish);
    }
}
