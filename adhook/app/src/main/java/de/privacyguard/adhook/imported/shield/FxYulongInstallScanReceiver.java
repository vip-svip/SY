package de.privacyguard.adhook.imported.shield;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;

import java.text.DateFormat;
import java.util.Date;

/** Install-time scan hook migrated from Yulong Shield 9.9.60. */
public final class FxYulongInstallScanReceiver extends BroadcastReceiver {
    private static final String PREFS = "shield_prefs";
    private static final String CHANNEL = "fx_yulong_install_scan";
    private static final int NOTIFICATION_ID = 0x594c;

    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();
        if (!Intent.ACTION_PACKAGE_ADDED.equals(action)
                && !Intent.ACTION_PACKAGE_REPLACED.equals(action)) return;
        if (Intent.ACTION_PACKAGE_ADDED.equals(action)
                && intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return;

        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean("automatic_install_scan_enabled", false)) return;

        Uri data = intent.getData();
        String packageName = data == null ? null : data.getSchemeSpecificPart();
        if (packageName == null || packageName.isEmpty()
                || packageName.equals(context.getPackageName())) return;

        final PendingResult pending = goAsync();
        final Context app = context.getApplicationContext();
        final boolean contentScan = prefs.getBoolean("automatic_content_scan_enabled", false);
        FxYulongScanEngine.scanPackage(app, packageName, contentScan, result -> {
            try {
                FxYulongScanEngine.Finding matched = null;
                for (FxYulongScanEngine.Finding finding : result.findings) {
                    if (packageName.equals(finding.packageName)) {
                        matched = finding;
                        break;
                    }
                }

                String status;
                String title;
                String detail;
                if (matched != null) {
                    status = (matched.severity == FxYulongScanEngine.Severity.CERTAIN
                            ? "高风险命中：" : "可疑项命中：")
                            + matched.label + "（" + matched.reason + "）";
                    title = matched.severity == FxYulongScanEngine.Severity.CERTAIN
                            ? "发现高风险应用" : "发现可疑应用";
                    detail = matched.label + "\n" + packageName + "\n" + matched.reason;
                } else {
                    status = result.databaseEntries <= 0
                            ? "扫描未形成安全结论：病毒库为空"
                            : "未命中当前已加载的病毒名单";
                    title = "新应用检测完成";
                    detail = packageName + "\n" + status;
                }

                prefs.edit()
                        .putString("automatic_scan_last_result", status)
                        .putString("automatic_scan_last_package", packageName)
                        .putString("automatic_scan_last_time",
                                DateFormat.getDateTimeInstance().format(new Date()))
                        .apply();
                if (matched != null) showFindingNotification(app, title, detail);
            } catch (Throwable ignored) {
                // Never let one broken package or notification break package installation.
            } finally {
                pending.finish();
            }
        });
    }

    private static void showFindingNotification(Context context, String title, String detail) {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return;
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL, "游龙安全护盾安装检测", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("显示新安装应用的名单命中提示");
            manager.createNotificationChannel(channel);
        }
        Intent open = new Intent(context, FxYulongScanActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent content = PendingIntent.getActivity(context, 9021, open,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL)
                : new Notification.Builder(context);
        Notification notification = builder
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle(title)
                .setContentText(detail.replace('\n', ' '))
                .setStyle(new Notification.BigTextStyle().bigText(detail))
                .setContentIntent(content)
                .setAutoCancel(true)
                .build();
        manager.notify(NOTIFICATION_ID, notification);
    }
}
