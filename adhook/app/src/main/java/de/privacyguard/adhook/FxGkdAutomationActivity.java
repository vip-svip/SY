package de.privacyguard.adhook;

import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.List;

/** FX Hook tab surface for explicitly scoped, local GKD selector rules. */
public final class FxGkdAutomationActivity extends FxNativeTabActivity {
    private LinearLayout body;
    private TextView serviceState;
    private Switch masterSwitch;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(0, dp(8), 0, dp(12));

        LinearLayout heading = new LinearLayout(this);
        heading.setGravity(Gravity.CENTER_VERTICAL);
        heading.setPadding(dp(14), dp(4), dp(14), dp(8));
        TextView title = new TextView(this);
        title.setText("GKD · 选择器自动化");
        title.setTextSize(20);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        title.setTextColor(0xff17212b);
        heading.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        Button back = new Button(this);
        back.setAllCaps(false);
        back.setText("返回 Hook");
        back.setOnClickListener(v -> finish());
        heading.addView(back);
        root.addView(heading);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(24));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView intro = text(
                "当前首批接入 GKD-XA v1.4.8 原生 selector/parser 引擎，支持本地手动规则与 Click 动作。\n" +
                "未接入的上游订阅、AI、快照、触发历史和云同步不会显示成已完成。", 0xff66727e, 13);
        card(intro);

        TextView privacy = text(
                "隐私与授权：只有你主动开启下方 GKD 总开关并为具体应用添加规则后，FX 才会读取该应用的无障碍控件树并在本机匹配。密码/可编辑输入框的文本不会被读取；不截图、不上传、不记录页面文本。关闭总开关立即停止规则匹配。", 0xff72511e, 13);
        card(privacy);

        serviceState = text("", 0xff536170, 13);
        card(serviceState);
        Button openAccessibility = action("打开 Android 无障碍设置", () -> {
            try {
                startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
            } catch (Exception error) {
                Toast.makeText(this, "无法打开无障碍设置：" + error.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
        body.addView(openAccessibility);

        masterSwitch = new Switch(this);
        masterSwitch.setText("启用 GKD 本地规则自动化");
        masterSwitch.setTextSize(16);
        masterSwitch.setPadding(dp(18), dp(16), dp(18), dp(16));
        masterSwitch.setChecked(FxGkdRuleStore.isEnabled(this));
        masterSwitch.setOnCheckedChangeListener((button, checked) -> {
            if (!FxGkdRuleStore.setEnabled(this, checked)) {
                button.setChecked(false);
                Toast.makeText(this,
                        checked ? "请先添加至少一条有效规则。" : "GKD 设置保存失败。",
                        Toast.LENGTH_LONG).show();
                return;
            }
            FxAccessibilityService.requestReconfigure(this);
            updateServiceState();
            Toast.makeText(this, checked ? "GKD 本地规则已启用" : "GKD 自动化已关闭",
                    Toast.LENGTH_SHORT).show();
        });
        body.addView(masterSwitch, new LinearLayout.LayoutParams(-1, -2));

        body.addView(action("＋ 添加本地选择器规则", this::showAddRuleDialog));
        renderRules();
        updateServiceState();
        setContentViewWithNativeTabs(root, 4);
    }

    @Override protected void onResume() {
        super.onResume();
        updateServiceState();
    }

    private TextView text(String value, int color, int size) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(size);
        view.setPadding(dp(16), dp(10), dp(16), dp(10));
        return view;
    }

    private void card(View view) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(8), dp(6), dp(8), dp(6));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(view);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(12), dp(5), dp(12), dp(5));
        body.addView(panel, params);
    }

    private Button action(String label, Runnable callback) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setOnClickListener(v -> callback.run());
        return button;
    }

    private void updateServiceState() {
        if (serviceState == null) return;
        boolean enabledInSystem = isFxAccessibilityEnabled();
        boolean connected = FxAccessibilityService.isConnected();
        serviceState.setText(
                "系统无障碍：" + (enabledInSystem ? "已授权" : "未授权") +
                " · FX 服务：" + (connected ? "已连接" : "未连接") +
                " · GKD 规则：" + (FxGkdRuleStore.isEnabled(this) ? "已启用" : "已关闭") +
                "\n系统无障碍授权需要你在 Android 设置中手动开启；FX 不会自行打开或绕过授权。");
    }

    private boolean isFxAccessibilityEnabled() {
        String enabled = Settings.Secure.getString(
                getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null) return false;
        ComponentName expected = new ComponentName(this, FxAccessibilityService.class);
        for (String item : enabled.split(":")) {
            ComponentName parsed = ComponentName.unflattenFromString(item);
            if (expected.equals(parsed)) return true;
        }
        return false;
    }

    private void showAddRuleDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(8), dp(20), dp(4));

        EditText packageInput = new EditText(this);
        packageInput.setSingleLine(true);
        packageInput.setHint("目标应用包名，例如 com.example.app");
        packageInput.setInputType(InputType.TYPE_CLASS_TEXT);
        form.addView(packageInput);

        EditText selectorInput = new EditText(this);
        selectorInput.setHint("GKD 选择器，例如 [text='Skip']");
        selectorInput.setSingleLine(false);
        selectorInput.setMinLines(2);
        selectorInput.setMaxLines(4);
        selectorInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        form.addView(selectorInput);

        EditText cooldownInput = new EditText(this);
        cooldownInput.setSingleLine(true);
        cooldownInput.setHint("规则冷却秒数（1–60，默认 3）");
        cooldownInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        form.addView(cooldownInput);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("添加 GKD 本地规则")
                .setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("校验并保存", null)
                .create();
        dialog.setOnShowListener(ignored ->
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                    String pkg = packageInput.getText().toString().trim();
                    String selector = selectorInput.getText().toString().trim();
                    String cooldownRaw = cooldownInput.getText().toString().trim();
                    long cooldownSeconds = 3L;
                    try {
                        if (!cooldownRaw.isEmpty()) cooldownSeconds = Long.parseLong(cooldownRaw);
                    } catch (NumberFormatException invalid) {
                        Toast.makeText(this, "冷却秒数无效。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    if (cooldownSeconds < 1L || cooldownSeconds > 60L) {
                        Toast.makeText(this, "冷却秒数必须在 1 到 60 秒之间。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    if (!isInstalledUserApplication(pkg)) {
                        Toast.makeText(this, "目标必须是已安装的普通用户应用，不能选择 FX 自身或系统应用。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdSelectorCompilation compiled = FxGkdSelectorEngine.compile(selector);
                    if (!compiled.isValid()) {
                        Toast.makeText(this, "选择器无效：" + compiled.getError(), Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdRule saved = FxGkdRuleStore.addRule(
                            this, pkg, selector, cooldownSeconds * 1000L);
                    if (saved == null) {
                        Toast.makeText(this, "保存失败：规则数量可能已达上限，或存储不可写。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdAutomationRuntime.invalidateRules();
                    FxAccessibilityService.requestReconfigure(this);
                    renderRules();
                    dialog.dismiss();
                    Toast.makeText(this, "本地 GKD 规则已保存。", Toast.LENGTH_SHORT).show();
                }));
        dialog.show();
    }

    private boolean isInstalledUserApplication(String pkg) {
        if (!FxGkdRuleStore.isValidPackageName(pkg) || pkg.equals(getPackageName())) return false;
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(pkg, 0);
            return (info.flags & (ApplicationInfo.FLAG_SYSTEM
                    | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) == 0;
        } catch (Exception missing) {
            return false;
        }
    }

    private void renderRules() {
        if (body == null) return;
        // Keep the two notice cards, service status, permission button,
        // master switch and add-rule button. Only replace the rule-list tail.
        while (body.getChildCount() > 6) body.removeViewAt(6);
        TextView section = text("本地规则（仅保存在本机）", 0xff17212b, 16);
        section.setTypeface(null, android.graphics.Typeface.BOLD);
        body.addView(section);

        List<FxGkdRule> rules = FxGkdRuleStore.getRules(this);
        if (rules.isEmpty()) {
            body.addView(text("还没有规则。添加目标应用包名和上游 GKD 选择器后，规则才会参与匹配。", 0xff66727e, 13));
            return;
        }

        for (FxGkdRule rule : rules) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(14), dp(8), dp(14), dp(8));
            row.setBackgroundColor(0xfff0f3f7);
            TextView label = text(rule.getPackageName() + "\n" + rule.getSelector()
                    + "\n动作：点击 · 冷却：" + (rule.getCooldownMillis() / 1000L) + " 秒",
                    0xff17212b, 13);
            row.addView(label);

            LinearLayout actions = new LinearLayout(this);
            actions.setGravity(Gravity.CENTER_VERTICAL);
            Switch enabled = new Switch(this);
            enabled.setText("启用");
            enabled.setChecked(rule.getEnabled());
            enabled.setOnCheckedChangeListener((button, checked) -> {
                FxGkdRuleStore.setRuleEnabled(this, rule.getId(), checked);
                if (checked) {
                    // Keep the master switch off until the user explicitly enables it.
                    FxGkdAutomationRuntime.invalidateRules();
                } else {
                    FxGkdAutomationRuntime.invalidateRules();
                    if (FxGkdRuleStore.getRules(this).stream().noneMatch(FxGkdRule::getEnabled)) {
                        FxGkdRuleStore.setEnabled(this, false);
                        if (masterSwitch != null) masterSwitch.setChecked(false);
                    }
                }
                FxAccessibilityService.requestReconfigure(this);
                updateServiceState();
            });
            actions.addView(enabled, new LinearLayout.LayoutParams(0, -2, 1));
            actions.addView(action("删除", () -> new AlertDialog.Builder(this)
                    .setMessage("删除这条本地 GKD 规则？")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("删除", (d, which) -> {
                        FxGkdRuleStore.removeRule(this, rule.getId());
                        FxGkdAutomationRuntime.invalidateRules();
                        if (!FxGkdRuleStore.isEnabled(this) && masterSwitch != null) masterSwitch.setChecked(false);
                        FxAccessibilityService.requestReconfigure(this);
                        renderRules();
                        updateServiceState();
                    }).show()));
            row.addView(actions);
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
            params.setMargins(dp(12), dp(4), dp(12), dp(5));
            body.addView(row, params);
        }
    }
}
