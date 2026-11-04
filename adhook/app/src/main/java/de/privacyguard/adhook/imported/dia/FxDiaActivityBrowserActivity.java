package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.text.Editable;
import android.text.TextWatcher;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.Locale;
import android.widget.Filter;
import android.widget.Filterable;

/** Native Dia-style Activity entry browser and explicit user-app component toggles. */
public final class FxDiaActivityBrowserActivity extends Activity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> { Thread t = new Thread(r, "fx-dia-app-browser"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private boolean submitWorker(Runnable task) {
        try {
            worker.execute(task);
            return true;
        } catch (RejectedExecutionException full) {
            if (!destroyed) {
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                    Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
                });
            }
            return false;
        }
    }
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> appLabels = new HashMap<>();
    private LinearLayout rows;
    private TextView target;
    private TextView status;
    private ApplicationInfo selected;
    private String selectedLabel;
    private boolean launcherOnly;
    private boolean appsLoaded;
    private boolean appsLoading;
    private volatile boolean destroyed;
    private int appsGeneration;
    private int activityGeneration;
    private AlertDialog appPickerDialog;
    private AppPickerAdapter appPickerAdapter;

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
        status = text("正在后台读取用户应用清单…", 13, 0xff617080, false);
        rows = new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
        card(body, "目标应用", launcherOnly
                        ? "仅列出用户应用的 MAIN/LAUNCHER 启动入口。禁用后图标会从启动器隐藏；可在此页重新启用。"
                        : "只显示非系统用户应用；组件禁用需要 Root 权限并逐项确认。",
                target,
                button("选择应用（可搜索）", this::chooseApp),
                button("刷新应用列表", this::loadApps),
                button("读取 Activity 入口", this::loadActivities));
        card(body, "状态", "组件状态来自 PackageManager；修改命令由 Root 执行并逐项确认。", status);
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
        if (destroyed || appsLoading) return;
        appsLoading = true;
        appsLoaded = false;
        final int request = ++appsGeneration;
        status.setText("正在后台读取用户应用清单与显示名称…");
        rows.removeAllViews();
        boolean accepted = submitWorker(() -> {
            List<ApplicationInfo> loaded = new ArrayList<>();
            Map<String, String> loadedLabels = new HashMap<>();
            String failure = null;
            try {
                PackageManager pm = getPackageManager();
                for (ApplicationInfo app : pm.getInstalledApplications(0)) {
                    if (Thread.currentThread().isInterrupted() || request != appsGeneration) return;
                    if (app.packageName == null || app.packageName.equals(getPackageName())
                            || (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                            || (app.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0) continue;
                    String label;
                    try { label = String.valueOf(pm.getApplicationLabel(app)); }
                    catch (Throwable ignored) { label = app.packageName; }
                    loaded.add(app);
                    loadedLabels.put(app.packageName, label);
                }
                loaded.sort(Comparator.comparing(app ->
                        loadedLabels.getOrDefault(app.packageName, app.packageName)
                                .toLowerCase(Locale.ROOT)));
            } catch (Throwable error) {
                failure = error.getClass().getSimpleName() + ": " + error.getMessage();
            }
            final String loadFailure = failure;
            runOnUiThread(() -> {
                if (destroyed || isFinishing() || isDestroyed() || request != appsGeneration) return;
                appsLoading = false;
                if (loadFailure != null) {
                    appsLoaded = false;
                    status.setText("读取应用列表失败：" + loadFailure + "。可点击“刷新应用列表”重试。");
                    return;
                }
                apps.clear();
                apps.addAll(loaded);
                appLabels.clear();
                appLabels.putAll(loadedLabels);
                appsLoaded = true;
                status.setText("已读取 " + apps.size() + " 个非系统用户应用。可搜索名称或包名。");
                if (appPickerAdapter != null) appPickerAdapter.notifyDataSetChanged();
                if (apps.isEmpty()) status.setText("没有可管理的非系统用户应用。");
            });
        });
        if (!accepted) appsLoading = false;
    }

    private void chooseApp() {
        if (appsLoading) {
            status.setText("应用清单仍在后台读取，请稍候；不会阻塞当前页面。");
            return;
        }
        if (!appsLoaded) {
            loadApps();
            return;
        }
        if (apps.isEmpty()) {
            status.setText("没有可管理的用户应用；可点击“刷新应用列表”重试。");
            return;
        }

        LinearLayout picker = new LinearLayout(this);
        picker.setOrientation(LinearLayout.VERTICAL);
        picker.setPadding(dp(16), dp(8), dp(16), dp(4));
        EditText search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("搜索应用名称或包名");
        picker.addView(search);
        ListView list = new ListView(this);
        list.setDividerHeight(dp(1));
        appPickerAdapter = new AppPickerAdapter();
        list.setAdapter(appPickerAdapter);
        picker.addView(list, new LinearLayout.LayoutParams(-1, dp(420)));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("选择应用")
                .setView(picker)
                .setNegativeButton("关闭", null)
                .create();
        list.setOnItemClickListener((parent, view, position, id) -> {
            ApplicationInfo choice = appPickerAdapter.getItem(position);
            if (choice == null) return;
            selected = choice;
            selectedLabel = appLabels.getOrDefault(choice.packageName, choice.packageName);
            target.setText(selectedLabel + "\n" + choice.packageName);
            rows.removeAllViews();
            status.setText("已选择目标应用：" + selectedLabel);
            dialog.dismiss();
        });
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                appPickerAdapter.getFilter().filter(s);
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
        appPickerDialog = dialog;
        dialog.setOnDismissListener(d -> {
            if (appPickerDialog == dialog) appPickerDialog = null;
            if (appPickerAdapter != null) appPickerAdapter = null;
        });
        dialog.show();
    }

    private final class AppPickerAdapter extends BaseAdapter implements Filterable {
        private final List<ApplicationInfo> visible = new ArrayList<>(apps);

        @Override public int getCount() { return visible.size(); }
        @Override public ApplicationInfo getItem(int position) {
            return position < 0 || position >= visible.size() ? null : visible.get(position);
        }
        @Override public long getItemId(int position) {
            ApplicationInfo item = getItem(position);
            return item == null ? position : item.packageName.hashCode();
        }
        @Override public View getView(int position, View convertView, android.view.ViewGroup parent) {
            TextView itemView = convertView instanceof TextView
                    ? (TextView) convertView : new TextView(FxDiaActivityBrowserActivity.this);
            ApplicationInfo app = getItem(position);
            if (app != null) {
                itemView.setText(appLabels.getOrDefault(app.packageName, app.packageName)
                        + "\n" + app.packageName);
            }
            itemView.setTextSize(14);
            itemView.setTextColor(0xff17212b);
            itemView.setPadding(dp(12), dp(10), dp(12), dp(10));
            return itemView;
        }
        @Override public Filter getFilter() {
            return new Filter() {
                @Override protected FilterResults performFiltering(CharSequence constraint) {
                    String query = constraint == null ? "" : constraint.toString().trim()
                            .toLowerCase(Locale.ROOT);
                    List<ApplicationInfo> matches = new ArrayList<>();
                    for (ApplicationInfo app : apps) {
                        String label = appLabels.getOrDefault(app.packageName, app.packageName);
                        if (query.isEmpty() || label.toLowerCase(Locale.ROOT).contains(query)
                                || app.packageName.toLowerCase(Locale.ROOT).contains(query)) {
                            matches.add(app);
                        }
                    }
                    FilterResults result = new FilterResults();
                    result.values = matches;
                    result.count = matches.size();
                    return result;
                }
                @Override protected void publishResults(CharSequence constraint, FilterResults results) {
                    visible.clear();
                    if (results.values instanceof List<?>) {
                        for (Object value : (List<?>) results.values) {
                            if (value instanceof ApplicationInfo) visible.add((ApplicationInfo) value);
                        }
                    }
                    notifyDataSetChanged();
                }
            };
        }
    }

    private void loadActivities() {
        if (selected == null) { status.setText("请先选择应用。"); return; }
        ApplicationInfo app = selected;
        final int request = ++activityGeneration;
        final String targetPackage = app.packageName;
        rows.removeAllViews();
        status.setText("正在读取 Activity 声明与组件状态…");
        boolean accepted = submitWorker(() -> {
            List<ActivityInfo> result = new ArrayList<>();
            String error = null;
            try {
                PackageManager pm = getPackageManager();
                PackageInfo info = pm.getPackageInfo(targetPackage,
                        PackageManager.GET_ACTIVITIES | PackageManager.MATCH_DISABLED_COMPONENTS);
                if (info.activities != null) {
                    java.util.Set<String> launcherNames = new java.util.HashSet<>();
                    if (launcherOnly) {
                        Intent launcherIntent = new Intent(Intent.ACTION_MAIN);
                        launcherIntent.addCategory(Intent.CATEGORY_LAUNCHER);
                        for (android.content.pm.ResolveInfo resolve :
                                pm.queryIntentActivities(launcherIntent, PackageManager.MATCH_DISABLED_COMPONENTS)) {
                            if (Thread.currentThread().isInterrupted()) return;
                            if (resolve.activityInfo != null
                                    && targetPackage.equals(resolve.activityInfo.packageName)
                                    && resolve.activityInfo.name != null) {
                                launcherNames.add(resolve.activityInfo.name);
                            }
                        }
                    }
                    for (ActivityInfo item : info.activities) {
                        if (Thread.currentThread().isInterrupted()) return;
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
                if (destroyed || isFinishing() || isDestroyed()
                        || request != activityGeneration || selected == null
                        || !targetPackage.equals(selected.packageName)) return;
                if (failure != null) { status.setText("读取失败：" + failure); return; }
                status.setText("已读取 " + activities.size() + " 个 Activity 声明。");
                for (ActivityInfo info : activities) addActivityRow(targetPackage, info);
                if (activities.isEmpty()) rows.addView(text("该应用没有声明符合当前视图的 Activity。", 13, 0xff718091, false));
            });
        });
        if (!accepted) status.setText("后台任务未能启动；请重试读取 Activity 入口。");
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
            String command = "user_id=$(am get-current-user 2>/dev/null); "
                    + "case \"$user_id\" in ''|*[!0-9]*) echo 'Unable to resolve current Android user' >&2; exit 65 ;; esac; "
                    + (wanted ? "pm enable --user \"$user_id\" " : "pm disable-user --user \"$user_id\" ")
                    + quote(componentArg);
            new AlertDialog.Builder(this).setTitle(wanted ? "启用 Activity？" : "禁用 Activity？")
                    .setMessage("这会修改目标应用的组件状态。禁用启动入口可能导致目标应用无法正常打开；可返回 FX 再次启用。")
                    .setNegativeButton("取消", (d, w) -> {
                        button.setChecked(!wanted);
                        button.setEnabled(true);
                    })
                    .setPositiveButton("继续", (d, w) -> submitWorker(() -> {
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
        destroyed = true;
        appsGeneration++;
        activityGeneration++;
        if (appPickerDialog != null) {
            appPickerDialog.dismiss();
            appPickerDialog = null;
        }
        appPickerAdapter = null;
        worker.shutdownNow();
        super.onDestroy();
    }
}
