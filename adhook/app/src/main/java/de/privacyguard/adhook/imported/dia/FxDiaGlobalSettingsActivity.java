package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import de.privacyguard.adhook.R;

/**
 * Dia 23.11 global settings, migrated into the unified FX application.
 *
 * The original preference namespace ("digXposed") and original preference keys
 * are retained, but values remain MODE_PRIVATE. Settings whose original
 * cross-process runtime has not been migrated are shown as unavailable rather
 * than being presented as active controls.
 */
public final class FxDiaGlobalSettingsActivity extends Activity {
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
    private SharedPreferences preferences;
    private LinearLayout body;

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
        control.setOnCheckedChangeListener((button, checked) ->
                preferences.edit().putBoolean(key, checked).apply());
        row(title, summary, control, null);
    }

    private void addUnavailableSwitch(String title, String summary, String key) {
        Switch control = new Switch(this);
        control.setChecked(preferences.getBoolean(key, false));
        control.setEnabled(false);
        row(title, summary, control, () -> showUnavailable(title, summary));
    }

    private void addAction(String title, String summary, Runnable action) {
        row(title, summary, text("›", 24, 0xff748292, false), action);
    }

    private void showUnavailable(String title, String detail) {
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(detail)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void showLanguagePicker() {
        final String[] labels = {"跟随系统", "中文", "English"};
        final String[] values = {"0", "1", "2"};
        String selected = preferences.getString("language_setting", "0");
        int checked = 0;
        for (int i = 0; i < values.length; i++) {
            if (values[i].equals(selected)) checked = i;
        }
        new AlertDialog.Builder(this)
                .setTitle("设置语言")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    preferences.edit().putString("language_setting", values[which]).apply();
                    dialog.dismiss();
                    showUnavailable("语言偏好已保存",
                            "已按 Dia 23.11 的原始键 language_setting 保存选择。原版多语言运行时依赖尚未迁入 FX；当前选择不会伪装成已切换整个 FX 应用语言。");
                })
                .setNegativeButton("取消", null)
                .show();
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
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia · 全局设置", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(24));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView notice = text(
                "此页对应 Dia 23.11 的原始 my_settings PreferenceScreen。FX 只启用已经迁入并验证的操作；原版依赖独立 APK、跨进程共享偏好或框架重启的项目会明确标记为未迁移。",
                12, 0xff526170, false);
        notice.setPadding(dp(16), dp(10), dp(16), dp(12));
        body.addView(notice);

        section("提示显示");
        addStoredSwitch("显示 Xposed 激活提示",
                "保存原始 digXposed/active_tip 偏好。FX 的原版 EMessage 提示事件总线尚未迁移；当前保存状态不会单独触发原版提示。",
                "active_tip", true);
        addStoredSwitch("显示原生模块激活提示",
                "保存原始 digXposed/native_active_tip 偏好。原版对应的 native 模块激活提示消费端尚未迁入。",
                "native_active_tip", true);

        section("框架与作用域");
        addUnavailableSwitch("自动同步到 LSPosed 作用域",
                "原版依赖 dialog.box.lsp.LScope 与跨进程作用域 API。FX 尚未迁入该运行时，因此此项保持禁用，不会显示为已同步。",
                "lsp_sync");
        addAction("快速重启系统",
                "原版实际是仅重启框架服务层，不是重启 Android 系统。FX 尚未迁入原版重启实现；点击只显示安全说明，不执行 Root 命令。",
                () -> showUnavailable("快速重启系统尚未迁移",
                        "原版操作会中断框架服务并可能影响 Hook/模块状态。FX 当前没有经过验证的框架专用重启实现，因此不会执行重启或伪装成功。"));

        section("应用与数据");
        addAction("设置语言",
                "保留原始 0/1/2 选择值；全局语言运行时尚未迁移。当前仅保存偏好，不声明 UI 已切换。",
                this::showLanguagePicker);
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
                "查看 Dia 原始版本信息及 FX 统一迁移说明。",
                () -> new AlertDialog.Builder(this)
                        .setTitle("关于 Dia 23.11")
                        .setMessage("原始功能版本：Dia 23.11\n当前宿主：FX 1.0.0 / FX Hook\n该页面属于统一应用内的迁移界面，不会启动原 Dia APK。")
                        .setPositiveButton("关闭", null)
                        .show());

        setContentView(root);
    }
}
