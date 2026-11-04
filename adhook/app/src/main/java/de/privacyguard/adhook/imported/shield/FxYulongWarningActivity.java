package de.privacyguard.adhook.imported.shield;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * User-confirmed Shield warning page.
 * It never automatically stops, disables, freezes, or uninstalls the target app.
 */
public final class FxYulongWarningActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String PREFS = "shield_prefs";
    private static final String WHITELIST_KEY = "whitelist_pkgs";
    private static final int MAX_PACKAGE_NAME = 255;
    private static final int MAX_WHITELIST_CHARS = 1024 * 1024;
    private static final String STATE_SCROLL_Y = "fx_yulong_warning_scroll_y";

    private String packageName = "";
    private String appLabel = "";
    private String reason = "";
    private String severity = "UNKNOWN";
    private String sourceLabel = "";
    private String matchedEntry = "";
    private TextView packageState;
    private Button addWhitelistButton;
    private Button uninstallButton;
    private ScrollView warningScroll;
    private boolean targetInstalled;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(null, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(6), dp(4), dp(6));
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent intent = getIntent();
        packageName = safe(intent == null ? null : intent.getStringExtra("package_name"), MAX_PACKAGE_NAME);
        appLabel = safe(intent == null ? null : intent.getStringExtra("app_label"), 256);
        reason = safe(intent == null ? null : intent.getStringExtra("reason"), 1024);
        String incomingSeverity = safe(intent == null ? null : intent.getStringExtra("severity"), 24)
                .toUpperCase(java.util.Locale.ROOT);
        if ("CERTAIN".equals(incomingSeverity) || "SUSPECT".equals(incomingSeverity)) {
            severity = incomingSeverity;
        }
        sourceLabel = safe(intent == null ? null : intent.getStringExtra("source_label"), 256);
        matchedEntry = safe(intent == null ? null : intent.getStringExtra("matched_entry"), 512);
        if (appLabel.isEmpty()) appLabel = packageName.isEmpty() ? "未知应用" : packageName;

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(button("‹ 返回安全护盾", this::finish));
        header.addView(text("风险应用详情", 19, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        warningScroll = new ScrollView(this);
        warningScroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(8), dp(14), dp(20));
        warningScroll.addView(body);
        root.addView(warningScroll, new LinearLayout.LayoutParams(-1, 0, 1));

        String severityLabel;
        int severityColor;
        String advice;
        if ("CERTAIN".equals(severity)) {
            severityLabel = "确定风险命中";
            severityColor = 0xffa32620;
            advice = "本地病毒库将此应用归类为确定风险命中。仍请检查命中原因、应用来源和版本；卸载操作只会打开 Android 系统确认界面，不会自动执行。";
        } else if ("SUSPECT".equals(severity)) {
            severityLabel = "可能风险 / 可疑命中";
            severityColor = 0xff8a5b12;
            advice = "该结果属于可疑匹配，不代表已确认恶意。不要仅凭应用名称或单条规则自动卸载；请先核实应用来源和命中原因。";
        } else {
            severityLabel = "风险级别未提供";
            severityColor = 0xff66727e;
            advice = "本页面没有收到有效风险等级。请返回扫描结果重新打开详情；在确认来源前，不要仅凭此提醒卸载应用。";
        }

        body.addView(text(severityLabel, 18, severityColor, true));
        body.addView(text(appLabel, 17, 0xff17212b, true));
        body.addView(text(packageName, 12, 0xff617080, false));
        packageState = text("正在核实应用安装状态…", 12, 0xff617080, false);
        body.addView(packageState);
        body.addView(text("风险原因", 14, 0xff17212b, true));
        body.addView(text(reason.isEmpty() ? "未提供详细命中原因。" : reason,
                14, 0xff334155, false));
        body.addView(text("命中来源：" + (sourceLabel.isEmpty() ? "未提供" : sourceLabel),
                12, 0xff526273, false));
        if (!matchedEntry.isEmpty()) {
            body.addView(text("匹配条目 / 特征族：" + matchedEntry, 12, 0xff526273, false));
        }
        body.addView(text("当前名单格式不提供稳定规则 ID 或数据库版本号；此处展示可核实的列表来源与实际匹配条目，不虚构规则编号。",
                11, 0xff75808a, false));
        body.addView(text(advice, 12, 0xff8a5b12, false));

        addWhitelistButton = button("加入白名单并停止后续提醒", this::trust);
        body.addView(addWhitelistButton);
        uninstallButton = button("打开 Android 系统卸载确认", this::uninstall);
        body.addView(uninstallButton);
        body.addView(button("稍后处理", this::finish));

        setContentViewWithNativeTabs(root, 5);
        if (state != null) {
            final int restoreY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            warningScroll.post(() -> warningScroll.scrollTo(0, restoreY));
        }
        refreshTargetAvailability();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        if (warningScroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, warningScroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    @Override protected void onResume() {
        super.onResume();
        refreshTargetAvailability();
    }

    private void refreshTargetAvailability() {
        targetInstalled = false;
        if (validPackageName()) {
            try {
                getPackageManager().getApplicationInfo(packageName, 0);
                targetInstalled = true;
            } catch (PackageManager.NameNotFoundException | SecurityException missingOrHidden) {
                targetInstalled = false;
            } catch (RuntimeException lookupFailure) {
                targetInstalled = false;
            }
        }
        if (packageState != null) {
            packageState.setText(!validPackageName()
                    ? "包名无效：已禁用白名单和卸载操作。"
                    : targetInstalled ? "应用当前已安装。" : "应用当前不存在或系统不允许查询；请重新扫描。");
            packageState.setTextColor(targetInstalled ? 0xff607080 : 0xffa32620);
        }
        boolean validRisk = "CERTAIN".equals(severity) || "SUSPECT".equals(severity);
        if (addWhitelistButton != null) addWhitelistButton.setEnabled(validPackageName() && targetInstalled);
        if (uninstallButton != null) uninstallButton.setEnabled(validPackageName() && validRisk && targetInstalled);
    }

    private String safe(String value, int maxChars) {
        if (value == null) return "";
        String trimmed = value.trim();
        return trimmed.length() > maxChars ? trimmed.substring(0, maxChars) : trimmed;
    }

    private boolean validPackageName() {
        return packageName != null && packageName.length() <= MAX_PACKAGE_NAME
                && packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    private void showMessage(String title, String message) {
        if (isFinishing() || isDestroyed()) return;
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void trust() {
        if (!validPackageName()) {
            showMessage("无法加入白名单", "目标包名无效，未更改白名单。");
            return;
        }

        try {
            ApplicationInfo application = getPackageManager().getApplicationInfo(packageName, 0);
            // The original whitelist manager deliberately excludes system apps.
            // Match that rule here so the detail page cannot report a save that
            // the whitelist screen will remove on its next refresh.
            if ((application.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                showMessage("系统应用不加入用户白名单",
                        "当前白名单只维护用户应用。该应用被 Android 标记为系统应用，未修改白名单。");
                return;
            }
        } catch (PackageManager.NameNotFoundException removed) {
            showMessage("目标应用已不存在", "应用可能已卸载或更新；请重新扫描后再处理。");
            return;
        } catch (RuntimeException lookupFailure) {
            showMessage("无法核实目标应用", "Android 未允许 FX 读取该应用信息；白名单保持不变，请检查应用可见性和系统状态后重试。");
            return;
        }

        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        final String raw;
        try {
            raw = preferences.getString(WHITELIST_KEY, "");
        } catch (RuntimeException unreadablePreference) {
            showMessage("白名单数据异常",
                    "现有白名单无法按文本读取，可能存在损坏或类型不匹配。为避免覆盖旧配置，本次没有修改任何白名单数据。");
            return;
        }
        String storedWhitelist = raw == null ? "" : raw;
        if (storedWhitelist.length() > MAX_WHITELIST_CHARS) {
            showMessage("白名单数据异常", "现有白名单超过安全读取上限。为避免覆盖数据，本次没有修改。");
            return;
        }

        if (!FxYulongWhitelistPolicy.isWellFormed(storedWhitelist)) {
            showMessage("白名单数据异常",
                    "现有白名单含无效条目或超过安全上限。为避免静默丢失旧配置，本次没有修改任何白名单数据。");
            return;
        }
        Set<String> packages = new LinkedHashSet<>(FxYulongWhitelistPolicy.parse(storedWhitelist));
        if (packages.contains(packageName)) {
            showMessage("已在白名单中", appLabel + " 已经在用户白名单里，无需重复添加。");
            return;
        }
        packages.add(packageName);

        // Use the same bounded canonical serializer as the whitelist manager and scanner.
        // Adding one more entry must not push a valid 10,000-item / 1 MiB list over its
        // limit and make the entire whitelist unreadable on the next scan.
        String serialized = FxYulongWhitelistPolicy.serialize(packages);
        if (serialized == null) {
            showMessage("白名单已达到安全上限",
                    "加入该应用后将超过 " + FxYulongWhitelistPolicy.MAX_ENTRIES
                            + " 个条目或 " + FxYulongWhitelistPolicy.MAX_RAW_CHARS
                            + " 个字符。原白名单保持不变，请先移除无用条目后重试。");
            return;
        }
        boolean saved = preferences.edit()
                .putString(WHITELIST_KEY, serialized)
                .commit();
        if (!saved) {
            showMessage("保存失败", "白名单没有确认写入磁盘；原配置保持不变，请稍后重试。");
            return;
        }

        new AlertDialog.Builder(this)
                .setTitle("已加入白名单")
                .setMessage(appLabel + " 已保存到本机用户白名单，后续扫描将按白名单规则处理。")
                .setPositiveButton("知道了", (dialog, which) -> finish())
                .show();
    }

    private void uninstall() {
        if (!validPackageName() || !("CERTAIN".equals(severity) || "SUSPECT".equals(severity))) {
            showMessage("无法打开卸载界面", "目标包名或风险等级无效。请返回扫描结果重新打开详情。");
            return;
        }
        if (!targetInstalled) {
            refreshTargetAvailability();
            showMessage("目标应用不可用", "应用当前不存在或系统不允许查询；请重新扫描后再处理。");
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("再次确认")
                .setMessage("将打开 Android 系统卸载界面。FX 不会自动确认卸载，也不会在后台静默删除应用。")
                .setNegativeButton("取消", null)
                .setPositiveButton("继续", (dialog, which) -> {
                    try {
                        getPackageManager().getApplicationInfo(packageName, 0);
                        startActivity(new Intent(Intent.ACTION_DELETE,
                                Uri.parse("package:" + packageName)));
                    } catch (Throwable error) {
                        showMessage("无法打开系统卸载界面",
                                "系统返回错误：" + error.getClass().getSimpleName());
                    }
                })
                .show();
    }
}
