package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
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
 * Only the original Wi-Fi/HTTP proxy destination currently has a real FX
 * implementation. The original ro.debuggable and package-installer controls
 * remain visible but disabled until their source behavior and security impact
 * can be migrated and verified.
 */
public final class FxDiaSystemExpandActivity extends Activity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-dia-install-source-picker"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

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
                    String[] labels = new String[sources.size()];
                    for (int i = 0; i < sources.size(); i++) labels[i] = sources.get(i).toString();
                    new AlertDialog.Builder(this)
                            .setTitle("选择要授权的安装来源")
                            .setItems(labels, (dialog, which) -> openInstallSourceSettings(
                                    sources.get(which).packageName))
                            .setNegativeButton("取消", null)
                            .show();
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

    private void openPackageInstallerAppInfo() {
        try {
            Intent install = new Intent(Intent.ACTION_INSTALL_PACKAGE);
            install.addCategory(Intent.CATEGORY_DEFAULT);
            install.setType("application/vnd.android.package-archive");
            android.content.pm.ResolveInfo resolved = getPackageManager()
                    .resolveActivity(install, PackageManager.MATCH_DEFAULT_ONLY);
            if (resolved == null || resolved.activityInfo == null
                    || resolved.activityInfo.packageName == null) {
                unavailable("找不到系统安装处理程序", "请从 Android 设置中的应用列表管理安装服务。");
                return;
            }
            String packageName = resolved.activityInfo.packageName;
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + packageName)));
        } catch (Throwable error) {
            unavailable("无法打开安装器应用信息", error.getClass().getSimpleName());
        }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
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
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(24));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView intro = text(
                "对应 Dia 23.11 的 system_expand_setting PreferenceScreen。原页面包含模块级开关、ro.debuggable、Wi-Fi Proxy 和安装来源控制。FX 只开放已迁入的系统 HTTP 代理操作，其余选项保持禁用。",
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
                "改用 Android 原生的逐来源应用授权。选择声明 REQUEST_INSTALL_PACKAGES 的应用后，由系统设置页完成授权；FX 不会绕过 PackageInstaller 的未知来源校验，也不会开启全局安装权限。",
                button("选择来源应用", this::chooseInstallSource));

        row(body, "重启 Package Installer",
                "不会强制停止或重启系统安装器（可能中断正在进行的安装会话）。可查看当前系统安装处理程序的应用信息，并由用户在 Android 设置中管理。",
                button("打开安装器应用信息", this::openPackageInstallerAppInfo));

        setContentView(root);
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

}
