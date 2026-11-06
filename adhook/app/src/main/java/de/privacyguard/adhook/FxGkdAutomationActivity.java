package de.privacyguard.adhook;

import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
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
import android.widget.Spinner;
import android.widget.ArrayAdapter;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.List;

/** FX Hook tab surface for explicitly scoped, local GKD selector rules. */
public final class FxGkdAutomationActivity extends FxNativeTabActivity {
    private static final int REQUEST_EXPORT_GKD_RULES = 7421;
    private static final int REQUEST_IMPORT_GKD_RULES = 7422;
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
                "已接入 GKD-XA v1.4.8 原生 selector/parser、限额 Accessibility 节点快照、本地规则匹配与 Click 执行。\n" +
                "尚未接入：上游订阅源、规则组/排除项、AI 服务商、触发历史、云同步与上游备份格式。", 0xff66727e, 13);
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
        masterSwitch.setOnCheckedChangeListener((button, checked) ->
                updateMasterEnabled((Switch) button, checked));
        body.addView(masterSwitch, new LinearLayout.LayoutParams(-1, -2));

        body.addView(action("＋ 添加本地选择器规则", this::showAddRuleDialog));
        LinearLayout transferActions = new LinearLayout(this);
        transferActions.setOrientation(LinearLayout.HORIZONTAL);
        transferActions.addView(action("导入本地规则", this::openImportRulesPicker),
                new LinearLayout.LayoutParams(0, -2, 1));
        transferActions.addView(action("导出本地规则", this::openExportRulesPicker),
                new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(transferActions, new LinearLayout.LayoutParams(-1, -2));
        renderRules();
        updateServiceState();
        setContentViewWithNativeTabs(root, 4);
    }

    @Override protected void onResume() {
        super.onResume();
        updateServiceState();
    }

    private void openImportRulesPicker() {
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("application/json");
        picker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivityForResult(picker, REQUEST_IMPORT_GKD_RULES);
        } catch (Exception error) {
            Toast.makeText(this, "无法打开规则导入选择器：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void openExportRulesPicker() {
        Intent picker = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("application/json");
        picker.putExtra(Intent.EXTRA_TITLE, "FX-GKD-Local-Rules.json");
        picker.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        try {
            startActivityForResult(picker, REQUEST_EXPORT_GKD_RULES);
        } catch (Exception error) {
            Toast.makeText(this, "无法打开规则导出选择器：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        if (requestCode == REQUEST_EXPORT_GKD_RULES) {
            exportRulesToUri(uri);
        } else if (requestCode == REQUEST_IMPORT_GKD_RULES) {
            importRulesFromUri(uri);
        }
    }

    private void exportRulesToUri(Uri uri) {
        final String json = FxGkdRuleStore.exportJson(this);
        try (java.io.OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
            if (output == null) throw new java.io.IOException("无法打开目标文件");
            output.write(json.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            output.flush();
            Toast.makeText(this, "本地规则已导出；导入到其他设备时所有规则均默认为关闭。",
                    Toast.LENGTH_LONG).show();
        } catch (Exception error) {
            Toast.makeText(this, "规则导出失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void importRulesFromUri(Uri uri) {
        try (java.io.InputStream input = getContentResolver().openInputStream(uri);
             java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()) {
            if (input == null) throw new java.io.IOException("无法读取所选文件");
            byte[] buffer = new byte[8192];
            int count;
            final int maximumBytes = 1024 * 1024;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() > maximumBytes - count) {
                    throw new java.io.IOException("规则文件超过 1 MiB 限制，已停止读取。");
                }
                output.write(buffer, 0, count);
            }
            String json = new String(output.toByteArray(), java.nio.charset.StandardCharsets.UTF_8);
            FxGkdImportResult result = FxGkdRuleStore.importJson(this, json);
            if (result.getError() != null) {
                Toast.makeText(this, "规则导入未完成：" + result.getError(), Toast.LENGTH_LONG).show();
                return;
            }
            FxGkdAutomationRuntime.invalidateRules();
            FxAccessibilityService.requestReconfigure(this);
            renderRules();
            syncMasterSwitch();
            updateServiceState();
            new AlertDialog.Builder(this)
                    .setTitle("规则导入完成")
                    .setMessage("新增 " + result.getImported() + " 条，跳过 " + result.getSkipped()
                            + " 条。所有新导入规则均已关闭；请逐条检查后手动启用。")
                    .setPositiveButton("知道了", null)
                    .show();
        } catch (Exception error) {
            Toast.makeText(this, "规则导入失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
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
        form.addView(action("从已安装的用户应用中选择", () -> showPackagePicker(packageInput)));

        EditText selectorInput = new EditText(this);
        selectorInput.setHint("GKD 选择器，例如 [text='Skip']");
        selectorInput.setSingleLine(false);
        selectorInput.setMinLines(2);
        selectorInput.setMaxLines(4);
        selectorInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        form.addView(selectorInput);

        Spinner actionInput = new Spinner(this);
        actionInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new String[]{"单击", "长按"}));
        form.addView(actionInput);

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
                            this, pkg, selector, cooldownSeconds * 1000L,
                            actionInput.getSelectedItemPosition() == 1 ? "long_click" : "click");
                    if (saved == null) {
                        Toast.makeText(this, "保存失败：请检查规则格式或本地存储是否可写。", Toast.LENGTH_LONG).show();
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

    private void showPackagePicker(EditText packageInput) {
        final List<ApplicationInfo> candidates = new java.util.ArrayList<>();
        try {
            for (ApplicationInfo info : getPackageManager().getInstalledApplications(0)) {
                if (isInstalledUserApplication(info.packageName)) candidates.add(info);
            }
        } catch (RuntimeException failure) {
            Toast.makeText(this, "读取已安装应用失败：" + failure.getMessage(), Toast.LENGTH_LONG).show();
            return;
        }
        if (candidates.isEmpty()) {
            Toast.makeText(this, "没有找到可配置的普通用户应用。", Toast.LENGTH_LONG).show();
            return;
        }
        candidates.sort((left, right) -> getPackageManager().getApplicationLabel(left).toString()
                .compareToIgnoreCase(getPackageManager().getApplicationLabel(right).toString()));
        CharSequence[] labels = new CharSequence[candidates.size()];
        for (int index = 0; index < candidates.size(); index++) {
            ApplicationInfo info = candidates.get(index);
            labels[index] = getPackageManager().getApplicationLabel(info) + "\n" + info.packageName;
        }
        new AlertDialog.Builder(this)
                .setTitle("选择 GKD 规则目标应用")
                .setItems(labels, (dialog, which) ->
                        packageInput.setText(candidates.get(which).packageName))
                .setNegativeButton("取消", null)
                .show();
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

    private void updateMasterEnabled(Switch control, boolean enabled) {
        if (!FxGkdRuleStore.setEnabled(this, enabled)) {
            control.setOnCheckedChangeListener(null);
            control.setChecked(!enabled);
            control.setOnCheckedChangeListener((button, checked) ->
                    updateMasterEnabled(control, checked));
            Toast.makeText(this,
                    enabled ? "请先添加至少一条有效规则。" : "GKD 设置保存失败。",
                    Toast.LENGTH_LONG).show();
            return;
        }
        FxGkdAutomationRuntime.invalidateRules();
        FxAccessibilityService.requestReconfigure(this);
        updateServiceState();
        Toast.makeText(this, enabled ? "GKD 本地规则已启用" : "GKD 自动化已关闭",
                Toast.LENGTH_SHORT).show();
    }

    private void showEditRuleDialog(FxGkdRule rule) {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(8), dp(20), dp(4));

        EditText selectorInput = new EditText(this);
        selectorInput.setHint("GKD 选择器");
        selectorInput.setSingleLine(false);
        selectorInput.setMinLines(2);
        selectorInput.setMaxLines(4);
        selectorInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        selectorInput.setText(rule.getSelector());
        form.addView(selectorInput);

        Spinner actionInput = new Spinner(this);
        actionInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new String[]{"单击", "长按"}));
        actionInput.setSelection("long_click".equals(rule.getAction()) ? 1 : 0);
        form.addView(actionInput);

        EditText cooldownInput = new EditText(this);
        cooldownInput.setSingleLine(true);
        cooldownInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        cooldownInput.setHint("规则冷却秒数（1–60）");
        cooldownInput.setText(String.valueOf(rule.getCooldownMillis() / 1000L));
        form.addView(cooldownInput);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("编辑 GKD 规则")
                .setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存修改", null)
                .create();
        dialog.setOnShowListener(ignored ->
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                    long seconds;
                    try {
                        seconds = Long.parseLong(cooldownInput.getText().toString().trim());
                    } catch (NumberFormatException invalid) {
                        Toast.makeText(this, "冷却秒数无效。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    if (seconds < 1L || seconds > 60L) {
                        Toast.makeText(this, "冷却秒数必须在 1 到 60 秒之间。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    String selector = selectorInput.getText().toString().trim();
                    FxGkdSelectorCompilation compiled = FxGkdSelectorEngine.compile(selector);
                    if (!compiled.isValid()) {
                        Toast.makeText(this, "选择器无效：" + compiled.getError(), Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdRule updated = FxGkdRuleStore.updateRule(
                            this, rule.getId(), selector, seconds * 1000L,
                            actionInput.getSelectedItemPosition() == 1 ? "long_click" : "click");
                    if (updated == null) {
                        Toast.makeText(this, "保存失败，原规则保持不变。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdAutomationRuntime.invalidateRules();
                    FxAccessibilityService.requestReconfigure(this);
                    renderRules();
                    dialog.dismiss();
                    Toast.makeText(this, "GKD 规则已更新。", Toast.LENGTH_SHORT).show();
                }));
        dialog.show();
    }

    private void updateRuleEnabled(FxGkdRule rule, Switch control, boolean enabled) {
        if (!FxGkdRuleStore.setRuleEnabled(this, rule.getId(), enabled)) {
            control.setOnCheckedChangeListener(null);
            control.setChecked(!enabled);
            control.setOnCheckedChangeListener((button, checked) ->
                    updateRuleEnabled(rule, control, checked));
            Toast.makeText(this, "规则状态保存失败，已恢复原状态。", Toast.LENGTH_LONG).show();
            return;
        }
        FxGkdAutomationRuntime.invalidateRules();
        syncMasterSwitch();
        FxAccessibilityService.requestReconfigure(this);
        updateServiceState();
    }

    private void syncMasterSwitch() {
        if (masterSwitch == null) return;
        masterSwitch.setOnCheckedChangeListener(null);
        masterSwitch.setChecked(FxGkdRuleStore.isEnabled(this));
        masterSwitch.setOnCheckedChangeListener((button, checked) ->
                updateMasterEnabled(masterSwitch, checked));
    }

    private void renderRules() {
        if (body == null) return;
        // Keep the two notice cards, service status, permission button,
        // master switch, add-rule and import/export controls stay in place.
        while (body.getChildCount() > 7) body.removeViewAt(7);
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
                    + "\n动作：" + ("long_click".equals(rule.getAction()) ? "长按" : "单击")
                    + " · 冷却：" + (rule.getCooldownMillis() / 1000L) + " 秒",
                    0xff17212b, 13);
            row.addView(label);

            LinearLayout actions = new LinearLayout(this);
            actions.setGravity(Gravity.CENTER_VERTICAL);
            Switch enabled = new Switch(this);
            enabled.setText("启用");
            enabled.setChecked(rule.getEnabled());
            enabled.setOnCheckedChangeListener((button, checked) ->
                    updateRuleEnabled(rule, (Switch) button, checked));
            actions.addView(enabled, new LinearLayout.LayoutParams(0, -2, 1));
            actions.addView(action("编辑", () -> showEditRuleDialog(rule)));
            actions.addView(action("删除", () -> new AlertDialog.Builder(this)
                    .setMessage("删除这条本地 GKD 规则？")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("删除", (d, which) -> {
                        if (!FxGkdRuleStore.removeRule(this, rule.getId())) {
                            Toast.makeText(this, "规则删除失败，原数据保持不变。", Toast.LENGTH_LONG).show();
                            return;
                        }
                        FxGkdAutomationRuntime.invalidateRules();
                        syncMasterSwitch();
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
