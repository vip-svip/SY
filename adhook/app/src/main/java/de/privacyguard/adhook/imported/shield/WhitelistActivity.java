package de.privacyguard.adhook.imported.shield;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 白名单管理（2026-10-30 重做）。
 *
 * 需求：
 *   · 去掉所有内置/自动加入的信任应用；
 *   · 已加入列表支持搜索；
 *   · 加入应用的选择器支持搜索、全选/取消全选；
 *   · 页面改为卡片式，减少「一层套一层」的旧样式。
 */
public class WhitelistActivity extends de.privacyguard.adhook.FxNativeTabActivity {

    /** 2026-10-30：按用户要求清空内置信任应用。 */
    public static final Set<String> DEFAULT_TRUSTED_PKGS = Collections.emptySet();

    private static final int COLOR_BG = 0xFFF4F6FB;
    private static final int COLOR_PRIMARY = 0xFF1565C0;
    private static final int COLOR_PRIMARY_DARK = 0xFF0B3D91;
    private static final int COLOR_TEXT = 0xFF172033;
    private static final int COLOR_SUB = 0xFF7B8499;
    private static final int COLOR_LINE = 0xFFE6EAF2;

    private PackageManager pm;
    private SharedPreferences prefs;
    private final Set<String> currentWhitelist = new HashSet<>();
    /** 只缓存白名单里的应用名/图标，绝不为整个应用列表加载。 */
    private final Map<String, String> labelCache = new HashMap<>();
    private final Map<String, Drawable> iconCache = new HashMap<>();

    private LinearLayout whitelistContainer;
    private LinearLayout emptyHint;
    private TextView emptyTitle;
    private TextView emptySub;
    private TextView countText;
    private TextView sectionTitle;
    private String whitelistDataWarning = "";
    private boolean whitelistDataCorrupt;
    private EditText searchInput;
    private ScrollView whitelistScroll;
    private String query = "";
    private int whitelistPage = 1;
    private static final int WHITELIST_PAGE_SIZE = 50;
    private static final String STATE_QUERY = "fx_shield_whitelist_query";
    private static final String STATE_PAGE = "fx_shield_whitelist_page";
    private static final String STATE_SCROLL_Y = "fx_shield_whitelist_scroll_y";

    private final ThreadPoolExecutor labelWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-shield-whitelist-labels"),
            new ThreadPoolExecutor.DiscardOldestPolicy());
    private final AtomicLong labelLoadGeneration = new AtomicLong();
    private volatile boolean activityDestroyed;

    private static class AppItem {
        String packageName;
        String label;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        pm = getPackageManager();
        prefs = getSharedPreferences("shield_prefs", MODE_PRIVATE);
        loadWhitelist();

        getWindow().setStatusBarColor(COLOR_PRIMARY_DARK);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(COLOR_BG);
        root.setFitsSystemWindows(true);

        root.addView(buildHeader());
        root.addView(buildContent());

        setContentViewWithNativeTabs(root, 5);
        if (savedInstanceState != null) {
            query = savedInstanceState.getString(STATE_QUERY, "");
            searchInput.setText(query);
            whitelistPage = Math.max(1, Math.min(200, savedInstanceState.getInt(STATE_PAGE, 1)));
            final int restoreY = Math.max(0, savedInstanceState.getInt(STATE_SCROLL_Y, 0));
            whitelistScroll.post(() -> whitelistScroll.scrollTo(0, restoreY));
        }

        refreshWhitelistUI();
        loadLabelsAsync();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putString(STATE_QUERY, searchInput == null ? query : searchInput.getText().toString());
        outState.putInt(STATE_PAGE, Math.max(1, Math.min(200, whitelistPage)));
        if (whitelistScroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, whitelistScroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 从全屏选择页返回后只刷新白名单本身；不再重新扫描全部应用。
        if (pm != null) {
            loadWhitelist();
            refreshWhitelistUI();
            loadLabelsAsync();
        }
    }

    /** 后台只加载白名单内的应用名称；数量很小，不进主线程。 */
    private void loadLabelsAsync() {
        final List<String> pkgs = new ArrayList<>(currentWhitelist);
        final long generation = labelLoadGeneration.incrementAndGet();
        if (pkgs.isEmpty()) {
            labelCache.clear();
            iconCache.clear();
            return;
        }
        try {
            labelWorker.execute(() -> {
                final Map<String, String> loadedLabels = new HashMap<>();
                final Map<String, Drawable> loadedIcons = new HashMap<>();
                for (String pkg : pkgs) {
                    if (Thread.currentThread().isInterrupted()
                            || generation != labelLoadGeneration.get()) return;
                    try {
                        ApplicationInfo ai = pm.getApplicationInfo(pkg, 0);
                        loadedLabels.put(pkg, ai.loadLabel(pm).toString());
                        try {
                            loadedIcons.put(pkg, ai.loadIcon(pm));
                        } catch (Throwable ignored) {
                        }
                    } catch (Throwable ignored) {
                    }
                }
                runOnUiThread(() -> {
                    if (activityDestroyed || isFinishing() || isDestroyed()
                            || generation != labelLoadGeneration.get()) return;
                    labelCache.clear();
                    labelCache.putAll(loadedLabels);
                    iconCache.clear();
                    iconCache.putAll(loadedIcons);
                    refreshWhitelistUI();
                });
            });
        } catch (RejectedExecutionException ignored) {
            // The page is closing or its one-slot refresh queue is being replaced.
        }
    }

    @Override
    protected void onDestroy() {
        activityDestroyed = true;
        labelLoadGeneration.incrementAndGet();
        labelWorker.shutdownNow();
        super.onDestroy();
    }

    // ============================================================
    // 顶栏
    // ============================================================
    private View buildHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(18), dp(12) + getStatusBarHeight(), dp(18), dp(14));

        GradientDrawable bg = new GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                new int[]{COLOR_PRIMARY, COLOR_PRIMARY}
        );
        header.setBackground(bg);

        TextView back = new TextView(this);
        back.setText("\u2190");
        back.setTextColor(Color.WHITE);
        back.setTextSize(23);
        back.setGravity(Gravity.CENTER);
        back.setPadding(0, 0, dp(14), 0);
        back.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                finish();
            }
        });
        header.addView(back);

        LinearLayout titleCol = new LinearLayout(this);
        titleCol.setOrientation(LinearLayout.VERTICAL);
        titleCol.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        TextView title = new TextView(this);
        title.setText("白名单管理");
        title.setTextColor(Color.WHITE);
        title.setTextSize(20);
        title.setTypeface(null, Typeface.BOLD);
        titleCol.addView(title);

        TextView sub = new TextView(this);
        sub.setText("不对这些应用触发管控名单提醒");
        sub.setTextColor(0xCCFFFFFF);
        sub.setTextSize(12);
        sub.setPadding(0, dp(2), 0, 0);
        titleCol.addView(sub);
        header.addView(titleCol);

        TextView add = new TextView(this);
        add.setText("＋ 添加");
        add.setTextColor(Color.WHITE);
        add.setTextSize(14);
        add.setTypeface(null, Typeface.BOLD);
        add.setGravity(Gravity.CENTER);
        add.setPadding(dp(16), dp(9), dp(16), dp(9));
        GradientDrawable addBg = new GradientDrawable();
        addBg.setShape(GradientDrawable.RECTANGLE);
        addBg.setCornerRadius(dp(22));
        addBg.setColor(0x33FFFFFF);
        addBg.setStroke(dp(1), 0x66FFFFFF);
        add.setBackground(addBg);
        add.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showAppPicker();
            }
        });
        header.addView(add);

        return header;
    }

    // ============================================================
    // 内容
    // ============================================================
    private View buildContent() {
        whitelistScroll = new ScrollView(this);
        whitelistScroll.setFillViewport(true);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(18), dp(16), dp(18), dp(28));

        // 概览卡片
        LinearLayout summary = new LinearLayout(this);
        summary.setOrientation(LinearLayout.VERTICAL);
        summary.setPadding(dp(18), dp(16), dp(18), dp(16));
        summary.setBackground(roundRect(Color.WHITE, 18, COLOR_LINE, 1));
        summary.setElevation(dp(1));

        LinearLayout summaryTop = new LinearLayout(this);
        summaryTop.setOrientation(LinearLayout.HORIZONTAL);
        summaryTop.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout countCol = new LinearLayout(this);
        countCol.setOrientation(LinearLayout.VERTICAL);
        countCol.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        countText = new TextView(this);
        countText.setText("0");
        countText.setTextColor(COLOR_PRIMARY);
        countText.setTextSize(24);
        countText.setTypeface(null, Typeface.BOLD);
        countCol.addView(countText);

        TextView countLabel = new TextView(this);
        countLabel.setText("个应用已加入白名单");
        countLabel.setTextColor(COLOR_TEXT);
        countLabel.setTextSize(14);
        countCol.addView(countLabel);
        summaryTop.addView(countCol);
        summary.addView(summaryTop);

        TextView summaryDesc = new TextView(this);
        summaryDesc.setText("白名单内的应用不会被拦截、冻结或终结");
        summaryDesc.setTextColor(COLOR_SUB);
        summaryDesc.setTextSize(12);
        summaryDesc.setPadding(0, dp(9), 0, 0);
        summary.addView(summaryDesc);
        content.addView(summary);

        // 搜索框
        searchInput = new EditText(this);
        searchInput.setHint("搜索已加入的应用名称或包名");
        searchInput.setHintTextColor(0xFFA8B0C2);
        searchInput.setTextColor(COLOR_TEXT);
        searchInput.setTextSize(14);
        searchInput.setSingleLine(true);
        searchInput.setPadding(dp(16), dp(12), dp(16), dp(12));
        searchInput.setBackground(roundRect(Color.WHITE, 14, COLOR_LINE, 1));
        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                query = s == null ? "" : s.toString().trim();
                whitelistPage = 1;
                refreshWhitelistUI();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        LinearLayout.LayoutParams searchLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        searchLp.topMargin = dp(14);
        searchInput.setLayoutParams(searchLp);
        content.addView(searchInput);

        // 列表区标题
        LinearLayout sectionHeader = new LinearLayout(this);
        sectionHeader.setOrientation(LinearLayout.HORIZONTAL);
        sectionHeader.setGravity(Gravity.CENTER_VERTICAL);
        sectionHeader.setPadding(dp(2), dp(20), dp(2), dp(8));

        sectionTitle = new TextView(this);
        sectionTitle.setText("已加入白名单");
        sectionTitle.setTextColor(COLOR_TEXT);
        sectionTitle.setTextSize(15);
        sectionTitle.setTypeface(null, Typeface.BOLD);
        sectionTitle.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        sectionHeader.addView(sectionTitle);

        TextView tip = new TextView(this);
        tip.setText("点击右侧可移除");
        tip.setTextColor(COLOR_SUB);
        tip.setTextSize(11);
        sectionHeader.addView(tip);
        content.addView(sectionHeader);

        // 空状态
        emptyHint = new LinearLayout(this);
        emptyHint.setOrientation(LinearLayout.VERTICAL);
        emptyHint.setGravity(Gravity.CENTER);
        emptyHint.setPadding(dp(20), dp(44), dp(20), dp(44));
        emptyHint.setBackground(roundRect(Color.WHITE, 18, COLOR_LINE, 1));

        TextView emptyIcon = new TextView(this);
        emptyIcon.setText("—");
        emptyIcon.setTextColor(COLOR_SUB);
        emptyIcon.setTextSize(22);
        emptyIcon.setGravity(Gravity.CENTER);
        emptyHint.addView(emptyIcon);

        emptyTitle = new TextView(this);
        emptyTitle.setText("还没有加入白名单应用");
        emptyTitle.setTextColor(COLOR_TEXT);
        emptyTitle.setTextSize(15);
        emptyTitle.setTypeface(null, Typeface.BOLD);
        emptyTitle.setGravity(Gravity.CENTER);
        emptyTitle.setPadding(0, dp(10), 0, 0);
        emptyHint.addView(emptyTitle);

        emptySub = new TextView(this);
        emptySub.setText("点击右上角「添加」，可搜索并多选应用");
        emptySub.setTextColor(COLOR_SUB);
        emptySub.setTextSize(12);
        emptySub.setGravity(Gravity.CENTER);
        emptySub.setPadding(0, dp(6), 0, 0);
        emptyHint.addView(emptySub);
        content.addView(emptyHint);

        // 白名单列表
        whitelistContainer = new LinearLayout(this);
        whitelistContainer.setOrientation(LinearLayout.VERTICAL);
        content.addView(whitelistContainer);

        whitelistScroll.addView(content);
        return whitelistScroll;
    }

    private int getStatusBarHeight() {
        int id = getResources().getIdentifier("status_bar_height", "dimen", "android");
        return id > 0 ? getResources().getDimensionPixelSize(id) : 0;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private GradientDrawable roundRect(int color, int radiusDp, int strokeColor, int strokeDp) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(dp(radiusDp));
        d.setColor(color);
        if (strokeDp > 0) d.setStroke(dp(strokeDp), strokeColor);
        return d;
    }

    // ============================================================
    // 数据
    // ============================================================
    private void loadWhitelist() {
        currentWhitelist.clear();
        // 系统应用不自动进入用户白名单。统一使用扫描侧同一解析器，
        // 避免 UI 展示的信任集合与风险扫描实际使用的集合不一致。
        String raw = prefs.getString("whitelist_pkgs", "");
        if (raw == null) raw = "";
        whitelistDataCorrupt = !raw.isEmpty() && !FxYulongWhitelistPolicy.isWellFormed(raw);
        Set<String> parsed = FxYulongWhitelistPolicy.parse(raw);
        whitelistDataWarning = whitelistDataCorrupt
                ? "原白名单格式异常或超过安全上限；为避免覆盖旧配置，当前禁止修改。"
                : "";
        boolean removedSystem = false;
        for (String packageName : parsed) {
            if (isSystemPackage(packageName)) {
                removedSystem = true;
                continue;
            }
            currentWhitelist.add(packageName);
        }
        if (removedSystem && !saveWhitelist()) {
            whitelistDataWarning = "系统应用条目已从当前显示中过滤，但本地白名单写入失败。";
        }
    }

    /** 是否是系统应用；系统应用不进入用户白名单。 */
    private boolean isSystemPackage(String pkg) {
        if (pkg == null || pkg.isEmpty() || pm == null) return false;
        try {
            ApplicationInfo ai = pm.getApplicationInfo(pkg, 0);
            return (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private boolean saveWhitelist() {
        if (whitelistDataCorrupt) {
            Toast.makeText(this, "原白名单数据异常，已阻止覆盖。请先核实并修复原始白名单数据。", Toast.LENGTH_LONG).show();
            return false;
        }
        String serialized = FxYulongWhitelistPolicy.serialize(currentWhitelist);
        if (serialized == null) {
            Toast.makeText(this, "白名单超过 " + FxYulongWhitelistPolicy.MAX_ENTRIES
                    + " 个应用或 " + FxYulongWhitelistPolicy.MAX_RAW_CHARS
                    + " 个字符，未保存任何部分数据。", Toast.LENGTH_LONG).show();
            return false;
        }
        boolean saved = prefs.edit().putString("whitelist_pkgs", serialized).commit();
        if (!saved) {
            Toast.makeText(this, "白名单保存失败，原有配置保持不变。", Toast.LENGTH_LONG).show();
            return false;
        }
        whitelistDataWarning = "";
        return true;
    }

    // ============================================================
    // 已加入列表
    // ============================================================
    private void refreshWhitelistUI() {
        View focused = getCurrentFocus();
        whitelistContainer.removeAllViews();

        List<AppItem> all = new ArrayList<>();
        for (String pkg : currentWhitelist) {
            AppItem item = new AppItem();
            item.packageName = pkg;
            String cached = labelCache.get(pkg);
            item.label = cached != null ? cached : pkg;
            all.add(item);
        }
        Collections.sort(all, new Comparator<AppItem>() {
            @Override
            public int compare(AppItem a, AppItem b) {
                return a.label.compareToIgnoreCase(b.label);
            }
        });

        List<AppItem> visible = new ArrayList<>();
        String q = query.toLowerCase(Locale.getDefault());
        for (AppItem a : all) {
            if (q.isEmpty()
                    || a.label.toLowerCase(Locale.getDefault()).contains(q)
                    || a.packageName.toLowerCase(Locale.getDefault()).contains(q)) {
                visible.add(a);
            }
        }

        countText.setText(currentWhitelist.size()
                + (whitelistDataWarning.isEmpty() ? "" : "\\n" + whitelistDataWarning));
        sectionTitle.setText("已加入白名单 (" + currentWhitelist.size() + ")");

        int maxPages = Math.max(1, (visible.size() + WHITELIST_PAGE_SIZE - 1) / WHITELIST_PAGE_SIZE);
        whitelistPage = Math.max(1, Math.min(whitelistPage, maxPages));
        int visibleLimit = Math.min(visible.size(), whitelistPage * WHITELIST_PAGE_SIZE);

        if (visible.isEmpty()) {
            emptyHint.setVisibility(View.VISIBLE);
            whitelistContainer.setVisibility(View.GONE);
            if (currentWhitelist.isEmpty() && !whitelistDataWarning.isEmpty()) {
                emptyTitle.setText("原白名单数据未能安全读取");
                emptySub.setText(whitelistDataWarning + " 请重新选择应用创建有效白名单。");
            } else if (currentWhitelist.isEmpty()) {
                emptyTitle.setText("还没有加入白名单应用");
                emptySub.setText("点击右上角「添加」，可搜索并多选应用");
            } else {
                emptyTitle.setText("没有匹配的应用");
                emptySub.setText("换个关键词试试");
            }
        } else {
            emptyHint.setVisibility(View.GONE);
            whitelistContainer.setVisibility(View.VISIBLE);
            for (int i = 0; i < visibleLimit; i++) {
                whitelistContainer.addView(buildWhitelistRow(visible.get(i)));
            }
            if (visibleLimit < visible.size()) {
                TextView more = new TextView(this);
                more.setText("加载更多（已显示 " + visibleLimit + " / " + visible.size() + "）");
                more.setTextColor(COLOR_PRIMARY);
                more.setTextSize(14);
                more.setGravity(Gravity.CENTER);
                more.setPadding(dp(12), dp(14), dp(12), dp(14));
                more.setOnClickListener(v -> {
                    int restoreY = whitelistScroll == null ? 0 : whitelistScroll.getScrollY();
                    whitelistPage = Math.min(maxPages, whitelistPage + 1);
                    refreshWhitelistUI();
                    if (whitelistScroll != null) {
                        whitelistScroll.post(() -> whitelistScroll.scrollTo(0, restoreY));
                    }
                });
                whitelistContainer.addView(more);
            }
        }

        if (focused == searchInput) {
            searchInput.requestFocus();
        }
    }

    private View buildWhitelistRow(final AppItem item) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackground(roundRect(Color.WHITE, 16, COLOR_LINE, 1));
        row.setElevation(dp(1));
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rp.bottomMargin = dp(9);
        row.setLayoutParams(rp);

        FrameLayout iconWrap = new FrameLayout(this);
        int avatarSize = dp(42);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(avatarSize, avatarSize);
        ip.rightMargin = dp(12);
        iconWrap.setLayoutParams(ip);

        TextView avatar = new TextView(this);
        String letter = item.label == null || item.label.isEmpty()
                ? "?" : item.label.substring(0, 1).toUpperCase(Locale.getDefault());
        avatar.setText(letter);
        avatar.setTextColor(Color.WHITE);
        avatar.setTextSize(16);
        avatar.setTypeface(null, Typeface.BOLD);
        avatar.setGravity(Gravity.CENTER);
        GradientDrawable avatarBg = new GradientDrawable();
        avatarBg.setShape(GradientDrawable.OVAL);
        avatarBg.setColor(avatarColor(Math.abs(item.packageName.hashCode()) % 8));
        avatar.setBackground(avatarBg);
        iconWrap.addView(avatar, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        ImageView icon = new ImageView(this);
        icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        icon.setVisibility(View.GONE);
        iconWrap.addView(icon, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        Drawable cachedIcon = iconCache.get(item.packageName);
        if (cachedIcon != null) {
            icon.setImageDrawable(cachedIcon);
            icon.setVisibility(View.VISIBLE);
            avatar.setVisibility(View.GONE);
        }
        row.addView(iconWrap);

        LinearLayout textCol = new LinearLayout(this);
        textCol.setOrientation(LinearLayout.VERTICAL);
        textCol.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        TextView name = new TextView(this);
        name.setText(item.label);
        name.setTextColor(COLOR_TEXT);
        name.setTextSize(15);
        name.setTypeface(null, Typeface.BOLD);
        name.setSingleLine(true);
        textCol.addView(name);

        TextView pkg = new TextView(this);
        pkg.setText(item.packageName);
        pkg.setTextColor(COLOR_SUB);
        pkg.setTextSize(11);
        pkg.setSingleLine(true);
        pkg.setPadding(0, dp(2), 0, 0);
        textCol.addView(pkg);
        row.addView(textCol);

        TextView remove = new TextView(this);
        remove.setText("移除");
        remove.setTextColor(0xFFE53935);
        remove.setTextSize(12);
        remove.setTypeface(null, Typeface.BOLD);
        remove.setGravity(Gravity.CENTER);
        remove.setPadding(dp(14), dp(8), dp(14), dp(8));
        GradientDrawable removeBg = new GradientDrawable();
        removeBg.setShape(GradientDrawable.RECTANGLE);
        removeBg.setCornerRadius(dp(18));
        removeBg.setColor(0xFFFFEBEE);
        remove.setBackground(removeBg);
        remove.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (!currentWhitelist.remove(item.packageName)) return;
                if (!saveWhitelist()) {
                    currentWhitelist.add(item.packageName);
                    return;
                }
                refreshWhitelistUI();
            }
        });
        row.addView(remove);

        return row;
    }

    // ============================================================
    // 应用选择器：搜索 + 全选
    // ============================================================
    /** 2026-10-30：改为全屏选择页，不再使用难看的弹窗。 */
    private void showAppPicker() {
        startActivity(new android.content.Intent(this, WhitelistPickerActivity.class));
    }


    private int avatarColor(int idx) {
        int[] colors = {
                0xFF1565C0, 0xFF2E7D32, 0xFFC62828, 0xFF6A1B9A,
                0xFFE65100, 0xFF00838F, 0xFF4E342E, 0xFF37474F
        };
        return colors[idx];
    }
}
