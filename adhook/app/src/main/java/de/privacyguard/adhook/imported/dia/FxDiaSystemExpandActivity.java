package de.privacyguard.adhook.imported.dia;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageInstaller;
import android.content.pm.ResolveInfo;
import de.privacyguard.adhook.RootAccess;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ListView;
import android.text.Editable;
import android.text.TextWatcher;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * Dia 23.11 SystemExpandActivity migration.
 *
 * Wi-Fi/HTTP proxy uses the dedicated FX system-proxy page. Unknown-source
 * approval is adapted to Android's per-install-source permission screen.
 * The old ro.debuggable hook depended on framework/System UI injection and is
 * intentionally not represented as an operational toggle in the unified APK.
 * Package Installer restart is guarded by the live PackageInstaller session list;
 * unknown session state fails closed and a root force-stop always requires confirmation.
 */
public final class FxDiaSystemExpandActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-dia-install-source-picker"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private static final String STATE_SCROLL_Y = "fx_dia_system_expand_scroll_y";
    private static final String STATE_INSTALL_PICKER_OPEN = "fx_dia_install_source_picker_open";
    private static final String STATE_INSTALL_PICKER_QUERY = "fx_dia_install_source_picker_query";
    private ScrollView systemExpandScroll;
    private int restoredScrollY;
    private boolean restoreInstallSourcePicker;
    private String restoredInstallSourceQuery = "";
    private AlertDialog installSourcePickerDialog;
    private EditText installSourceSearch;

    private static final class InstallSource {
        final String packageName;
        final String label;
        InstallSource(String packageName, String label) {
            this.packageName = packageName;
            this.label = label;
        }
        @Override public String toString() { return label + "\n" + packageName; }
    }
    // Original Dia 23.11 res/xml/system_expand_setting.xml keys.
    private static final String[] ORIGINAL_SETTING_KEYS = {
            "switchModule", "ro_debuggable", "wifi_proxy",
            "allowed_install_from_unknown_source", "restart_package_installer"
    };
    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private Button button(String value, Runnable action) {
        Button result = new Button(this);
        result.setAllCaps(false);
        result.setText(value);
        result.setOnClickListener(v -> action.run());
        return result;
    }

    private void divider(LinearLayout parent) {
        View line = new View(this);
        line.setBackgroundColor(0xffe3e8ee);
        parent.addView(line, new LinearLayout.LayoutParams(-1, dp(1)));
    }

    private void row(LinearLayout parent, String title, String summary, View trailing) {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.HORIZONTAL);
        container.setGravity(Gravity.CENTER_VERTICAL);
        container.setPadding(dp(16), dp(12), dp(14), dp(12));
        LinearLayout labels = new LinearLayout(this);
        labels.setOrientation(LinearLayout.VERTICAL);
        labels.addView(text(title, 15, 0xff17212b, true));
        TextView detail = text(summary, 12, 0xff687583, false);
        detail.setPadding(0, dp(3), dp(6), 0);
        labels.addView(detail);
        container.addView(labels, new LinearLayout.LayoutParams(0, -2, 1));
        if (trailing != null) container.addView(trailing);
        parent.addView(container);
        divider(parent);
    }

    private void unavailable(String title, String summary) {
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(summary)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void openDeveloperOptions() {
        try {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS));
        } catch (Throwable unavailable) {
            try { startActivity(new Intent(Settings.ACTION_SETTINGS)); }
            catch (Throwable ignored) {
                unavailable("开发者选项不可用", "此设备没有提供 Android 开发者选项页面。");
            }
        }
    }

    private void chooseInstallSource() {
        chooseInstallSource("");
    }

    private void chooseInstallSource(String initialQuery) {
        final String queryToRestore = initialQuery == null ? "" : initialQuery;
        Toast.makeText(this, "正在读取声明了安装请求权限的应用…", Toast.LENGTH_SHORT).show();
        try {
            worker.execute(() -> {
                List<InstallSource> sources = new ArrayList<>();
                try {
                    PackageManager pm = getPackageManager();
                    for (PackageInfo info : pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)) {
                        if (info == null || info.packageName == null
                                || info.packageName.equals(getPackageName())
                                || info.requestedPermissions == null) continue;
                        boolean requestsInstall = false;
                        for (String permission : info.requestedPermissions) {
                            if ("android.permission.REQUEST_INSTALL_PACKAGES".equals(permission)) {
                                requestsInstall = true;
                                break;
                            }
                        }
                        if (!requestsInstall) continue;
                        String label;
                        try {
                            label = String.valueOf(pm.getApplicationLabel(info.applicationInfo));
                        } catch (Throwable ignored) {
                            label = info.packageName;
                        }
                        sources.add(new InstallSource(info.packageName, label));
                    }
                } catch (Throwable error) {
                    final String message = error.getClass().getSimpleName() + ": " + error.getMessage();
                    runOnUiThread(() -> unavailable("读取安装来源应用失败", message));
                    return;
                }
                Collections.sort(sources, (left, right) ->
                        left.label.compareToIgnoreCase(right.label));
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    if (sources.isEmpty()) {
                        unavailable("没有可授权的安装来源应用",
                                "当前未发现声明 REQUEST_INSTALL_PACKAGES 的应用。安装权限仍由 Android 系统控制。");
                        return;
                    }
                    // Keep package identity visible and make large installer lists searchable.
                    LinearLayout picker = new LinearLayout(this);
                    picker.setOrientation(LinearLayout.VERTICAL);
                    picker.setPadding(dp(16), dp(8), dp(16), dp(4));
                    EditText search = new EditText(this);
                    search.setSingleLine(true);
                    search.setHint("搜索应用名称或包名");
                    search.setTextSize(14);
                    picker.addView(search, new LinearLayout.LayoutParams(-1, -2));
                    FrameLayout listFrame = new FrameLayout(this);
                    LinearLayout.LayoutParams frameParams =
                            new LinearLayout.LayoutParams(-1, dp(320));
                    frameParams.topMargin = dp(6);
                    picker.addView(listFrame, frameParams);
                    ListView list = new ListView(this);
                    TextView empty = text("没有匹配的安装来源应用", 13, 0xff687583, false);
                    empty.setGravity(Gravity.CENTER);
                    listFrame.addView(list, new FrameLayout.LayoutParams(-1, -1));
                    listFrame.addView(empty, new FrameLayout.LayoutParams(-1, -1));
                    list.setEmptyView(empty);
                    ArrayAdapter<InstallSource> adapter = new ArrayAdapter<>(
                            this, android.R.layout.simple_list_item_1, new ArrayList<>(sources));
                    list.setAdapter(adapter);
                    search.addTextChangedListener(new TextWatcher() {
                        @Override public void beforeTextChanged(CharSequence value,
                                int start, int count, int after) { }
                        @Override public void onTextChanged(CharSequence value,
                                int start, int before, int count) {
                            adapter.getFilter().filter(value == null ? "" : value.toString());
                            list.setSelection(0);
                        }
                        @Override public void afterTextChanged(Editable value) { }
                    });
                    if (!queryToRestore.isEmpty()) search.setText(queryToRestore);
                    AlertDialog pickerDialog = new AlertDialog.Builder(this)
                            .setTitle("选择要授权的安装来源")
                            .setView(picker)
                            .setNegativeButton("取消", null)
                            .create();
                    installSourcePickerDialog = pickerDialog;
                    installSourceSearch = search;
                    pickerDialog.setOnDismissListener(dialog -> {
                        if (installSourcePickerDialog == pickerDialog) {
                            installSourcePickerDialog = null;
                            installSourceSearch = null;
                        }
                    });
                    list.setOnItemClickListener((parent, view, position, id) -> {
                        InstallSource selected = adapter.getItem(position);
                        if (selected == null) return;
                        pickerDialog.dismiss();
                        openInstallSourceSettings(selected.packageName);
                    });
                    pickerDialog.show();
                });
            });
        } catch (RejectedExecutionException full) {
            Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
        }
    }

    private void openInstallSourceSettings(String packageName) {
        if (packageName == null || !packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) return;
        if (Build.VERSION.SDK_INT < 26) {
            try { startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS)); }
            catch (Throwable error) { unavailable("安装来源设置不可用", error.getClass().getSimpleName()); }
            return;
        }
        Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + packageName));
        try {
            startActivity(settings);
        } catch (Throwable error) {
            try {
                startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + packageName)));
            } catch (Throwable fallback) {
                unavailable("无法打开来源应用设置",
                        "Android 没有提供该应用的未知来源授权页面：" + error.getClass().getSimpleName());
            }
        }
    }

    private String resolvePackageInstallerPackage() {
        Intent install = new Intent(Intent.ACTION_INSTALL_PACKAGE);
        install.addCategory(Intent.CATEGORY_DEFAULT);
        install.setType("application/vnd.android.package-archive");
        ResolveInfo resolved = getPackageManager()
                .resolveActivity(install, PackageManager.MATCH_DEFAULT_ONLY);
        if (resolved == null || resolved.activityInfo == null
                || resolved.activityInfo.packageName == null
                || resolved.activityInfo.name == null) {
            throw new IllegalStateException("找不到确定的系统安装处理程序");
        }
        String packageName = resolved.activityInfo.packageName;
        String activityName = resolved.activityInfo.name.toLowerCase(java.util.Locale.ROOT);
        // Never force-stop Android's generic resolver/chooser when there is no
        // single default installer selected by the current user.
        if ("android".equals(packageName)
                || activityName.contains("resolver")
                || activityName.contains("chooser")) {
            throw new IllegalStateException("Android 当前返回的是通用选择器，无法确定唯一安装处理程序");
        }
        if (!packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
            throw new IllegalStateException("安装处理程序包名格式无效");
        }
        return packageName;
    }

    private void checkPackageInstallerBeforeRestart() {
        Toast.makeText(this, "正在检查 Android 安装会话…", Toast.LENGTH_SHORT).show();
        try {
            worker.execute(() -> {
                final String packageName;
                final int active;
                final int committed;
                final int staged;
                try {
                    packageName = resolvePackageInstallerPackage();
                    PackageInstaller installer = getPackageManager().getPackageInstaller();
                    List<PackageInstaller.SessionInfo> sessions = installer.getAllSessions();
                    if (sessions == null) throw new IllegalStateException("系统未返回安装会话清单");
                    int activeCount = 0;
                    int committedCount = 0;
                    int stagedCount = 0;
                    for (PackageInstaller.SessionInfo session : sessions) {
                        if (session == null) throw new IllegalStateException("安装会话清单包含未知项目");
                        if (session.isActive()) activeCount++;
                        if (Build.VERSION.SDK_INT >= 29 && session.isCommitted()) committedCount++;
                        if (Build.VERSION.SDK_INT >= 30 && session.isStagedSessionActive()) stagedCount++;
                    }
                    active = activeCount;
                    committed = committedCount;
                    staged = stagedCount;
                } catch (Throwable error) {
                    String detail = error.getClass().getSimpleName()
                            + (error.getMessage() == null ? "" : ": " + error.getMessage());
                    runOnUiThread(() -> unavailable("无法确认安装会话状态",
                            "FX 为避免中断系统安装，会话信息读取失败后不会执行重启。\n" + detail));
                    return;
                }

                boolean safe = FxDiaInstallerRestartPolicy.isSafeToRestart(
                        true, active, committed, staged);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    if (!safe) {
                        unavailable("暂不允许重启 Package Installer",
                                "检测到 Android 安装会话仍在使用或等待处理。\n"
                                        + "活动会话：" + active + "；已提交会话：" + committed
                                        + "；待应用 staged 会话：" + staged
                                        + "。\n请等安装/卸载操作全部结束后再重试。");
                        return;
                    }
                    confirmPackageInstallerRestart(packageName);
                });
            });
        } catch (RejectedExecutionException full) {
            Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
        }
    }

    private void confirmPackageInstallerRestart(String packageName) {
        new AlertDialog.Builder(this)
                .setTitle("重启 Package Installer？")
                .setMessage("已确认当前没有活动、已提交或待应用的安装会话。FX 将使用 Root 强制停止：\n"
                        + packageName + "\nAndroid 会在下一次安装操作时重新启动该处理程序。")
                .setNegativeButton("取消", null)
                .setNeutralButton("打开应用信息", (dialog, which) ->
                        openPackageInstallerAppInfo(packageName))
                .setPositiveButton("确认重启", (dialog, which) ->
                        forceStopPackageInstaller(packageName))
                .show();
    }

    private void openPackageInstallerAppInfo(String packageName) {
        try {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + packageName)));
        } catch (Throwable error) {
            unavailable("无法打开安装器应用信息", error.getClass().getSimpleName());
        }
    }

    private void forceStopPackageInstaller(String packageName) {
        if (packageName == null || !packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
            unavailable("拒绝执行", "安装处理程序包名无效。");
            return;
        }
        try {
            worker.execute(() -> {
                // Re-read immediately after the user's confirmation. A new install
                // session may have started while the confirmation dialog was open.
                try {
                    List<PackageInstaller.SessionInfo> currentSessions =
                            getPackageManager().getPackageInstaller().getAllSessions();
                    if (currentSessions == null) {
                        runOnUiThread(() -> unavailable("安装会话状态未知",
                                "系统未返回会话清单；为避免中断安装，FX 已取消强制停止。"));
                        return;
                    }
                    int activeNow = 0;
                    int committedNow = 0;
                    int stagedNow = 0;
                    for (PackageInstaller.SessionInfo session : currentSessions) {
                        if (session == null) throw new IllegalStateException("会话清单包含未知项目");
                        if (session.isActive()) activeNow++;
                        if (Build.VERSION.SDK_INT >= 29 && session.isCommitted()) committedNow++;
                        if (Build.VERSION.SDK_INT >= 30 && session.isStagedSessionActive()) stagedNow++;
                    }
                    if (!FxDiaInstallerRestartPolicy.isSafeToRestart(
                            true, activeNow, committedNow, stagedNow)) {
                        runOnUiThread(() -> unavailable("安装会话状态已变化",
                                "确认窗口打开后检测到新的活动/已提交安装会话；FX 已取消强制停止。"));
                        return;
                    }
                } catch (Throwable sessionError) {
                    String detail = sessionError.getClass().getSimpleName()
                            + (sessionError.getMessage() == null ? "" : ": " + sessionError.getMessage());
                    runOnUiThread(() -> unavailable("无法再次确认安装会话",
                            "会话状态读取失败；为避免中断安装，FX 已取消强制停止。\n" + detail));
                    return;
                }
                RootAccess.Result result = RootAccess.execute(
                        "am force-stop " + packageName, 15000L, 8192);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    if (result.exitCode == 0) {
                        Toast.makeText(this,
                                "安装处理程序已停止；Android 会在下次安装操作时重新启动它。",
                                Toast.LENGTH_LONG).show();
                    } else {
                        unavailable("Package Installer 重启失败",
                                "Root 命令未成功（exit=" + result.exitCode + "）："
                                        + (result.output == null ? "" : result.output));
                    }
                });
            });
        } catch (RejectedExecutionException full) {
            Toast.makeText(this, "后台任务繁忙，本次重启未执行。", Toast.LENGTH_LONG).show();
        }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            restoreInstallSourcePicker = state.getBoolean(STATE_INSTALL_PICKER_OPEN, false);
            String query = state.getString(STATE_INSTALL_PICKER_QUERY, "");
            restoredInstallSourceQuery = query == null ? ""
                    : query.substring(0, Math.min(query.length(), 256));
        }
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia · 系统扩展", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        systemExpandScroll = scroll;
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(24));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView intro = text(
                "对应 Dia 23.11 的 system_expand_setting PreferenceScreen。Wi-Fi HTTP 代理、逐安装来源授权和安装器应用信息入口已迁入；ro.debuggable 原版全局 Hook 因依赖 framework/System UI 注入，不在统一 FX APK 中伪装启用。模块级独立开关由统一 FX 模块生命周期取代。",
                12, 0xff526170, false);
        intro.setPadding(dp(16), dp(10), dp(16), dp(12));
        body.addView(intro);

        row(body, "Wi-Fi Proxy",
                "已迁入 FX：可设置系统 HTTP 代理，默认关闭，并在关闭时验证系统值是否仍由 FX 持有。",
                button("打开", () -> startActivity(new Intent(this, FxDiaWifiProxyActivity.class))));

        row(body, "模块级开关",
                "原版依赖 Dia 独立模块状态。统一 FX 版本不再单独启停 Dia 子模块；该控制尚未迁移。",
                button("未迁移", () -> unavailable("模块级开关未迁移",
                        "FX 使用统一的模块生命周期，不会创建一个独立 Dia 模块开关。")));

        row(body, "ro.debuggable / 调试目标",
                "原版 DebugHook 会介入系统进程启动与 Settings AppPicker，并非单纯修改一个属性。FX 的当前 Hook runtime 不向 Android framework/System UI 注入此类全局钩子；这里仅提供 Android 自己的开发者选项入口，不会伪装成已启用的调试 Hook。",
                button("打开开发者选项", this::openDeveloperOptions));

        row(body, "允许从未知来源安装",
                "改用 Android 原生的逐来源应用授权。选择声明 REQUEST_INSTALL_PACKAGES 的应用后，由系统设置页完成授权；FX 不会绕过PackageInstaller 的未知来源校验，也不会开启全局安装权限。",
                button("选择来源应用", this::chooseInstallSource));

        row(body, "重启 Package Installer",
                "先检查 Android 全部安装会话；只在无活动/已提交/staged 会话且用户二次确认后，才通过 KernelSU Root 强制停止默认安装处理程序。",
                button("检查并重启", this::checkPackageInstallerBeforeRestart));

        setContentViewWithNativeTabs(root, 5);
        if (restoredScrollY > 0) {
            final int restoreY = restoredScrollY;
            scroll.post(() -> {
                if (!isFinishing() && !isDestroyed()
                        && systemExpandScroll == scroll && scroll.getParent() != null) {
                    scroll.scrollTo(0, restoreY);
                }
            });
        }
        if (restoreInstallSourcePicker) {
            final String query = restoredInstallSourceQuery;
            restoreInstallSourcePicker = false;
            restoredInstallSourceQuery = "";
            chooseInstallSource(query);
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (systemExpandScroll != null) {
            outState.putInt(STATE_SCROLL_Y, Math.max(0, systemExpandScroll.getScrollY()));
        }
        if (installSourcePickerDialog != null && installSourcePickerDialog.isShowing()) {
            outState.putBoolean(STATE_INSTALL_PICKER_OPEN, true);
            String query = installSourceSearch == null ? "" : installSourceSearch.getText().toString();
            outState.putString(STATE_INSTALL_PICKER_QUERY,
                    query.substring(0, Math.min(query.length(), 256)));
        }
    }

    @Override protected void onDestroy() {
        if (installSourcePickerDialog != null) installSourcePickerDialog.dismiss();
        worker.shutdownNow();
        super.onDestroy();
    }

}
