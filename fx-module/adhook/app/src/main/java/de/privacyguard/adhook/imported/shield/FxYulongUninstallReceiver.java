package de.privacyguard.adhook.imported.shield;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.widget.Toast;

/**
 * Explicit, non-exported shortcut from the Yulong Shield warning notification.
 * It only opens Android's uninstall confirmation; FX never confirms or performs
 * an uninstall itself.
 */
public final class FxYulongUninstallReceiver extends BroadcastReceiver {
    private static final String EXTRA_TARGET_PACKAGE = "target_pkg";

    private static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String packageName = intent.getStringExtra(EXTRA_TARGET_PACKAGE);
        if (!isValidPackageName(packageName)
                || packageName.equals(context.getPackageName())) {
            return;
        }

        final ApplicationInfo target;
        try {
            target = context.getPackageManager().getApplicationInfo(packageName, 0);
        } catch (PackageManager.NameNotFoundException missing) {
            Toast.makeText(context, "目标应用已经不在设备上。", Toast.LENGTH_SHORT).show();
            return;
        }

        // Do not offer a removal shortcut for protected system packages.
        if ((target.flags & (ApplicationInfo.FLAG_SYSTEM
                | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0) {
            Toast.makeText(context, "系统应用不能通过此快捷操作卸载。", Toast.LENGTH_LONG).show();
            return;
        }

        Intent uninstall = new Intent(Intent.ACTION_UNINSTALL_PACKAGE,
                Uri.parse("package:" + packageName));
        uninstall.putExtra(Intent.EXTRA_RETURN_RESULT, true);
        uninstall.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(uninstall);
        } catch (RuntimeException unavailable) {
            // Preserve a useful user-controlled fallback on ROMs that do not
            // expose the package uninstaller Activity.
            Intent details = new Intent(
                    android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + packageName));
            details.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                context.startActivity(details);
            } catch (RuntimeException ignored) {
                Toast.makeText(context, "无法打开系统应用管理界面。", Toast.LENGTH_LONG).show();
            }
        }
    }
}
