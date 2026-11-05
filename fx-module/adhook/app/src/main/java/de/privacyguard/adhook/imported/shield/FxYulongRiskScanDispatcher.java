package de.privacyguard.adhook.imported.shield;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

/** Shared Yulong 9.9.60 foreground/install risk-scan dispatch and notification policy. */
public final class FxYulongRiskScanDispatcher {
    private static final String PREFS = "shield_prefs";
    private static final String CHANNEL = "fx_yulong_auto_risk";
    private static final long PACKAGE_COOLDOWN_MS = 90_000L;
    private static final Object COOLDOWN_LOCK = new Object();
    private static final AtomicBoolean FULL_SCAN_RUNNING = new AtomicBoolean(false);

    private FxYulongRiskScanDispatcher() { }

    public static void onForegroundPackageChanged(Context context, String packageName) {
        if (context == null || !validPackage(packageName)) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean("auto_block_on", true)) return;
        dispatch(context, packageName, "前台",
                prefs.getBoolean("automatic_content_scan_enabled", false), null);
    }

    public static void onPackageInstalled(Context context, String packageName, Runnable completion) {
        if (context == null || !validPackage(packageName)) {
            finish(completion);
            return;
        }
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean("automatic_install_scan_enabled", true)) {
            finish(completion);
            return;
        }
        dispatch(context, packageName, "安装/更新",
                prefs.getBoolean("automatic_content_scan_enabled", false), completion);
    }

    private static void dispatch(Context context, String packageName, String source,
                                 boolean contentScan, Runnable completion) {
        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        // The same stored user whitelist is applied to foreground/install scans
        // before claiming the cooldown or reading the virus database. A whitelisted
        // app must not continue producing automatic risk notifications.
        if (FxYulongWhitelistPolicy.isWhitelisted(app, packageName)) {
            finish(completion);
            return;
        }
        if (!claimPackage(prefs, packageName)) {
            finish(completion);
            return;
        }

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
                if (matched != null) {
                    status = (matched.severity == FxYulongScanEngine.Severity.CERTAIN
                            ? "确定风险命中：" : "可疑项命中：")
                            + matched.label + "（" + matched.reason + "）";
                } else if (!result.inventoryComplete || result.databaseEntries <= 0 || result.scanned <= 0) {
                    status = "未形成安全结论：" + result.message;
                } else {
                    status = "未命中当前已加载名单（不代表设备绝对安全）";
                }
                recordResult(prefs, packageName, source, status, matched != null);
                if (matched != null) notifyFinding(app, matched,
                        prefs.getString("auto_block_mode", "direct"));
            } catch (Throwable error) {
                android.util.Log.w("FX-YulongRisk", "risk scan callback failed for " + packageName, error);
            } finally {
                finish(completion);
            }
        });
    }

    /** Run the original full installed-app sweep after either Yulong database is refreshed. */
    public static void onVirusDatabaseUpdated(Context context, boolean contentScan) {
        if (context == null) return;
        Context app = context.getApplicationContext();
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!prefs.getBoolean("auto_block_on", true)
                || !FULL_SCAN_RUNNING.compareAndSet(false, true)) return;
        FxYulongScanEngine.scan(app, contentScan, result -> {
            try {
                int notified = 0;
                for (FxYulongScanEngine.Finding finding : result.findings) {
                    if (claimPackage(prefs, finding.packageName)) {
                        notifyFinding(app, finding, prefs.getString("auto_block_mode", "direct"));
                        notified++;
                    }
                }
                String status;
                if (result.databaseEntries <= 0 || result.scanned <= 0) {
                    status = "全量扫描未形成安全结论：" + result.message;
                } else if (!result.inventoryComplete) {
                    status = "全量扫描不完整，不能据此判断所有应用安全；命中 " + result.findings.size() + " 项";
                } else {
                    status = "病毒库更新后扫描 " + result.scanned + " 个应用，命中 "
                            + result.findings.size() + " 项，新提醒 " + notified + " 项"
                            + (result.contentTruncated ? "（内容扫描达到时间预算）" : "");
                }
                recordFullScanResult(prefs, result, status);
            } catch (Throwable error) {
                android.util.Log.w("FX-YulongRisk", "full scan result callback failed", error);
            } finally {
                FULL_SCAN_RUNNING.set(false);
            }
        });
    }

    private static boolean claimPackage(SharedPreferences prefs, String packageName) {
        long now = System.currentTimeMillis();
        synchronized (COOLDOWN_LOCK) {
            String key = "auto_risk_scan_last_attempt_" + packageName;
            long last = prefs.getLong(key, 0L);
            if (last > 0L && now >= last && now - last < PACKAGE_COOLDOWN_MS) return false;
            prefs.edit().putLong(key, now).apply();
            return true;
        }
    }

    private static void recordFullScanResult(SharedPreferences prefs,
                                             FxYulongScanEngine.Result result, String status) {
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date());
        String oldDay = prefs.getString("automatic_scan_day", "");
        int scans = today.equals(oldDay) ? prefs.getInt("automatic_scan_count_today", 0) : 0;
        int findings = today.equals(oldDay) ? prefs.getInt("automatic_scan_findings_today", 0) : 0;
        prefs.edit()
                .putString("automatic_scan_day", today)
                .putInt("automatic_scan_count_today", scans + Math.max(0, result.scanned))
                .putInt("automatic_scan_findings_today", findings + result.findings.size())
                .putString("automatic_scan_last_result", status)
                .putString("automatic_scan_last_package", "全部已安装应用")
                .putString("automatic_scan_last_time", DateFormat.getDateTimeInstance().format(new Date()))
                .apply();
    }

    private static void recordResult(SharedPreferences prefs, String packageName,
                                     String source, String status, boolean hit) {
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date());
        String oldDay = prefs.getString("automatic_scan_day", "");
        int scans = today.equals(oldDay) ? prefs.getInt("automatic_scan_count_today", 0) : 0;
        int findings = today.equals(oldDay) ? prefs.getInt("automatic_scan_findings_today", 0) : 0;
        prefs.edit()
                .putString("automatic_scan_day", today)
                .putInt("automatic_scan_count_today", scans + 1)
                .putInt("automatic_scan_findings_today", findings + (hit ? 1 : 0))
                .putString("automatic_scan_last_result", source + " · " + status)
                .putString("automatic_scan_last_package", packageName)
                .putString("automatic_scan_last_time",
                        DateFormat.getDateTimeInstance().format(new Date()))
                .apply();
    }

    private static void notifyFinding(Context context, FxYulongScanEngine.Finding finding,
                                      String requestedMode) {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            android.util.Log.w("FX-YulongRisk", "notification permission missing for " + finding.packageName);
            return;
        }
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL, "游龙安全护盾自动风险扫描", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("前台应用和新安装应用的病毒名单命中提醒");
            manager.createNotificationChannel(channel);
        }

        boolean direct = "direct".equalsIgnoreCase(requestedMode)
                && finding.severity == FxYulongScanEngine.Severity.CERTAIN;
        Intent open;
        String actionLabel;
        if (direct) {
            // User tap opens Android's uninstall confirmation; this code never uninstalls.
            open = new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + finding.packageName));
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            actionLabel = "点击后由 Android 显示卸载确认";
        } else {
            open = new Intent(context, FxYulongWarningActivity.class);
            open.setData(Uri.parse("fx-risk-warning://" + Uri.encode(finding.packageName)));
            open.putExtra("package_name", finding.packageName);
            open.putExtra("app_label", finding.label);
            open.putExtra("reason", finding.reason);
            open.putExtra("severity", finding.severity.name());
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            actionLabel = "点击查看风险详情并确认处理";
        }
        PendingIntent content = PendingIntent.getActivity(context,
                finding.packageName.hashCode() & 0x7fffffff, open,
                PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        String title = finding.severity == FxYulongScanEngine.Severity.CERTAIN
                ? "发现确定风险应用" : "发现可疑应用";
        String detail = finding.label + "（" + finding.packageName + "）\n"
                + finding.reason + " · " + actionLabel;
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL) : new Notification.Builder(context);
        Notification notification = builder
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle(title)
                .setContentText(finding.label + " · " + finding.reason)
                .setStyle(new Notification.BigTextStyle().bigText(detail))
                .setContentIntent(content)
                .setAutoCancel(true)
                .build();
        manager.notify("fx-yulong-auto-risk:" + finding.packageName, 0x594c, notification);
    }

    private static boolean validPackage(String value) {
        return value != null && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    private static void finish(Runnable callback) {
        if (callback == null) return;
        try { callback.run(); } catch (RuntimeException ignored) { }
    }
}
