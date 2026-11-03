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
        filter = new EditText(this); filter.setSingleLine(true); filter.setHint("搜索类名、方法名、字段名或描述符");
        results = new LinearLayout(this); results.setOrientation(LinearLayout.VERTICAL);
        card(body, "目标 APK", "只读解析 DEX class/method/field 索引；不加载目标类、不执行目标代码。",
                target, button("选择已安装应用", this::chooseApp),
                button("读取 DEX 类名", this::loadDex));
        card(body, "搜索", "结果只显示类名、方法/字段签名和来源 APK，不读取目标应用私有数据库或进程内存。",
                filter, summary, button("导出当前匹配的类/方法/字段签名", this::exportMatches));
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
        summary.setText("正在只读解析 DEX 类、方法与字段索引…");
        results.removeAllViews();
        worker.execute(() -> {
            List<String> paths = new ArrayList<>();
            if (app.sourceDir != null) paths.add(app.sourceDir);
            if (app.splitSourceDirs != null) Collections.addAll(paths, app.splitSourceDirs);
            final java.util.Map<String, FxDiaDexIndex.DexClass> found = new java.util.TreeMap<>();
            String error = null;
            try {
                found.putAll(FxDiaDexIndex.readApks(paths));
            } catch (Throwable failure) {
                error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
            }
            final String err = error;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
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
    }

    private void render() {
        if (results == null) return;
        results.removeAllViews();
        String q = filter.getText() == null ? "" : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        int shown = 0;
        for (FxDiaDexIndex.DexClass item : classes) {
            String className = item.javaName();
            boolean classMatch = q.isEmpty() || className.toLowerCase(Locale.ROOT).contains(q)
                    || item.descriptor.toLowerCase(Locale.ROOT).contains(q);
            List<String> matches = new ArrayList<>();
            if (!classMatch && !q.isEmpty()) {
                for (FxDiaDexIndex.Member member : item.methods) {
                    if (member.display().toLowerCase(Locale.ROOT).contains(q)) matches.add(member.display());
                }
                for (FxDiaDexIndex.Member member : item.fields) {
                    if (member.display().toLowerCase(Locale.ROOT).contains(q)) matches.add(member.display());
                }
            }
            if (!classMatch && matches.isEmpty()) continue;

            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(12), dp(6), dp(12), dp(6));
            TextView title = text(className, 12, 0xff17212b, true);
            TextView detail = text("方法 " + item.methods.size() + " · 字段 " + item.fields.size()
                    + (matches.isEmpty() ? "" : " · 命中成员 " + matches.size()),
                    10, 0xff718091, false);
            row.addView(title);
            row.addView(detail);
            row.setBackgroundColor(0xffffffff);
            row.setOnClickListener(v -> showClassMembers(item, matches));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(10), dp(2), dp(10), dp(2));
            results.addView(row, lp);
            if (++shown >= 300) break;
        }
        if (shown == 0) results.addView(text(
                classes.isEmpty() ? "尚无 DEX 结果。" : "没有匹配的类、方法或字段。",
                13, 0xff718091, false));
        else if (shown >= 300) results.addView(text(
                "仅显示前 300 个匹配类，请缩小搜索范围。",
                12, 0xff8a6d3b, false));
    }

    private void exportMatches() {
        if (classes.isEmpty()) {
            summary.setText("尚无可导出的 DEX 索引，请先读取 DEX。");
            return;
        }
        String q = filter.getText() == null ? "" : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        StringBuilder out = new StringBuilder();
        int emitted = 0;
        boolean truncated = false;
        for (FxDiaDexIndex.DexClass item : classes) {
            String className = item.javaName();
            boolean classMatch = q.isEmpty() || className.toLowerCase(Locale.ROOT).contains(q)
                    || item.descriptor.toLowerCase(Locale.ROOT).contains(q);
            List<FxDiaDexIndex.Member> members = new ArrayList<>();
            if (classMatch) {
                members.addAll(item.fields);
                members.addAll(item.methods);
            } else {
                for (FxDiaDexIndex.Member member : item.fields) {
                    if (member.display().toLowerCase(Locale.ROOT).contains(q)) members.add(member);
                }
                for (FxDiaDexIndex.Member member : item.methods) {
                    if (member.display().toLowerCase(Locale.ROOT).contains(q)) members.add(member);
                }
            }
            if (!classMatch && members.isEmpty()) continue;
            if (out.length() + className.length() + 32 > 512 * 1024 || emitted >= 12000) {
                truncated = true;
                break;
            }
            out.append("CLASS ").append(item.descriptor).append('\n');
            for (FxDiaDexIndex.Member member : members) {
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
        if (out.length() == 0) {
            summary.setText("当前搜索条件没有可导出结果。");
            return;
        }
        android.content.ClipboardManager clipboard =
                (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard == null) {
            summary.setText("系统剪贴板不可用。");
            return;
        }
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Dia DEX signatures", out.toString()));
        summary.setText("已复制 " + emitted + " 个成员签名"
                + (truncated ? "（输出达到安全上限，请进一步缩小搜索）" : "") + "。");
    }

    private void showClassMembers(FxDiaDexIndex.DexClass item, List<String> searchMatches) {
        StringBuilder detail = new StringBuilder();
        detail.append(item.descriptor).append("\\n");
        detail.append("父类：").append(item.superDescriptor == null
                ? "无/根类型" : item.superDescriptor).append("\\n");
        if (!item.interfaces.isEmpty()) {
            detail.append("接口：");
            for (String iface : item.interfaces) detail.append(iface).append("  ");
            detail.append("\\n");
        }
        detail.append("字段：").append(item.fields.size()).append(" · 方法：")
                .append(item.methods.size()).append(" · 调用边：").append(item.calls.size())
                .append("\\n\\n");
        List<FxDiaDexIndex.Member> source = new ArrayList<>();
        source.addAll(item.fields);
        source.addAll(item.methods);
        String q = filter.getText() == null ? "" : filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        int count = 0;
        for (FxDiaDexIndex.Member member : source) {
            String line = member.display();
            if (!q.isEmpty() && !item.javaName().toLowerCase(Locale.ROOT).contains(q)
                    && !line.toLowerCase(Locale.ROOT).contains(q)) continue;
            detail.append(line).append("\\n");
            if (++count >= 400) {
                detail.append("…成员显示达到 400 条上限，请缩小搜索范围。\\n");
                break;
            }
        }
        detail.append("\\n直接调用关系（DEX invoke 指令）：\\n");
        int callCount = 0;
        for (FxDiaDexIndex.CallSite call : item.calls) {
            String line = call.display();
            if (!q.isEmpty() && !line.toLowerCase(Locale.ROOT).contains(q)
                    && !item.javaName().toLowerCase(Locale.ROOT).contains(q)) continue;
            detail.append(line).append("\\n");
            if (++callCount >= 200) {
                detail.append("…调用边显示达到 200 条上限。\\n");
                break;
            }
        }
        if (item.calls.isEmpty()) detail.append("没有可解析的直接调用边；抽象/native/无代码方法不会产生调用边。\\n");
        EditText output = new EditText(this);
        output.setText(detail.toString());
        output.setSingleLine(false);
        output.setMinLines(10);
        output.setGravity(Gravity.TOP | Gravity.START);
        output.setTextIsSelectable(true);
        new AlertDialog.Builder(this).setTitle("DEX 成员 · " + item.javaName())
                .setView(output)
                .setNegativeButton("关闭", null)
                .setPositiveButton("复制签名", (dialog, which) -> {
                    android.content.ClipboardManager clipboard =
                            (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                    if (clipboard != null) {
                        clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                                "DEX signatures", output.getText().toString()));
                    }
                }).show();
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
