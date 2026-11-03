package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Dia 23.11 SystemExpandActivity migration.
 *
 * Only the original Wi-Fi/HTTP proxy destination currently has a real FX
 * implementation. The original ro.debuggable and package-installer controls
 * remain visible but disabled until their source behavior and security impact
 * can be migrated and verified.
 */
public final class FxDiaSystemExpandActivity extends Activity {
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

        row(body, "ro.debuggable",
                "原版会修改系统调试属性，具有系统范围影响。FX 尚未迁移该操作，也不会通过普通开关伪装成功。",
                button("未迁移", () -> unavailable("系统调试属性未迁移",
                        "修改 ro.debuggable 需要设备级 Root、属性服务与回滚验证。当前版本不会更改系统属性。")));

        row(body, "允许从未知来源安装",
                "原版依赖模块级安装来源修改。FX 尚未迁移对应的系统策略控制；请使用 Android 系统提供的逐应用授权。",
                button("未迁移", () -> unavailable("安装来源控制未迁移",
                        "为避免扩大安装权限，FX 不会替用户开启全局未知来源安装。请在 Android 设置中按需授权具体安装来源应用。")));

        row(body, "重启 Package Installer",
                "依赖原版安装来源控制及包安装器状态；当前未迁移，不执行强制停止或重启系统服务。",
                button("未迁移", () -> unavailable("Package Installer 操作未迁移",
                        "当前 FX 不会强制停止或重启系统 Package Installer。")));

        setContentView(root);
    }
}
