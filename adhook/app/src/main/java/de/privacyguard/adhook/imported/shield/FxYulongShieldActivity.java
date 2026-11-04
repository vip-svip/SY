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
import android.widget.Toast;

/**
 * Yulong Shield 9.9.60 third-level hub inside FX.
 * Original feature pages are kept as separate fourth-level Activities.
 */
public final class FxYulongShieldActivity extends Activity {
    private LinearLayout body;
    private android.content.SharedPreferences shieldPrefs;
    private TextView runtimeStatus;
    private android.widget.Switch installScanSwitch;
    private android.widget.Switch contentScanSwitch;
    private android.widget.Switch autoRiskScanSwitch;
    private android.widget.Switch protectionSwitch;
    private android.widget.Switch overlayRescueSwitch;
    private android.widget.Switch volumeTriggerSwitch;
    private android.widget.Switch shakeTriggerSwitch;
    private android.widget.RadioGroup riskModeGroup;
    private android.widget.RadioButton directModeButton;
    private android.widget.RadioButton confirmModeButton;
    private android.widget.Button volumeKeyButton;
    private android.widget.Button volumeCountButton;
    private boolean refreshingControls;

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

    @Override protected void onResume() {
        super.onResume();
        refreshControlsFromSystem();
    }

    private boolean isAccessibilityEnabledInSystem() {
        String enabled = android.provider.Settings.Secure.getString(
                getContentResolver(),
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null || enabled.trim().isEmpty()) return false;
        String expectedPackage = getPackageName();
        String expectedClass =
                de.privacyguard.adhook.FxAccessibilityService.class.getName();
        for (String entry : enabled.split(":")) {
            android.content.ComponentName component =
                    android.content.ComponentName.unflattenFromString(entry);
            if (component != null
                    && expectedPackage.equals(component.getPackageName())
                    && expectedClass.equals(component.getClassName())) return true;
        }
        return false;
    }

    private boolean isAccessibilityServiceConnectedNow(boolean systemEnabled) {
        if (!systemEnabled || !de.privacyguard.adhook.FxAccessibilityService.isConnected()) {
            return false;
        }
        android.content.SharedPreferences prefs =
                getSharedPreferences("fx_accessibility", MODE_PRIVATE);
        return prefs.getBoolean("service_connected", false)
                && prefs.getInt("service_pid", -1) == android.os.Process.myPid();
    }

    private boolean hasNotificationPermission() {
        return android.os.Build.VERSION.SDK_INT < 33
                || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    @SuppressWarnings("deprecation")
    private boolean isServiceRunning(Class<?> serviceClass) {
        android.app.ActivityManager manager =
                (android.app.ActivityManager) getSystemService(ACTIVITY_SERVICE);
        if (manager == null) return false;
        try {
            for (android.app.ActivityManager.RunningServiceInfo info
                    : manager.getRunningServices(100)) {
                if (info != null && serviceClass.getName().equals(info.service.getClassName())
                        && getPackageName().equals(info.service.getPackageName())) return true;
            }
        } catch (RuntimeException ignored) { }
        return false;
    }

    private void refreshControlsFromSystem() {
        if (shieldPrefs == null) return;
        refreshingControls = true;
        if (installScanSwitch != null) installScanSwitch.setChecked(
                shieldPrefs.getBoolean("automatic_install_scan_enabled", true));
        if (contentScanSwitch != null) contentScanSwitch.setChecked(
                shieldPrefs.getBoolean("automatic_content_scan_enabled", false));
        if (autoRiskScanSwitch != null) autoRiskScanSwitch.setChecked(
                shieldPrefs.getBoolean("auto_block_on", true));
        if (protectionSwitch != null) protectionSwitch.setChecked(
                shieldPrefs.getBoolean("protect_on", false));
        if (overlayRescueSwitch != null) overlayRescueSwitch.setChecked(
                shieldPrefs.getBoolean("overlay_rescue_on", false));
        if (volumeTriggerSwitch != null) volumeTriggerSwitch.setChecked(
                shieldPrefs.getBoolean("volume_trigger_on", false));
        if (shakeTriggerSwitch != null) shakeTriggerSwitch.setChecked(
                shieldPrefs.getBoolean("shake_trigger_on", false));
        if (riskModeGroup != null && directModeButton != null && confirmModeButton != null) {
            riskModeGroup.check("confirm".equalsIgnoreCase(
                    shieldPrefs.getString("auto_block_mode", "direct"))
                    ? confirmModeButton.getId() : directModeButton.getId());
        }
        if (volumeKeyButton != null) {
            volumeKeyButton.setText("触发按键：" + ("up".equalsIgnoreCase(
                    shieldPrefs.getString("volume_trigger_key", "down")) ? "音量上键" : "音量下键"));
        }
        if (volumeCountButton != null) {
            int count = de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
                    .normalizeCount(shieldPrefs.getInt("volume_trigger_count", 3));
            volumeCountButton.setText("连续触发次数：" + count + " 次");
        }
        refreshingControls = false;

        if (runtimeStatus != null) {
            boolean usage = hasUsageAccess();
            boolean notifications = hasNotificationPermission();
            boolean accessibilityEnabled = isAccessibilityEnabledInSystem();
            boolean accessibilityConnected =
                    isAccessibilityServiceConnectedNow(accessibilityEnabled);
            boolean overlay = android.provider.Settings.canDrawOverlays(this);
            boolean protectionRunning = isServiceRunning(FxYulongProtectionService.class);
            boolean rescueRunning = isServiceRunning(FxYulongRescueOverlayService.class);
            boolean foregroundProtection = shieldPrefs.getBoolean("protect_on", false);
            boolean shakeRescue = shieldPrefs.getBoolean("shake_trigger_on", false);
            boolean autoRiskEnabled = shieldPrefs.getBoolean("auto_block_on", true);
            boolean volumeTriggerEnabled = shieldPrefs.getBoolean("volume_trigger_on", false);
            StringBuilder state = new StringBuilder();
            state.append("使用情况访问：").append(usage ? "已授权" : "未授权");
            state.append("\n通知权限：").append(notifications ? "已授权" : "未授权");
            state.append("\n无障碍系统开关：").append(accessibilityEnabled ? "已启用" : "未启用");
            state.append(" · FX 服务连接：").append(accessibilityConnected ? "已连接" : "未连接");
            state.append("\n悬浮窗权限：").append(overlay ? "已授权" : "未授权");
            state.append("\n守护 Service 进程：").append(protectionRunning ? "运行中" : "未运行");
            if (foregroundProtection) {
                state.append(" · 前台名单监测开关：已开启");
            } else if (shakeRescue && protectionRunning) {
                state.append(" · 仅为摇动救援运行，前台名单监测关闭");
            } else {
                state.append(" · 前台名单监测开关：关闭");
            }
            state.append("\n悬浮救援服务：").append(rescueRunning ? "运行中" : "未运行");
            if (!notifications && (foregroundProtection || shakeRescue)) {
                state.append("\n警告：通知权限已撤销，后台服务无法正常维持提醒。");
            }
            if (!usage && foregroundProtection) {
                state.append("\n警告：使用情况访问已撤销，前台名单监测不可工作；请重新授权。");
            }
            if (!accessibilityConnected && (autoRiskEnabled || volumeTriggerEnabled)) {
                state.append("\n提示：无障碍功能开关已保存，但系统服务未连接；前台自动扫描/音量键触发当前不可用。");
            }
            if (!overlay && shieldPrefs.getBoolean("overlay_rescue_on", false)) {
                state.append("\n提示：悬浮窗权限已撤销，已保存的救援入口无法显示。");
            }
            runtimeStatus.setText(state.toString());
        }
    }

    private void syncProtectionService(android.content.SharedPreferences prefs) {
        boolean protect = prefs.getBoolean("protect_on", false);
        boolean shake = prefs.getBoolean("shake_trigger_on", false);
        if (protect && !hasUsageAccess()) {
            // Usage Access gates foreground monitoring only; preserve the
            // independent accelerometer rescue trigger.
            prefs.edit().putBoolean("protect_on", false)
                    .putString("protect_restore_error", "usage access revoked").apply();
            protect = false;
        }
        Intent intent = new Intent(this, FxYulongProtectionService.class);
        if (protect || shake) {
            intent.setAction(FxYulongProtectionService.ACTION_START);
            if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(intent);
            else startService(intent);
        } else {
            stopService(intent);
        }
        FxYulongKeepAliveReceiver.refreshSchedule(this);
    }

    private boolean ensureNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT < 33
                || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                == android.content.pm.PackageManager.PERMISSION_GRANTED) return true;
        requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 9022);
        return false;
    }

    private boolean hasUsageAccess() {
        try {
            android.app.AppOpsManager appOps =
                    (android.app.AppOpsManager) getSystemService(APP_OPS_SERVICE);
            if (appOps == null) return false;
            int mode = appOps.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), getPackageName());
            return mode == android.app.AppOpsManager.MODE_ALLOWED;
        } catch (Throwable ignored) { return false; }
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
                "已迁入病毒名单、离线缓存、手动扫描、白名单/管控名单、安装后扫描、前台应用守护、Stellar 权限管理、开机恢复与 15 分钟低频恢复 Alarm。原版 2 分钟高频 watchdog、强制恢复无障碍权限和部分覆盖层自保护行为未照搬；FX 不会擅自修改系统权限或强停目标应用。");
        card("实时权限与服务状态", "从系统权限和实际运行服务读取；开关保存状态不等同于服务正在运行。", 
                runtimeStatus = text("正在读取系统权限与服务状态…", 12, 0xff617080, false));
        card("屏幕滤镜",
                "迁入标准浅色/暖色覆盖预设及亮度、色温叠加调节。滤镜使用不接收触摸的透明悬浮层，不读取屏幕图像；普通悬浮层不能对下层应用画面执行像素级对比度/饱和度变换。",
                action("打开屏幕滤镜设置", () -> startActivity(new Intent(this,
                        FxYulongScreenFilterActivity.class))));
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
                "保留原版应用选择、批量加入、移除与清空确认流程；开启实时守护后，黑名单应用进入前台时会收到提醒，白名单应用不会触发提醒。",
                action("打开管控列表", () -> startActivity(new Intent(this, BlacklistActivity.class))));
        card("Stellar 金龙权限管理",
                "保留原版 roro.stellar.manager 命令授权、逐应用能力作用域和始终允许清单；此页面属于安全护盾内部，不新增 FX 主导航标签。",
                action("打开 Stellar 特权管理", () -> startActivity(new Intent(this,
                        roro.stellar.manager.authorization.FxStellarManagerActivity.class))));
        card("批量风险应用清理",
                "勾选扫描结果后逐项打开 Android 系统卸载确认；不会自动强停、冻结或静默卸载。",
                action("扫描并进入批量清理", () -> startActivity(new Intent(this, FxYulongScanActivity.class))));
        card("风险应用警告",
                "先扫描并选择具体命中项，再进入带有包名、应用名和命中理由的风险提醒页；不会显示无目标的空白警告。",
                action("扫描应用并查看风险项", () -> startActivity(new Intent(this, FxYulongScanActivity.class))));
        card("应用签名与完整性",
                "展示 FX 当前安装包证书指纹；不复用原游龙 APK 固定证书强制退出校验。",
                action("查看当前签名指纹", () -> startActivity(new Intent(this, FxYulongIntegrityActivity.class))));
        shieldPrefs = getSharedPreferences("shield_prefs", MODE_PRIVATE);
        installScanSwitch = new android.widget.Switch(this);
        installScanSwitch.setText("安装新应用时自动扫描");
        installScanSwitch.setChecked(shieldPrefs.getBoolean("automatic_install_scan_enabled", true));
        installScanSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("automatic_install_scan_enabled", enabled).apply();
        });
        contentScanSwitch = new android.widget.Switch(this);
        contentScanSwitch.setText("同时启用 APK 内容特征扫描");
        contentScanSwitch.setChecked(shieldPrefs.getBoolean("automatic_content_scan_enabled", false));
        contentScanSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            shieldPrefs.edit().putBoolean("automatic_content_scan_enabled", enabled).apply();
        });
        card("安装后自动检测",
                "监听系统安装与更新广播，调用已迁入的 9.9.60 病毒名单扫描器。只提示命中结果，不会自动卸载、冻结或修改目标应用。",
                installScanSwitch, contentScanSwitch);
        autoRiskScanSwitch = new android.widget.Switch(this);
        autoRiskScanSwitch.setText("自动前台风险扫描");
        autoRiskScanSwitch.setChecked(shieldPrefs.getBoolean("auto_block_on", true));
        autoRiskScanSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("auto_block_on", enabled).apply();
            if (enabled && !de.privacyguard.adhook.FxAccessibilityService.isConnected()) {
                new android.app.AlertDialog.Builder(this)
                        .setTitle("需要启用 FX 无障碍服务")
                        .setMessage("前台自动扫描只使用系统提供的前台应用包名事件，不读取界面文字或点击控件。请在 Android 无障碍设置中手动启用 FX。")
                        .setNegativeButton("稍后", null)
                        .setPositiveButton("打开设置", (dialog, which) -> {
                            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
                            catch (Throwable ignored) { }
                        }).show();
            }
        });
        riskModeGroup = new android.widget.RadioGroup(this);
        directModeButton = new android.widget.RadioButton(this);
        directModeButton.setText("直接打开 Android 系统卸载确认（你仍需确认）");
        directModeButton.setId(android.view.View.generateViewId());
        confirmModeButton = new android.widget.RadioButton(this);
        confirmModeButton.setText("先查看 FX 风险详情，再决定处理");
        confirmModeButton.setId(android.view.View.generateViewId());
        riskModeGroup.addView(directModeButton);
        riskModeGroup.addView(confirmModeButton);
        String storedRiskMode = shieldPrefs.getString("auto_block_mode", "direct");
        riskModeGroup.check("confirm".equalsIgnoreCase(storedRiskMode) ? confirmModeButton.getId() : directModeButton.getId());
        riskModeGroup.setOnCheckedChangeListener((group, checkedId) -> {
            if (refreshingControls) return;
            shieldPrefs.edit().putString("auto_block_mode",
                    checkedId == confirmModeButton.getId() ? "confirm" : "direct").apply();
        });
        card("原版自动风险管控",
                "保留原版前台自动风险扫描和 direct/confirm 两种处理路径。direct 只会在你点击通知后打开 Android 系统卸载确认；FX 不会静默卸载、强停或冻结应用。前台扫描需要你主动启用 FX 无障碍服务。",
                autoRiskScanSwitch, directModeButton, confirmModeButton,
                action("打开无障碍服务设置", () -> {
                    try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
                    catch (Throwable ignored) { }
                }));
        String warning = shieldPrefs.getString("protect_last_warn_message", "尚无管控名单提醒");
        String warningTime = shieldPrefs.getString("protect_last_warn_time", "");
        int warningCount = shieldPrefs.getInt("protect_warn_count", 0);
        card("最近守护提醒",
                "累计提醒：" + warningCount
                        + (warningTime.isEmpty() ? "" : "\n最近提醒：" + warningTime)
                        + "\n" + warning);
        boolean recoveryEnabled = shieldPrefs.getBoolean("protect_on", false)
                || shieldPrefs.getBoolean("shake_trigger_on", false);
        card("开机与低频后台恢复",
                (recoveryEnabled
                        ? "已启用：系统启动时按用户保存的开关恢复；运行期间每 15 分钟安排一次低频检查。"
                        : "未启用：守护与救援触发均关闭时，不安排后台恢复 Alarm。")
                        + "\n只恢复用户主动开启的 FX 守护/救援服务，不会自动开启无障碍权限。",
                action("重新计算恢复计划", () -> {
                    FxYulongKeepAliveReceiver.refreshSchedule(this);
                    Toast.makeText(this, "后台恢复计划已重新计算。", Toast.LENGTH_SHORT).show();
                }));
        card("每日安全总结",
                "汇总当日管控名单提醒、新安装应用扫描数量与风险命中情况。",
                action("打开每日安全总结", () -> startActivity(new Intent(this,
                        FxYulongDailySummaryActivity.class))));
        String lastScan = shieldPrefs.getString("automatic_scan_last_result", "尚无自动扫描记录");
        String lastPackage = shieldPrefs.getString("automatic_scan_last_package", "");
        String lastTime = shieldPrefs.getString("automatic_scan_last_time", "");
        card("最近自动检测",
                lastScan + (lastPackage.isEmpty() ? "" : "\n包名：" + lastPackage)
                        + (lastTime.isEmpty() ? "" : "\n时间：" + lastTime),
                action("打开完整应用扫描", () -> startActivity(new Intent(this,
                        FxYulongScanActivity.class))));
        protectionSwitch = new android.widget.Switch(this);
        protectionSwitch.setText("实时应用守护（黑名单前台提醒）");
        protectionSwitch.setChecked(shieldPrefs.getBoolean("protect_on", false));
        protectionSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled) {
                if (!hasUsageAccess()) {
                    button.setChecked(false);
                    new android.app.AlertDialog.Builder(this)
                            .setTitle("需要使用情况访问权限")
                            .setMessage("实时守护需要读取当前前台应用包名，才能识别管控名单。只读取前台包名，不读取屏幕内容或输入内容。")
                            .setNegativeButton("稍后", null)
                            .setPositiveButton("打开设置", (dialog, which) -> {
                                try { startActivity(new Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)); }
                                catch (Throwable ignored) { }
                            }).show();
                    return;
                }
                if (!ensureNotificationPermission()) {
                    button.setChecked(false);
                    return;
                }
                shieldPrefs.edit().putBoolean("protect_on", true).apply();
                syncProtectionService(shieldPrefs);
            } else {
                shieldPrefs.edit().putBoolean("protect_on", false).apply();
                syncProtectionService(shieldPrefs);
            }
        });
        card("实时应用守护",
                "复用原版 blacklist_pkgs / whitelist_pkgs 规则，周期识别前台应用并向用户发出提醒。需要手动授予使用情况访问权限。为避免误操作，FX 不自动强停、冻结或卸载任何应用。",
                protectionSwitch,
                action("打开使用情况访问权限设置", () -> {
                    try { startActivity(new Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)); }
                    catch (Throwable ignored) { }
                }));
                overlayRescueSwitch = new android.widget.Switch(this);
        overlayRescueSwitch.setText("显示浮动救援入口");
        overlayRescueSwitch.setChecked(shieldPrefs.getBoolean("overlay_rescue_on", false));
        overlayRescueSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            if (enabled && !android.provider.Settings.canDrawOverlays(this)) {
                button.setChecked(false);
                new android.app.AlertDialog.Builder(this)
                        .setTitle("需要悬浮窗权限")
                        .setMessage("FX 只显示可点击的救援入口；不会读取其他应用界面、自动点击或遮挡输入框。请手动授权。")
                        .setNegativeButton("稍后", null)
                        .setPositiveButton("打开设置", (d, w) -> {
                            try { startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    android.net.Uri.parse("package:" + getPackageName()))); }
                            catch (Throwable ignored) { }
                        }).show();
                return;
            }
            shieldPrefs.edit().putBoolean("overlay_rescue_on", enabled).apply();
            Intent overlay = new Intent(this, FxYulongRescueOverlayService.class);
            if (enabled) {
                if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(overlay);
                else startService(overlay);
            } else stopService(overlay);
        });
        card("悬浮救援入口",
                "用户主动开启后在屏幕边缘显示小型 FX 入口；点击可返回安全护盾，不会自动操作其他应用。",
                overlayRescueSwitch,
                action("打开悬浮窗权限设置", () -> {
                    try { startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:" + getPackageName()))); }
                    catch (Throwable ignored) { }
                }));
        card("救援中心",
                "保留独立救援操作：查看最近前台应用、打开应用信息或系统卸载确认、恢复名单和关闭错误启用的守护/悬浮入口。",
                action("打开救援中心", () -> startActivity(new Intent(this,
                        FxYulongRescueActivity.class))));
        volumeTriggerSwitch = new android.widget.Switch(this);
        volumeTriggerSwitch.setText("音量键连续触发救援提醒（需启用 FX 无障碍服务）");
        volumeTriggerSwitch.setChecked(shieldPrefs.getBoolean("volume_trigger_on", false));
        volumeTriggerSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("volume_trigger_on", enabled).apply();
            if (enabled && !de.privacyguard.adhook.FxAccessibilityService.isConnected()) {
                int count = de.privacyguard.adhook.imported.shield.FxYulongVolumeTriggerSequence
                        .normalizeCount(shieldPrefs.getInt("volume_trigger_count", 3));
                String key = "up".equalsIgnoreCase(
                        shieldPrefs.getString("volume_trigger_key", "down")) ? "音量上键" : "音量下键";
                new android.app.AlertDialog.Builder(this).setTitle("需要 FX 无障碍服务")
                        .setMessage("已保存设置：连续按下" + key + " " + count
                                + " 次触发救援提醒。FX 不读取屏幕内容、不吞掉按键事件，也不会改变系统音量。"
                                + "请到系统无障碍设置手动启用 FX。")
                        .setNegativeButton("稍后", null)
                        .setPositiveButton("打开设置", (d, w) -> {
                            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
                            catch (Throwable ignored) { }
                        }).show();
            }
        });
        String initialVolumeKey = shieldPrefs.getString("volume_trigger_key", "down");
        volumeKeyButton = new android.widget.Button(this);
        volumeKeyButton.setAllCaps(false);
        volumeKeyButton.setText("触发按键：" + ("up".equalsIgnoreCase(initialVolumeKey) ? "音量上键" : "音量下键"));
        volumeKeyButton.setOnClickListener(v -> {
            String storedKey = shieldPrefs.getString("volume_trigger_key", "down");
            int checked = "up".equalsIgnoreCase(storedKey) ? 1 : 0;
            new android.app.AlertDialog.Builder(this)
                    .setTitle("选择救援触发按键")
                    .setSingleChoiceItems(new String[]{"音量下键", "音量上键"}, checked,
                            (dialog, which) -> {
                                String selected = which == 1 ? "up" : "down";
                                shieldPrefs.edit().putString("volume_trigger_key", selected).apply();
                                volumeKeyButton.setText("触发按键：" + (which == 1 ? "音量上键" : "音量下键"));
                                dialog.dismiss();
                            })
                    .setNegativeButton("取消", null).show();
        });
        int initialVolumeCount = de.privacyguard.adhook.imported.shield
                .FxYulongVolumeTriggerSequence.normalizeCount(
                        shieldPrefs.getInt("volume_trigger_count", 3));
        volumeCountButton = new android.widget.Button(this);
        volumeCountButton.setAllCaps(false);
        volumeCountButton.setText("连续触发次数：" + initialVolumeCount + " 次");
        volumeCountButton.setOnClickListener(v -> {
            android.widget.NumberPicker picker = new android.widget.NumberPicker(this);
            picker.setMinValue(de.privacyguard.adhook.imported.shield
                    .FxYulongVolumeTriggerSequence.MIN_COUNT);
            picker.setMaxValue(de.privacyguard.adhook.imported.shield
                    .FxYulongVolumeTriggerSequence.MAX_COUNT);
            picker.setWrapSelectorWheel(false);
            picker.setValue(de.privacyguard.adhook.imported.shield
                    .FxYulongVolumeTriggerSequence.normalizeCount(
                            shieldPrefs.getInt("volume_trigger_count", 3)));
            new android.app.AlertDialog.Builder(this)
                    .setTitle("连续按键次数（2–10 次）")
                    .setView(picker)
                    .setNegativeButton("取消", null)
                    .setPositiveButton("保存", (dialog, which) -> {
                        int selected = de.privacyguard.adhook.imported.shield
                                .FxYulongVolumeTriggerSequence.normalizeCount(picker.getValue());
                        shieldPrefs.edit().putInt("volume_trigger_count", selected).apply();
                        volumeCountButton.setText("连续触发次数：" + selected + " 次");
                    }).show();
        });
        shakeTriggerSwitch = new android.widget.Switch(this);
        shakeTriggerSwitch.setText("摇动设备触发救援提醒");
        shakeTriggerSwitch.setChecked(shieldPrefs.getBoolean("shake_trigger_on", false));
        shakeTriggerSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (refreshingControls) return;
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("shake_trigger_on", enabled).apply();
            syncProtectionService(shieldPrefs);
        });
        card("原版救援触发迁移",
                "音量键序列支持原版的音量上/下键选择与 2–10 次阈值（默认音量下键 3 次）；摇动触发使用加速度传感器。触发后只显示提醒，不会擅自强停、卸载应用或修改无障碍权限。",
                volumeTriggerSwitch, volumeKeyButton, volumeCountButton, shakeTriggerSwitch);
    }
}
