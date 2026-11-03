package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import dalvik.system.DexFile;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Read-only DEX class-name browser migrated from Dia 23.11. */
public final class FxDiaDexBrowserActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final List<String> classes = new ArrayList<>();
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
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · DEX 查找与解析", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18)); scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        target = text("尚未选择应用。", 13, 0xff334155, false);
        summary = text("选择应用后读取 APK 中的 DEX 类名。", 13, 0xff334155, false);
        filter = new EditText(this); filter.setSingleLine(true); filter.setHint("按包名、类名或关键词筛选");
        results = new LinearLayout(this); results.setOrientation(LinearLayout.VERTICAL);
        card(body, "目标 APK", "只读取 APK 中的 DEX 类名，不加载目标类、不执行目标代码。",
                target, button("选择已安装应用", this::chooseApp),
                button("读取 DEX 类名", this::loadDex));
        card(body, "搜索", "结果只显示类名和来源 APK，不读取目标应用私有数据库或进程内存。",
                filter, summary);
        body.addView(results);
        filter.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { render(); }
            @Override public void afterTextChanged(Editable s) {}
        });
        loadInstalledApps();
    }

    private void loadInstalledApps() {
        try {
            apps.clear();
            apps.addAll(getPackageManager().getInstalledApplications(0));
            apps.removeIf(app -> app.packageName == null || app.packageName.equals(getPackageName()));
            apps.sort(Comparator.comparing(app -> {
                try { return String.valueOf(getPackageManager().getApplicationLabel(app)).toLowerCase(Locale.ROOT); }
                catch (Throwable ignored) { return app.packageName.toLowerCase(Locale.ROOT); }
            }));
        } catch (Throwable error) {
            summary.setText("读取应用清单失败：" + error.getClass().getSimpleName());
        }
    }

    private void chooseApp() {
        if (apps.isEmpty()) loadInstalledApps();
        if (apps.isEmpty()) { summary.setText("当前无法读取已安装应用。"); return; }
        String[] labels = new String[apps.size()];
        for (int i = 0; i < apps.size(); i++) {
            String label;
            try { label = String.valueOf(getPackageManager().getApplicationLabel(apps.get(i))); }
            catch (Throwable ignored) { label = apps.get(i).packageName; }
            labels[i] = label + "\n" + apps.get(i).packageName;
        }
        new AlertDialog.Builder(this).setTitle("选择要分析的 APK")
                .setItems(labels, (dialog, which) -> {
                    selected = apps.get(which);
                    target.setText(labels[which]);
                    classes.clear(); render();
                }).setNegativeButton("取消", null).show();
    }

    private void loadDex() {
        if (selected == null) { summary.setText("请先选择应用。"); return; }
        final ApplicationInfo app = selected;
        summary.setText("正在只读枚举 DEX 类名…");
        results.removeAllViews();
        worker.execute(() -> {
            Set<String> found = new HashSet<>();
            List<String> paths = new ArrayList<>();
            if (app.sourceDir != null) paths.add(app.sourceDir);
            if (app.splitSourceDirs != null) Collections.addAll(paths, app.splitSourceDirs);
            String error = null;
            int dexFiles = 0;
            outer:
            for (String path : paths) {
                DexFile dex = null;
                try {
                    dex = new DexFile(path);
                    dexFiles++;
                    Enumeration<String> names = dex.entries();
                    while (names.hasMoreElements()) {
                        found.add(names.nextElement());
                        if (found.size() >= 100000) break outer;
                    }
                } catch (Throwable failure) {
                    error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
                } finally {
                    if (dex != null) try { dex.close(); } catch (IOException ignored) { }
                }
            }
            List<String> ordered = new ArrayList<>(found);
            Collections.sort(ordered);
            final int fileCount = dexFiles;
            final String err = error;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                classes.clear(); classes.addAll(ordered);
                summary.setText("已枚举 " + classes.size() + " 个类名 · DEX/APK 文件数 " + fileCount
                        + (classes.size() >= 100000 ? " · 达到 100000 条安全上限" : "")
                        + (err == null ? "" : " · 部分读取错误：" + err));
                render();
            });
        });
    }

    private void render() {
        if (results == null) return;
        results.removeAllViews();
        String q = filter.getText() == null ? "" : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        int shown = 0;
        for (String name : classes) {
            if (!q.isEmpty() && !name.toLowerCase(Locale.ROOT).contains(q)) continue;
            results.addView(text(name, 12, 0xff37474f, false));
            if (++shown >= 300) break;
        }
        if (shown == 0) results.addView(text(
                classes.isEmpty() ? "尚无 DEX 结果。" : "没有匹配的类名。",
                13, 0xff718091, false));
        else if (shown >= 300) results.addView(text("仅显示前 300 条匹配结果，请缩小搜索范围。", 12, 0xff8a6d3b, false));
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
