package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.TimePickerDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.TrafficStats;
import android.net.Uri;
import android.os.Build;
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

import de.privacyguard.adhook.RootAccess;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Native Yulong 7.0.1 per-app firewall UI; separate from FX's per-app VPN route. */
public final class FxYulongFirewallActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int APP_PAGE_SIZE = 50;
    private static final String STATE_APP_PAGE = "fx_firewall_app_page";
    private static final String STATE_QUERY = "fx_firewall_query";
    private static final String STATE_SCROLL_Y = "fx_firewall_scroll_y";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> new Thread(r, "fx-yulong-firewall-root"), new ThreadPoolExecutor.AbortPolicy());
    private final ThreadPoolExecutor appWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-yulong-firewall-apps"), new ThreadPoolExecutor.AbortPolicy());
    private int appPage = 1;
    private volatile boolean destroyed;
    private LinearLayout rows;
    private TextView status;
    private Switch master;
    private EditText query;
    private ScrollView scroll;
    private int pendingScrollY;
    private boolean pendingScrollRestore;
    private int scrollRestoreGeneration;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> labels = new HashMap<>();
    private static final class FirewallRule {
        boolean enabled;
        boolean blockWifi = true;
        boolean blockMobile = true;
        boolean scheduleEnabled;
        String startTime = "22:00";
        String endTime = "06:00";
        FirewallRule copy() {
            FirewallRule value = new FirewallRule();
            value.enabled = enabled; value.blockWifi = blockWifi;
            value.blockMobile = blockMobile; value.scheduleEnabled = scheduleEnabled;
            value.startTime = startTime; value.endTime = endTime;
            return value;
        }
    }
    private final Map<String, FirewallRule> rules = new HashMap<>();
    private boolean loading = true;
    private boolean appsLoaded;
    // A retained package snapshot is display-only until Root and PackageManager refresh both succeed.
    private boolean inventoryReady;
    private boolean refreshAfterLoad;
    private boolean packageChangeReceiverRegistered;
    private boolean suppressMaster;
    private final BroadcastReceiver packageChangeReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            String action = intent.getAction();
            Uri data = intent.getData();
            String packageName = data == null ? null : data.getSchemeSpecificPart();
            if (packageName == null || packageName.isEmpty()
                    || packageName.equals(getPackageName()) || "android".equals(packageName)) return;
            boolean added = Intent.ACTION_PACKAGE_ADDED.equals(action);
            boolean removed = Intent.ACTION_PACKAGE_REMOVED.equals(action)
                    || Intent.ACTION_PACKAGE_FULLY_REMOVED.equals(action);
            boolean replaced = Intent.ACTION_PACKAGE_REPLACED.equals(action);
            if (!added && !removed && !replaced) return;
            // Android reports an app update as remove/add with EXTRA_REPLACING.
            // Wait for PACKAGE_REPLACED so the temporary uninstall is not shown.
            if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false) && (added || removed)) return;
            refreshPackageInventory();
        }
    };
    private String suitePage = "应用网络拦截";
    private int appFilterMode;

    private boolean hasEnabledRules() {
        for (FirewallRule rule : rules.values()) if (rule != null && rule.enabled) return true;
        return false;
    }
    private static boolean validTime(String value) {
        return value != null && value.matches("(?:[01][0-9]|2[0-3]):[0-5][0-9]");
    }
    private static String formatTime(int hour, int minute) {
        return String.format(Locale.ROOT, "%02d:%02d", hour, minute);
    }
    private static int[] parseTime(String value) {
        if (!validTime(value)) return new int[]{22, 0};
        String[] parts = value.split(":", -1);
        return new int[]{Integer.parseInt(parts[0]), Integer.parseInt(parts[1])};
    }
    private FirewallRule ruleFor(String packageName) {
        FirewallRule rule = rules.get(packageName);
        if (rule == null) { rule = new FirewallRule(); rules.put(packageName, rule); }
        return rule;
    }
    private void persistRule(String packageName, int uid, FirewallRule draft,
                             java.util.function.Consumer<Boolean> completion) {
        if (!inventoryReady) {
            status.setText("应用列表尚未成功刷新，暂不允许修改防火墙规则。");
            if (completion != null) completion.accept(false);
            return;
        }
        String command = "rule " + quote(packageName) + " " + uid
                + " " + (draft.enabled ? "1" : "0")
                + " " + (draft.blockWifi ? "1" : "0")
                + " " + (draft.blockMobile ? "1" : "0")
                + " " + (draft.scheduleEnabled ? "1" : "0")
                + " " + draft.startTime + " " + draft.endTime;
        runRoot(command, result -> {
            boolean ok = result.exitCode == 0;
            if (ok) { rules.put(packageName, draft.copy()); status.setText("已保存 " + packageName + " 的防火墙规则。"); }
            else status.setText("规则保存失败：" + safeOutput(result.output));
            if (completion != null) completion.accept(ok);
        });
    }
    private void showTimePicker(TextView target, String prefix, String current) {
        int[] time = parseTime(current);
        new TimePickerDialog(this, (picker, hour, minute) ->
                target.setText(prefix + " · " + formatTime(hour, minute)),
                time[0], time[1], true).show();
    }
    private void showRuleDialog(String packageName, int uid) {
        if (!inventoryReady) {
            status.setText("应用列表尚未成功刷新，暂不允许修改防火墙规则。");
            return;
        }
        FirewallRule draft = ruleFor(packageName).copy();
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL); panel.setPadding(dp(18), dp(8), dp(18), dp(8));
        Switch wifi = new Switch(this); wifi.setText("阻断 Wi-Fi 网络"); wifi.setChecked(draft.blockWifi);
        Switch mobile = new Switch(this); mobile.setText("阻断移动数据"); mobile.setChecked(draft.blockMobile);
        Switch schedule = new Switch(this); schedule.setText("启用每日时间计划"); schedule.setChecked(draft.scheduleEnabled);
        TextView start = text("每日开始 · " + draft.startTime, 14, 0xff17212b, false);
        TextView end = text("每日结束 · " + draft.endTime, 14, 0xff17212b, false);
        panel.addView(wifi); panel.addView(mobile); panel.addView(schedule);
        panel.addView(button("选择每日开始时间", () -> showTimePicker(start, "每日开始", draft.startTime)));
        panel.addView(start);
        panel.addView(button("选择每日结束时间", () -> showTimePicker(end, "每日结束", draft.endTime)));
        panel.addView(end);
        panel.addView(text("时间采用设备本地时间；开始和结束分钟均包含，支持跨午夜。两端相同表示仅该分钟生效。", 11, 0xff718091, false));
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("应用网络类型与每日计划")
                .setView(panel).setNegativeButton("取消", null).setPositiveButton("保存", null).create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> {
            draft.blockWifi = wifi.isChecked(); draft.blockMobile = mobile.isChecked();
            draft.scheduleEnabled = schedule.isChecked();
            String a = start.getText().toString(), b = end.getText().toString();
            draft.startTime = a.substring(a.lastIndexOf("·") + 1).trim();
            draft.endTime = b.substring(b.lastIndexOf("·") + 1).trim();
            if (!validTime(draft.startTime) || !validTime(draft.endTime)) {
                status.setText("时间格式无效，请重新选择。"); return;
            }
            dialog.dismiss();
            persistRule(packageName, uid, draft, ok -> { if (ok) renderRows(); });
        }));
        dialog.show();
    }
    private String ruleSummary(FirewallRule rule) {
        StringBuilder value = new StringBuilder(rule.enabled ? "已启用 · " : "未启用 · ");
        if (rule.blockWifi) value.append("Wi-Fi");
        if (rule.blockWifi && rule.blockMobile) value.append(" / ");
        if (rule.blockMobile) value.append("移动数据");
        if (!rule.blockWifi && !rule.blockMobile) value.append("未选网络类型");
        value.append(rule.scheduleEnabled ? " · 每日 " + rule.startTime + "–" + rule.endTime : " · 全天");
        return value.toString();
    }

    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private String scriptCommand(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-app-firewall.sh\" " + args;
    }
    private String quote(String s) {
        return "'" + (s == null ? "" : s.replace("'", "'\\''")) + "'";
    }
    private void runRoot(String args, java.util.function.Consumer<RootAccess.Result> callback) {
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(scriptCommand(args), 60000L, 1024 * 1024);
                runOnUiThread(() -> {
                    if (!destroyed && !isFinishing() && !isDestroyed()) callback.accept(result);
                });
            });
        } catch (RejectedExecutionException full) {
            // Queue saturation is a completed operation failure, not a fake
            // command-validation attempt. Do not call the Root process at all.
            RootAccess.Result rejected = RootAccess.failure(
                    75, "后台任务繁忙，本次防火墙操作未执行。");
            runOnUiThread(() -> {
                if (!destroyed && !isFinishing() && !isDestroyed()) {
                    status.setText("后台任务繁忙，本次防火墙操作未执行。");
                    callback.accept(rejected);
                }
            });
        }
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5)); return view;
    }
    private Button button(String value, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(value);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(String title, String detail, View... children) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(14), dp(10), dp(14), dp(10));
        card.setBackgroundColor(0xfff0f3f7);
        card.addView(text(title, 16, 0xff17212b, true));
        card.addView(text(detail, 12, 0xff617080, false));
        if (children != null) {
            for (View child : children) if (child != null) card.addView(child);
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5)); rows.addView(card, lp);
    }

    @Override protected void onResume() {
        super.onResume();
        registerPackageChangeReceiver();
        // Package broadcasts are not delivered while the Activity is paused.
        // Re-read the authoritative Root list when returning from another app.
        if (appsLoaded) refreshPackageInventory();
    }

    @Override protected void onPause() {
        unregisterPackageChangeReceiver();
        super.onPause();
    }

    private void registerPackageChangeReceiver() {
        if (packageChangeReceiverRegistered) return;
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);
        filter.addAction(Intent.ACTION_PACKAGE_REMOVED);
        filter.addAction(Intent.ACTION_PACKAGE_REPLACED);
        filter.addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED);
        filter.addDataScheme("package");
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(packageChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                registerReceiver(packageChangeReceiver, filter);
            }
            packageChangeReceiverRegistered = true;
        } catch (RuntimeException error) {
            // Returning to the Activity still reconciles packages in onResume.
            android.util.Log.w("FXYulongFirewall", "Package receiver registration failed", error);
        }
    }

    private void unregisterPackageChangeReceiver() {
        if (!packageChangeReceiverRegistered) return;
        packageChangeReceiverRegistered = false;
        try {
            unregisterReceiver(packageChangeReceiver);
        } catch (IllegalArgumentException alreadyDetached) {
            // Activity teardown may race a framework receiver detach.
        }
    }

    private void refreshPackageInventory() {
        if (destroyed || isFinishing() || isDestroyed()) return;
        if (loading) {
            refreshAfterLoad = true;
            return;
        }
        loading = true;
        inventoryReady = false;
        master.setEnabled(false);
        scrollRestoreGeneration++;
        if (scroll != null) {
            pendingScrollY = Math.max(0, scroll.getScrollY());
            pendingScrollRestore = true;
        }
        master.setEnabled(false);
        status.setText("检测到应用安装状态变化，正在刷新防火墙应用列表…");
        runRoot("list", result -> {
            if (result.exitCode != 0) {
                loading = false;
                master.setEnabled(false);
                status.setText("应用列表刷新失败，保留上次列表（只读）：" + safeOutput(result.output));
                return;
            }
            parseList(result.output);
            loadAppsAsync();
        });
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        String requestedPage = getIntent() == null ? null : getIntent().getStringExtra("suite_page");
        if ("用户应用".equals(requestedPage) || "系统应用".equals(requestedPage)
                || "按应用设置".equals(requestedPage) || "应用网络拦截".equals(requestedPage)) {
            suitePage = requestedPage;
        } else {
            suitePage = "应用网络拦截";
        }
        appFilterMode = "用户应用".equals(suitePage) ? 1 : "系统应用".equals(suitePage) ? 2 : 0;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL); header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Ad", this::finish));
        header.addView(text("FX Ad · " + suitePage, 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        scroll = new ScrollView(this); scroll.setFillViewport(true);
        rows = new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL);
        rows.setPadding(0, dp(4), 0, dp(20)); scroll.addView(rows);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 1);

        TextView intro = text("按应用 UID 分别限制 Wi-Fi 与移动数据，可为每个应用设置每日时间段。规则覆盖 IPv4/IPv6，并独立于 FX 分应用 VPN 路由；不启动第二个 VpnService。", 13, 0xff617080, false);
        card("防火墙说明", "系统级应用网络限制", intro);
        status = text("正在读取设备端防火墙设置…", 13, 0xff526170, false);
        card("当前状态", "Root 与 IPv4/IPv6 规则应用结果", status);
        master = new Switch(this); master.setText("启用已选择应用的网络拦截");
        master.setEnabled(false);
        card("防火墙总开关", "关闭时只移除 FX 自己的防火墙链，不修改其他应用规则。已启用但不在每日计划内的应用不会被阻断。", master);
        query = new EditText(this); query.setSingleLine(true); query.setHint("搜索应用名称或包名");
        query.setPadding(dp(14), dp(8), dp(14), dp(8));
        if (state != null) {
            appPage = Math.max(1, state.getInt(STATE_APP_PAGE, 1));
            query.setText(state.getString(STATE_QUERY, ""));
            pendingScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            pendingScrollRestore = true;
        }
        card("应用列表", "每个应用独立配置 Wi-Fi、移动数据与每日计划；UID 收发字节不是 DNS 查询次数。", query, button("刷新流量统计", this::renderRows));
        master.setOnCheckedChangeListener((button, checked) -> {
            if (loading || suppressMaster) return;
            if (checked && !hasEnabledRules()) {
                suppressMaster = true; master.setChecked(false); suppressMaster = false;
                status.setText("启用前至少选择一个应用。"); return;
            }
            master.setEnabled(false);
            runRoot("master " + (checked ? "1" : "0"), result -> {
                master.setEnabled(true);
                if (result.exitCode != 0) {
                    suppressMaster = true; master.setChecked(!checked); suppressMaster = false;
                    status.setText("防火墙未应用：" + safeOutput(result.output));
                } else {
                    getSharedPreferences("yulong_app_firewall", MODE_PRIVATE).edit()
                            .putBoolean("master_enabled", checked).apply();
                    status.setText(checked ? "应用网络拦截已启用。" : "应用网络拦截已关闭。");
                }
            });
        });
        query.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                appPage = 1;
                scrollRestoreGeneration++;
                pendingScrollY = 0;
                pendingScrollRestore = false;
                renderRows();
                if (scroll != null) scroll.scrollTo(0, 0);
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        runRoot("list", result -> {
            if (result.exitCode != 0) {
                loading = false; inventoryReady = false; master.setEnabled(false);
                status.setText("无法读取防火墙配置：" + safeOutput(result.output)); return;
            }
            parseList(result.output);
            loadAppsAsync();
        });
    }
    private String safeOutput(String value) {
        return value == null || value.trim().isEmpty() ? "请确认 FX Hook 已获得 Root 权限。" : value.trim();
    }
    private void parseList(String output) {
        rules.clear();
        boolean masterEnabled = false;
        for (String line : (output == null ? "" : output).split("\\r?\\n")) {
            if (line.startsWith("master=")) {
                masterEnabled = "1".equals(line.substring(7).trim());
                suppressMaster = true; master.setChecked(masterEnabled); suppressMaster = false;
                continue;
            }
            if (line.startsWith("FXYULONGFW")) continue;
            String[] p = line.split("\\|", -1);
            if (p.length < 3 || !p[0].contains(".") || !("0".equals(p[2]) || "1".equals(p[2]))) continue;
            FirewallRule rule = new FirewallRule();
            rule.enabled = "1".equals(p[2]);
            if (p.length == 8 && ("0".equals(p[3]) || "1".equals(p[3]))
                    && ("0".equals(p[4]) || "1".equals(p[4]))
                    && ("0".equals(p[5]) || "1".equals(p[5]))
                    && validTime(p[6]) && validTime(p[7])) {
                rule.blockWifi = "1".equals(p[3]); rule.blockMobile = "1".equals(p[4]);
                rule.scheduleEnabled = "1".equals(p[5]); rule.startTime = p[6]; rule.endTime = p[7];
            }
            rules.put(p[0], rule);
        }
        getSharedPreferences("yulong_app_firewall", MODE_PRIVATE).edit()
                .putBoolean("master_enabled", masterEnabled).apply();
    }
    /** Package enumeration, label resolution and sorting must never block the Activity UI. */
    private void loadAppsAsync() {
        loading = true;
        master.setEnabled(false);
        status.setText("正在后台读取已安装应用…");
        try {
            appWorker.execute(() -> {
                List<ApplicationInfo> loaded = new ArrayList<>();
                Map<String, String> loadedLabels = new HashMap<>();
                Throwable failure = null;
                try {
                    PackageManager pm = getPackageManager();
                    loaded.addAll(pm.getInstalledApplications(0));
                    loaded.removeIf(info -> {
                        if (info.packageName == null || info.packageName.equals(getPackageName())) return true;
                        boolean systemApp = (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                                || (info.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0;
                        return !FxYulongFirewallAppFilterPolicy.includes(appFilterMode, info.flags);
                    });
                    for (ApplicationInfo info : loaded) {
                        String label;
                        try { label = String.valueOf(pm.getApplicationLabel(info)); }
                        catch (Throwable ignored) { label = info.packageName; }
                        loadedLabels.put(info.packageName, label);
                    }
                    loaded.sort(Comparator.comparing(info ->
                            loadedLabels.getOrDefault(info.packageName, info.packageName)
                                    .toLowerCase(Locale.ROOT)));
                } catch (Throwable error) {
                    failure = error;
                }
                final Throwable loadFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    if (loadFailure != null) {
                        loading = false;
                        inventoryReady = false;
                        refreshAfterLoad = false;
                        master.setEnabled(false);
                        status.setText("无法读取应用列表：" + loadFailure.getClass().getSimpleName());
                        renderRows();
                        return;
                    }
                    apps.clear();
                    apps.addAll(loaded);
                    labels.clear();
                    labels.putAll(loadedLabels);
                    for (ApplicationInfo info : loaded) {
                        if (!rules.containsKey(info.packageName)) rules.put(info.packageName, new FirewallRule());
                    }
                    loading = false;
                    appsLoaded = true;
                    inventoryReady = true;
                    master.setEnabled(true);
                    status.setText("已读取 " + apps.size() + " 个" + ("用户应用".equals(suitePage) ? "用户应用" : "系统应用".equals(suitePage) ? "系统应用" : "应用") + "；列表按需分页加载。");
                    renderRows();
                    restoreScrollIfNeeded();
                    if (refreshAfterLoad) {
                        refreshAfterLoad = false;
                        refreshPackageInventory();
                    }
                });
            });
        } catch (java.util.concurrent.RejectedExecutionException closing) {
            loading = false;
            inventoryReady = false;
            master.setEnabled(false);
            if (!destroyed && !isFinishing()) status.setText("应用列表加载任务已停止，请重新打开页面。");
        }
    }
    private void restoreScrollIfNeeded() {
        if (!pendingScrollRestore || scroll == null) return;
        final int restoreY = pendingScrollY;
        final int generation = ++scrollRestoreGeneration;
        scroll.post(() -> {
            if (destroyed || isFinishing() || isDestroyed() || scroll == null
                    || generation != scrollRestoreGeneration || !pendingScrollRestore) return;
            scroll.scrollTo(0, restoreY);
            pendingScrollRestore = false;
        });
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putInt(STATE_APP_PAGE, Math.max(1, appPage));
        if (query != null) outState.putString(STATE_QUERY, query.getText().toString());
        if (scroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, scroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    private String formatBytes(long bytes) {
        if (bytes < 0) return "系统未提供";
        if (bytes < 1024) return bytes + " B";
        double value = bytes;
        String[] units = {"B", "KiB", "MiB", "GiB", "TiB"};
        int unit = 0;
        while (value >= 1024.0 && unit < units.length - 1) {
            value /= 1024.0;
            unit++;
        }
        return String.format(Locale.ROOT, "%.2f %s", value, units[unit]);
    }

    private void renderRows() {
        if (rows == null || isFinishing() || destroyed) return;
        rows.removeViews(4, Math.max(0, rows.getChildCount() - 4));
        String filter = query.getText() == null ? "" : query.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched = 0;
        int shown = 0;
        int limit = Math.max(1, appPage) * APP_PAGE_SIZE;
        for (ApplicationInfo info : apps) {
            String pkg = info.packageName, label = labels.getOrDefault(pkg, pkg);
            if (!filter.isEmpty() && !label.toLowerCase(Locale.ROOT).contains(filter)
                    && !pkg.toLowerCase(Locale.ROOT).contains(filter)) continue;
            matched++;
            if (shown >= limit) continue;
            FirewallRule existing = ruleFor(pkg);
            LinearLayout item = new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL);
            item.setPadding(dp(12), dp(7), dp(12), dp(7));
            TextView name = text(label, 14, 0xff17212b, true);
            TextView packageText = text(pkg + " · UID " + info.uid, 10, 0xff718091, false);
            long received = TrafficStats.getUidRxBytes(info.uid), transmitted = TrafficStats.getUidTxBytes(info.uid);
            TextView traffic = text("系统 UID 计数 · 接收 " + formatBytes(received)
                    + " · 发送 " + formatBytes(transmitted), 10, 0xff526170, false);
            TextView detail = text(ruleSummary(existing), 11, 0xff526170, false);
            Switch enabled = new Switch(this); enabled.setText("启用该应用的网络拦截规则");
            enabled.setChecked(existing.enabled);
            enabled.setEnabled(inventoryReady);
            final boolean[] suppressRow = {false};
            enabled.setOnCheckedChangeListener((button, checked) -> {
                if (suppressRow[0] || !inventoryReady) return;
                FirewallRule draft = ruleFor(pkg).copy();
                boolean previous = draft.enabled; draft.enabled = checked; button.setEnabled(false);
                persistRule(pkg, info.uid, draft, ok -> {
                    button.setEnabled(true);
                    if (!ok) {
                        suppressRow[0] = true; button.setChecked(previous); suppressRow[0] = false;
                    } else renderRows();
                });
            });
            item.addView(name); item.addView(packageText); item.addView(traffic); item.addView(detail); item.addView(enabled);
            Button configure = button("配置 Wi-Fi / 移动数据 / 每日时段", () -> showRuleDialog(pkg, info.uid));
            configure.setEnabled(inventoryReady);
            item.addView(configure);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(12), dp(2), dp(12), dp(2)); rows.addView(item, lp); shown++;
        }
        if (shown == 0) rows.addView(text("没有匹配的应用。", 13, 0xff617080, false));
        if (matched > limit) rows.addView(button("加载更多（剩余 " + (matched - limit) + " 个）", () -> {
            appPage++; renderRows();
        }), new LinearLayout.LayoutParams(-1, -2));
    }
    @Override protected void onDestroy() {
        unregisterPackageChangeReceiver();
        destroyed = true;
        scrollRestoreGeneration++;
        worker.shutdownNow();
        appWorker.shutdownNow();
        super.onDestroy();
    }
}
