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

    private void syncProtectionService(android.content.SharedPreferences prefs) {
        boolean protect = prefs.getBoolean("protect_on", false);
        boolean shake = prefs.getBoolean("shake_trigger_on", false);
        if (protect && !hasUsageAccess()) return;
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
                "已迁入原版病毒名单匹配、离线缓存、手动扫描、白名单与管控名单、安装后扫描、前台应用守护与 Stellar 权限管理。原版持续进程 watchdog、KeepAliveAlarm、自保护覆盖层救援及部分权限降级逻辑仍在迁移。");
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
        card("Stellar 金龙权限管理",
                "保留原版 roro.stellar.manager 命令授权、逐应用能力作用域和始终允许清单；此页面属于安全护盾内部，不新增 FX 主导航标签。",
                action("打开 Stellar 特权管理", () -> startActivity(new Intent(this,
                        roro.stellar.manager.authorization.FxStellarManagerActivity.class))));
        card("批量风险应用清理",
                "勾选扫描结果后逐项打开 Android 系统卸载确认；不会自动强停、冻结或静默卸载。",
                action("扫描并进入批量清理", () -> startActivity(new Intent(this, FxYulongScanActivity.class))));
        card("风险应用警告",
                "查看风险命中原因；可加入白名单或手动打开系统卸载确认。",
                action("打开风险提醒页", () -> startActivity(new Intent(this, FxYulongWarningActivity.class))));
        card("应用签名与完整性",
                "展示 FX 当前安装包证书指纹；不复用原游龙 APK 固定证书强制退出校验。",
                action("查看当前签名指纹", () -> startActivity(new Intent(this, FxYulongIntegrityActivity.class))));
        android.content.SharedPreferences shieldPrefs =
                getSharedPreferences("shield_prefs", MODE_PRIVATE);
        android.widget.Switch installScan = new android.widget.Switch(this);
        installScan.setText("安装新应用时自动扫描");
        installScan.setChecked(shieldPrefs.getBoolean("automatic_install_scan_enabled", false));
        installScan.setOnCheckedChangeListener((button, enabled) -> {
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("automatic_install_scan_enabled", enabled).apply();
        });
        android.widget.Switch contentScan = new android.widget.Switch(this);
        contentScan.setText("同时启用 APK 内容特征扫描");
        contentScan.setChecked(shieldPrefs.getBoolean("automatic_content_scan_enabled", false));
        contentScan.setOnCheckedChangeListener((button, enabled) ->
                shieldPrefs.edit().putBoolean("automatic_content_scan_enabled", enabled).apply());
        card("安装后自动检测",
                "监听系统安装与更新广播，调用已迁入的 9.9.60 病毒名单扫描器。只提示命中结果，不会自动卸载、冻结或修改目标应用。",
                installScan, contentScan);
        String protectionState = shieldPrefs.getBoolean("protect_service_running", false)
                ? "实时守护服务正在运行"
                : (shieldPrefs.getBoolean("protect_on", false) ? "守护开关已保存，服务当前未运行" : "实时守护未开启");
        String warning = shieldPrefs.getString("protect_last_warn_message", "尚无管控名单提醒");
        String warningTime = shieldPrefs.getString("protect_last_warn_time", "");
        int warningCount = shieldPrefs.getInt("protect_warn_count", 0);
        card("实时守护状态",
                protectionState + "\\n累计提醒：" + warningCount
                        + (warningTime.isEmpty() ? "" : "\\n最近提醒：" + warningTime)
                        + "\\n" + warning);
        card("每日安全总结",
                "汇总当日管控名单提醒、新安装应用扫描数量与风险命中情况。",
                action("打开每日安全总结", () -> startActivity(new Intent(this,
                        FxYulongDailySummaryActivity.class))));
        String lastScan = shieldPrefs.getString("automatic_scan_last_result", "尚无自动扫描记录");
        String lastPackage = shieldPrefs.getString("automatic_scan_last_package", "");
        String lastTime = shieldPrefs.getString("automatic_scan_last_time", "");
        card("最近自动检测",
                lastScan + (lastPackage.isEmpty() ? "" : "\\n包名：" + lastPackage)
                        + (lastTime.isEmpty() ? "" : "\\n时间：" + lastTime),
                action("打开完整应用扫描", () -> startActivity(new Intent(this,
                        FxYulongScanActivity.class))));
        android.widget.Switch protection = new android.widget.Switch(this);
        protection.setText("实时应用守护（黑名单前台提醒）");
        protection.setChecked(shieldPrefs.getBoolean("protect_on", false));
        protection.setOnCheckedChangeListener((button, enabled) -> {
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
                protection,
                action("打开使用情况访问权限设置", () -> {
                    try { startActivity(new Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)); }
                    catch (Throwable ignored) { }
                }));
                android.widget.Switch overlayRescue = new android.widget.Switch(this);
        overlayRescue.setText("显示浮动救援入口");
        overlayRescue.setChecked(shieldPrefs.getBoolean("overlay_rescue_on", false));
        overlayRescue.setOnCheckedChangeListener((button, enabled) -> {
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
                overlayRescue,
                action("打开悬浮窗权限设置", () -> {
                    try { startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:" + getPackageName()))); }
                    catch (Throwable ignored) { }
                }));
android.widget.Switch volumeTrigger = new android.widget.Switch(this);
        volumeTrigger.setText("音量上键连续触发救援提醒（需启用 FX 无障碍服务）");
        volumeTrigger.setChecked(shieldPrefs.getBoolean("volume_trigger_on", false));
        volumeTrigger.setOnCheckedChangeListener((button, enabled) -> {
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("volume_trigger_on", enabled).apply();
            if (enabled && !de.privacyguard.adhook.FxAccessibilityService.isConnected()) {
                new android.app.AlertDialog.Builder(this).setTitle("需要 FX 无障碍服务")
                        .setMessage("音量键触发只监听连续六次音量上键，不读取屏幕内容，也不吞掉按键事件。请到系统无障碍设置手动启用 FX。")
                        .setNegativeButton("稍后", null)
                        .setPositiveButton("打开设置", (d, w) -> {
                            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
                            catch (Throwable ignored) { }
                        }).show();
            }
        });
        android.widget.Switch shakeTrigger = new android.widget.Switch(this);
        shakeTrigger.setText("摇动设备触发救援提醒");
        shakeTrigger.setChecked(shieldPrefs.getBoolean("shake_trigger_on", false));
        shakeTrigger.setOnCheckedChangeListener((button, enabled) -> {
            if (enabled && !ensureNotificationPermission()) {
                button.setChecked(false);
                return;
            }
            shieldPrefs.edit().putBoolean("shake_trigger_on", enabled).apply();
            syncProtectionService(shieldPrefs);
        });
        card("原版救援触发迁移",
                "支持用户主动开启的音量键序列和加速度传感器摇动触发。触发后只显示提醒，不会擅自强停、卸载应用或修改无障碍权限。",
                volumeTrigger, shakeTrigger);
    }
}
