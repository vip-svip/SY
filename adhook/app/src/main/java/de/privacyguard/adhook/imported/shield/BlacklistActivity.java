package de.privacyguard.adhook.imported.shield;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.Toast;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HashMap;
import java.util.Map;
import java.util.Locale;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 管控应用管理（原黑名单管理）。
 * 用户将应用加入管控后，实时守护会提醒这些应用进入前台；不会自动停止、冻结或卸载应用。
 * 不显示系统应用。
 * "我都很信任" 按钮清空管控列表。
 */
public class BlacklistActivity extends de.privacyguard.adhook.FxNativeTabActivity {

    private PackageManager pm;
    private SharedPreferences prefs;
    private Set<String> currentBlacklist = new HashSet<>();
    private final List<AppItem> allApps = new ArrayList<>();
    private final Map<String, AppItem> appByPackage = new HashMap<>();
    private final ThreadPoolExecutor appLoader = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-shield-blacklist-apps"),
            new ThreadPoolExecutor.AbortPolicy());
    private final AtomicLong appLoadGeneration = new AtomicLong();
    private volatile boolean activityDestroyed;
    private boolean appsLoading = true;
    private static final int BLACKLIST_PAGE_SIZE = 50;
    private static final int MAX_PICKER_STAGED = 100;
    private int blacklistPage = 1;
    private LinearLayout blacklistContainer;
    private ScrollView blacklistScroll;
    private static final String STATE_PAGE = "fx_shield_blacklist_page";
    private static final String STATE_SCROLL_Y = "fx_shield_blacklist_scroll_y";
    private static final String STATE_PICKER_OPEN = "fx_shield_blacklist_picker_open";
    private static final String STATE_PICKER_QUERY = "fx_shield_blacklist_picker_query";
    private static final String STATE_PICKER_PAGE = "fx_shield_blacklist_picker_page";
    private static final String STATE_PICKER_STAGED = "fx_shield_blacklist_picker_staged";
    private static final String STATE_PICKER_SCROLL_Y = "fx_shield_blacklist_picker_scroll_y";
    private boolean pickerDialogOpen;
    private String pickerQuery = "";
    private int pickerPage = 1;
    private final Set<String> pickerStaged = new HashSet<>();
    private ScrollView pickerScroll;
    private int pickerScrollY;
    private LinearLayout emptyHint;
    private TextView trustAllBtn;
    private TextView blacklistDataWarningView;
    private boolean blacklistDataCorrupt;
    private String blacklistDataWarning = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        pm = getPackageManager();
        prefs = getSharedPreferences("shield_prefs", MODE_PRIVATE);
        loadBlacklist();

        if (savedInstanceState != null) {
            blacklistPage = Math.max(1, savedInstanceState.getInt(STATE_PAGE, 1));
            pickerDialogOpen = savedInstanceState.getBoolean(STATE_PICKER_OPEN, false);
            pickerQuery = savedInstanceState.getString(STATE_PICKER_QUERY, "");
            pickerPage = Math.max(1, savedInstanceState.getInt(STATE_PICKER_PAGE, 1));
            pickerScrollY = Math.max(0, savedInstanceState.getInt(STATE_PICKER_SCROLL_Y, 0));
            ArrayList<String> staged = savedInstanceState.getStringArrayList(STATE_PICKER_STAGED);
            if (staged != null && staged.size() <= MAX_PICKER_STAGED) pickerStaged.addAll(staged);
        }

        // ===== 根布局 =====
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xFFF5F6FA);
        root.setFitsSystemWindows(true);

        // ------- 顶栏 -------
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setBackgroundColor(0xFFD32F2F);
        header.setPadding(24, dp(12) + getStatusBarHeight(), 24, dp(12));

        TextView backBtn = new TextView(this);
        backBtn.setText("\u2190");
        backBtn.setTextColor(Color.WHITE);
        backBtn.setTextSize(22);
        backBtn.setPadding(0, 0, dp(16), 0);
        backBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) { finish(); }
        });
        header.addView(backBtn);

        TextView title = new TextView(this);
        title.setText("管控应用的列表");
        title.setTextColor(Color.WHITE);
        title.setTextSize(20);
        title.setTypeface(null, Typeface.BOLD);
        header.addView(title);

        root.addView(header);

        // ------- 内容区 -------
        blacklistScroll = new ScrollView(this);
        blacklistScroll.setFillViewport(true);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(24), dp(20), dp(24), dp(40));

        blacklistDataWarningView = new TextView(this);
        blacklistDataWarningView.setTextColor(0xffa32620);
        blacklistDataWarningView.setTextSize(13);
        blacklistDataWarningView.setPadding(dp(12), dp(10), dp(12), dp(10));
        blacklistDataWarningView.setVisibility(View.GONE);
        content.addView(blacklistDataWarningView);

        // 图标
        TextView iconView = new TextView(this);
        iconView.setText("\u26A0\uFE0F");
        iconView.setTextSize(40);
        iconView.setGravity(Gravity.CENTER);
        GradientDrawable iconBg = new GradientDrawable();
        iconBg.setShape(GradientDrawable.OVAL);
        iconBg.setColor(0xFFFFEBEE);
        int iconSize = dp(80);
        iconBg.setSize(iconSize, iconSize);
        iconView.setBackground(iconBg);
        iconView.setMinWidth(iconSize);
        iconView.setMinHeight(iconSize);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(iconSize, iconSize);
        ip.gravity = Gravity.CENTER_HORIZONTAL;
        iconView.setLayoutParams(ip);
        content.addView(iconView);

        // 加入管控按钮
        Button addBtn = new Button(this);
        addBtn.setText("添加要管控的应用");
        addBtn.setTextColor(Color.WHITE);
        addBtn.setTextSize(17);
        addBtn.setTypeface(null, Typeface.BOLD);
        GradientDrawable btnBg = new GradientDrawable();
        btnBg.setShape(GradientDrawable.RECTANGLE);
        btnBg.setCornerRadius(dp(28));
        btnBg.setColor(0xFF1565C0);
        addBtn.setBackground(btnBg);
        addBtn.setPadding(dp(48), dp(14), dp(48), dp(14));
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bp.topMargin = dp(24);
        bp.gravity = Gravity.CENTER_HORIZONTAL;
        addBtn.setLayoutParams(bp);
        addBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showAppPicker();
            }
        });
        content.addView(addBtn);

        // "我都很信任" 按钮 — 清空全部管控
        trustAllBtn = new TextView(this);
        trustAllBtn.setText("我都很信任");
        trustAllBtn.setTextColor(0xFF666666);
        trustAllBtn.setTextSize(14);
        trustAllBtn.setGravity(Gravity.CENTER);
        trustAllBtn.setPadding(0, dp(16), 0, dp(8));
        trustAllBtn.setTypeface(null, Typeface.BOLD);
        trustAllBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                trustAll();
            }
        });
        content.addView(trustAllBtn);

        // 说明文字
        TextView hint = new TextView(this);
        hint.setText("管控中的应用将启动安全护盾拦截\n不显示系统应用");
        hint.setTextColor(0xFF999999);
        hint.setTextSize(13);
        hint.setGravity(Gravity.CENTER);
        hint.setPadding(0, dp(4), 0, dp(24));
        content.addView(hint);

        // 空状态提示
        emptyHint = new LinearLayout(this);
        emptyHint.setOrientation(LinearLayout.VERTICAL);
        emptyHint.setGravity(Gravity.CENTER);
        emptyHint.setPadding(0, dp(20), 0, 0);
        TextView emptyText = new TextView(this);
        emptyText.setText("暂无管控应用\n所有应用都不会被拦截");
        emptyText.setTextColor(0xFFBBBBBB);
        emptyText.setTextSize(15);
        emptyText.setGravity(Gravity.CENTER);
        emptyHint.addView(emptyText);
        content.addView(emptyHint);

        // 已加入管控列表容器
        blacklistContainer = new LinearLayout(this);
        blacklistContainer.setOrientation(LinearLayout.VERTICAL);
        blacklistContainer.setPadding(0, dp(16), 0, 0);
        content.addView(blacklistContainer);

        blacklistScroll.addView(content);
        root.addView(blacklistScroll);

        setContentViewWithNativeTabs(root, 5);
        if (savedInstanceState != null) {
            final int restoreY = Math.max(0, savedInstanceState.getInt(STATE_SCROLL_Y, 0));
            blacklistScroll.post(() -> blacklistScroll.scrollTo(0, restoreY));
        }

        refreshBlacklistUI();
        loadAppsAsync();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putInt(STATE_PAGE, Math.max(1, blacklistPage));
        outState.putBoolean(STATE_PICKER_OPEN, pickerDialogOpen);
        outState.putString(STATE_PICKER_QUERY, pickerQuery.length() > 256 ? pickerQuery.substring(0, 256) : pickerQuery);
        outState.putInt(STATE_PICKER_PAGE, Math.max(1, Math.min(100, pickerPage)));
        if (pickerScroll != null) outState.putInt(STATE_PICKER_SCROLL_Y, Math.max(0, pickerScroll.getScrollY()));
        if (pickerStaged.size() <= MAX_PICKER_STAGED) outState.putStringArrayList(STATE_PICKER_STAGED, new ArrayList<>(pickerStaged));
        if (blacklistScroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, blacklistScroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    private int getStatusBarHeight() {
        int id = getResources().getIdentifier("status_bar_height", "dimen", "android");
        return id > 0 ? getResources().getDimensionPixelSize(id) : 0;
    }

    private int dp(int px) {
        float d = getResources().getDisplayMetrics().density;
        return (int) (px * d + 0.5f);
    }

    private void loadBlacklist() {
        currentBlacklist.clear();
        String raw = prefs.getString("blacklist_pkgs", "");
        blacklistDataCorrupt = !raw.isEmpty() && !FxYulongBlacklistPolicy.isWellFormed(raw);
        blacklistDataWarning = blacklistDataCorrupt
                ? "原管控名单格式异常或超过安全上限；为避免覆盖旧配置，当前禁止修改。"
                : "";
        if (!blacklistDataCorrupt) currentBlacklist.addAll(FxYulongBlacklistPolicy.parse(raw));
    }

    private boolean saveBlacklist() {
        if (blacklistDataCorrupt) {
            Toast.makeText(this, "原管控名单数据异常，已阻止覆盖。请先核实并修复原始数据。",
                    Toast.LENGTH_LONG).show();
            return false;
        }
        String serialized = FxYulongBlacklistPolicy.serialize(currentBlacklist);
        if (serialized == null) {
            Toast.makeText(this, "管控名单超过安全条数或字符上限，未保存任何部分数据。",
                    Toast.LENGTH_LONG).show();
            return false;
        }
        if (!prefs.edit().putString("blacklist_pkgs", serialized).commit()) {
            Toast.makeText(this, "管控名单保存失败，原有配置保持不变。", Toast.LENGTH_LONG).show();
            return false;
        }
        return true;
    }

    private static class AppItem {
        String packageName;
        String label;
    }

    /** 判断是否为系统应用 */
    private boolean isSystemApp(ApplicationInfo app) {
        if ((app.flags & ApplicationInfo.FLAG_SYSTEM) != 0) return true;
        if ((app.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0) return true;
        if (app.sourceDir != null && app.sourceDir.startsWith("/system/")) return true;
        return false;
    }

    /** Package enumeration and label resolution stay off the Activity UI thread. */
    private void loadAppsAsync() {
        final long generation = appLoadGeneration.incrementAndGet();
        appsLoading = true;
        try {
            appLoader.execute(() -> {
                final List<AppItem> loaded = new ArrayList<>();
                final Map<String, AppItem> loadedIndex = new HashMap<>();
                Throwable failure = null;
                try {
                    PackageManager backgroundPm = getApplicationContext().getPackageManager();
                    for (ApplicationInfo app : backgroundPm.getInstalledApplications(0)) {
                        if (Thread.currentThread().isInterrupted()
                                || generation != appLoadGeneration.get()) return;
                        if (app.packageName == null || app.packageName.equals(getPackageName())
                                || isSystemApp(app)) continue;
                        AppItem item = new AppItem();
                        item.packageName = app.packageName;
                        try {
                            CharSequence label = backgroundPm.getApplicationLabel(app);
                            item.label = label == null ? app.packageName : label.toString();
                        } catch (Throwable ignored) {
                            item.label = app.packageName;
                        }
                        loaded.add(item);
                        loadedIndex.put(item.packageName, item);
                    }
                    loaded.sort(Comparator.comparing(item ->
                            item.label.toLowerCase(Locale.ROOT)));
                } catch (Throwable error) {
                    failure = error;
                }
                final Throwable loadFailure = failure;
                runOnUiThread(() -> {
                    if (activityDestroyed || isFinishing() || isDestroyed()
                            || generation != appLoadGeneration.get()) return;
                    appsLoading = false;
                    if (loadFailure != null) {
                        Toast.makeText(this,
                                "读取已安装应用失败：" + loadFailure.getClass().getSimpleName(),
                                Toast.LENGTH_LONG).show();
                        return;
                    }
                    allApps.clear();
                    allApps.addAll(loaded);
                    appByPackage.clear();
                    appByPackage.putAll(loadedIndex);
                    refreshBlacklistUI();
                    if (pickerDialogOpen) showAppPicker(true);
                });
            });
        } catch (RejectedExecutionException full) {
            appsLoading = false;
            if (!activityDestroyed && !isFinishing()) {
                Toast.makeText(this, "应用列表任务繁忙，请重新打开管控页面。", Toast.LENGTH_LONG).show();
            }
        }
    }

    private void showAppPicker() { showAppPicker(false); }

    private void showAppPicker(boolean restoring) {
        if (blacklistDataCorrupt) {
            Toast.makeText(this, "原管控名单数据异常，已禁止修改；请先修复原始数据。", Toast.LENGTH_LONG).show();
            return;
        }
        if (!restoring && appsLoading) {
            Toast.makeText(this, "正在读取应用列表，请稍后再试。", Toast.LENGTH_SHORT).show();
            return;
        }
        if (!restoring) {
            pickerDialogOpen = true;
            pickerQuery = "";
            pickerPage = 1;
            pickerStaged.clear();
        }
        if (appsLoading) {
            Toast.makeText(this, "正在读取应用列表，请稍后再试。", Toast.LENGTH_SHORT).show();
            return;
        }
        final List<AppItem> candidates = new ArrayList<>();
        for (AppItem item : allApps) {
            if (!currentBlacklist.contains(item.packageName)) candidates.add(item);
        }
        if (candidates.isEmpty()) {
            pickerDialogOpen = false;
            pickerQuery = "";
            pickerPage = 1;
            pickerScrollY = 0;
            pickerStaged.clear();
            new AlertDialog.Builder(this)
                    .setTitle("提示")
                    .setMessage("没有可加入管控的应用")
                    .setPositiveButton("确定", null)
                    .show();
            return;
        }

        final Set<String> staged = pickerStaged;
        final int[] page = {Math.max(1, Math.min(100, pickerPage))};
        final int pageSize = 50;
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(16), dp(6), dp(16), dp(4));
        EditText search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("搜索应用名称或包名");
        search.setText(pickerQuery);
        content.addView(search, new LinearLayout.LayoutParams(-1, -2));
        TextView count = new TextView(this);
        count.setTextColor(0xff687681);
        count.setTextSize(12);
        content.addView(count);
        ScrollView scroll = new ScrollView(this);
        pickerScroll = scroll;
        LinearLayout rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(rows);
        content.addView(scroll, new LinearLayout.LayoutParams(-1, dp(360)));
        Button more = new Button(this);
        more.setAllCaps(false);
        more.setText("加载更多");
        content.addView(more);

        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("选择要加入管控的应用（可多选）")
                .setView(content)
                .setPositiveButton("确定加入", null)
                .setNegativeButton("取消", null)
                .create();

        final Runnable[] render = new Runnable[1];
        render[0] = () -> {
            rows.removeAllViews();
            String filter = search.getText() == null ? ""
                    : search.getText().toString().trim().toLowerCase(Locale.ROOT);
            List<AppItem> filtered = new ArrayList<>();
            for (AppItem item : candidates) {
                if (filter.isEmpty()
                        || item.packageName.toLowerCase(Locale.ROOT).contains(filter)
                        || item.label.toLowerCase(Locale.ROOT).contains(filter)) {
                    filtered.add(item);
                }
            }
            int limit = Math.min(filtered.size(), page[0] * pageSize);
            for (int i = 0; i < limit; i++) {
                AppItem item = filtered.get(i);
                CheckBox check = new CheckBox(this);
                check.setText(item.label + "\n" + item.packageName);
                check.setTextSize(13);
                check.setChecked(staged.contains(item.packageName));
                check.setOnCheckedChangeListener((button, checked) -> {
                    if (checked && !staged.contains(item.packageName)) {
                        if (staged.size() >= MAX_PICKER_STAGED) {
                            button.setChecked(false);
                            Toast.makeText(this, "单次最多选择 " + MAX_PICKER_STAGED
                                    + " 个应用，已保留当前选择。", Toast.LENGTH_LONG).show();
                            return;
                        }
                        staged.add(item.packageName);
                    } else if (!checked) {
                        staged.remove(item.packageName);
                    }
                    count.setText("匹配 " + filtered.size() + " 个，已选择 "
                            + staged.size() + " / " + MAX_PICKER_STAGED + " 个");
                });
                rows.addView(check, new LinearLayout.LayoutParams(-1, -2));
            }
            count.setText("匹配 " + filtered.size() + " 个，已选择 " + staged.size()
                    + " / " + MAX_PICKER_STAGED + " 个");
            more.setVisibility(filtered.size() > limit ? View.VISIBLE : View.GONE);
            more.setText("加载更多（剩余 " + Math.max(0, filtered.size() - limit) + " 个）");
        };
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence value, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence value, int start, int before, int count) {
                page[0] = 1;
                pickerPage = 1;
                pickerQuery = value == null ? "" : value.toString();
                render[0].run();
            }
            @Override public void afterTextChanged(Editable value) { }
        });
        more.setOnClickListener(v -> {
            page[0] = Math.min(100, page[0] + 1);
            pickerPage = page[0];
            render[0].run();
        });
        dialog.setOnShowListener(ignored -> dialog.getButton(DialogInterface.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    currentBlacklist.addAll(staged);
                    if (!saveBlacklist()) {
                        currentBlacklist.removeAll(staged);
                        return;
                    }
                    blacklistPage = 1;
                    refreshBlacklistUI();
                    dialog.dismiss();
                }));
        render[0].run();
        if (restoring) {
            final int restorePickerY = pickerScrollY;
            scroll.post(() -> scroll.scrollTo(0, restorePickerY));
        }
        dialog.setOnDismissListener(ignored -> {
            pickerScroll = null;
            if (!isChangingConfigurations()) {
                pickerDialogOpen = false;
                pickerQuery = "";
                pickerPage = 1;
                pickerScrollY = 0;
                pickerStaged.clear();
            }
        });
        dialog.show();
    }

    /** "我都很信任" — 清空所有管控 */
    private void trustAll() {
        if (blacklistDataCorrupt) {
            Toast.makeText(this, "原管控名单数据异常，已禁止清空，避免覆盖旧配置。", Toast.LENGTH_LONG).show();
            return;
        }
        if (currentBlacklist.isEmpty()) {
            new AlertDialog.Builder(this)
                    .setTitle("提示")
                    .setMessage("当前没有管控应用")
                    .setPositiveButton("确定", null)
                    .show();
            return;
        }

        new AlertDialog.Builder(this)
                .setTitle("确认清空")
                .setMessage("确定要清空所有管控吗？\n所有应用将不再触发管控提醒。")
                .setPositiveButton("确定清空", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        Set<String> previous = new HashSet<>(currentBlacklist);
                        currentBlacklist.clear();
                        if (!saveBlacklist()) {
                            currentBlacklist.addAll(previous);
                            refreshBlacklistUI();
                            return;
                        }
                        blacklistPage = 1;
                        refreshBlacklistUI();
                    }
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void refreshBlacklistUI() {
        blacklistContainer.removeAllViews();
        if (blacklistDataWarningView != null) {
            blacklistDataWarningView.setText(blacklistDataWarning);
            blacklistDataWarningView.setVisibility(blacklistDataWarning.isEmpty() ? View.GONE : View.VISIBLE);
        }
        if (trustAllBtn != null) trustAllBtn.setEnabled(!blacklistDataCorrupt);

        if (trustAllBtn != null) {
            trustAllBtn.setText("我都很信任" + (currentBlacklist.isEmpty()
                    ? "" : "（清空" + currentBlacklist.size() + "个管控）"));
        }

        List<AppItem> blacklisted = new ArrayList<>();
        for (String pkg : currentBlacklist) {
            AppItem found = appByPackage.get(pkg);
            if (found == null) {
                try {
                    ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
                    if (isSystemApp(info)) continue;
                    AppItem item = new AppItem();
                    item.packageName = pkg;
                    item.label = String.valueOf(info.loadLabel(pm));
                    found = item;
                    appByPackage.put(pkg, item);
                } catch (Throwable ignored) {
                    // Keep the saved package token; the app may be temporarily unavailable.
                    AppItem item = new AppItem();
                    item.packageName = pkg;
                    item.label = pkg;
                    found = item;
                }
            }
            blacklisted.add(found);
        }
        Collections.sort(blacklisted, Comparator.comparing(item ->
                item.label == null ? item.packageName : item.label, String.CASE_INSENSITIVE_ORDER));

        if (blacklisted.isEmpty()) {
            blacklistPage = 1;
            blacklistContainer.setVisibility(View.GONE);
            return;
        }

        blacklistContainer.setVisibility(View.VISIBLE);
        TextView listTitle = new TextView(this);
        listTitle.setText("已加入管控 (" + blacklisted.size() + ")");
        listTitle.setTextColor(0xff333333);
        listTitle.setTextSize(16);
        listTitle.setTypeface(null, Typeface.BOLD);
        listTitle.setPadding(0, dp(12), 0, dp(12));
        blacklistContainer.addView(listTitle);

        int limit = Math.min(blacklisted.size(), Math.max(1, blacklistPage) * BLACKLIST_PAGE_SIZE);
        for (int i = 0; i < limit; i++) {
            blacklistContainer.addView(buildBlacklistRow(blacklisted.get(i)));
        }
        if (limit < blacklisted.size()) {
            TextView more = new TextView(this);
            more.setText("加载更多（剩余 " + (blacklisted.size() - limit) + " 个）");
            more.setTextColor(0xff1565c0);
            more.setTextSize(14);
            more.setGravity(Gravity.CENTER);
            more.setPadding(dp(12), dp(14), dp(12), dp(14));
            more.setOnClickListener(v -> {
                blacklistPage++;
                refreshBlacklistUI();
            });
            blacklistContainer.addView(more);
        }
    }

    private View buildBlacklistRow(final AppItem item) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackgroundColor(Color.WHITE);
        GradientDrawable rowBg = new GradientDrawable();
        rowBg.setShape(GradientDrawable.RECTANGLE);
        rowBg.setCornerRadius(dp(12));
        rowBg.setColor(Color.WHITE);
        rowBg.setStroke(dp(1), 0xFFE53935);
        row.setBackground(rowBg);

        TextView avatar = new TextView(this);
        String letter = item.label.isEmpty() ? "?" : item.label.substring(0, 1).toUpperCase();
        avatar.setText(letter);
        avatar.setTextColor(Color.WHITE);
        avatar.setTextSize(15);
        avatar.setTypeface(null, Typeface.BOLD);
        avatar.setGravity(Gravity.CENTER);
        GradientDrawable avatarBg = new GradientDrawable();
        avatarBg.setShape(GradientDrawable.OVAL);
        int c = avatarColor(Math.abs(item.packageName.hashCode()) % 8);
        avatarBg.setColor(c);
        int size = dp(38);
        avatar.setBackground(avatarBg);
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(size, size);
        ap.rightMargin = dp(12);
        avatar.setLayoutParams(ap);
        row.addView(avatar);

        LinearLayout textCol = new LinearLayout(this);
        textCol.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        textCol.setLayoutParams(tp);

        TextView nameTv = new TextView(this);
        nameTv.setText(item.label);
        nameTv.setTextColor(0xFF222222);
        nameTv.setTextSize(14);
        nameTv.setSingleLine(true);
        textCol.addView(nameTv);

        TextView pkgTv = new TextView(this);
        pkgTv.setText(item.packageName);
        pkgTv.setTextColor(0xFFAAAAAA);
        pkgTv.setTextSize(11);
        pkgTv.setSingleLine(true);
        textCol.addView(pkgTv);

        row.addView(textCol);

        // 移除按钮
        Button removeBtn = new Button(this);
        removeBtn.setText("移出");
        removeBtn.setTextColor(0xFF2E7D32);
        removeBtn.setTextSize(13);
        GradientDrawable rbBg = new GradientDrawable();
        rbBg.setShape(GradientDrawable.RECTANGLE);
        rbBg.setCornerRadius(dp(16));
        rbBg.setColor(0xFFE8F5E9);
        removeBtn.setBackground(rbBg);
        removeBtn.setPadding(dp(14), dp(6), dp(14), dp(6));
        removeBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (!currentBlacklist.remove(item.packageName)) return;
                if (!saveBlacklist()) {
                    currentBlacklist.add(item.packageName);
                    return;
                }
                blacklistPage = 1;
                refreshBlacklistUI();
            }
        });
        row.addView(removeBtn);

        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rp.bottomMargin = dp(8);
        row.setLayoutParams(rp);

        return row;
    }

    @Override
    protected void onDestroy() {
        activityDestroyed = true;
        appLoadGeneration.incrementAndGet();
        appLoader.shutdownNow();
        super.onDestroy();
    }

    private int avatarColor(int idx) {
        int[] colors = {
                0xFFD32F2F, 0xFFC62828, 0xFFB71C1C, 0xFFE53935,
                0xFF6A1B9A, 0xFFE65100, 0xFF4E342E, 0xFF37474F
        };
        return colors[idx];
    }
}
