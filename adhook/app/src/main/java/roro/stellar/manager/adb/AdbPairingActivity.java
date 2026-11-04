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
    private final AtomicLong probeGeneration = new AtomicLong();
    private final ThreadPoolExecutor probeWorker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> {
                Thread thread = new Thread(r, "fx-stellar-adb-shell-probe");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());
    private final Map<String, AdbPairingDiscovery.Device> devices = new LinkedHashMap<>();

    private TextView status;
    private TextView devicesSummary;
    private LinearLayout deviceRows;
    private EditText pairingCode;
    private Button scanButton;
    private Button pairButton;
    private Button connectTestButton;
    private AdbPairingDiscovery discovery;
    private AdbPairingDiscovery.Device selectedDevice;
    private volatile AdbPairingClient activeClient;
    private volatile AdbShellProbeClient activeProbe;
    private volatile boolean destroyed;
    private boolean pairing;
    private boolean connectDiscoveryMode;

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
        scanButton = button("扫描附近的 ADB 配对服务", () -> {
            if (connectDiscoveryMode) startConnectDiscovery(operationGeneration.get());
            else startDiscovery();
        });
        connectTestButton = button("验证所选设备的 ADB Shell 通道", this::probeSelectedConnectEndpoint);
        connectTestButton.setEnabled(false);
        devicesSummary = text("尚未发现设备", 12, 0xff617080, false);
        deviceRows = new LinearLayout(this);
        deviceRows.setOrientation(LinearLayout.VERTICAL);
        card(body, "设备发现",
                "配对后会继续发现 _adb-tls-connect._tcp。选中目标 connect 端点后，可进行一次固定只读 echo 探测；不会执行任意命令或授予系统权限。",
                scanButton, connectTestButton, status, devicesSummary, deviceRows);

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
        connectDiscoveryMode = false;
        pairButton.setText("配对所选设备");
        scanButton.setText("扫描附近的 ADB 配对服务");
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
        pairButton.setEnabled(!pairing && !connectDiscoveryMode && selectedDevice != null);
        if (connectTestButton != null) {
            connectTestButton.setEnabled(!pairing && connectDiscoveryMode && selectedDevice != null);
        }
    }

    private void selectDevice(AdbPairingDiscovery.Device device) {
        if (pairing || device == null) return;
        selectedDevice = device;
        renderDevices();
        if (connectDiscoveryMode) {
            status.setText("已选择配对后的 ADB connect 端点 " + device.host + ":" + device.port
                    + "。点击固定只读探测以验证 ADB Shell 通道。");
        } else {
            status.setText("已选择 " + device.serviceName + " · " + device.host + ":" + device.port);
        }
    }

    /** Open the authenticated ADB shell channel with a fixed, read-only echo probe only. */
    private void probeSelectedConnectEndpoint() {
        if (destroyed || pairing || !connectDiscoveryMode || selectedDevice == null) return;
        final AdbPairingDiscovery.Device target = selectedDevice;
        final long generation = probeGeneration.incrementAndGet();
        connectTestButton.setEnabled(false);
        status.setText("正在通过已配对的 ADB 主机密钥建立 TLS/CNXN/AUTH，并验证固定 Shell 探测…");
        try {
            probeWorker.execute(() -> {
                AdbShellProbeClient client = null;
                String output = null;
                String failure = null;
                try {
                    if (destroyed || generation != probeGeneration.get()) return;
                    AdbKey key = AdbKey.getOrCreate(getApplicationContext());
                    client = new AdbShellProbeClient(target.host, target.port, key);
                    activeProbe = client;
                    if (destroyed || generation != probeGeneration.get()) {
                        client.close();
                        return;
                    }
                    output = client.probe();
                } catch (Exception error) {
                    failure = error.getClass().getSimpleName()
                            + (error.getMessage() == null ? "" : ": " + error.getMessage());
                } finally {
                    if (activeProbe == client) activeProbe = null;
                    if (client != null) client.close();
                }
                final String probeOutput = output;
                final String probeFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()
                            || generation != probeGeneration.get()
                            || selectedDevice == null
                            || !selectedDevice.serviceName.equals(target.serviceName)) return;
                    if (probeFailure == null) {
                        pairButton.setText("ADB Shell 固定只读探测已通过");
                        status.setText("ADB TLS/AUTH 与 Shell 通道探测成功。固定命令返回："
                                + probeOutput.trim()
                                + "。这只验证最小只读通道，不代表通用 Shell 管理功能已全部迁入。");
                    } else {
                        pairButton.setText("ADB Shell 固定只读探测尚未通过");
                        status.setText("ADB Shell 探测失败（不会修改设备状态）："
                                + probeFailure + "。可重新扫描 connect 服务或重试。");
                    }
                    renderDevices();
                });
            });
        } catch (RejectedExecutionException full) {
            status.setText("ADB Shell 探测队列繁忙，本次未开始；请稍后重试。");
            renderDevices();
        }
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
                                + " 正在查找配对后的 ADB connect 服务；不会自动执行命令或授予系统权限。");
                        startConnectDiscovery(generation);
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

    /**
     * Original Stellar behavior: after the pairing port closes, discover the
     * separate _adb-tls-connect._tcp endpoint and retain its address/port.
     * This migration deliberately stops at endpoint discovery; it does not
     * claim to provide an ADB Shell session or silently execute pm grant.
     */
    private void startConnectDiscovery(final long generation) {
        if (destroyed || generation != operationGeneration.get()) return;
        probeGeneration.incrementAndGet();
        AdbShellProbeClient previousProbe = activeProbe;
        activeProbe = null;
        if (previousProbe != null) previousProbe.close();
        stopDiscovery();
        connectDiscoveryMode = true;
        selectedDevice = null;
        devices.clear();
        pairButton.setText("ADB Shell 固定只读探测尚未通过");
        pairButton.setEnabled(false);
        if (connectTestButton != null) connectTestButton.setEnabled(false);
        scanButton.setText("重新扫描 ADB connect 服务");
        scanButton.setEnabled(false);
        renderDevices();
        status.setText("配对已完成，正在扫描 _adb-tls-connect._tcp…");
        try {
            discovery = new AdbPairingDiscovery(getApplicationContext(),
                    AdbPairingDiscovery.CONNECT_SERVICE_TYPE,
                    new AdbPairingDiscovery.Listener() {
                        @Override public void onStarted() {
                            if (!destroyed && generation == operationGeneration.get()) {
                                status.setText("ADB 配对已完成；正在发现 connect 端点…");
                            }
                        }

                        @Override public void onDeviceFound(AdbPairingDiscovery.Device device) {
                            if (destroyed || generation != operationGeneration.get() || device == null) return;
                            devices.put(device.serviceName, device);
                            boolean saved = getSharedPreferences("fx_stellar_adb_pairing", MODE_PRIVATE)
                                    .edit()
                                    .putString("connect_service_name", device.serviceName)
                                    .putString("connect_host", device.host)
                                    .putInt("connect_port", device.port)
                                    .putLong("connect_discovered_at", System.currentTimeMillis())
                                    .commit();
                            renderDevices();
                            status.setText("已发现配对后的 ADB connect 端点：" + device.host + ":" + device.port
                                    + (saved ? "，端点信息已保存。" : "，但端点信息保存失败。")
                                    + " 当前尚未迁入 ADB Shell 命令通道；不会把端点发现冒充成 Shell 已连接。"
                                    + " WRITE_SECURE_SETTINGS 仍需返回 Stellar 页面单独确认。");
                        }

                        @Override public void onDeviceLost(String serviceName) {
                            if (destroyed || generation != operationGeneration.get()) return;
                            devices.remove(serviceName);
                            if (selectedDevice != null
                                    && selectedDevice.serviceName.equals(serviceName)) {
                                selectedDevice = null;
                                pairButton.setText("ADB Shell 固定只读探测尚未通过");
                                probeGeneration.incrementAndGet();
                                AdbShellProbeClient probing = activeProbe;
                                activeProbe = null;
                                if (probing != null) probing.close();
                            }
                            String savedName = getSharedPreferences("fx_stellar_adb_pairing", MODE_PRIVATE)
                                    .getString("connect_service_name", "");
                            if (serviceName.equals(savedName)) {
                                getSharedPreferences("fx_stellar_adb_pairing", MODE_PRIVATE).edit()
                                        .remove("connect_service_name")
                                        .remove("connect_host")
                                        .remove("connect_port")
                                        .remove("connect_discovered_at")
                                        .commit();
                            }
                            renderDevices();
                            status.setText("ADB connect 服务已停止广播；已移除过期端点。");
                        }

                        @Override public void onError(String message, int errorCode) {
                            if (destroyed || generation != operationGeneration.get()) return;
                            scanButton.setEnabled(true);
                            status.setText("ADB 配对成功，但 connect 服务发现失败：" + message
                                    + "（错误码 " + errorCode + "）。可点击重新扫描；ADB Shell 尚未连接。");
                        }

                        @Override public void onStopped() {
                            if (!destroyed && generation == operationGeneration.get()) {
                                scanButton.setEnabled(true);
                            }
                        }
                    });
            discovery.start();
        } catch (RuntimeException failure) {
            scanButton.setEnabled(true);
            status.setText("ADB 配对成功，但启动 connect 服务发现失败："
                    + failure.getClass().getSimpleName() + "；ADB Shell 尚未连接。");
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
        probeGeneration.incrementAndGet();
        AdbShellProbeClient probing = activeProbe;
        activeProbe = null;
        if (probing != null) probing.close();
        pairWorker.shutdownNow();
        probeWorker.shutdownNow();
        super.onDestroy();
    }
}
