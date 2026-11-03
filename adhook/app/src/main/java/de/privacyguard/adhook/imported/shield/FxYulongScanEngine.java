package de.privacyguard.adhook.imported.shield;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Read-only installed-app scanner using the migrated Shield 9.9.60 database.
 * Installed application results and launcher results are merged by package name.
 * The scanner never disables, freezes, or uninstalls an application.
 */
public final class FxYulongScanEngine {
    public enum Severity { CERTAIN, SUSPECT }

    public static final class Finding {
        public final String packageName;
        public final String label;
        public final Severity severity;
        public final String reason;

        Finding(String packageName, String label, Severity severity, String reason) {
            this.packageName = packageName;
            this.label = label;
            this.severity = severity;
            this.reason = reason;
        }
    }

    public static final class Result {
        public final int scanned;
        public final int databaseEntries;
        public final int certainCount;
        public final int suspectCount;
        public final List<Finding> findings;
        public final String message;
        public final boolean contentScanEnabled;
        public final boolean contentDatabaseReady;
        public final int contentScanned;
        public final boolean contentTruncated;

        Result(int scanned, int entries, List<Finding> findings, int certain, int suspect,
               String message, boolean contentEnabled, boolean contentReady,
               int contentScanned, boolean contentTruncated) {
            this.scanned = scanned;
            this.databaseEntries = entries;
            this.findings = Collections.unmodifiableList(findings);
            this.certainCount = certain;
            this.suspectCount = suspect;
            this.message = message;
            this.contentScanEnabled = contentEnabled;
            this.contentDatabaseReady = contentReady;
            this.contentScanned = contentScanned;
            this.contentTruncated = contentTruncated;
        }
    }

    public interface Callback { void onResult(Result result); }

    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "fx-yulong-scan");
        t.setDaemon(true);
        return t;
    });

    private FxYulongScanEngine() { }

    public static void scan(Context context, Callback callback) {
        scan(context, false, callback);
    }

    public static void scan(Context context, boolean enableContentScan, Callback callback) {
        scanInternal(context, null, enableContentScan, callback);
    }

    /** Scan one package after an install/update event without reading every installed APK. */
    public static void scanPackage(Context context, String packageName,
                                   boolean enableContentScan, Callback callback) {
        if (packageName == null || packageName.trim().isEmpty()) {
            if (callback != null) callback.onResult(new Result(0, 0,
                    Collections.emptyList(), 0, 0, "目标包名为空。", enableContentScan,
                    false, 0, false));
            return;
        }
        scanInternal(context, packageName.trim(), enableContentScan, callback);
    }

    private static void scanInternal(Context context, String onlyPackage,
                                     boolean enableContentScan, Callback callback) {
        Context app = context.getApplicationContext();
        WORKER.execute(() -> {
            List<Finding> findings = new ArrayList<>();
            int scanned = 0;
            int certain = 0;
            int suspect = 0;
            int contentScanned = 0;
            boolean contentTruncated = false;
            boolean contentReady = false;
            long contentDeadline = System.currentTimeMillis() + 8000L;
            String message;
            try {
                FxYulongVirusDb.Data database = FxYulongVirusDb.get(app);
                if (enableContentScan) {
                    FxYulongVirusContentDb.loadFromCache(app);
                    contentReady = FxYulongVirusContentDb.isContentDatabaseReady(app);
                }
                if (database.isEmpty()) {
                    message = "病毒库为空。请先同步名单；无规则时不能把扫描结果解释为安全。";
                    if (callback != null) callback.onResult(new Result(0, 0, findings, 0, 0, message, enableContentScan, contentReady, 0, false));
                    return;
                }

                LinkedHashMap<String, ApplicationInfo> installed = collectInstalled(app);
                PackageManager pm = app.getPackageManager();
                for (ApplicationInfo info : installed.values()) {
                    String pkg = info.packageName == null ? "" : info.packageName.trim();
                    if (onlyPackage != null && !onlyPackage.equals(pkg)) continue;
                    if (pkg.isEmpty() || pkg.equals(app.getPackageName())
                            || "com.youlong.zoo".equals(pkg) || "com.youlong.tool".equals(pkg)) continue;
                    boolean pureSystem = (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                            && (info.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0;
                    if (pureSystem) continue;
                    scanned++;

                    String label;
                    try { label = String.valueOf(pm.getApplicationLabel(info)); }
                    catch (Throwable ignored) { label = pkg; }

                    if (database.isCertain(pkg, label)) {
                        certain++;
                        findings.add(new Finding(pkg, label, Severity.CERTAIN, "命中 100% 病毒包名或名称列表"));
                        continue;
                    }
                    String reason = database.matchSuspect(pkg, label);
                    if (reason != null) {
                        suspect++;
                        findings.add(new Finding(pkg, label, Severity.SUSPECT, reason));
                        continue;
                    }

                    // Optional second phase from the original 9.9.60 content DB.
                    // One shared eight-second deadline prevents long APK reads from freezing the scan.
                    if (enableContentScan && contentReady) {
                        if (System.currentTimeMillis() >= contentDeadline) {
                            contentTruncated = true;
                        } else {
                            try {
                                FxYulongVirusContentDb.Verdict verdict =
                                        FxYulongVirusContentDb.inspectApk(app, pkg, contentDeadline);
                                contentScanned++;
                                if (verdict.truncated) {
                                    contentTruncated = true;
                                } else if (verdict.level == FxYulongVirusContentDb.BLOCK) {
                                    certain++;
                                    findings.add(new Finding(pkg, label, Severity.CERTAIN,
                                            "内容特征命中：" + verdict.reason));
                                } else if (verdict.level == FxYulongVirusContentDb.WARN) {
                                    suspect++;
                                    findings.add(new Finding(pkg, label, Severity.SUSPECT,
                                            "内容特征告警：" + verdict.reason));
                                }
                            } catch (Throwable itemError) {
                                // Keep scanning the remaining apps if one APK is malformed or unreadable.
                            }
                        }
                    }
                }

                findings.sort(Comparator
                        .comparing((Finding f) -> f.severity.ordinal())
                        .thenComparing(f -> f.label.toLowerCase(Locale.ROOT)));
                message = enableContentScan
                        ? (contentReady ? "扫描完成。" : "名单扫描完成；内容特征库未就绪，未执行第二阶段。")
                        : "扫描完成。";
            } catch (Throwable error) {
                message = "扫描失败：" + error.getClass().getSimpleName()
                        + (error.getMessage() == null ? "" : "：" + error.getMessage());
            }
            int entries = 0;
            try { entries = FxYulongVirusDb.get(app).total(); } catch (Throwable ignored) { }
            if (callback != null) callback.onResult(
                    new Result(scanned, entries, findings, certain, suspect, message,
                            enableContentScan, contentReady, contentScanned, contentTruncated));
        });
    }

    private static LinkedHashMap<String, ApplicationInfo> collectInstalled(Context context) {
        PackageManager pm = context.getPackageManager();
        LinkedHashMap<String, ApplicationInfo> result = new LinkedHashMap<>();
        try {
            for (ApplicationInfo app : pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                if (app != null && app.packageName != null) result.put(app.packageName, app);
            }
        } catch (Throwable ignored) { }

        // Some ROMs restrict the installed-app query. Merge launcher-visible apps as a fallback.
        try {
            Intent launcher = new Intent(Intent.ACTION_MAIN);
            launcher.addCategory(Intent.CATEGORY_LAUNCHER);
            List<ResolveInfo> resolved = pm.queryIntentActivities(launcher, 0);
            if (resolved != null) {
                for (ResolveInfo item : resolved) {
                    if (item.activityInfo == null) continue;
                    ApplicationInfo app = item.activityInfo.applicationInfo;
                    if (app != null && app.packageName != null) result.put(app.packageName, app);
                }
            }
        } catch (Throwable ignored) { }
        return result;
    }
}
