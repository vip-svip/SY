package de.privacyguard.adhook.imported.dia;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
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
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

/**
 * Native Dia Activity entry browser and explicit user-app launcher/component controls.
 * Package inventory and Activity metadata are loaded off the UI thread; both pages
 * support local search, bounded pagination and state restoration.
 */
public final class FxDiaActivityBrowserActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int APP_PAGE_SIZE = 50;
    private static final int ACTIVITY_PAGE_SIZE = 80;
    private static final String STATE_SELECTED_PACKAGE = "fx_dia_browser_selected_package";
    private static final String STATE_APP_QUERY = "fx_dia_browser_app_query";
    private static final String STATE_ACTIVITY_QUERY = "fx_dia_browser_activity_query";
    private static final String STATE_APP_PAGE = "fx_dia_browser_app_page";
    private static final String STATE_ACTIVITY_PAGE = "fx_dia_browser_activity_page";
    private static final String STATE_SCROLL_Y = "fx_dia_browser_scroll_y";

    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> {
                Thread thread = new Thread(r, "fx-dia-app-browser");
                thread.setDaemon(true);
                return thread;
            },
            new ThreadPoolExecutor.AbortPolicy());

    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> appLabels = new HashMap<>();
    private final List<ActivityEntry> activities = new ArrayList<>();

    private LinearLayout appRows;
    private LinearLayout activityRows;
    private LinearLayout appPager;
    private LinearLayout activityPager;
    private ScrollView pageScroll;
    private EditText appSearch;
    private EditText activitySearch;
    private TextView appCount;
    private TextView activityCount;
    private TextView appPageText;
    private TextView activityPageText;
    private TextView target;
    private TextView status;
    private ApplicationInfo selected;

    private boolean launcherOnly;
    private boolean appsLoading;
    private boolean activitiesLoading;
    private boolean appsLoaded;
    private volatile boolean destroyed;
    private int appGeneration;
    private int activityGeneration;
    private int appPage;
    private int activityPage;
    private String pendingRestorePackage;
    private int restoredScrollY;

    private static final class ActivityEntry {
        final ActivityInfo info;
        final int componentState;
        final boolean applicationEnabled;
        final boolean enabled;

        ActivityEntry(ActivityInfo activityInfo, int state, boolean appEnabled) {
            info = activityInfo;
            componentState = state;
            applicationEnabled = appEnabled;
            enabled = appEnabled
                    && (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        || (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
                            && activityInfo.enabled));
        }
    }
    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private boolean submitWorker(Runnable task) {
        if (destroyed) return false;
        try {
            worker.execute(task);
            return true;
        } catch (RejectedExecutionException full) {
            if (!destroyed) {
                if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
            }
            return false;
        }
    }


    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        launcherOnly = getIntent().getBooleanExtra("launcher_only", false);
        if (state != null) {
            pendingRestorePackage = state.getString(STATE_SELECTED_PACKAGE);
            appPage = Math.max(0, state.getInt(STATE_APP_PAGE, 0));
            activityPage = Math.max(0, state.getInt(STATE_ACTIVITY_PAGE, 0));
            restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Hook", this::finish));
        header.addView(text(launcherOnly
                        ? "Hook · 隐藏应用"
                        : "Hook · Activity 入口与禁用",
                18, 0xff17212b, true), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        pageScroll = scroll;
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        target = text("尚未选择应用。", 13, 0xff334155, false);
        status = text("正在读取用户应用清单…", 12, 0xff617080, false);
        card(body, "目标应用",
                launcherOnly
                        ? "仅列出用户应用的 MAIN/LAUNCHER 启动入口。禁用启动入口会隐藏图标；可在此页重新启用。"
                        : "只显示非系统用户应用。禁用组件需要 Root 权限和逐项确认；FX 不会静默停用整个应用。",
                target,
                status,
                button("重新读取 Activity 入口", this::loadActivities),
                button("刷新已安装应用", () -> loadApps(true)),
                button("清除当前目标", this::clearSelection));

        appSearch = new EditText(this);
        appSearch.setSingleLine(true);
        appSearch.setHint("搜索应用名称或包名");
        if (state != null) appSearch.setText(state.getString(STATE_APP_QUERY, ""));
        appCount = text("正在读取应用列表…", 12, 0xff617080, false);
        appRows = new LinearLayout(this);
        appRows.setOrientation(LinearLayout.VERTICAL);
        appPageText = text("", 11, 0xff617080, false);
        appPager = new LinearLayout(this);
        appPager.setGravity(Gravity.CENTER_VERTICAL);
        Button previousApps = button("上一页", () -> {
            appPage = Math.max(0, appPage - 1);
            renderAppList();
        });
        Button nextApps = button("下一页", () -> {
            appPage++;
            renderAppList();
        });
        appPager.addView(previousApps, new LinearLayout.LayoutParams(0, -2, 1));
        appPager.addView(appPageText, new LinearLayout.LayoutParams(0, -2, 1));
        appPager.addView(nextApps, new LinearLayout.LayoutParams(0, -2, 1));
        appPager.setTag(new Button[]{previousApps, nextApps});
        card(body, "用户应用列表",
                "点击应用即可选为目标。列表只显示用户安装的应用；搜索和分页在本地完成，不会把搜索文本传入 Root 命令。",
                appSearch, appCount, appRows, appPager);

        activitySearch = new EditText(this);
        activitySearch.setSingleLine(true);
        activitySearch.setHint("筛选 Activity 类名、权限或导出状态");
        if (state != null) activitySearch.setText(state.getString(STATE_ACTIVITY_QUERY, ""));
        activityCount = text("请先选择应用并读取 Activity。", 12, 0xff617080, false);
        activityRows = new LinearLayout(this);
        activityRows.setOrientation(LinearLayout.VERTICAL);
        activityPageText = text("", 11, 0xff617080, false);
        activityPager = new LinearLayout(this);
        activityPager.setGravity(Gravity.CENTER_VERTICAL);
        Button previousActivities = button("上一页", () -> {
            activityPage = Math.max(0, activityPage - 1);
            renderActivities();
        });
        Button nextActivities = button("下一页", () -> {
            activityPage++;
            renderActivities();
        });
        activityPager.addView(previousActivities, new LinearLayout.LayoutParams(0, -2, 1));
        activityPager.addView(activityPageText, new LinearLayout.LayoutParams(0, -2, 1));
        activityPager.addView(nextActivities, new LinearLayout.LayoutParams(0, -2, 1));
        activityPager.setTag(new Button[]{previousActivities, nextActivities});
        card(body, launcherOnly ? "启动器入口" : "Activity 组件列表",
                launcherOnly
                        ? "只列出当前目标应用声明的 MAIN/LAUNCHER 组件。启用/禁用操作会显示确认框并通过 Root 修改当前 Android 用户的组件状态。"
                        : "显示目标应用声明的 Activity、导出属性、Manifest 状态和系统当前组件状态。列表最多每页显示 80 项。",
                activitySearch, activityCount, activityRows, activityPager);

        if (!launcherOnly) {
            card(body, "批量管理 Activity 组件",
                    "只处理当前搜索条件与当前页中的组件：可恢复已禁用项，也可停用已启用项。不会修改整个应用或其他分页；每次操作均需明确确认。",
                    button("启用当前页筛选中的已禁用 Activity", this::confirmEnableVisibleActivities),
                    button("禁用当前页筛选中的已启用 Activity", this::confirmDisableVisibleActivities));
        }

        setContentViewWithNativeTabs(root, 4);
        if (restoredScrollY > 0) {
            final int restoreY = restoredScrollY;
            scroll.post(() -> {
                if (!destroyed && !isFinishing() && !isDestroyed()
                        && pageScroll == scroll && scroll.getParent() != null) {
                    scroll.scrollTo(0, restoreY);
                }
            });
        }
        appSearch.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count,
                                                    int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before,
                                                int count) {
                appPage = 0;
                renderAppList();
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
        activitySearch.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count,
                                                    int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before,
                                                int count) {
                activityPage = 0;
                renderActivities();
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
        loadApps(false);
    }

    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(10), dp(14), dp(10));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 16, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(12), dp(5), dp(12), dp(5));
        parent.addView(panel, params);
    }

    @Override protected void onResume() {
        super.onResume();
        if (appsLoaded && !appsLoading) loadApps(true);
    }

    private void loadApps(boolean preserveSelection) {
        if (destroyed || appsLoading) return;
        appsLoading = true;
        final int request = ++appGeneration;
        final String keepPackage = selected != null && preserveSelection
                ? selected.packageName : pendingRestorePackage;
        status.setText("正在后台读取用户应用清单…");
        try {
            worker.execute(() -> {
                List<ApplicationInfo> loaded = new ArrayList<>();
                Map<String, String> labels = new HashMap<>();
                String failure = null;
                try {
                    PackageManager pm = getPackageManager();
                    for (ApplicationInfo app : pm.getInstalledApplications(0)) {
                        if (Thread.currentThread().isInterrupted()) return;
                        if (app == null || !isSafePackage(app.packageName)
                                || app.packageName.equals(getPackageName())
                                || (app.flags & (ApplicationInfo.FLAG_SYSTEM
                                        | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0) continue;
                        String label;
                        try { label = String.valueOf(pm.getApplicationLabel(app)); }
                        catch (RuntimeException unavailable) { label = app.packageName; }
                        loaded.add(app);
                        labels.put(app.packageName, label);
                    }
                    loaded.sort(Comparator.comparing(app ->
                            labels.get(app.packageName).toLowerCase(Locale.ROOT)));
                } catch (RuntimeException error) {
                    failure = error.getClass().getSimpleName();
                }
                if (Thread.currentThread().isInterrupted()) return;
                final List<ApplicationInfo> result = loaded;
                final Map<String, String> resultLabels = labels;
                final String loadFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()
                            || request != appGeneration) return;
                    appsLoading = false;
                    if (loadFailure != null) {
                        appsLoaded = false;
                        status.setText("读取应用列表失败：" + loadFailure + "。请重试。");
                        return;
                    }
                    apps.clear();
                    apps.addAll(result);
                    appLabels.clear();
                    appLabels.putAll(resultLabels);
                    appsLoaded = true;
                    renderAppList();

                    if (keepPackage != null) {
                        ApplicationInfo restored = findApp(keepPackage);
                        pendingRestorePackage = null;
                        if (restored == null) {
                            selected = null;
                            target.setText("原目标应用已卸载或不再可用。");
                            activities.clear();
                            activityRows.removeAllViews();
                            activityCount.setText("目标已失效；原配置不会被删除。");
                            status.setText("已刷新用户应用列表；原目标不在当前安装清单中。");
                        } else {
                            selected = restored;
                            target.setText(appLabel(restored) + "\n" + restored.packageName);
                            status.setText("已恢复目标应用；正在从 PackageManager 重新读取组件状态…");
                            loadActivities();
                        }
                    } else {
                        status.setText("可管理用户应用：" + apps.size() + " 个。点击列表选择目标。");
                    }
                });
            });
        } catch (RejectedExecutionException full) {
            appsLoading = false;
            status.setText("后台任务队列繁忙，应用列表未读取；请稍后重试。");
        }
    }

    private boolean isSafePackage(String packageName) {
        return packageName != null && packageName.length() <= 255
                && packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                && !packageName.contains("..");
    }

    private String appLabel(ApplicationInfo app) {
        String label = app == null ? null : appLabels.get(app.packageName);
        return label == null || label.trim().isEmpty()
                ? (app == null ? "未知应用" : app.packageName) : label;
    }

    private ApplicationInfo findApp(String packageName) {
        for (ApplicationInfo app : apps) {
            if (app.packageName.equals(packageName)) return app;
        }
        return null;
    }

    private void renderAppList() {
        if (appRows == null || appSearch == null || appCount == null) return;
        appRows.removeAllViews();
        String query = appSearch.getText() == null ? ""
                : appSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<ApplicationInfo> matches = new ArrayList<>();
        for (ApplicationInfo app : apps) {
            String label = appLabel(app);
            if (query.isEmpty() || label.toLowerCase(Locale.ROOT).contains(query)
                    || app.packageName.toLowerCase(Locale.ROOT).contains(query)) {
                matches.add(app);
            }
        }
        int pages = Math.max(1, (matches.size() + APP_PAGE_SIZE - 1) / APP_PAGE_SIZE);
        appPage = Math.min(appPage, pages - 1);
        int start = appPage * APP_PAGE_SIZE;
        int end = Math.min(matches.size(), start + APP_PAGE_SIZE);
        appCount.setText("匹配 " + matches.size() + " / 已安装用户应用 " + apps.size() + " 个");
        appPageText.setText((appPage + 1) + " / " + pages);
        Button[] pagerButtons = (Button[]) appPager.getTag();
        pagerButtons[0].setEnabled(appPage > 0);
        pagerButtons[1].setEnabled(appPage + 1 < pages);

        if (matches.isEmpty()) {
            appRows.addView(text(query.isEmpty() ? "没有可管理的用户应用。"
                    : "没有匹配此搜索词的应用。", 13, 0xff718091, false));
            return;
        }
        for (int i = start; i < end; i++) {
            ApplicationInfo app = matches.get(i);
            boolean chosen = selected != null && selected.packageName.equals(app.packageName);
            TextView row = text(appLabel(app) + "\n" + app.packageName,
                    13, chosen ? 0xff164c86 : 0xff263443, chosen);
            row.setPadding(dp(12), dp(10), dp(12), dp(10));
            row.setBackgroundColor(chosen ? 0xffe2edf8 : 0xffffffff);
            row.setOnClickListener(v -> selectApp(app));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
            params.setMargins(dp(2), dp(2), dp(2), dp(2));
            appRows.addView(row, params);
        }
    }

    private void loadActivities() {
        if (destroyed) return;
        if (selected == null || !isSafePackage(selected.packageName)) {
            status.setText("请先从用户应用列表中选择一个目标。");
            return;
        }
        if (activitiesLoading) return;
        activitiesLoading = true;
        final int request = ++activityGeneration;
        final ApplicationInfo app = selected;
        final String packageName = app.packageName;
        activities.clear();
        activityRows.removeAllViews();
        status.setText("正在后台读取 " + packageName + " 的 Activity 声明与组件状态…");
        activityCount.setText("读取中…");
        try {
            worker.execute(() -> {
                List<ActivityEntry> result = new ArrayList<>();
                String failure = null;
                try {
                    PackageManager pm = getPackageManager();
                    PackageInfo info = pm.getPackageInfo(packageName,
                            PackageManager.GET_ACTIVITIES | PackageManager.MATCH_DISABLED_COMPONENTS);
                    boolean applicationEnabled = info.applicationInfo == null
                            || info.applicationInfo.enabled;
                    if (info.activities != null) {
                        Set<String> launcherNames = new HashSet<>();
                        if (launcherOnly) {
                            Intent launcherIntent = new Intent(Intent.ACTION_MAIN);
                            launcherIntent.addCategory(Intent.CATEGORY_LAUNCHER);
                            for (android.content.pm.ResolveInfo resolve : pm.queryIntentActivities(
                                    launcherIntent, PackageManager.MATCH_DISABLED_COMPONENTS)) {
                                if (resolve.activityInfo != null
                                        && packageName.equals(resolve.activityInfo.packageName)
                                        && resolve.activityInfo.name != null) {
                                    launcherNames.add(resolve.activityInfo.name);
                                }
                            }
                        }
                        for (ActivityInfo item : info.activities) {
                            if (Thread.currentThread().isInterrupted()) return;
                            if (item == null || item.name == null
                                    || !item.name.matches("[A-Za-z0-9_.$]+")) continue;
                            if (launcherOnly && !launcherNames.contains(item.name)) continue;
                            int state;
                            try {
                                state = pm.getComponentEnabledSetting(
                                        new ComponentName(packageName, item.name));
                            } catch (RuntimeException unavailable) {
                                state = PackageManager.COMPONENT_ENABLED_STATE_DEFAULT;
                            }
                            result.add(new ActivityEntry(item, state, applicationEnabled));
                        }
                    }
                    result.sort(Comparator.comparing(entry ->
                            entry.info.name == null ? "" : entry.info.name));
                } catch (PackageManager.NameNotFoundException error) {
                    failure = "NameNotFoundException: " + safeError(error.getMessage());
                } catch (RuntimeException error) {
                    failure = error.getClass().getSimpleName() + ": " + safeError(error.getMessage());
                }
                if (Thread.currentThread().isInterrupted()) return;
                final List<ActivityEntry> loaded = result;
                final String loadFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()
                            || request != activityGeneration
                            || selected == null || !packageName.equals(selected.packageName)) return;
                    activitiesLoading = false;
                    if (loadFailure != null) {
                        activities.clear();
                        activityRows.removeAllViews();
                        activityCount.setText("读取失败，未生成可操作列表。");
                        status.setText("读取 Activity 失败：" + loadFailure);
                        return;
                    }
                    activities.clear();
                    activities.addAll(loaded);
                    status.setText("已读取 " + activities.size()
                            + (launcherOnly ? " 个启动器入口。" : " 个 Activity 声明。"));
                    renderActivities();
                });
            });
        } catch (RejectedExecutionException full) {
            activitiesLoading = false;
            activityCount.setText("读取队列繁忙。");
            status.setText("后台任务队列繁忙，Activity 列表未读取；请稍后重试。");
        }
    }

    private String safeError(String value) {
        if (value == null) return "没有错误详情";
        String text = value.replace('\n', ' ').replace('\r', ' ').trim();
        return text.length() > 180 ? text.substring(0, 180) : text;
    }

    private void renderActivities() {
        if (activityRows == null || activitySearch == null || activityCount == null) return;
        activityRows.removeAllViews();
        String query = activitySearch.getText() == null ? ""
                : activitySearch.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<ActivityEntry> matches = new ArrayList<>();
        for (ActivityEntry entry : activities) {
            String name = entry.info.name == null ? "" : entry.info.name;
            String permission = entry.info.permission == null ? "" : entry.info.permission;
            String state = Integer.toString(entry.componentState);
            if (query.isEmpty() || name.toLowerCase(Locale.ROOT).contains(query)
                    || permission.toLowerCase(Locale.ROOT).contains(query)
                    || state.contains(query)
                    || Boolean.toString(entry.info.exported).contains(query)
                    || Boolean.toString(entry.enabled).contains(query)) {
                matches.add(entry);
            }
        }
        int pages = Math.max(1, (matches.size() + ACTIVITY_PAGE_SIZE - 1) / ACTIVITY_PAGE_SIZE);
        activityPage = Math.min(activityPage, pages - 1);
        int start = activityPage * ACTIVITY_PAGE_SIZE;
        int end = Math.min(matches.size(), start + ACTIVITY_PAGE_SIZE);
        activityCount.setText("匹配 " + matches.size() + " / 已读取 " + activities.size() + " 个组件");
        activityPageText.setText((activityPage + 1) + " / " + pages);
        Button[] pagerButtons = (Button[]) activityPager.getTag();
        pagerButtons[0].setEnabled(activityPage > 0);
        pagerButtons[1].setEnabled(activityPage + 1 < pages);

        if (activities.isEmpty()) {
            activityRows.addView(text("该应用没有声明可读取的 Activity。", 13, 0xff718091, false));
            return;
        }
        if (matches.isEmpty()) {
            activityRows.addView(text("没有匹配此筛选条件的 Activity。", 13, 0xff718091, false));
            return;
        }
        for (int i = start; i < end; i++) addActivityRow(selected.packageName, matches.get(i));
    }

    private void addActivityRow(String packageName, ActivityEntry entry) {
        ActivityInfo info = entry.info;
        String className = info.name;
        if (!isSafePackage(packageName) || className == null
                || !className.matches("[A-Za-z0-9_.$]+")) return;

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(12), dp(7), dp(12), dp(7));
        row.setBackgroundColor(0xffffffff);
        TextView name = text(className, 13, 0xff17212b, true);
        String permission = info.permission == null ? "无" : info.permission;
        TextView meta = text("exported=" + info.exported + " · manifestEnabled=" + info.enabled
                + " · appEnabled=" + entry.applicationEnabled
                + " · componentState=" + entry.componentState + " · permission=" + permission,
                10, 0xff718091, false);
        Switch toggle = new Switch(this);
        toggle.setText("启用此 Activity");
        toggle.setChecked(entry.enabled);
        final boolean[] changingProgrammatically = {false};
        toggle.setOnCheckedChangeListener((button, wanted) -> {
            if (changingProgrammatically[0]) return;
            button.setEnabled(false);
            String componentArg = packageName + "/" + className;
            String command = "user_id=$(am get-current-user 2>/dev/null); "
                    + "case \"$user_id\" in ''|*[!0-9]*) echo 'Unable to resolve current Android user' >&2; exit 65 ;; esac; "
                    + (wanted ? "pm enable --user \"$user_id\" "
                            : "pm disable-user --user \"$user_id\" ")
                    + quote(componentArg);
            Runnable rollback = () -> {
                changingProgrammatically[0] = true;
                button.setChecked(entry.enabled);
                changingProgrammatically[0] = false;
                button.setEnabled(true);
            };
            final boolean[] operationAccepted = {false};
            AlertDialog dialog = fxDialogBuilder()
                    .setTitle(wanted ? "启用 Activity？" : "禁用 Activity？")
                    .setMessage("这会修改目标应用的组件状态。禁用启动入口可能导致目标应用无法正常打开；可返回 FX 再次启用。")
                    .setNegativeButton("取消", (ignored, which) -> rollback.run())
                    .setPositiveButton("继续", (ignored, which) -> {
                        operationAccepted[0] = true;
                        boolean queued = submitWorker(() -> {
                            RootAccess.Result applied = null;
                            String failure = null;
                            try {
                                applied = RootAccess.execute(command, 30000L, 65536);
                            } catch (RuntimeException error) {
                                failure = error.getClass().getSimpleName() + ": " + error.getMessage();
                            }
                            final RootAccess.Result result = applied;
                            final String operationFailure = failure;
                            runOnUiThread(() -> {
                                if (destroyed || isFinishing() || isDestroyed()) return;
                                if (selected == null || !packageName.equals(selected.packageName)) return;
                                if (operationFailure != null || result == null || result.exitCode != 0) {
                                    rollback.run();
                                    String detail = operationFailure != null ? operationFailure
                                            : result == null ? "Root 没有返回结果。"
                                            : safeError(result.output);
                                    status.setText("组件状态修改失败：" + detail);
                                    return;
                                }
                                button.setEnabled(true);
                                status.setText(wanted ? "Activity 启用命令已执行，正在读取系统新状态…"
                                        : "Activity 禁用命令已执行，正在读取系统新状态…");
                                activityGeneration++;
                                activitiesLoading = false;
                                loadActivities();
                            });
                        });
                        if (!queued) rollback.run();
                    })
                    .create();
            dialog.setOnCancelListener(ignored -> {
                if (!operationAccepted[0]) rollback.run();
            });
            showFxDialog(dialog);
        });
        row.addView(name);
        row.addView(meta);
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(button("复制组件名", () -> {
            try {
                android.content.ClipboardManager clipboard =
                        (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                if (clipboard == null) throw new IllegalStateException("系统剪贴板不可用");
                clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                        "FX Activity component", packageName + "/" + className));
                Toast.makeText(this, "已复制 Activity 组件名。", Toast.LENGTH_SHORT).show();
            } catch (RuntimeException error) {
                Toast.makeText(this, "复制失败：" + safeError(error.getMessage()),
                        Toast.LENGTH_LONG).show();
            }
        }));
        if (info.exported) {
            actions.addView(button("启动 Activity", () -> launchExportedActivity(packageName, className)));
        }
        row.addView(actions);
        row.addView(toggle);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(10), dp(3), dp(10), dp(3));
        activityRows.addView(row, params);
    }

    private void confirmEnableVisibleActivities() {
        if (launcherOnly || selected == null || !isSafePackage(selected.packageName)
                || activitiesLoading || destroyed) {
            status.setText("请先选择目标应用并完成 Activity 读取。");
            return;
        }
        String query = activitySearch == null || activitySearch.getText() == null ? ""
                : activitySearch.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<ActivityEntry> matches = new ArrayList<>();
        for (ActivityEntry entry : activities) {
            String name = entry.info == null || entry.info.name == null ? "" : entry.info.name;
            String permission = entry.info == null || entry.info.permission == null
                    ? "" : entry.info.permission;
            String state = Integer.toString(entry.componentState);
            if (query.isEmpty() || name.toLowerCase(Locale.ROOT).contains(query)
                    || permission.toLowerCase(Locale.ROOT).contains(query)
                    || state.contains(query)
                    || Boolean.toString(entry.info.exported).contains(query)
                    || Boolean.toString(entry.enabled).contains(query)) {
                matches.add(entry);
            }
        }
        int start = activityPage * ACTIVITY_PAGE_SIZE;
        int end = Math.min(matches.size(), start + ACTIVITY_PAGE_SIZE);
        List<String> components = new ArrayList<>();
        for (int i = start; i < end; i++) {
            ActivityEntry entry = matches.get(i);
            String name = entry.info == null ? null : entry.info.name;
            if (entry.enabled || name == null || !name.matches("[A-Za-z0-9_.$]+")) continue;
            components.add(selected.packageName + "/" + name);
        }
        if (components.isEmpty()) {
            Toast.makeText(this, "当前页筛选结果中没有已禁用的 Activity。", Toast.LENGTH_SHORT).show();
            return;
        }
        final List<String> currentPage = new ArrayList<>(components);
        final String packageName = selected.packageName;
        fxDialogBuilder()
                .setTitle("批量启用当前页 Activity？")
                .setMessage("将仅启用当前筛选结果当前页中的 " + currentPage.size()
                        + " 个 Activity 组件，目标包：" + packageName
                        + "。不会修改应用整体启用状态，也不会处理其他分页。请确认这些组件确实需要恢复。")
                .setNegativeButton("取消", null)
                .setPositiveButton("启用所列组件", (dialog, which) -> {
                    status.setText("正在批量启用当前页 " + currentPage.size() + " 个组件…");
                    submitWorker(() -> {
                        RootAccess.Result result = null;
                        String failure = null;
                        try {
                            StringBuilder command = new StringBuilder();
                            command.append("user_id=$(am get-current-user 2>/dev/null); ")
                                    .append("case \"$user_id\" in ''|*[!0-9]*) echo 'Unable to resolve current Android user' >&2; exit 65 ;; esac; ")
                                    .append("fx_ok=0; fx_fail=0; ");
                            for (String component : currentPage) {
                                command.append("if pm enable --user \"$user_id\" ")
                                        .append(quote(component))
                                        .append(" >/dev/null 2>&1; then fx_ok=$((fx_ok+1)); ")
                                        .append("else fx_fail=$((fx_fail+1)); fi; ");
                            }
                            command.append("printf 'FX_ENABLED=%s\\nFX_FAILED=%s\\n' \"$fx_ok\" \"$fx_fail\"; ")
                                    .append("[ \"$fx_fail\" -eq 0 ]");
                            result = RootAccess.execute(command.toString(), 60000L, 16384);
                        } catch (RuntimeException error) {
                            failure = error.getClass().getSimpleName() + ": " + safeError(error.getMessage());
                        }
                        final RootAccess.Result applied = result;
                        final String operationFailure = failure;
                        runOnUiThread(() -> {
                            if (destroyed || isFinishing() || isDestroyed()
                                    || selected == null || !packageName.equals(selected.packageName)) return;
                            if (operationFailure != null || applied == null) {
                                status.setText("批量启用未完成：" + (operationFailure == null
                                        ? "Root 没有返回结果。" : operationFailure));
                                return;
                            }
                            String output = applied.output == null ? "" : applied.output;
                            java.util.regex.Matcher ok = java.util.regex.Pattern
                                    .compile("FX_ENABLED=([0-9]+)").matcher(output);
                            java.util.regex.Matcher failed = java.util.regex.Pattern
                                    .compile("FX_FAILED=([0-9]+)").matcher(output);
                            String okCount = ok.find() ? ok.group(1) : "0";
                            String failCount = failed.find() ? failed.group(1) : "?";
                            status.setText("批量启用结果：成功 " + okCount + "，失败 " + failCount
                                    + "。正在重新读取系统组件状态…");
                            activityGeneration++;
                            activitiesLoading = false;
                            loadActivities();
               private void confirmDisableVisibleActivities() {
        if (launcherOnly || selected == null || !isSafePackage(selected.packageName)
                || activitiesLoading || destroyed) {
            status.setText("请先选择目标应用并完成 Activity 读取。");
            return;
        }
        String query = activitySearch == null || activitySearch.getText() == null ? ""
                : activitySearch.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<ActivityEntry> matches = new ArrayList<>();
        for (ActivityEntry entry : activities) {
            String name = entry.info == null || entry.info.name == null ? "" : entry.info.name;
            String permission = entry.info == null || entry.info.permission == null
                    ? "" : entry.info.permission;
            String state = Integer.toString(entry.componentState);
            if (query.isEmpty() || name.toLowerCase(Locale.ROOT).contains(query)
                    || permission.toLowerCase(Locale.ROOT).contains(query)
                    || state.contains(query)
                    || Boolean.toString(entry.info.exported).contains(query)
                    || Boolean.toString(entry.enabled).contains(query)) {
                matches.add(entry);
            }
        }
        int start = activityPage * ACTIVITY_PAGE_SIZE;
        int end = Math.min(matches.size(), start + ACTIVITY_PAGE_SIZE);
        List<String> components = new ArrayList<>();
        for (int i = start; i < end; i++) {
            ActivityEntry entry = matches.get(i);
            String name = entry.info == null ? null : entry.info.name;
            if (!entry.enabled || name == null || !name.matches("[A-Za-z0-9_.$]+")) continue;
            components.add(selected.packageName + "/" + name);
        }
        if (components.isEmpty()) {
            Toast.makeText(this, "当前页筛选结果中没有已启用的 Activity。", Toast.LENGTH_SHORT).show();
            return;
        }
        final List<String> currentPage = new ArrayList<>(components);
        final String packageName = selected.packageName;
        fxDialogBuilder()
                .setTitle("批量禁用当前页 Activity？")
                .setMessage("将仅禁用当前筛选结果当前页中的 " + currentPage.size()
                        + " 个 Activity 组件，目标包：" + packageName
                        + "。不会修改应用整体启用状态，也不会处理其他分页。请确认这些组件确实需要恢复。")
                .setNegativeButton("取消", null)
                .setPositiveButton("禁用所列组件", (dialog, which) -> {
                    status.setText("正在批量禁用当前页 " + currentPage.size() + " 个组件…");
                    submitWorker(() -> {
                        RootAccess.Result result = null;
                        String failure = null;
                        try {
                            StringBuilder command = new StringBuilder();
                            command.append("user_id=$(am get-current-user 2>/dev/null); ")
                                    .append("case \"$user_id\" in ''|*[!0-9]*) echo 'Unable to resolve current Android user' >&2; exit 65 ;; esac; ")
                                    .append("fx_ok=0; fx_fail=0; ");
                            for (String component : currentPage) {
                                command.append("if pm disable-user --user \"$user_id\" ")
                                        .append(quote(component))
                                        .append(" >/dev/null 2>&1; then fx_ok=$((fx_ok+1)); ")
                                        .append("else fx_fail=$((fx_fail+1)); fi; ");
                            }
                            command.append("printf 'FX_DISABLED=%s\\nFX_FAILED=%s\\n' \"$fx_ok\" \"$fx_fail\"; ")
                                    .append("[ \"$fx_fail\" -eq 0 ]");
                            result = RootAccess.execute(command.toString(), 60000L, 16384);
                        } catch (RuntimeException error) {
                            failure = error.getClass().getSimpleName() + ": " + safeError(error.getMessage());
                        }
                        final RootAccess.Result applied = result;
                        final String operationFailure = failure;
                        runOnUiThread(() -> {
                            if (destroyed || isFinishing() || isDestroyed()
                                    || selected == null || !packageName.equals(selected.packageName)) return;
                            if (operationFailure != null || applied == null) {
                                status.setText("批量禁用未完成：" + (operationFailure == null
                                        ? "Root 没有返回结果。" : operationFailure));
                                return;
                            }
                            String output = applied.output == null ? "" : applied.output;
                            java.util.regex.Matcher ok = java.util.regex.Pattern
                                    .compile("FX_DISABLED=([0-9]+)").matcher(output);
                            java.util.regex.Matcher failed = java.util.regex.Pattern
                                    .compile("FX_FAILED=([0-9]+)").matcher(output);
                            String okCount = ok.find() ? ok.group(1) : "0";
                            String failCount = failed.find() ? failed.group(1) : "?";
                            status.setText("批量禁用结果：成功 " + okCount + "，失败 " + failCount
                                    + "。正在重新读取系统组件状态…");
                            activityGeneration++;
                            activitiesLoading = false;
                            loadActivities();
                        });
                    });
                })
                .show();
    }

             });
                    });
                })
                .show();
    }

    private void launchExportedActivity(String packageName, String className) {
        if (!isSafePackage(packageName) || className == null
                || !className.matches("[A-Za-z0-9_.$]+")
                || selected == null || !packageName.equals(selected.packageName)) {
            Toast.makeText(this, "目标组件已变化，请重新读取列表。", Toast.LENGTH_SHORT).show();
            return;
        }
        ActivityEntry current = null;
        for (ActivityEntry entry : activities) {
            if (entry.info != null && className.equals(entry.info.name)) {
                current = entry;
                break;
            }
        }
        if (current == null || !current.info.exported || !current.enabled) {
            Toast.makeText(this, "该 Activity 未导出或当前处于禁用状态，不能从此处启动。",
                    Toast.LENGTH_LONG).show();
            return;
        }
        String permission = current.info.permission;
        String warning = "将显式启动目标应用声明的已导出 Activity：\\n"
                + packageName + "/" + className
                + (permission == null || permission.isEmpty()
                    ? "\\n该组件未声明启动权限。"
                    : "\\n该组件声明启动权限：" + permission
                        + "。当前调用方可能不具备该权限。")
                + "\\n目标应用可能执行页面跳转或其他自身逻辑。";
        fxDialogBuilder()
                .setTitle("启动目标 Activity？")
                .setMessage(warning)
                .setNegativeButton("取消", null)
                .setPositiveButton("启动", (dialog, which) -> {
                    try {
                        Intent intent = new Intent();
                        intent.setComponent(new ComponentName(packageName, className));
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        status.setText("已向 Android 提交显式 Activity 启动请求。");
                    } catch (SecurityException denied) {
                        status.setText("启动被 Android 权限策略拒绝：" + safeError(denied.getMessage()));
                    } catch (RuntimeException error) {
                        status.setText("Activity 启动失败：" + error.getClass().getSimpleName()
                                + "：" + safeError(error.getMessage()));
                    }
                })
                .show();
    }

    private void selectApp(ApplicationInfo app) {
        if (app == null || !isSafePackage(app.packageName)) return;
        activityGeneration++;
        activitiesLoading = false;
        selected = app;
        target.setText(appLabel(app) + "\n" + app.packageName);
        activitySearch.setText("");
        activities.clear();
        activityPage = 0;
        activityRows.removeAllViews();
        activityCount.setText("正在读取 Activity 入口…");
        status.setText("目标已选择；正在读取系统组件状态。");
        renderAppList();
        loadActivities();
    }

    private void clearSelection() {
        selected = null;
        pendingRestorePackage = null;
        activityGeneration++;
        activitiesLoading = false;
        activities.clear();
        target.setText("尚未选择应用。");
        status.setText("已清除当前目标选择；不会修改目标应用组件状态。");
        activityRows.removeAllViews();
        activityCount.setText("请从用户应用列表中选择目标。");
        renderAppList();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putString(STATE_SELECTED_PACKAGE,
                selected == null ? pendingRestorePackage : selected.packageName);
        outState.putString(STATE_APP_QUERY,
                appSearch == null ? "" : appSearch.getText().toString());
        outState.putString(STATE_ACTIVITY_QUERY,
                activitySearch == null ? "" : activitySearch.getText().toString());
        outState.putInt(STATE_APP_PAGE, appPage);
        outState.putInt(STATE_ACTIVITY_PAGE, activityPage);
        outState.putInt(STATE_SCROLL_Y, pageScroll == null
                ? restoredScrollY : Math.max(0, pageScroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    @Override protected void onDestroy() {
        destroyed = true;
        appGeneration++;
        activityGeneration++;
        worker.shutdownNow();
        super.onDestroy();
    }
}
