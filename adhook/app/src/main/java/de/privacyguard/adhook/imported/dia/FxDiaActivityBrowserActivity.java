package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native Dia-style Activity entry browser and explicit user-app component toggles. */
public final class FxDiaActivityBrowserActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private LinearLayout rows;
    private TextView target;
    private TextView status;
    private ApplicationInfo selected;
    private boolean launcherOnly;

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private String quote(String value) { return "'" + value.replace("'", "'\\''") + "'"; }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        launcherOnly = getIntent().getBooleanExtra("launcher_only", false);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text(launcherOnly ? "Dia 23.11 · 隐藏应用" : "Dia 23.11 · Activity 入口与禁用", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18)); scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        target = text("尚未选择应用。", 13, 0xff334155, false);
        status = text("选择用户应用以查看其声明的 Activity 入口。", 13, 0xff617080, false);
        rows = new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
        card(body, "目标应用", launcherOnly
                        ? "仅列出用户应用的 MAIN/LAUNCHER 启动入口。禁用后图标会从启动器隐藏；可在此页重新启用。"
                        : "只显示非系统用户应用；组件禁用需要 Root 权限并逐项确认。",
                target, button("选择应用", this::chooseApp), button("读取 Activity 入口", this::loadActivities));
        card(body, "状态", "系统 PackageManager 实际返回值", status);
        body.addView(rows, rp);
        loadApps();
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

    private void loadApps() {
        apps.clear();
        try {
            apps.addAll(getPackageManager().getInstalledApplications(0));
            apps.removeIf(app -> app.packageName == null || app.packageName.equals(getPackageName())
                    || (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                    || (app.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0);
            apps.sort(Comparator.comparing(app -> {
                try { return String.valueOf(getPackageManager().getApplicationLabel(app)).toLowerCase(Locale.ROOT); }
                catch (Throwable ignored) { return app.packageName.toLowerCase(Locale.ROOT); }
            }));
        } catch (Throwable error) {
            status.setText("无法读取应用列表：" + error.getClass().getSimpleName());
        }
    }

    private void chooseApp() {
        if (apps.isEmpty()) loadApps();
        if (apps.isEmpty()) { status.setText("没有可管理的用户应用。"); return; }
        String[] labels = new String[apps.size()];
        for (int i = 0; i < apps.size(); i++) {
            String label;
            try { label = String.valueOf(getPackageManager().getApplicationLabel(apps.get(i))); }
            catch (Throwable ignored) { label = apps.get(i).packageName; }
            labels[i] = label + "\n" + apps.get(i).packageName;
        }
        new AlertDialog.Builder(this).setTitle("选择应用")
                .setItems(labels, (dialog, which) -> {
                    selected = apps.get(which);
                    target.setText(labels[which]);
                    rows.removeAllViews();
                    status.setText("已选择目标应用。");
                }).setNegativeButton("取消", null).show();
    }

    private void loadActivities() {
        if (selected == null) { status.setText("请先选择应用。"); return; }
        ApplicationInfo app = selected;
        rows.removeAllViews();
        status.setText("正在读取 Activity 声明…");
        worker.execute(() -> {
            List<ActivityInfo> result = new ArrayList<>();
            String error = null;
            try {
                PackageManager pm = getPackageManager();
                PackageInfo info = pm.getPackageInfo(app.packageName,
                        PackageManager.GET_ACTIVITIES | PackageManager.MATCH_DISABLED_COMPONENTS);
                if (info.activities != null) {
                    java.util.Set<String> launcherNames = new java.util.HashSet<>();
                    if (launcherOnly) {
                        Intent launcherIntent = new Intent(Intent.ACTION_MAIN);
                        launcherIntent.addCategory(Intent.CATEGORY_LAUNCHER);
                        for (android.content.pm.ResolveInfo resolve :
                                pm.queryIntentActivities(launcherIntent, PackageManager.MATCH_DISABLED_COMPONENTS)) {
                            if (resolve.activityInfo != null
                                    && app.packageName.equals(resolve.activityInfo.packageName)
                                    && resolve.activityInfo.name != null) {
                                launcherNames.add(resolve.activityInfo.name);
                            }
                        }
                    }
                    for (ActivityInfo item : info.activities) {
                        if (item != null && (!launcherOnly || launcherNames.contains(item.name))) result.add(item);
                    }
                }
                result.sort(Comparator.comparing(item -> item.name == null ? "" : item.name));
            } catch (Throwable failure) {
                error = failure.getClass().getSimpleName() + ": " + failure.getMessage();
            }
            final List<ActivityInfo> activities = result;
            final String failure = error;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (failure != null) { status.setText("读取失败：" + failure); return; }
                status.setText("已读取 " + activities.size() + " 个 Activity 声明。");
                for (ActivityInfo info : activities) addActivityRow(app.packageName, info);
                if (activities.isEmpty()) rows.addView(text("该应用没有声明 Activity。", 13, 0xff718091, false));
            });
        });
    }

    private void addActivityRow(String packageName, ActivityInfo info) {
        String className = info.name;
        if (className == null || !className.matches("[A-Za-z0-9_.$]+")) return;
        ComponentName component = new ComponentName(packageName, className);
        int state;
        try { state = getPackageManager().getComponentEnabledSetting(component); }
        catch (Throwable ignored) { state = PackageManager.COMPONENT_ENABLED_STATE_DEFAULT; }
        boolean enabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                || (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && info.enabled);
        if (state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                || state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER) enabled = false;

        LinearLayout row = new LinearLayout(this); row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(12), dp(7), dp(12), dp(7)); row.setBackgroundColor(0xffffffff);
        TextView name = text(className, 13, 0xff17212b, true);
        TextView meta = text("exported=" + info.exported + " · manifestEnabled=" + info.enabled
                + " · state=" + state, 10, 0xff718091, false);
        Switch toggle = new Switch(this); toggle.setText("启用此 Activity");
        toggle.setChecked(enabled);
        toggle.setOnCheckedChangeListener((button, wanted) -> {
            button.setEnabled(false);
            String componentArg = packageName + "/" + className;
            String command = wanted
                    ? "pm enable --user 0 " + quote(componentArg)
                    : "pm disable-user --user 0 " + quote(componentArg);
            new AlertDialog.Builder(this).setTitle(wanted ? "启用 Activity？" : "禁用 Activity？")
                    .setMessage("这会修改目标应用的组件状态。禁用启动入口可能导致目标应用无法正常打开；可返回 FX 再次启用。")
                    .setNegativeButton("取消", (d, w) -> {
                        button.setChecked(!wanted);
                        button.setEnabled(true);
                    })
                    .setPositiveButton("继续", (d, w) -> worker.execute(() -> {
                        RootAccess.Result applied = RootAccess.execute(command, 30000L, 65536);
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            button.setEnabled(true);
                            if (applied.exitCode != 0) {
                                button.setChecked(!wanted);
                                status.setText("组件状态修改失败：" + applied.output);
                            } else {
                                status.setText(wanted ? "Activity 已启用。" : "Activity 已禁用。");
                                loadActivities();
                            }
                        });
                    })).show();
        });
        row.addView(name); row.addView(meta); row.addView(toggle);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(10), dp(3), dp(10), dp(3)); rows.addView(row, lp);
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
