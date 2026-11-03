package de.privacyguard.adhook.imported.shield;

import android.app.Activity;
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
 * Yulong Shield 9.9.60 third-level hub inside FX.
 * Original feature pages are kept as separate fourth-level Activities.
 */
public final class FxYulongShieldActivity extends Activity {
    private LinearLayout body;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }
    private Button action(String label, Runnable click) {
        Button button = new Button(this);
        button.setAllCaps(false); button.setText(label);
        button.setOnClickListener(v -> click.run());
        return button;
    }
    private void card(String title, String detail, View... controls) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(10), dp(14), dp(10));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 16, 0xff17212b, true));
        panel.addView(text(detail, 13, 0xff617080, false));
        for (View control : controls) panel.addView(control);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5));
        body.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(action("‹ 返回 FX 设置", this::finish));
        header.addView(text("游龙安全护盾 9.9.60", 19, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);

        card("功能迁移状态",
                "已迁入原版病毒名单匹配、离线缓存、手动扫描、白名单与管控名单管理。原版 ProtectService 实时守护、自保 watchdog 和 Stellar 特权运行时尚未迁入。");
        card("病毒库与名单",
                "五类逻辑名单：确定风险包名、可能风险包名、确定风险名称、可能风险名称、风险关键字；名称库会合并原版旧名单。",
                action("打开病毒库管理页", () -> startActivity(new Intent(this,
                        FxYulongVirusDatabaseActivity.class))));
        card("已安装应用扫描",
                "扫描合并系统安装清单与桌面启动器清单。结果只读，风险项需要再次确认后才能打开系统卸载界面。",
                action("打开应用扫描页", () -> startActivity(new Intent(this,
                        FxYulongScanActivity.class))));
        card("白名单管理",
                "保留原版搜索、应用选择、列表维护和本地保存行为；未接入原版 Stellar 指令白名单同步。",
                action("打开白名单", () -> startActivity(new Intent(this, WhitelistActivity.class))));
        card("管控应用列表",
                "保留原版应用选择、批量加入、移除与清空确认流程；后台自动拦截服务尚未迁入。",
                action("打开管控列表", () -> startActivity(new Intent(this, BlacklistActivity.class))));
        card("实时守护与自保服务",
                "ProtectService、音量/摇动触发、守护通知、自保 watchdog、扫描自动拦截和 Stellar 金龙引擎仍在迁移队列中。为避免误导，这里暂不提供无效开关。");
    }
}
