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
    private String selectedGroupFilter = "全部分组";
    private String selectedStatusFilter = "全部状态";
    private String selectedTextFilter = "";
    private final java.util.Set<String> selectedRuleIds = new java.util.LinkedHashSet<>();

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
                "已接入 GKD-XA v1.4.8 selector/parser、本地规则组、排除选择器、单击/长按、冷却与本地导入导出。\n" +
                "当前规则仅在本机运行；上游订阅源、AI 服务商、云同步和上游备份格式仍未接入。", 0xff66727e, 13);
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

    private String decodeGkdRuleJson(byte[] bytes) {
        try {
            String decoded = java.nio.charset.StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                    .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                    .decode(java.nio.ByteBuffer.wrap(bytes)).toString();
            // Accept an optional UTF-8 BOM, but never replace malformed byte sequences.
            return !decoded.isEmpty() && decoded.charAt(0) == 0xFEFF
                    ? decoded.substring(1) : decoded;
        } catch (java.nio.charset.CharacterCodingException malformed) {
            throw new IllegalArgumentException("规则文件不是有效的 UTF-8 编码。", malformed);
        }
    }
    private void importRulesFromUri(Uri uri) {
        try (java.io.InputStream input = getContentResolver().openInputStream(uri);
             java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()) {
            if (input == null) throw new java.io.IOException("无法读取所选文件");
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            String json = decodeGkdRuleJson(output.toByteArray());
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

        EditText excludeInput = new EditText(this);
        excludeInput.setHint("排除选择器（可选；命中时整条规则跳过）");
        excludeInput.setSingleLine(false);
        excludeInput.setMinLines(1);
        excludeInput.setMaxLines(3);
        excludeInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        form.addView(excludeInput);

        EditText groupInput = new EditText(this);
        groupInput.setSingleLine(true);
        groupInput.setHint("规则组（最多 40 字，默认：默认）");
        form.addView(groupInput);

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
                    String excludeSelector = excludeInput.getText().toString().trim();
                    if (!excludeSelector.isEmpty() && !FxGkdSelectorEngine.compile(excludeSelector).isValid()) {
                        Toast.makeText(this, "排除选择器无效：" +
                                FxGkdSelectorEngine.compile(excludeSelector).getError(), Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdRule saved = FxGkdRuleStore.addRule(
                            this, pkg, selector, cooldownSeconds * 1000L,
                            actionInput.getSelectedItemPosition() == 1 ? "long_click" : "click",
                            groupInput.getText().toString(), excludeSelector);
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

        EditText excludeInput = new EditText(this);
        excludeInput.setHint("排除选择器（可选；命中时整条规则跳过）");
        excludeInput.setSingleLine(false);
        excludeInput.setMinLines(1);
        excludeInput.setMaxLines(3);
        excludeInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        excludeInput.setText(rule.getExcludeSelector());
        form.addView(excludeInput);

        EditText groupInput = new EditText(this);
        groupInput.setSingleLine(true);
        groupInput.setHint("规则组（最多 40 字）");
        groupInput.setText(rule.getGroup());
        form.addView(groupInput);

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
                    String excludeSelector = excludeInput.getText().toString().trim();
                    if (!excludeSelector.isEmpty() && !FxGkdSelectorEngine.compile(excludeSelector).isValid()) {
                        Toast.makeText(this, "排除选择器无效：" +
                                FxGkdSelectorEngine.compile(excludeSelector).getError(), Toast.LENGTH_LONG).show();
                        return;
                    }
                    FxGkdRule updated = FxGkdRuleStore.updateRule(
                            this, rule.getId(), selector, seconds * 1000L,
                            actionInput.getSelectedItemPosition() == 1 ? "long_click" : "click",
                            groupInput.getText().toString(), excludeSelector);
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

    private void moveRule(FxGkdRule rule, int direction) {
        if (!FxGkdRuleStore.moveRule(this, rule.getId(), direction)) {
            Toast.makeText(this, direction < 0 ? "规则已在最前面或调整失败。" : "规则已在最后面或调整失败。", Toast.LENGTH_SHORT).show();
            return;
        }
        FxGkdAutomationRuntime.invalidateRules();
        renderRules();
    }

    private void setGroupEnabled(String group, boolean enabled) {
        if (!FxGkdRuleStore.setGroupEnabled(this, group, enabled)) {
            Toast.makeText(this, "规则组状态保存失败。", Toast.LENGTH_LONG).show();
            return;
        }
        FxGkdAutomationRuntime.invalidateRules();
        syncMasterSwitch();
        FxAccessibilityService.requestReconfigure(this);
        renderRules();
        updateServiceState();
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
        List<FxGkdRule> rules = FxGkdRuleStore.getRules(this);
        TextView section = text("本地规则（仅保存在本机） · " + rules.size() + " 条", 0xff17212b, 16);
        section.setTypeface(null, android.graphics.Typeface.BOLD);
        body.addView(section);

        LinearLayout batchActions = new LinearLayout(this);
        batchActions.setOrientation(LinearLayout.HORIZONTAL);
        batchActions.setPadding(dp(12), dp(2), dp(12), dp(4));
        batchActions.addView(action("全选当前筛选", () -> {
            selectedRuleIds.clear();
            for (FxGkdRule item : rules) {
                if (isRuleVisible(item)) selectedRuleIds.add(item.getId());
            }
            renderRules();
        }), new LinearLayout.LayoutParams(0, -2, 1));
        batchActions.addView(action("清空选择", () -> {
            selectedRuleIds.clear();
            renderRules();
        }), new LinearLayout.LayoutParams(0, -2, 1));
        batchActions.addView(action("启用所选", () -> applyBatchEnabled(true)),
                new LinearLayout.LayoutParams(0, -2, 1));
        batchActions.addView(action("关闭所选", () -> applyBatchEnabled(false)),
                new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(batchActions);
        LinearLayout destructiveActions = new LinearLayout(this);
        destructiveActions.setOrientation(LinearLayout.HORIZONTAL);
        destructiveActions.setPadding(dp(12), 0, dp(12), dp(4));
        destructiveActions.addView(action("删除所选（" + selectedRuleIds.size() + "）", this::confirmBatchDelete),
                new LinearLayout.LayoutParams(0, -2, 1));
        destructiveActions.addView(action("整理重复规则", this::confirmDuplicateCleanup),
                new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(destructiveActions);

        if (rules.isEmpty()) {
            body.addView(text("还没有规则。添加目标应用包名和上游 GKD 选择器后，规则才会参与匹配。", 0xff66727e, 13));
            return;
        }

        java.util.TreeSet<String> groupNames = new java.util.TreeSet<>();
        for (FxGkdRule item : rules) groupNames.add(item.getGroup());
        java.util.ArrayList<String> groupOptions = new java.util.ArrayList<>();
        groupOptions.add("全部分组");
        groupOptions.addAll(groupNames);
        if (!groupOptions.contains(selectedGroupFilter)) selectedGroupFilter = "全部分组";

        LinearLayout filters = new LinearLayout(this);
        filters.setOrientation(LinearLayout.HORIZONTAL);
        filters.setPadding(dp(12), dp(2), dp(12), dp(6));
        Spinner groupFilter = new Spinner(this);
        groupFilter.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, groupOptions));
        groupFilter.setSelection(groupOptions.indexOf(selectedGroupFilter));
        filters.addView(groupFilter, new LinearLayout.LayoutParams(0, -2, 1));

        String[] statusOptions = new String[]{"全部状态", "仅启用", "仅关闭"};
        Spinner statusFilter = new Spinner(this);
        statusFilter.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, statusOptions));
        int statusIndex = java.util.Arrays.asList(statusOptions).indexOf(selectedStatusFilter);
        statusFilter.setSelection(statusIndex < 0 ? 0 : statusIndex);
        filters.addView(statusFilter, new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(filters);
        if (!"全部分组".equals(selectedGroupFilter)) {
            body.addView(action("重命名当前分组", this::renameSelectedGroup));
        }

        LinearLayout searchRow = new LinearLayout(this);
        searchRow.setOrientation(LinearLayout.HORIZONTAL);
        searchRow.setPadding(dp(12), dp(0), dp(12), dp(6));
        EditText searchInput = new EditText(this);
        searchInput.setSingleLine(true);
        searchInput.setTextSize(14);
        searchInput.setHint("筛选包名、选择器、排除条件或分组");
        searchInput.setText(selectedTextFilter);
        searchRow.addView(searchInput, new LinearLayout.LayoutParams(0, -2, 1));
        searchRow.addView(action("应用筛选", () -> {
            selectedTextFilter = searchInput.getText().toString().trim();
            renderRules();
        }));
        searchRow.addView(action("清除", () -> {
            selectedTextFilter = "";
            renderRules();
        }));
        body.addView(searchRow);

        android.widget.AdapterView.OnItemSelectedListener filterListener =
                new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override public void onItemSelected(android.widget.AdapterView<?> parent, View view,
                                                         int position, long id) {
                        String group = groupFilter.getSelectedItem().toString();
                        String status = statusFilter.getSelectedItem().toString();
                        if (!group.equals(selectedGroupFilter) || !status.equals(selectedStatusFilter)) {
                            selectedGroupFilter = group;
                            selectedStatusFilter = status;
                            renderRules();
                        }
                    }
                    @Override public void onNothingSelected(android.widget.AdapterView<?> parent) {}
                };
        groupFilter.setOnItemSelectedListener(filterListener);
        statusFilter.setOnItemSelectedListener(filterListener);

        int shown = 0;
        for (FxGkdRule rule : rules) {
            if (!"全部分组".equals(selectedGroupFilter) && !selectedGroupFilter.equals(rule.getGroup())) continue;
            if ("仅启用".equals(selectedStatusFilter) && !rule.getEnabled()) continue;
            if ("仅关闭".equals(selectedStatusFilter) && rule.getEnabled()) continue;
            if (!matchesTextFilter(rule, selectedTextFilter)) continue;
            shown++;
        }
        TextView count = text("当前筛选显示 " + shown + " / " + rules.size() + " 条规则", 0xff66727e, 12);
        body.addView(count);
        if (shown == 0) {
            body.addView(text("当前筛选条件下没有规则。可切换分组或启用状态筛选。", 0xff66727e, 13));
            return;
        }

        for (FxGkdRule rule : rules) {
            if (!"全部分组".equals(selectedGroupFilter) && !selectedGroupFilter.equals(rule.getGroup())) continue;
            if ("仅启用".equals(selectedStatusFilter) && !rule.getEnabled()) continue;
            if ("仅关闭".equals(selectedStatusFilter) && rule.getEnabled()) continue;
            if (!matchesTextFilter(rule, selectedTextFilter)) continue;
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(14), dp(8), dp(14), dp(8));
            row.setBackgroundColor(0xfff0f3f7);
            Switch selected = new Switch(this);
            selected.setText("选择此规则");
            selected.setChecked(selectedRuleIds.contains(rule.getId()));
            selected.setOnCheckedChangeListener((button, checked) -> {
                if (checked) selectedRuleIds.add(rule.getId());
                else selectedRuleIds.remove(rule.getId());
            });
            row.addView(selected);
            TextView label = text("规则组：" + rule.getGroup() + "\n" + rule.getPackageName() + "\n" + rule.getSelector()
                    + (rule.getExcludeSelector().isEmpty() ? "" : "\n排除：" + rule.getExcludeSelector())
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
            actions.addView(action("启用本组", () -> setGroupEnabled(rule.getGroup(), true)));
            actions.addView(action("关闭本组", () -> setGroupEnabled(rule.getGroup(), false)));
            actions.addView(action("上移", () -> moveRule(rule, -1)));
            actions.addView(action("下移", () -> moveRule(rule, 1)));
            actions.addView(action("编辑", () -> showEditRuleDialog(rule)));
            actions.addView(action("复制为草稿", () -> {
                FxGkdRule duplicate = FxGkdRuleStore.duplicateRule(this, rule.getId());
                if (duplicate == null) {
                    Toast.makeText(this, "复制失败：规则不存在、存储不可写或已达到 500 条上限。", Toast.LENGTH_LONG).show();
                    return;
                }
                selectedRuleIds.clear();
                FxGkdAutomationRuntime.invalidateRules();
                renderRules();
                Toast.makeText(this, "已复制为关闭状态的草稿，请检查后手动启用。", Toast.LENGTH_LONG).show();
            }));
            actions.addView(action("复制规则 JSON", () -> {
                String json = FxGkdRuleStore.exportRuleJson(this, rule.getId());
                if (json == null) {
                    Toast.makeText(this, "规则已不存在，无法导出。", Toast.LENGTH_LONG).show();
                    return;
                }
                android.content.ClipboardManager clipboard =
                        (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                if (clipboard == null) {
                    Toast.makeText(this, "系统剪贴板不可用。", Toast.LENGTH_LONG).show();
                    return;
                }
                clipboard.setPrimaryClip(android.content.ClipData.newPlainText("FX GKD Rule JSON", json));
                Toast.makeText(this, "单条规则 JSON 已复制；可粘贴到支持 FX-GKD-LOCAL-RULES 格式的文件中。", Toast.LENGTH_LONG).show();
            }));
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

    private void renameSelectedGroup() {
        final String oldName = selectedGroupFilter;
        if (oldName == null || oldName.trim().isEmpty() || "全部分组".equals(oldName)) return;
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setText(oldName);
        input.setSelection(input.getText().length());
        input.setHint("新分组名称（最多 40 字）");
        new AlertDialog.Builder(this)
                .setTitle("重命名 GKD 规则组")
                .setMessage("将当前分组内全部规则统一改名；规则顺序、选择器、动作、冷却时间及启用状态均保持不变。若目标名称已存在，将合并到同名分组。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) -> {
                    String newName = input.getText() == null ? "" : input.getText().toString().trim();
                    if (newName.isEmpty() || newName.length() > 40 || newName.contains("\\n") || newName.contains("\\r")) {
                        Toast.makeText(this, "分组名称不能为空，且最多 40 字。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    int changed = FxGkdRuleStore.renameGroup(this, oldName, newName);
                    if (changed < 0) {
                        Toast.makeText(this, "分组重命名失败，原规则保持不变。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    if (changed == 0) {
                        Toast.makeText(this, "名称未变化，或当前分组已不存在。", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    selectedGroupFilter = newName;
                    selectedRuleIds.clear();
                    FxGkdAutomationRuntime.invalidateRules();
                    FxAccessibilityService.requestReconfigure(this);
                    renderRules();
                    updateServiceState();
                    Toast.makeText(this, "已重命名 " + changed + " 条规则。", Toast.LENGTH_SHORT).show();
                }).show();
    }

    private boolean isRuleVisible(FxGkdRule rule) {
        if (!"全部分组".equals(selectedGroupFilter) && !selectedGroupFilter.equals(rule.getGroup())) return false;
        if ("仅启用".equals(selectedStatusFilter) && !rule.getEnabled()) return false;
        if ("仅关闭".equals(selectedStatusFilter) && rule.getEnabled()) return false;
        return matchesTextFilter(rule, selectedTextFilter);
    }

    private void applyBatchEnabled(boolean enabled) {
        int changed = FxGkdRuleStore.setRulesEnabled(this,
                new java.util.HashSet<>(selectedRuleIds), enabled);
        if (changed < 0) {
            Toast.makeText(this, "批量状态保存失败，原规则保持不变。", Toast.LENGTH_LONG).show();
            return;
        }
        if (changed == 0) {
            Toast.makeText(this, "请先选择规则。", Toast.LENGTH_SHORT).show();
            return;
        }
        selectedRuleIds.clear();
        FxGkdAutomationRuntime.invalidateRules();
        syncMasterSwitch();
        FxAccessibilityService.requestReconfigure(this);
        renderRules();
        updateServiceState();
        Toast.makeText(this, "已更新 " + changed + " 条规则。", Toast.LENGTH_SHORT).show();
    }

    private void confirmBatchDelete() {
        if (selectedRuleIds.isEmpty()) {
            Toast.makeText(this, "请先选择要删除的规则。", Toast.LENGTH_SHORT).show();
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("批量删除规则")
                .setMessage("确定删除已选择的 " + selectedRuleIds.size() + " 条规则？此操作不可撤销。")
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> {
                    int removed = FxGkdRuleStore.removeRules(this,
                            new java.util.HashSet<>(selectedRuleIds));
                    if (removed < 0) {
                        Toast.makeText(this, "批量删除失败，原规则保持不变。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    selectedRuleIds.clear();
                    FxGkdAutomationRuntime.invalidateRules();
                    syncMasterSwitch();
                    FxAccessibilityService.requestReconfigure(this);
                    renderRules();
                    updateServiceState();
                    Toast.makeText(this, "已删除 " + removed + " 条规则。", Toast.LENGTH_SHORT).show();
                }).show();
    }

    private void confirmDuplicateCleanup() {
        new AlertDialog.Builder(this)
                .setTitle("整理重复规则")
                .setMessage("按目标包名 + 主选择器识别重复项，保留列表中最靠前的一条；其余重复项将被删除。")
                .setNegativeButton("取消", null)
                .setPositiveButton("整理", (dialog, which) -> {
                    int removed = FxGkdRuleStore.removeDuplicateRules(this);
                    if (removed < 0) {
                        Toast.makeText(this, "重复规则整理失败，原规则保持不变。", Toast.LENGTH_LONG).show();
                        return;
                    }
                    selectedRuleIds.clear();
                    FxGkdAutomationRuntime.invalidateRules();
                    syncMasterSwitch();
                    FxAccessibilityService.requestReconfigure(this);
                    renderRules();
                    updateServiceState();
                    Toast.makeText(this, "已整理，删除重复规则 " + removed + " 条。", Toast.LENGTH_SHORT).show();
                }).show();
    }

    private boolean matchesTextFilter(FxGkdRule rule, String query) {
        if (query == null || query.trim().isEmpty()) return true;
        String needle = query.trim().toLowerCase(java.util.Locale.ROOT);
        return rule.getPackageName().toLowerCase(java.util.Locale.ROOT).contains(needle)
                || rule.getSelector().toLowerCase(java.util.Locale.ROOT).contains(needle)
                || rule.getExcludeSelector().toLowerCase(java.util.Locale.ROOT).contains(needle)
                || rule.getGroup().toLowerCase(java.util.Locale.ROOT).contains(needle);
    }
}
