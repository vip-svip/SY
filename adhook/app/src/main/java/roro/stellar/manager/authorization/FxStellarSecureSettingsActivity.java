package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.graphics.Typeface;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * FX migration of Stellar's WRITE_SECURE_SETTINGS authorization outcome.
 *
 * The original ADB TLS/SPAKE2 pairing flow is hosted by AdbPairingActivity.
 * This page keeps the separate, explicitly confirmed WRITE_SECURE_SETTINGS
 * grant/revoke operation and verifies the resulting PackageManager state.
 */
public final class FxStellarSecureSettingsActivity extends Activity {
    private static final String PERMISSION = "android.permission.WRITE_SECURE_SETTINGS";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> {
                Thread thread = new Thread(r, "fx-stellar-secure-settings");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    private TextView status;
    private Button grantButton;
    private Button revokeButton;
    private volatile boolean destroyed;

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        view.setTextIsSelectable(true);
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private void card(LinearLayout parent, String title, String detail, android.view.View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(9), dp(12), dp(9));
        panel.setBackgroundColor(0xffeef2f6);
        panel.addView(text(title, 15, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (android.view.View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(5), 0, dp(5));
        parent.addView(panel, lp);
    }

    private boolean permissionGranted() {
        return checkSelfPermission(PERMISSION) == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    private void refreshStatus() {
        boolean granted = permissionGranted();
        status.setText(granted
                ? "当前状态：FX 已获得 WRITE_SECURE_SETTINGS。权限仅授予本 FX 包名。"
                : "当前状态：FX 尚未获得 WRITE_SECURE_SETTINGS。普通系统设置不会授予此签名/开发级权限。");
        grantButton.setEnabled(!granted);
        revokeButton.setEnabled(granted);
    }

    private String quote(String value) {
        return "'" + value.replace("'", "'\''") + "'";
    }

    private String permissionCommand(boolean grant) {
        String pkg = quote(getPackageName());
        String op = grant ? "grant" : "revoke";
                return "set -eu; P=" + pkg + "; "
                + "[ -n \"$(pm path \"$P\" 2>/dev/null)\" ] || { echo FX_PACKAGE_MISSING; exit 20; }; "
                + "pm " + op + " \"$P\" " + PERMISSION + "; "
                + "echo FX_PERMISSION_COMMAND_SUCCEEDED";
    }

    private void runPermissionChange(boolean grant) {
        final String operation = grant ? "授权" : "撤销";
        if (destroyed || isFinishing() || isDestroyed()) return;
        grantButton.setEnabled(false);
        revokeButton.setEnabled(false);
        status.setText("正在通过 FX Root " + operation + " " + PERMISSION + "…");
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(permissionCommand(grant), 20000L, 16384);
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    boolean verified = result.exitCode == 0 && result.output != null
                            && result.output.contains("FX_PERMISSION_COMMAND_SUCCEEDED")
                            && permissionGranted() == grant;
                    if (verified) {
                        status.setText("已" + operation + "并核验成功："
                                + getPackageName() + " · " + PERMISSION);
                    } else {
                        status.setText(operation + "未能核验成功（Root 退出码 "
                                + result.exitCode + "）。实际输出："
                                + (result.output == null || result.output.isEmpty()
                                ? "无错误详情" : result.output));
                    }
                    refreshButtonsOnly();
                });
            });
        } catch (RejectedExecutionException full) {
            status.setText("Root 授权任务队列繁忙，本次操作未开始；请稍后重试。");
            refreshButtonsOnly();
        }
    }

    private void refreshButtonsOnly() {
        boolean granted = permissionGranted();
        grantButton.setEnabled(!granted);
        revokeButton.setEnabled(granted);
    }

    private void openWirelessDebuggingSettings() {
        try {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS));
        } catch (Throwable first) {
            try {
                startActivity(new Intent(Settings.ACTION_SETTINGS));
            } catch (Throwable second) {
                status.setText("无法打开 Android 开发者选项：" + first.getClass().getSimpleName());
            }
        }
    }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(10), dp(6));
        header.addView(button("‹ 返回 Stellar", this::finish));
        header.addView(text("无线调试与安全设置授权", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(4), dp(12), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        status = text("正在读取当前权限状态…", 13, 0xff334155, true);
        grantButton = button("通过 FX Root 授予 WRITE_SECURE_SETTINGS", () ->
                new AlertDialog.Builder(this)
                        .setTitle("确认授予 FX 安全设置权限")
                        .setMessage("仅向当前 FX 包名授予 " + PERMISSION
                                + "。该权限允许 FX 读写受保护的 Android 系统设置；不会授予其他应用。"
                                + "\\n\\n只有在信任当前 FX 安装包并确实需要 Stellar 系统设置能力时才继续。")
                        .setNegativeButton("取消", null)
                        .setPositiveButton("明确授予", (dialog, which) -> runPermissionChange(true))
                        .show());
        revokeButton = button("撤销 FX WRITE_SECURE_SETTINGS", () ->
                new AlertDialog.Builder(this)
                        .setTitle("确认撤销 FX 安全设置权限")
                        .setMessage("撤销后，依赖此权限的 FX 系统设置能力将停止工作；不会修改其他应用权限。")
                        .setNegativeButton("取消", null)
                        .setPositiveButton("明确撤销", (dialog, which) -> runPermissionChange(false))
                        .show());
        card(body, "FX 权限状态",
                "对应原版 Stellar ADB 配对完成后的实际授权结果。当前采用 KernelSU Root 直接执行 pm grant/revoke，并在命令端与 Android PackageManager 两侧核验。",
                status,
                button("刷新权限状态", this::refreshStatus),
                grantButton, revokeButton);
        card(body, "原版无线 ADB 配对",
                "FX 已迁入原版 libadb.so JNI SPAKE2、TLS 1.3、ADB PeerInfo、配对后的 _adb-tls-connect._tcp GUID 匹配及 mDNS 自动发现、端点保存，以及基于已配对主机密钥的一次性固定只读 echo Shell 探测。自动配对使用 Android 12/API 31+ 的公开 TLS exporter；Android 11 及更旧系统不支持本页的 FX 独立主机密钥自动配对，系统自带 ADB 客户端的手动配对不会登记 FX 密钥，不能视为 FX 配对成功。原版通用 Shell 命令、root: 通道和 tcpip 管理操作尚未迁入；固定探测成功不代表这些完整管理能力已完成。配对成功不会自动授予 WRITE_SECURE_SETTINGS。",
                button("扫描并自动配对 ADB 设备", () ->
                        startActivity(new Intent(this, roro.stellar.manager.adb.AdbPairingActivity.class))),
                button("打开 Android 开发者选项 / 无线调试", this::openWirelessDebuggingSettings));
        card(body, "配对后的权限授予",
                "完成 ADB TLS/SPAKE2 配对后，如确实需要系统安全设置能力，请返回本页单独点击“通过 FX Root 授予 WRITE_SECURE_SETTINGS”。此操作仍需你明确确认，并会核验 PackageManager 实际权限状态。");
        setContentView(root);
        refreshStatus();
    }

    @Override protected void onResume() {
        super.onResume();
        if (status != null && !destroyed) refreshStatus();
    }

    @Override protected void onDestroy() {
        destroyed = true;
        worker.shutdownNow();
        super.onDestroy();
    }
}
