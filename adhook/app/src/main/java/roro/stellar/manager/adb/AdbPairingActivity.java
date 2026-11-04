package roro.stellar.manager.adb;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.os.Bundle;
import android.text.InputType;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/** Explicit user-initiated ADB wireless pairing screen for Stellar. */
public final class AdbPairingActivity extends Activity {
    private final ThreadPoolExecutor pairWorker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> {
                Thread thread = new Thread(r, "fx-stellar-adb-pair");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());
    private final AtomicLong operationGeneration = new AtomicLong();
    private final Map<String, AdbPairingDiscovery.Device> devices = new LinkedHashMap<>();

    private TextView status;
    private TextView devicesSummary;
    private LinearLayout deviceRows;
    private EditText pairingCode;
    private Button scanButton;
    private Button pairButton;
    private AdbPairingDiscovery discovery;
    private AdbPairingDiscovery.Device selectedDevice;
    private volatile AdbPairingClient activeClient;
    private volatile boolean destroyed;
    private boolean pairing;

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(9), dp(12), dp(9));
        panel.setBackgroundColor(0xffeef2f6);
        panel.addView(text(title, 15, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(5), 0, dp(5));
        parent.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(10), dp(6));
        header.addView(button("‹ 返回安全设置", this::finish));
        header.addView(text("ADB 无线配对", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(4), dp(12), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        status = text("尚未开始扫描。请先在 Android 开发者选项中开启无线调试。", 13,
                0xff334155, true);
        scanButton = button("扫描附近的 ADB 配对服务", this::startDiscovery);
        devicesSummary = text("尚未发现设备", 12, 0xff617080, false);
        deviceRows = new LinearLayout(this);
        deviceRows.setOrientation(LinearLayout.VERTICAL);
        card(body, "设备发现",
                "只发现广播 _adb-tls-pairing._tcp 的设备。扫描由你主动启动；FX 不会扫描或保存 Wi-Fi 密码。",
                scanButton, status, devicesSummary, deviceRows);

        pairingCode = new EditText(this);
        pairingCode.setSingleLine(true);
        pairingCode.setInputType(InputType.TYPE_CLASS_NUMBER
                | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pairingCode.setHint("Android 无线调试页面显示的六位配对码");
        pairButton = button("配对所选设备", this::confirmAndPair);
        pairButton.setEnabled(false);
        card(body, "输入配对码",
                "请在 Android“无线调试 → 使用配对码配对设备”中读取六位配对码。配对码只在本次操作内存中使用，不写入日志或偏好设置。",
                pairingCode, pairButton);
        card(body, "安全边界",
                "配对只建立 ADB TLS/SPAKE2 信任关系，不会自动授予 WRITE_SECURE_SETTINGS、不会打开 Shell 常驻服务，也不会执行其他设备命令。后续权限授予仍需你在 Stellar 权限页明确确认。");

        setContentView(root);
    }

    private void startDiscovery() {
        if (destroyed || pairing) return;
        stopDiscovery();
        devices.clear();
        selectedDevice = null;
        renderDevices();
        status.setText("正在扫描 _adb-tls-pairing._tcp…");
        pairButton.setEnabled(false);
        scanButton.setEnabled(false);
        try {
            discovery = new AdbPairingDiscovery(getApplicationContext(),
                    new AdbPairingDiscovery.Listener() {
                        @Override public void onStarted() {
                            if (!destroyed) status.setText("扫描中：等待 Android 无线调试设备广播…");
                        }

                        @Override public void onDeviceFound(AdbPairingDiscovery.Device device) {
                            if (destroyed || device == null) return;
                            devices.put(device.serviceName, device);
                            renderDevices();
                            status.setText("已发现 " + devices.size() + " 个配对服务。选择目标设备后输入配对码。");
                        }

                        @Override public void onDeviceLost(String serviceName) {
                            if (destroyed) return;
                            devices.remove(serviceName);
                            if (selectedDevice != null
                                    && selectedDevice.serviceName.equals(serviceName)) {
                                selectedDevice = null;
                            }
                            renderDevices();
                            status.setText("有设备停止广播；已更新当前列表。");
                        }

                        @Override public void onError(String message, int errorCode) {
                            if (destroyed) return;
                            scanButton.setEnabled(true);
                            status.setText(message + "（错误码 " + errorCode + "）");
                        }

                        @Override public void onStopped() {
                            if (!destroyed && !pairing) scanButton.setEnabled(true);
                        }
                    });
            discovery.start();
        } catch (RuntimeException failure) {
            scanButton.setEnabled(true);
            status.setText("启动设备发现失败：" + failure.getClass().getSimpleName());
        }
    }

    private void renderDevices() {
        if (deviceRows == null) return;
        deviceRows.removeAllViews();
        devicesSummary.setText("当前发现 " + devices.size() + " 个设备");
        for (AdbPairingDiscovery.Device device : devices.values()) {
            boolean selected = selectedDevice != null
                    && selectedDevice.serviceName.equals(device.serviceName);
            Button row = button((selected ? "✓ " : "") + device.toString(),
                    () -> selectDevice(device));
            row.setTextSize(12);
            row.setEnabled(!pairing);
            deviceRows.addView(row);
        }
        pairButton.setEnabled(!pairing && selectedDevice != null);
    }

    private void selectDevice(AdbPairingDiscovery.Device device) {
        if (pairing || device == null) return;
        selectedDevice = device;
        renderDevices();
        status.setText("已选择 " + device.serviceName + " · " + device.host + ":" + device.port);
    }

    private void confirmAndPair() {
        if (destroyed || pairing || selectedDevice == null) return;
        String code = pairingCode.getText().toString().trim();
        if (!code.matches("[0-9]{6}")) {
            pairingCode.setError("请输入 Android 无线调试页面显示的六位配对码");
            return;
        }
        AdbPairingDiscovery.Device target = selectedDevice;
        new AlertDialog.Builder(this)
                .setTitle("确认 ADB 无线配对")
                .setMessage("目标：" + target.host + ":" + target.port
                        + "\n\nFX 将通过 TLS 1.3 与 SPAKE2 验证配对码。"
                        + "只有 PeerInfo 加密交换成功才会报告配对成功。"
                        + "不会自动授予系统权限。")
                .setNegativeButton("取消", null)
                .setPositiveButton("开始配对", (dialog, which) -> startPairing(target, code))
                .show();
    }

    private void startPairing(AdbPairingDiscovery.Device target, String code) {
        if (destroyed || pairing) return;
        pairing = true;
        pairingCode.setText("");
        final long generation = operationGeneration.incrementAndGet();
        scanButton.setEnabled(false);
        pairButton.setEnabled(false);
        status.setText("正在创建/读取 FX ADB 主机密钥并连接 " + target.host + ":" + target.port + "…");
        try {
            pairWorker.execute(() -> {
                AdbPairingClient client = null;
                try {
                    AdbKey key = AdbKey.getOrCreate(getApplicationContext());
                    client = new AdbPairingClient(target.host, target.port, code, key);
                    activeClient = client;
                    if (destroyed || generation != operationGeneration.get()) {
                        client.close();
                        return;
                    }
                    client.start();
                    boolean saved = getSharedPreferences("fx_stellar_adb_pairing", MODE_PRIVATE)
                            .edit()
                            .putBoolean("paired", true)
                            .putString("service_name", target.serviceName)
                            .putString("host", target.host)
                            .putInt("port", target.port)
                            .putLong("paired_at", System.currentTimeMillis())
                            .commit();
                    runOnUiThread(() -> {
                        if (destroyed || generation != operationGeneration.get()) return;
                        status.setText("ADB 无线配对成功。SPAKE2 已验证对端，PeerInfo 已加密交换。"
                                + (saved ? " 配对状态已保存。" : " 但本地状态保存失败，请重新打开页面核验。")
                                + " 如需 WRITE_SECURE_SETTINGS，请返回 Stellar 页面单独确认授予。");
                    });
                } catch (Exception failure) {
                    final String detail = failure.getMessage() == null
                            ? failure.getClass().getSimpleName() : failure.getMessage();
                    runOnUiThread(() -> {
                        if (destroyed || generation != operationGeneration.get()) return;
                        status.setText("ADB 配对失败：" + detail);
                    });
                } finally {
                    if (client != null) client.close();
                    activeClient = null;
                    runOnUiThread(() -> {
                        if (destroyed || generation != operationGeneration.get()) return;
                        pairing = false;
                        scanButton.setEnabled(true);
                        renderDevices();
                    });
                }
            });
        } catch (RejectedExecutionException full) {
            pairing = false;
            scanButton.setEnabled(true);
            renderDevices();
            status.setText("ADB 配对任务队列繁忙，本次操作未开始。");
        }
    }

    private void stopDiscovery() {
        AdbPairingDiscovery current = discovery;
        discovery = null;
        if (current != null) current.close();
    }

    @Override protected void onDestroy() {
        destroyed = true;
        operationGeneration.incrementAndGet();
        stopDiscovery();
        AdbPairingClient client = activeClient;
        activeClient = null;
        if (client != null) client.close();
        pairWorker.shutdownNow();
        super.onDestroy();
    }
}
