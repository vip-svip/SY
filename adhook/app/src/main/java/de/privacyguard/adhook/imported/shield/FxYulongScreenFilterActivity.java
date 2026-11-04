package de.privacyguard.adhook.imported.shield;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/** Native Yulong Shield screen-filter controls integrated into FX Hook. */
public final class FxYulongScreenFilterActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int REQUEST_NOTIFICATIONS = 8811;
    private static final String PREFS = "shield_prefs";
    private SharedPreferences prefs;
    private Switch enabled;
    private boolean binding;
    private boolean pendingEnable;

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView v = new TextView(this);
        v.setText(value); v.setTextSize(size); v.setTextColor(color);
        if (bold) v.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        v.setPadding(dp(4), dp(5), dp(4), dp(5));
        return v;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout body, String title, String detail, android.view.View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(10), dp(14), dp(10));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 15, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (android.view.View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(10), dp(4), dp(10), dp(4));
        body.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回安全护盾", this::finish));
        header.addView(text("屏幕滤镜", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 5);

        enabled = new Switch(this);
        enabled.setText("启用全屏屏幕滤镜");
        enabled.setTextSize(15);
        enabled.setChecked(prefs.getBoolean("screen_filter_enabled", false));
        enabled.setOnCheckedChangeListener((button, checked) -> {
            if (binding) return;
            if (checked) {
                if (!Settings.canDrawOverlays(this)) {
                    setSwitch(false);
                    new AlertDialog.Builder(this).setTitle("需要悬浮窗权限")
                            .setMessage("滤镜使用不接收触摸的透明覆盖层。请手动授予 FX 悬浮窗权限后再开启。")
                            .setNegativeButton("稍后", null)
                            .setPositiveButton("打开设置", (d, w) -> openOverlaySettings()).show();
                    return;
                }
                if (Build.VERSION.SDK_INT >= 33
                        && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                        != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    pendingEnable = true;
                    setSwitch(false);
                    requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},
                            REQUEST_NOTIFICATIONS);
                    return;
                }
                startFilter();
            } else stopFilter();
        });
        card(body, "滤镜状态",
                "使用不接收触摸的透明覆盖层调节叠加色，不读取屏幕图像。系统显示可停止的前台通知。",
                enabled,
                button("打开悬浮窗权限设置", this::openOverlaySettings),
                button("停止并移除滤镜", this::stopFilter));

        Spinner preset = new Spinner(this);
        String[] presetNames = {"标准浅色", "暖色覆盖"};
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_item, presetNames);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        preset.setAdapter(adapter);
        preset.setSelection(Math.max(0, Math.min(1, prefs.getInt("screen_filter_preset", 0))));
        preset.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override public void onNothingSelected(android.widget.AdapterView<?> parent) { }
            @Override public void onItemSelected(android.widget.AdapterView<?> parent,
                    android.view.View view, int position, long id) {
                prefs.edit().putInt("screen_filter_preset", position).apply();
                applyIfRunning();
            }
        });
        card(body, "滤镜预设", "预设只改变覆盖滤镜的颜色；Android 普通悬浮层不能对下层应用画面进行真实像素级对比度/饱和度变换。", preset);
        Switch volumeAdjust = new Switch(this);
        volumeAdjust.setText("使用音量键微调滤镜亮度");
        volumeAdjust.setChecked(prefs.getBoolean("screen_filter_volume_adjust_enabled", false));
        volumeAdjust.setOnCheckedChangeListener((button, checked) -> {
            if (checked && !de.privacyguard.adhook.FxAccessibilityService.isConnected()) {
                binding = true; volumeAdjust.setChecked(false); binding = false;
                new AlertDialog.Builder(this).setTitle("需要 FX 无障碍服务")
                        .setMessage("音量键调节只接收音量上/下键方向，不读取界面内容，也不会吞掉按键。请手动启用 FX 无障碍服务。")
                        .setNegativeButton("稍后", null)
                        .setPositiveButton("打开设置", (d, w) -> {
                            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
                            catch (Throwable ignored) { }
                        }).show();
                return;
            }
            prefs.edit().putBoolean("screen_filter_volume_adjust_enabled", checked).apply();
        });
        card(body, "音量键快捷调节",
                "开启后音量上/下键按每次 5 个单位调整滤镜亮度；系统音量仍正常变化。",
                volumeAdjust);
        addSlider(body, "亮度", "screen_filter_brightness", 0, 200, 100, "%");
        addSlider(body, "覆盖色对比度", "screen_filter_contrast", 0, 200, 100, "%");
        addSlider(body, "覆盖色饱和度", "screen_filter_saturation", 0, 200, 100, "%");
        addSlider(body, "色温", "screen_filter_temperature", 0, 100, 50, "");
        card(body, "操作", "启用后拖动参数会即时更新；关闭后只移除 FX 自己创建的覆盖层。",
                button("应用当前参数", this::applyIfRunning),
                button("恢复默认参数", this::resetDefaults));
    }

    private void setSwitch(boolean checked) {
        binding = true;
        if (enabled != null) enabled.setChecked(checked);
        binding = false;
    }
    private void addSlider(LinearLayout body, String label, String key,
                           int min, int max, int fallback, String suffix) {
        TextView value = text("", 12, 0xff617080, false);
        SeekBar seek = new SeekBar(this);
        seek.setMax(max - min);
        int current = Math.max(min, Math.min(max, prefs.getInt(key, fallback)));
        seek.setProgress(current - min);
        value.setText(label + "：" + current + suffix);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                int actual = progress + min;
                value.setText(label + "：" + actual + suffix);
                if (fromUser) {
                    prefs.edit().putInt(key, actual).apply();
                    applyIfRunning();
                }
            }
            @Override public void onStartTrackingTouch(SeekBar bar) { }
            @Override public void onStopTrackingTouch(SeekBar bar) { }
        });
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(7), dp(14), dp(7));
        panel.addView(value); panel.addView(seek);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(10), dp(2), dp(10), dp(2));
        body.addView(panel, lp);
    }
    private void openOverlaySettings() {
        try {
            startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName())));
        } catch (Throwable error) {
            Toast.makeText(this, "无法打开悬浮窗设置：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }
    private void startFilter() {
        if (!Settings.canDrawOverlays(this)) { setSwitch(false); return; }
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            pendingEnable = true;
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},
                    REQUEST_NOTIFICATIONS);
            return;
        }
        pendingEnable = false;
        prefs.edit().putBoolean("screen_filter_enabled", true).apply();
        Intent service = new Intent(this, FxYulongScreenFilterService.class);
        service.setAction(FxYulongScreenFilterService.ACTION_START);
        dispatchService(service);
        setSwitch(true);
    }
    private void stopFilter() {
        pendingEnable = false;
        prefs.edit().putBoolean("screen_filter_enabled", false).apply();
        stopService(new Intent(this, FxYulongScreenFilterService.class));
        setSwitch(false);
    }
    private void applyIfRunning() {
        if (!prefs.getBoolean("screen_filter_enabled", false)) return;
        if (!Settings.canDrawOverlays(this)) { stopFilter(); return; }
        Intent service = new Intent(this, FxYulongScreenFilterService.class);
        service.setAction(FxYulongScreenFilterService.ACTION_APPLY);
        dispatchService(service);
    }
    private void dispatchService(Intent service) {
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service);
        else startService(service);
    }
    private void resetDefaults() {
        prefs.edit().putInt("screen_filter_preset", 0)
                .putInt("screen_filter_brightness", 100)
                .putInt("screen_filter_contrast", 100)
                .putInt("screen_filter_saturation", 100)
                .putInt("screen_filter_temperature", 50).apply();
        applyIfRunning();
        recreate();
    }
    @Override protected void onResume() {
        super.onResume();
        setSwitch(prefs.getBoolean("screen_filter_enabled", false));
    }
    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == REQUEST_NOTIFICATIONS) {
            boolean granted = results.length > 0
                    && results[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
            boolean shouldEnable = pendingEnable;
            pendingEnable = false;
            if (granted && shouldEnable) startFilter();
            else if (shouldEnable) {
                Toast.makeText(this, "未授予通知权限，滤镜没有启动。", Toast.LENGTH_LONG).show();
                setSwitch(false);
            }
        }
    }
}
