package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import de.privacyguard.adhook.DeveloperHookRule;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Read-only DEX class-name browser migrated from Dia 23.11. */
public final class FxDiaDexBrowserActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int REQUEST_DEX_DOCUMENT = 0xD3A;
    private static final String STATE_SOURCE_KIND = "fx_dex_source_kind";
    private static final String STATE_TARGET_PACKAGE = "fx_dex_target_package";
    private static final String STATE_DOCUMENT_URI = "fx_dex_document_uri";
    private static final String STATE_DOCUMENT_NAME = "fx_dex_document_name";
    private static final String STATE_DOCUMENT_PERSISTED = "fx_dex_document_persisted";
    private static final String STATE_QUERY = "fx_dex_query";
    private static final String STATE_SCROLL_Y = "fx_dex_scroll_y";
    private static final int MAX_QUERY_CHARS = 256;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> new Thread(r, "fx-dia-dex-io"), new ThreadPoolExecutor.AbortPolicy());
    private final ThreadPoolExecutor searchWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-dia-dex-search"), new ThreadPoolExecutor.DiscardOldestPolicy());
    private final ThreadPoolExecutor exportWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-dia-dex-export"), new ThreadPoolExecutor.DiscardOldestPolicy());
    private final ThreadPoolExecutor detailWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-dia-dex-detail"), new ThreadPoolExecutor.DiscardOldestPolicy());
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> appLabels = new HashMap<>();
    private volatile int searchGeneration;
    private volatile int exportGeneration;
    private volatile int detailGeneration;
    private volatile int dexGeneration;
    private boolean appsLoading;
    private volatile boolean destroyed;
    private String sourceKind = "none";
    private String documentName = "selected.dex";
    private Uri documentUri;
    private boolean documentPermissionPersisted;
    private String restoredQuery = "";
    private int restoredScrollY;
    private boolean restoreScrollPending;
    private boolean restoringSourceState;
    private ScrollView resultScroll;

    private static final class SearchHit {
        final FxDiaDexIndex.DexClass item;
        final List<String> matches;
        SearchHit(FxDiaDexIndex.DexClass item, List<String> matches) {
            this.item = item;
            this.matches = matches;
        }
    }
    private final List<FxDiaDexIndex.DexClass> classes = new ArrayList<>();
    private EditText filter;
    private TextView target;
    private TextView summary;
    private LinearLayout results;
    private ApplicationInfo selected;

    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView t = new TextView(this);
        t.setText(value); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this); panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(10), dp(14), dp(10)); panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 16, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5)); parent.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            sourceKind = state.getString(STATE_SOURCE_KIND, "none");
            if (!"installed-selected".equals(sourceKind)
                    && !"installed-loaded".equals(sourceKind)
                    && !"framework".equals(sourceKind)
                    && !"document".equals(sourceKind)) sourceKind = "none";
            restoredQuery = state.getString(STATE_QUERY, "");
            if (restoredQuery.length() > MAX_QUERY_CHARS)
                restoredQuery = restoredQuery.substring(0, MAX_QUERY_CHARS);
            restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            restoreScrollPending = restoredScrollY > 0;
            documentName = state.getString(STATE_DOCUMENT_NAME, "selected.dex");
            if (documentName == null || documentName.length() > 256) documentName = "selected.dex";
            String savedUri = state.getString(STATE_DOCUMENT_URI);
            if ("document".equals(sourceKind) && savedUri != null && savedUri.length() <= 4096) {
                try { documentUri = Uri.parse(savedUri); }
                catch (RuntimeException invalid) { documentUri = null; }
                documentPermissionPersisted = state.getBoolean(STATE_DOCUMENT_PERSISTED, false);
            } else if ("document".equals(sourceKind)) {
                sourceKind = "none";
            }
        }
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Hook", this::finish));
        header.addView(text("Hook · DEX 查找与解析", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        resultScroll = scroll;
        LinearLayout body = new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18)); scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 4);

        target = text("尚未选择应用。", 13, 0xff334155, false);
        summary = text("选择应用后读取 APK 中的 DEX 类名。", 13, 0xff334155, false);
        filter = new EditText(this); filter.setSingleLine(true); filter.setHint("搜索类名、方法名、字段名或描述符");
        filter.setText(restoredQuery);
        results = new LinearLayout(this); results.setOrientation(LinearLayout.VERTICAL);
        card(body, "目标 APK", "只读解析 DEX class/method/field 索引；不加载目标类、不执行目标代码。",
                target, button("选择已安装应用", this::chooseApp),
                button("读取 DEX 类名", this::loadDex),
                button("浏览 Dia 原版 Android Framework DEX", this::loadFrameworkDex));
        card(body, "独立 DEX 文件", "读取本地或文档提供方中的 DEX 文件，建立只读索引；不会加载或运行文件内容。",
                button("选择 DEX 文件", this::chooseDexDocument));
        card(body, "搜索", "结果只显示类名、方法/字段签名和来源 APK，不读取目标应用私有数据库或进程内存。",
                filter, summary, button("导出当前匹配的类/方法/字段签名", this::exportMatches));
        body.addView(results);
        filter.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                exportGeneration++;
                detailGeneration++;
                resetResultScrollRestoration();
                render();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        loadInstalledApps();
        restoringSourceState = true;
        try { restoreSourceAfterRecreation(state); }
        finally { restoringSourceState = false; }
    }

    private void restoreSourceAfterRecreation(Bundle state) {
        if (state == null || "none".equals(sourceKind)) return;
        if ("framework".equals(sourceKind)) {
            loadFrameworkDex();
            return;
        }
        if ("document".equals(sourceKind)) {
            if (documentUri == null) {
                summary.setText("上次选择的 DEX 文件 URI 无效，请重新选择文件。");
                sourceKind = "none";
                documentPermissionPersisted = false;
                return;
            }
            if (!documentPermissionPersisted) {
                summary.setText("正在尝试恢复上次选择的 DEX 文件；若文件提供方未保留本次读取授权，请重新选择文件。");
            }
            loadDexDocument(documentUri, documentName);
            return;
        }
        String packageName = state.getString(STATE_TARGET_PACKAGE, "");
        if (packageName.isEmpty()) {
            summary.setText("上次选择的应用信息无效，请重新选择应用。");
            sourceKind = "none";
            return;
        }
        try {
            selected = getPackageManager().getApplicationInfo(packageName, 0);
            CharSequence label = getPackageManager().getApplicationLabel(selected);
            target.setText(String.valueOf(label) + "\n" + packageName);
            if ("installed-loaded".equals(sourceKind)) loadDex();
            else summary.setText("已恢复目标应用。点击“读取 DEX 类名”重新建立只读索引。");
        } catch (PackageManager.NameNotFoundException missing) {
            selected = null;
            sourceKind = "none";
            summary.setText("上次选择的应用已卸载，请重新选择应用。");
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putString(STATE_SOURCE_KIND, sourceKind);
        if (selected != null && selected.packageName != null)
            outState.putString(STATE_TARGET_PACKAGE, selected.packageName);
        if (documentUri != null && documentUri.toString().length() <= 4096)
            outState.putString(STATE_DOCUMENT_URI, documentUri.toString());
        if (documentName != null && documentName.length() <= 256)
            outState.putString(STATE_DOCUMENT_NAME, documentName);
        outState.putBoolean(STATE_DOCUMENT_PERSISTED, documentPermissionPersisted);
        String query = filter == null || filter.getText() == null
                ? "" : filter.getText().toString();
        outState.putString(STATE_QUERY,
                query.length() > MAX_QUERY_CHARS ? query.substring(0, MAX_QUERY_CHARS) : query);
        outState.putInt(STATE_SCROLL_Y,
                Math.max(0, resultScroll == null ? restoredScrollY : resultScroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    private void resetResultScrollRestoration() {
        restoreScrollPending = false;
        restoredScrollY = 0;
        if (resultScroll != null) resultScroll.scrollTo(0, 0);
    }

    private void restoreResultScrollAfterRender() {
        if (!restoreScrollPending || resultScroll == null) return;
        final ScrollView expected = resultScroll;
        final int y = restoredScrollY;
        restoreScrollPending = false;
        expected.post(() -> {
            if (!destroyed && !isFinishing() && !isDestroyed() && expected == resultScroll)
                expected.scrollTo(0, y);
        });
    }

    private void releaseDocumentPermission() {
        Uri old = documentUri;
        boolean release = documentPermissionPersisted;
        documentUri = null;
        documentPermissionPersisted = false;
        if (release && old != null) {
            try {
                getContentResolver().releasePersistableUriPermission(
                        old, Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } catch (SecurityException | IllegalArgumentException ignored) { }
        }
    }

    private void chooseDexDocument() {
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("*/*");
        picker.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                "application/vnd.android.dex", "application/octet-stream"
        });
        try {
            startActivityForResult(picker, REQUEST_DEX_DOCUMENT);
        } catch (RuntimeException error) {
            summary.setText("无法打开文件选择器：" + error.getClass().getSimpleName());
        }
    }

    private String documentName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(uri,
                new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0 && cursor.getString(index) != null) return cursor.getString(index);
            }
        } catch (RuntimeException ignored) { }
        return "selected.dex";
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_DEX_DOCUMENT) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            summary.setText("没有选择 DEX 文件。");
            return;
        }
        final Uri uri = data.getData();
        final String name = documentName(uri);
        resetResultScrollRestoration();
        int grantFlags = data.getFlags();
        boolean persisted = false;
        if ((grantFlags & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0
                && (grantFlags & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0) {
            try {
                getContentResolver().takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                persisted = true;
            } catch (SecurityException | IllegalArgumentException ignored) { }
        }
        boolean sameDocument = uri.equals(documentUri);
        if (!sameDocument) releaseDocumentPermission();
        documentUri = uri;
        documentName = name == null || name.length() > 256 ? "selected.dex" : name;
        documentPermissionPersisted = persisted || (sameDocument && documentPermissionPersisted);
        sourceKind = "document";
        selected = null;
        loadDexDocument(uri, documentName);
    }

    private void loadDexDocument(Uri uri, String name) {
        if (uri == null) {
            summary.setText("DEX 文档 URI 无效，请重新选择文件。");
            return;
        }
        final int request = ++dexGeneration;
        searchGeneration++;
        exportGeneration++;
        detailGeneration++;
        selected = null;
        classes.clear();
        target.setText("DEX 文件：" + name);
        summary.setText(documentPermissionPersisted
                ? "正在后台只读解析 DEX 文件…"
                : "正在读取本次选择的 DEX 文件；该文件授权可能无法跨进程重建…");
        results.removeAllViews();
        try {
            worker.execute(() -> {
                Map<String, FxDiaDexIndex.DexClass> found = new java.util.TreeMap<>();
                String failure = null;
                try (InputStream input = getContentResolver().openInputStream(uri)) {
                    if (input == null) throw new IOException("文件提供方没有返回数据流");
                    found.putAll(FxDiaDexIndex.readDex(input,
                            () -> Thread.currentThread().isInterrupted() || request != dexGeneration));
                } catch (Throwable error) {
                    failure = error.getClass().getSimpleName() + ": " + error.getMessage();
                }
                final String message = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed() || request != dexGeneration) return;
                    classes.clear();
                    if (message == null) classes.addAll(found.values());
                    int methods = 0, fields = 0;
                    for (FxDiaDexIndex.DexClass item : classes) {
                        methods += item.methods.size();
                        fields += item.fields.size();
                    }
                    summary.setText(message == null
                            ? "解析完成：" + classes.size() + " 个类 · " + methods + " 个方法 · " + fields + " 个字段。文件仅用于索引预览。"
                            : "解析失败：" + message);
                    render();
                });
            });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 后台队列繁忙，请稍后重试。");
        }
    }

    private void loadInstalledApps() {
        if (appsLoading || destroyed) return;
        appsLoading = true;
        summary.setText("正在后台读取已安装应用…");
        try {
            worker.execute(() -> {
                List<ApplicationInfo> loaded = new ArrayList<>();
                Map<String, String> loadedLabels = new HashMap<>();
                Throwable failure = null;
                try {
                    PackageManager pm = getApplicationContext().getPackageManager();
                    loaded.addAll(pm.getInstalledApplications(0));
                    loaded.removeIf(app -> app.packageName == null || app.packageName.equals(getPackageName()));
                    for (ApplicationInfo app : loaded) {
                        try {
                            loadedLabels.put(app.packageName, String.valueOf(pm.getApplicationLabel(app)));
                        } catch (Throwable ignored) {
                            loadedLabels.put(app.packageName, app.packageName);
                        }
                    }
                    loaded.sort(Comparator.comparing(app ->
                            loadedLabels.getOrDefault(app.packageName, app.packageName).toLowerCase(Locale.ROOT)));
                } catch (Throwable error) {
                    failure = error;
                }
                final Throwable readFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    appsLoading = false;
                    if (readFailure != null) {
                        summary.setText("读取应用清单失败：" + readFailure.getClass().getSimpleName());
                        return;
                    }
                    apps.clear();
                    apps.addAll(loaded);
                    appLabels.clear();
                    appLabels.putAll(loadedLabels);
                    // The APK/Framework/SAF source loader may have started while this
                    // independent inventory request was still running. Never let its
                    // late status text overwrite the active DEX parse/result status.
                    if ("none".equals(sourceKind) || "installed-selected".equals(sourceKind)) {
                        summary.setText("已读取 " + apps.size() + " 个应用；选择目标后读取 DEX。");
                    }
                });
            });
        } catch (RejectedExecutionException full) {
            appsLoading = false;
            summary.setText("应用清单后台队列繁忙，请稍后重试。");
        }
    }

    private void chooseApp() {
        if (appsLoading) {
            summary.setText("应用清单仍在后台读取，请稍后选择。");
            return;
        }
        if (apps.isEmpty()) {
            loadInstalledApps();
            summary.setText("正在读取应用清单；读取完成后再次点击选择。");
            return;
        }
        String[] labels = new String[apps.size()];
        for (int i = 0; i < apps.size(); i++) {
            String label = appLabels.getOrDefault(apps.get(i).packageName, apps.get(i).packageName);
            labels[i] = label + "\n" + apps.get(i).packageName;
        }
        fxDialogBuilder().setTitle("选择要分析的 APK")
                .setItems(labels, (dialog, which) -> {
                    releaseDocumentPermission();
                    resetResultScrollRestoration();
                    sourceKind = "installed-selected";
                    selected = apps.get(which);
                    dexGeneration++;
                    exportGeneration++;
                    detailGeneration++;
                    target.setText(labels[which]);
                    classes.clear(); render();
                }).setNegativeButton("取消", null).show();
    }

    private void loadFrameworkDex() {
        if (!restoringSourceState) resetResultScrollRestoration();
        releaseDocumentPermission();
        sourceKind = "framework";
        selected = null;
        exportGeneration++;
        detailGeneration++;
        summary.setText("正在读取可访问的 Android Framework DEX…");
        results.removeAllViews();
        final int request = ++dexGeneration;
        try {
        worker.execute(() -> {
            final java.util.Map<String, FxDiaDexIndex.DexClass> found = new java.util.TreeMap<>();
            String error = null;
            try (java.io.InputStream input = getAssets().open("dia/android_framework.dex")) {
                found.putAll(FxDiaDexIndex.readDex(input,
                        () -> Thread.currentThread().isInterrupted() || request != dexGeneration));
            } catch (Throwable failure) {
                error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
            }
            final String err = error;
            runOnUiThread(() -> {
                if (destroyed || isFinishing() || isDestroyed() || request != dexGeneration) return;
                selected = null;
                target.setText("Dia 原版 Android Framework DEX");
                classes.clear();
                classes.addAll(found.values());
                int methods = 0, fields = 0;
                for (FxDiaDexIndex.DexClass c : classes) {
                    methods += c.methods.size();
                    fields += c.fields.size();
                }
                summary.setText("已读取 Framework DEX：" + classes.size()
                        + " 个类 · " + methods + " 个方法 · " + fields + " 个字段"
                        + (err == null ? "" : " · 解析错误：" + err));
                render();
            });
        });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 后台队列繁忙，请稍后重试。");
        }
    }

    private void loadDex() {
        if (selected == null) { summary.setText("请先选择应用。"); return; }
        if (!restoringSourceState) resetResultScrollRestoration();
        releaseDocumentPermission();
        sourceKind = "installed-loaded";
        final ApplicationInfo app = selected;
        final int request = ++dexGeneration;
        summary.setText("正在只读解析 DEX 类、方法与字段索引…");
        results.removeAllViews();
        try {
        worker.execute(() -> {
            List<String> paths = new ArrayList<>();
            if (app.sourceDir != null) paths.add(app.sourceDir);
            if (app.splitSourceDirs != null) Collections.addAll(paths, app.splitSourceDirs);
            final java.util.Map<String, FxDiaDexIndex.DexClass> found = new java.util.TreeMap<>();
            String error = null;
            try {
                found.putAll(FxDiaDexIndex.readApks(paths,
                        () -> Thread.currentThread().isInterrupted() || request != dexGeneration));
            } catch (Throwable failure) {
                error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
            }
            final String err = error;
            runOnUiThread(() -> {
                if (destroyed || isFinishing() || isDestroyed() || request != dexGeneration) return;
                classes.clear();
                classes.addAll(found.values());
                int methods = 0, fields = 0;
                for (FxDiaDexIndex.DexClass c : classes) {
                    methods += c.methods.size();
                    fields += c.fields.size();
                }
                summary.setText("已解析 " + classes.size() + " 个类 · " + methods
                        + " 个方法 · " + fields + " 个字段"
                        + (classes.size() >= 100000 ? " · 达到安全上限" : "")
                        + (err == null ? "" : " · 解析错误：" + err));
                render();
            });
        });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 后台队列繁忙，请稍后重试。");
        }
    }

    private void render() {
        if (results == null || destroyed) return;
        final int request = ++searchGeneration;
        final String q = filter.getText() == null ? ""
                : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        final List<FxDiaDexIndex.DexClass> snapshot = new ArrayList<>(classes);
        try {
            searchWorker.execute(() -> {
                List<SearchHit> hits = new ArrayList<>();
                boolean hasMore = false;
                for (FxDiaDexIndex.DexClass item : snapshot) {
                    if (Thread.currentThread().isInterrupted() || request != searchGeneration) return;
                    String className = item.javaName();
                    boolean classMatch = q.isEmpty() || className.toLowerCase(Locale.ROOT).contains(q)
                            || item.descriptor.toLowerCase(Locale.ROOT).contains(q);
                    List<String> matches = new ArrayList<>();
                    if (!classMatch && !q.isEmpty()) {
                        for (FxDiaDexIndex.Member member : item.methods) {
                            if (Thread.currentThread().isInterrupted() || request != searchGeneration) return;
                            if (member.display().toLowerCase(Locale.ROOT).contains(q))
                                matches.add(member.display());
                        }
                        for (FxDiaDexIndex.Member member : item.fields) {
                            if (Thread.currentThread().isInterrupted() || request != searchGeneration) return;
                            if (member.display().toLowerCase(Locale.ROOT).contains(q))
                                matches.add(member.display());
                        }
                    }
                    if (!classMatch && matches.isEmpty()) continue;
                    if (hits.size() >= 300) {
                        hasMore = true;
                        break;
                    }
                    hits.add(new SearchHit(item, matches));
                }
                final boolean truncated = hasMore;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed() || request != searchGeneration) return;
                    results.removeAllViews();
                    for (SearchHit hit : hits) {
                        DexClassRow(hit);
                    }
                    if (hits.isEmpty()) results.addView(text(
                            snapshot.isEmpty() ? "尚无 DEX 结果。" : "没有匹配的类、方法或字段。",
                            13, 0xff718091, false));
                    else if (truncated) results.addView(text(
                            "仅显示前 300 个匹配类，请缩小搜索范围。",
                            12, 0xff8a6d3b, false));
                    restoreResultScrollAfterRender();
                });
            });
        } catch (RejectedExecutionException full) {
            // The search executor discards the oldest queued query; this callback
            // is only a defensive fallback for an unexpected shutdown/rejection.
        }
    }

    private void DexClassRow(SearchHit hit) {
        FxDiaDexIndex.DexClass item = hit.item;
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(12), dp(6), dp(12), dp(6));
        TextView title = text(item.javaName(), 12, 0xff17212b, true);
        TextView detail = text("方法 " + item.methods.size() + " · 字段 " + item.fields.size()
                + (hit.matches.isEmpty() ? "" : " · 命中成员 " + hit.matches.size()),
                10, 0xff718091, false);
        row.addView(title);
        row.addView(detail);
        row.setBackgroundColor(0xffffffff);
        row.setOnClickListener(v -> showClassMembers(item));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(10), dp(2), dp(10), dp(2));
        results.addView(row, lp);
    }

    private void exportMatches() {
        if (classes.isEmpty()) {
            summary.setText("尚无可导出的 DEX 索引，请先读取 DEX。");
            return;
        }
        final int request = ++exportGeneration;
        final String q = filter.getText() == null ? ""
                : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        final List<FxDiaDexIndex.DexClass> snapshot = new ArrayList<>(classes);
        summary.setText("正在后台生成 DEX 签名导出…");
        try {
            exportWorker.execute(() -> {
                StringBuilder out = new StringBuilder();
                int emitted = 0;
                boolean truncated = false;
                for (FxDiaDexIndex.DexClass item : snapshot) {
                    if (Thread.currentThread().isInterrupted() || request != exportGeneration) return;
                    String className = item.javaName();
                    boolean classMatch = q.isEmpty() || className.toLowerCase(Locale.ROOT).contains(q)
                            || item.descriptor.toLowerCase(Locale.ROOT).contains(q);
                    List<FxDiaDexIndex.Member> members = new ArrayList<>();
                    if (classMatch) {
                        members.addAll(item.fields);
                        members.addAll(item.methods);
                    } else {
                        for (FxDiaDexIndex.Member member : item.fields) {
                            if (Thread.currentThread().isInterrupted() || request != exportGeneration) return;
                            if (member.display().toLowerCase(Locale.ROOT).contains(q)) members.add(member);
                        }
                        for (FxDiaDexIndex.Member member : item.methods) {
                            if (Thread.currentThread().isInterrupted() || request != exportGeneration) return;
                            if (member.display().toLowerCase(Locale.ROOT).contains(q)) members.add(member);
                        }
                    }
                    if (!classMatch && members.isEmpty()) continue;
                    if (out.length() + item.descriptor.length() + 32 > 512 * 1024 || emitted >= 12000) {
                        truncated = true;
                        break;
                    }
                    out.append("CLASS ").append(item.descriptor).append('\n');
                    for (FxDiaDexIndex.Member member : members) {
                        if (Thread.currentThread().isInterrupted() || request != exportGeneration) return;
                        String line = member.display();
                        if (out.length() + line.length() + 1 > 512 * 1024 || emitted >= 12000) {
                            truncated = true;
                            break;
                        }
                        out.append(line).append('\n');
                        emitted++;
                    }
                    if (truncated) break;
                }
                if (truncated) out.append("\n# 已达到导出安全上限（512 KiB / 12000 成员）；请缩小搜索条件后再次导出。\n");
                final String exported = out.toString();
                final int exportedCount = emitted;
                final boolean wasTruncated = truncated;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed() || request != exportGeneration) return;
                    if (exported.isEmpty()) {
                        summary.setText("当前搜索条件没有可导出结果。");
                        return;
                    }
                    android.content.ClipboardManager clipboard =
                            (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                    if (clipboard == null) {
                        summary.setText("系统剪贴板不可用。");
                        return;
                    }
                    clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                            "Dia DEX signatures", exported));
                    summary.setText("已复制 " + exportedCount + " 个成员签名"
                            + (wasTruncated ? "（输出达到安全上限，请进一步缩小搜索）" : "") + "。");
                });
            });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 导出后台队列繁忙，请稍后重试。");
        }
    }

    private void showClassMembers(FxDiaDexIndex.DexClass item) {
        final int request = ++detailGeneration;
        final String q = filter.getText() == null ? ""
                : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        summary.setText("正在后台整理类成员和直接调用关系…");
        try {
            detailWorker.execute(() -> {
                String built = buildClassDetail(item, q, request);
                if (built == null || Thread.currentThread().isInterrupted()
                        || request != detailGeneration) return;
                final String content = built;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed() || request != detailGeneration) return;
                    EditText output = new EditText(this);
                    output.setText(content);
                    output.setSingleLine(false);
                    output.setMinLines(10);
                    output.setGravity(Gravity.TOP | Gravity.START);
                    output.setTextIsSelectable(true);
                    AlertDialog.Builder detailDialog = fxDialogBuilder()
                            .setTitle("DEX 成员 · " + item.javaName())
                            .setView(output)
                            .setNegativeButton("关闭", null)
                            .setPositiveButton("复制签名", (dialog, which) -> {
                                android.content.ClipboardManager clipboard =
                                        (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                                if (clipboard != null) {
                                    clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                                            "DEX signatures", output.getText().toString()));
                                }
                            });
                    if (getIntent().getBooleanExtra("allow_hook_method_pick", false)
                            && selected != null
                            && (selected.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0
                            && (selected.flags & (ApplicationInfo.FLAG_SYSTEM
                                    | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) == 0) {
                        detailDialog.setNeutralButton("选择方法并添加 OBSERVE Hook",
                                (dialog, which) -> chooseDexHookMethod(item));
                    }
                    detailDialog.show();
                });
            });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 详情后台队列繁忙，请稍后重试。");
        }
    }

    private void chooseDexHookMethod(FxDiaDexIndex.DexClass owner) {
        if (!getIntent().getBooleanExtra("allow_hook_method_pick", false)
                || selected == null
                || (selected.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                || (selected.flags & (ApplicationInfo.FLAG_SYSTEM
                        | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0) {
            summary.setText("导入 Hook 只允许 debuggable 用户应用；Framework DEX 和系统应用保持只读。");
            return;
        }
        final String targetPackage = selected.packageName;
        final String query = filter.getText() == null ? ""
                : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        final int request = ++detailGeneration;
        summary.setText("正在后台筛选可导入的具体方法…");
        try {
            detailWorker.execute(() -> {
                try {
                    final List<FxDiaDexIndex.Member> candidates =
                            collectDexHookCandidates(owner, query, targetPackage);
                    final String[] labels = new String[candidates.size()];
                    for (int i = 0; i < candidates.size(); i++) {
                        labels[i] = candidates.get(i).display();
                    }
                    runOnUiThread(() -> {
                        if (destroyed || isFinishing() || isDestroyed()
                                || request != detailGeneration || selected == null
                                || !targetPackage.equals(selected.packageName)) return;
                        if (candidates.isEmpty()) {
                            summary.setText("当前类没有符合条件的具体 Java 方法。请缩小搜索范围，或确认选择的是 debuggable 用户应用。");
                            return;
                        }
                        fxDialogBuilder().setTitle("选择精确方法 · " + candidates.size() + " 个")
                                .setItems(labels, (dialog, which) -> {
                                    if (request != detailGeneration || selected == null
                                            || !targetPackage.equals(selected.packageName)) {
                                        summary.setText("目标应用或搜索条件已变化，请重新选择方法。");
                                        return;
                                    }
                                    FxDiaDexIndex.Member member = candidates.get(which);
                                    String descriptor = owner.descriptor + "->" + member.name + member.descriptor;
                                    if (DeveloperHookRule.parse("dexPick|" + descriptor + "|OBSERVE|0",
                                            targetPackage) == null) {
                                        summary.setText("所选方法签名未通过 FX 规则校验，未返回。");
                                        return;
                                    }
                                    Intent result = new Intent();
                                    result.putExtra("fx_dex_hook_package", targetPackage);
                                    result.putExtra("fx_dex_hook_descriptor", descriptor);
                                    result.putExtra("fx_dex_hook_display", member.display());
                                    setResult(RESULT_OK, result);
                                    finish();
                                })
                                .setNegativeButton("取消", null).show();
                    });
                } catch (Throwable error) {
                    runOnUiThread(() -> {
                        if (!destroyed && !isFinishing() && !isDestroyed()
                                && request == detailGeneration) {
                            summary.setText("方法筛选失败：" + error.getClass().getSimpleName());
                        }
                    });
                }
            });
        } catch (RejectedExecutionException full) {
            summary.setText("DEX 方法筛选后台队列繁忙，请稍后重试。");
        }
    }

    private String buildClassDetail(FxDiaDexIndex.DexClass item, String q, int request) {
        StringBuilder detail = new StringBuilder();
        detail.append(item.descriptor).append('\n');
        detail.append("父类：").append(item.superDescriptor == null
                ? "无/根类型" : item.superDescriptor).append('\n');
        if (!item.interfaces.isEmpty()) {
            detail.append("接口：");
            for (String iface : item.interfaces) detail.append(iface).append("  ");
            detail.append('\n');
        }
        detail.append("字段：").append(item.fields.size()).append(" · 方法：")
                .append(item.methods.size()).append(" · 调用边：").append(item.calls.size())
                .append("\n\n");
        String className = item.javaName().toLowerCase(Locale.ROOT);
        int count = 0;
        boolean memberLimit = false;
        List<FxDiaDexIndex.Member> source = new ArrayList<>(item.fields.size() + item.methods.size());
        source.addAll(item.fields);
        source.addAll(item.methods);
        for (FxDiaDexIndex.Member member : source) {
            if (Thread.currentThread().isInterrupted() || request != detailGeneration) return null;
            String line = member.display();
            if (!q.isEmpty() && !className.contains(q) && !line.toLowerCase(Locale.ROOT).contains(q)) continue;
            if (count >= 400) {
                memberLimit = true;
                break;
            }
            detail.append(line).append('\n');
            count++;
        }
        if (memberLimit) detail.append("…成员显示达到 400 条上限，请缩小搜索范围。\n");

        detail.append("\n直接调用关系（DEX invoke 指令）：\n");
        int callCount = 0;
        for (FxDiaDexIndex.CallSite call : item.calls) {
            if (Thread.currentThread().isInterrupted() || request != detailGeneration) return null;
            String line = call.display();
            if (!q.isEmpty() && !line.toLowerCase(Locale.ROOT).contains(q) && !className.contains(q)) continue;
            if (callCount >= 200) {
                detail.append("…调用边显示达到 200 条上限。\n");
                break;
            }
            detail.append(line).append('\n');
            callCount++;
        }
        if (item.calls.isEmpty()) detail.append("没有可解析的直接调用边；抽象/native/无代码方法不会产生调用边。\n");
        return detail.toString();
    }

    private static List<FxDiaDexIndex.Member> collectDexHookCandidates(
            FxDiaDexIndex.DexClass owner, String query, String targetPackage) {
        List<FxDiaDexIndex.Member> candidates = new ArrayList<>();
        for (FxDiaDexIndex.Member member : owner.methods) {
            if (member == null || !member.method || member.name == null
                    || member.name.startsWith("<") || member.descriptor == null
                    || (member.accessFlags & (0x0400 | 0x0100)) != 0) continue;
            if (!query.isEmpty()
                    && !member.display().toLowerCase(Locale.ROOT).contains(query)) continue;
            String descriptor = owner.descriptor + "->" + member.name + member.descriptor;
            if (DeveloperHookRule.parse("dexPick|" + descriptor + "|OBSERVE|0",
                    targetPackage) == null) continue;
            candidates.add(member);
            if (candidates.size() >= 200) break;
        }
        return candidates;
    }

    @Override protected void onDestroy() {
        destroyed = true;
        if (!isChangingConfigurations()) releaseDocumentPermission();
        searchGeneration++;
        exportGeneration++;
        detailGeneration++;
        dexGeneration++;
        worker.shutdownNow();
        searchWorker.shutdownNow();
        exportWorker.shutdownNow();
        detailWorker.shutdownNow();
        super.onDestroy();
    }
}
