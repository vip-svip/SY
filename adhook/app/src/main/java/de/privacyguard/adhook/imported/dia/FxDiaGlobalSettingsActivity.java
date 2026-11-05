package de.privacyguard.adhook.imported.dia;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.R;
import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * Dia 23.11 global settings, migrated into the unified FX application.
 *
 * The original preference namespace ("digXposed") and original preference keys
 * are retained, but values remain MODE_PRIVATE. Settings whose original
 * cross-process runtime has not been migrated are shown as unavailable rather
 * than being presented as active controls.
 */
public final class FxDiaGlobalSettingsActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String PREFS = "digXposed";
    // Original Dia 23.11 res/xml/my_settings.xml preference keys, including
    // actions whose old standalone runtime is intentionally not invoked by FX.
    // "console" exists in my_settings.xml but Dia SettingsActivity removes
    // it from the visible PreferenceScreen before display. Keep it in the
    // source inventory, not as a new FX global setting.
    private static final String[] ORIGINAL_SETTING_KEYS = {
            "active_tip", "native_active_tip", "lsp_sync", "console", "fast_restart_system",
            "language_setting", "app_update", "data_backup", "system_expand",
            "internal_community", "about"
    };
    private static final String FRAMEWORK_RESTART_COMMAND =
            "stop; fx_stop_rc=$?; start; fx_start_rc=$?; "
                    + "printf 'FX_STOP_RC=%s\\nFX_START_RC=%s\\n' "
                    + "\"$fx_stop_rc\" \"$fx_start_rc\"; "
                    + "[ \"$fx_stop_rc\" -eq 0 ] && [ \"$fx_start_rc\" -eq 0 ]";
    private static final ThreadPoolExecutor FRAMEWORK_RESTART_EXECUTOR =
            new ThreadPoolExecutor(1, 1, 30L, TimeUnit.SECONDS,
                    new ArrayBlockingQueue<>(1),
                    task -> {
                        Thread thread = new Thread(task, "fx-dia-framework-restart");
                        thread.setDaemon(true);
                        return thread;
                    }, new ThreadPoolExecutor.AbortPolicy());
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private SharedPreferences preferences;
    private LinearLayout body;
    private TextView frameworkRestartStatus;
    private boolean frameworkRestartBusy;

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

    private void section(String title) {
        TextView heading = text(title, 14, 0xff526170, true);
        heading.setPadding(dp(16), dp(16), dp(16), dp(6));
        body.addView(heading);
    }

    private void divider() {
        View line = new View(this);
        line.setBackgroundColor(0xffe3e8ee);
        body.addView(line, new LinearLayout.LayoutParams(-1, dp(1)));
    }

    private void row(String title, String summary, View trailing, Runnable click) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.HORIZONTAL);
        panel.setGravity(Gravity.CENTER_VERTICAL);
        panel.setPadding(dp(16), dp(10), dp(14), dp(10));

        LinearLayout labels = new LinearLayout(this);
        labels.setOrientation(LinearLayout.VERTICAL);
        labels.addView(text(title, 15, 0xff17212b, true));
        TextView detail = text(summary, 12, 0xff687583, false);
        detail.setPadding(0, dp(3), dp(8), 0);
        labels.addView(detail);
        panel.addView(labels, new LinearLayout.LayoutParams(0, -2, 1));

        if (trailing != null) panel.addView(trailing);
        if (click != null) panel.setOnClickListener(v -> click.run());
        body.addView(panel);
        divider();
    }

    private void addStoredSwitch(String title, String summary, String key, boolean defaultValue) {
        Switch control = new Switch(this);
        control.setChecked(preferences.getBoolean(key, defaultValue));
        control.setOnCheckedChangeListener((button, enabled) ->
                preferences.edit().putBoolean(key, enabled).apply());
        row(title, summary, control, null);
    }

    private void addUnavailableSwitch(String title, String summary, String key, boolean defaultValue) {
        Switch control = new Switch(this);
        control.setChecked(preferences.getBoolean(key, defaultValue));
        control.setEnabled(false);
        row(title, summary, control, () -> showUnavailable(title, summary));
    }

    private void addUnavailableAction(String title, String summary) {
        row(title, summary, text("未迁移", 12, 0xff9aa4ae, false),
                () -> showUnavailable(title + "尚未迁移", summary));
    }

    private void addAction(String title, String summary, Runnable action) {
        row(title, summary, text("›", 24, 0xff748292, false), action);
    }

    private void showUnavailable(String title, String detail) {
        fxDialogBuilder()
                .setTitle(title)
                .setMessage(detail)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void confirmFrameworkRestart() {
        if (frameworkRestartBusy) {
            showUnavailable("框架重启正在执行", "请勿重复触发。重启命令返回后会显示执行结果；框架重启本身可能导致 FX 界面随应用进程退出。");
            return;
        }
        fxDialogBuilder()
                .setTitle("确认快速重启框架服务？")
                .setMessage("此操作通过 Root 重启 Android 框架服务（stop;start），不是重启内核或整台设备。Android 框架会短暂停止并重新启动，所有正在运行的应用及 unsaved state、VPN 连接、LSPosed/Hook 会中断。请先保存工作。需要 KernelSU Root 授权。")
                .setNegativeButton("取消", null)
                .setPositiveButton("确认重启框架服务", (dialog, which) -> executeFrameworkRestart())
                .show();
    }

    private void executeFrameworkRestart() {
        if (frameworkRestartBusy) return;
        frameworkRestartBusy = true;
        frameworkRestartStatus.setText("正在向 Root shell 提交 stop;start 框架重启命令…");
        try {
            FRAMEWORK_RESTART_EXECUTOR.execute(() -> {
                RootAccess.Result result = RootAccess.execute(
                        FRAMEWORK_RESTART_COMMAND, 30000L, 16 * 1024);
                mainHandler.post(() -> {
                    frameworkRestartBusy = false;
                    if (isFinishing() || isDestroyed()) return;
                    boolean stopOk = result.output != null && result.output.contains("FX_STOP_RC=0");
                    boolean startOk = result.output != null && result.output.contains("FX_START_RC=0");
                    if (result.exitCode == 0 && stopOk && startOk) {
                        frameworkRestartStatus.setText(
                                "Root shell 已返回 stop=0、start=0。框架服务重启命令已执行；设备可能仍在恢复应用服务。");
                        Toast.makeText(this, "框架服务重启命令已执行。", Toast.LENGTH_LONG).show();
                    } else {
                        String detail = result.output == null ? "" : result.output.trim();
                        if (detail.length() > 700) detail = detail.substring(0, 700);
                        frameworkRestartStatus.setText(
                                "框架服务重启未能确认成功（退出码 " + result.exitCode + "）。"
                                        + (detail.isEmpty() ? "请确认 KernelSU Root 授权和系统 stop/start 命令可用。" : "\\n" + detail));
                    }
                });
            });
        } catch (RejectedExecutionException full) {
            frameworkRestartBusy = false;
            frameworkRestartStatus.setText("后台执行队列繁忙，本次框架重启未提交。请稍后重试。");
        }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Hook", this::finish));
        header.addView(text("Hook · 工具与运行设置", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(24));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView notice = text(
                "管理 FX Hook 的提示显示、LSPosed 作用域、数据备份与系统扩展。尚未接入或当前设备不支持的能力会明确标记，不会启动旧应用或创建第二套设置入口。",
                12, 0xff526170, false);
        notice.setPadding(dp(16), dp(10), dp(16), dp(12));
        body.addView(notice);

        section("提示显示");
        addStoredSwitch("显示 LSPosed 激活状态提示",
                "在 Dia 功能入口显示 FX Hook 当前是否收到 LSPosed 官方服务 Binder。该状态只说明框架服务可用，不代表任一目标进程已注入；目标应用作用域仍须在 LSPosed Manager 中确认。",
                "active_tip", true);
        addUnavailableSwitch("显示原生模块激活提示",
                "原始 APK 的 my_settings.xml 声明了 native_active_tip，但完整 Smali 检索未发现该键的读取/消费逻辑。FX 保留该原始键状态，不把无消费路径的偏好伪装成有效开关。",
                "native_active_tip", true);

        section("框架与作用域");
        addStoredSwitch("自动申请 LSPosed 作用域",
                "开启后，进入用户应用的 Hook 配置页时，FX 会先读取 LSPosed 当前作用域；若尚未包含该应用，则通过官方 libXposed 服务向 LSPosed Manager 提交申请。系统应用不会自动申请，Manager 仍须批准；作用域批准不代表目标进程已注入。",
                "lsp_sync", false);
        addAction("重启 LSPosed 框架服务",
                "通过 Root 执行框架服务 stop;start，不会重启内核或整台设备。需要 KernelSU Root 授权；正在运行的应用、VPN 和 Hook 会被中断。",
                this::confirmFrameworkRestart);
        frameworkRestartStatus = text("框架服务重启：尚未执行。", 12, 0xff687583, false);
        frameworkRestartStatus.setPadding(dp(16), dp(4), dp(16), dp(8));
        body.addView(frameworkRestartStatus);

        section("应用与数据");
        addUnavailableAction("设置语言",
                "原版通过 MultiLanguages 运行时切换独立 Dia APK 的资源语言。FX 尚未迁入统一应用的完整本地化资源和 Locale 生命周期；此项暂不可用，不再只保存一个不会改变界面的选择值。");
        addAction("应用更新",
                "原版更新器面向独立 Dia APK。统一版 FX 不会启动旧 APK 更新器；请使用 FX 统一发布渠道更新。",
                () -> showUnavailable("统一应用更新",
                        "旧 Dia 更新器不能用于更新统一 FX APK。此入口暂不启动独立更新器，以免覆盖或破坏统一安装。"));
        addAction("数据备份",
                "打开已迁入 FX 的加密本地备份、GitHub 和 WebDAV 备份管理。",
                () -> startActivity(new Intent(this, FxDiaBackupActivity.class)));
        addAction("系统扩展",
                "进入 Dia 原系统扩展页的 FX 迁移页面。当前已接入系统 HTTP 代理；其他原始扩展会分别标注状态。",
                () -> startActivity(new Intent(this, FxDiaSystemExpandActivity.class)));

        section("其他");
        TextView communityState = text("原版默认禁用", 12, 0xff9aa4ae, false);
        row("内部社区", "原版 PreferenceScreen 中此项默认 enabled=false；FX 保持禁用。", communityState, null);
        addAction("关于软件",
                "查看 FX Hook 版本和统一运行信息。",
                () -> fxDialogBuilder()
                        .setTitle("关于 FX Hook")
                        .setMessage("当前版本：FX 1.0.0\n功能宿主：FX Hook\n此页面由 FX 统一管理，不会启动其他 APK。")
                        .setPositiveButton("关闭", null)
                        .show());

        setContentViewWithNativeTabs(root, 4);
    }
}
