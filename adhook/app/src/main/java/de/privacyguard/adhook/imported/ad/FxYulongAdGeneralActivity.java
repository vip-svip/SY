package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.ComponentName;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.drawable.Icon;
import android.net.Uri;
import android.os.Bundle;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.service.quicksettings.TileService;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.ArrayList;
import java.util.List;

/** Yulong AdBlock 7.0.1 general settings and transactional filter backup/restore. */
public final class FxYulongAdGeneralActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int IMPORT_REQUEST = 7811;
    private static final int EXPORT_REQUEST = 7812;
    private static final int MAX_BACKUP_BYTES = 1024 * 1024;
    private static final String STATE_PENDING_EXPORT = "fx_yulong_ad_pending_export";
    private static final String STATE_IMPORT_PENDING = "fx_yulong_ad_import_pending";
    private static final String STATE_EXPORT_PENDING = "fx_yulong_ad_export_pending";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> { Thread t = new Thread(r, "fx-yulong-ad-backup"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private TextView batteryStatus, operationStatus, taskerResultStatus;
    private Switch taskerExternalControl;
    private EditText taskerSenderPackageInput;
    private TextView taskerSecurityStatus;
    private boolean updatingTaskerControlSwitch;
    private boolean taskerResultReceiverRegistered;
    private String pendingExport;
    private boolean importRequestPending;
    private boolean exportRequestPending;

    private final BroadcastReceiver taskerResultReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null || !FxYulongAdTaskerReceiver.ACTION_RESULT.equals(intent.getAction())) return;
            // Older receiver builds did not include this flag; keep their existing
            // persisted-receipt refresh behavior for backward compatibility.
            if (intent.getBooleanExtra("receipt_persisted", true)) {
                refreshTaskerResultStatus();
                return;
            }

            String action = boundedTaskerText(intent.getStringExtra("source_action"), 160);
            String target = boundedTaskerText(intent.getStringExtra("target"), 40);
            String detail = boundedTaskerText(intent.getStringExtra("detail"), 360);
            boolean success = intent.getBooleanExtra("success", false);
            int exitCode = intent.getIntExtra("exit_code", 127);
            int requested = intent.getIntExtra("requested_enabled", -1);
            StringBuilder display = new StringBuilder();
            display.append("收到本次实时命令回执，但未能保存到本地历史。")
                    .append(System.lineSeparator()).append("控制目标：")
                    .append("vpn".equals(target) ? "FX VPN" : "广告过滤")
                    .append(" · 请求：").append(requested == 1 ? "开启/启动" : requested == 0 ? "关闭/停止" : "未知")
                    .append(System.lineSeparator()).append("动作：").append(action)
                    .append(System.lineSeparator()).append("命令结果：")
                    .append(success ? "执行成功" : "执行失败")
                    .append(" · 退出码：").append(exitCode);
            if (!detail.isEmpty()) {
                display.append(System.lineSeparator()).append("回执详情：").append(detail);
            }
            display.append(System.lineSeparator())
                    .append("关闭或重启页面后，本次未持久化的回执将无法恢复。");
            if (taskerResultStatus != null) taskerResultStatus.setText(display.toString());
        }
    };

    private static String boundedTaskerText(String value, int maxChars) {
        if (value == null) return "";
        String trimmed = value.trim();
        return trimmed.length() > maxChars
                ? trimmed.substring(0, maxChars) + "…" : trimmed;
    }

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (!isFinishing() && !isDestroyed() && operationStatus != null)
                    operationStatus.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
            });
        }
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setTag("fx-action-row"); b.setAllCaps(false); b.setText(label); b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout body, String title, String detail, View... children) {
        LinearLayout p = new LinearLayout(this); p.setTag("fx-card"); p.setOrientation(1);
        p.setPadding(dp(14), dp(9), dp(14), dp(9)); p.setBackgroundColor(0xfff0f3f7);
        TextView heading = text(title, 15, 0xff17212b, true); heading.setTag("fx-card-title"); p.addView(heading); TextView description = text(detail, 12, 0xff617080, false); description.setTag("fx-card-detail"); p.addView(description);
        for (View child : children) p.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); body.addView(p, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            pendingExport = state.getString(STATE_PENDING_EXPORT);
            importRequestPending = state.getBoolean(STATE_IMPORT_PENDING, false);
            exportRequestPending = state.getBoolean(STATE_EXPORT_PENDING, false);
            if (pendingExport != null && pendingExport.length() > MAX_BACKUP_BYTES) {
                pendingExport = null;
                exportRequestPending = false;
            }
        }
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Ad", this::finish));
        header.addView(text("Ad · 通用设置与备份恢复", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 1);

        batteryStatus = text("正在读取系统省电策略…", 12, 0xff526170, false);
        card(body, "后台运行与电池优化",
                "只打开 Android 系统设置由用户自行决定是否豁免电池优化。FX 不会静默修改系统省电策略。",
                batteryStatus, button("打开电池优化设置", this::openBatterySettings));

        operationStatus = text("尚未执行导入或导出。", 12, 0xff526170, false);
        card(body, "过滤设置备份",
                "导出/导入范围：广告过滤总开关、订阅来源、域名白/黑名单、DNS 策略与服务器、每周过滤计划。导入前会备份 settings.conf 与 schedule 文件；失败会恢复原文件并重新应用。",
                button("导出过滤设置 JSON", this::exportSettings),
                button("从 JSON 导入设置", this::pickImport),
                operationStatus);

        card(body, "页面快捷入口", "以下入口属于 FX Ad 的内部功能页面，可在统一应用内继续管理。",
                button("过滤列表", () -> openPage("过滤列表")),
                button("DNS 设置", () -> openPage("DNS 设置")),
                button("域名白/黑名单", () -> openPage("域名名单")),
                button("计划任务", () -> openPage("计划任务")),
                button("VPN 与 Root Proxy", () -> openPage("VPN 与 Root Proxy")));

        card(body, "系统快捷开关",
                "通过 Android 系统的“添加磁贴”确认流程，将FX 广告过滤或 FX VPN 加入快捷设置面板。磁贴由系统托管；添加不会自动启动过滤或 VPN。",
                button("添加“FX 广告过滤”快捷开关", () ->
                        requestQuickSettingsTile(FxYulongAdTileService.class, "FX 广告过滤")),
                button("添加“FX VPN”快捷开关", () ->
                        requestQuickSettingsTile(FxYulongVpnTileService.class, "FX VPN")));

        card(body, "桌面小组件",
                "将 FX 广告过滤状态组件固定到支持的桌面启动器。组件会读取设备端真实 VPN/Root Proxy 状态；固定操作由桌面启动器确认。",
                button("添加 FX 广告过滤桌面小组件", this::requestHomeWidgetPin));

        android.content.SharedPreferences taskerPrefs =
                getSharedPreferences(FxYulongAdTaskerReceiver.PREFS_NAME, MODE_PRIVATE);
        taskerSenderPackageInput = new EditText(this);
        taskerSenderPackageInput.setSingleLine(true);
        taskerSenderPackageInput.setInputType(android.text.InputType.TYPE_CLASS_TEXT
                | android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD);
        taskerSenderPackageInput.setHint("授权自动化应用包名（必须已安装）");
        taskerSenderPackageInput.setText(taskerPrefs.getString(
                FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE, ""));

        taskerSecurityStatus = text("", 12, 0xff526170, false);
        taskerExternalControl = new Switch(this);
        taskerExternalControl.setText("允许指定自动化应用执行 Root 操作");
        boolean senderReady = Build.VERSION.SDK_INT >= 34
                && isAutomationSenderPinned(
                        taskerPrefs.getString(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE, ""),
                        taskerPrefs.getString(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_CERT_SHA256, ""));
        boolean storedAllowed = taskerPrefs.getBoolean(
                FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false);
        if (!senderReady && storedAllowed) {
            taskerPrefs.edit().putBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false).commit();
            storedAllowed = false;
        }
        taskerExternalControl.setChecked(storedAllowed);
        taskerExternalControl.setEnabled(senderReady);
        taskerExternalControl.setOnCheckedChangeListener((button, checked) -> {
            if (updatingTaskerControlSwitch) return;
            String allowed = taskerPrefs.getString(
                    FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE, "");
            if (checked && (Build.VERSION.SDK_INT < 34 || !isAutomationSenderPinned(
                    allowed, taskerPrefs.getString(
                            FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_CERT_SHA256, "")))) {
                updatingTaskerControlSwitch = true;
                button.setChecked(false);
                updatingTaskerControlSwitch = false;
                Toast.makeText(this, Build.VERSION.SDK_INT < 34
                        ? "当前 Android 版本无法可靠识别广播发送方；为防止任意应用触发 Root，自动化控制保持关闭。"
                        : "请先保存一个已安装的授权自动化应用包名。", Toast.LENGTH_LONG).show();
                return;
            }
            boolean saved = taskerPrefs.edit()
                    .putBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, checked)
                    .commit();
            if (!saved) {
                updatingTaskerControlSwitch = true;
                button.setChecked(!checked);
                updatingTaskerControlSwitch = false;
                Toast.makeText(this, "自动化授权设置保存失败，原状态保持不变。", Toast.LENGTH_LONG).show();
                return;
            }
            refreshTaskerResultStatus();
        });
        taskerResultStatus = text("尚无自动化执行回执。", 12, 0xff526170, false);
        card(body, "Tasker / 自动化广播",
                "兼容原游龙 Tasker 动作名，并提供 FX 广播动作。Receiver 可调用 Root，因此需要验证并保存已安装自动化应用的包名与 APK 签名 SHA-256，再手动开启开关。仅 Android 14+ 可校验真实广播发送方、UID 包映射和固定签名；签名改变后必须重新授权，Android 14 以下直接拒绝执行。最近回执不代表服务当前仍在运行。",
                taskerSenderPackageInput,
                button("选择已安装应用", this::chooseTaskerSenderApp),
                button("验证包名并固定 APK 签名", this::saveTaskerSenderPackage),
                taskerSecurityStatus,
                taskerExternalControl,
                button("复制：开启广告过滤", () -> copyTaskerAction("开启广告过滤", FxYulongAdTaskerReceiver.ACTION_ENABLE)),
                button("复制：关闭广告过滤", () -> copyTaskerAction("关闭广告过滤", FxYulongAdTaskerReceiver.ACTION_DISABLE)),
                button("复制：启动 FX VPN", () -> copyTaskerAction("启动 FX VPN", FxYulongAdTaskerReceiver.ACTION_VPN_START)),
                button("复制：停止 FX VPN", () -> copyTaskerAction("停止 FX VPN", FxYulongAdTaskerReceiver.ACTION_VPN_STOP)),
                button("复制：原版 Tasker_START", () -> copyTaskerAction("原版 Tasker_START", FxYulongAdTaskerReceiver.LEGACY_ACTION_START)),
                button("复制：原版 Tasker_STOP", () -> copyTaskerAction("原版 Tasker_STOP", FxYulongAdTaskerReceiver.LEGACY_ACTION_STOP)),
                button("刷新最近执行回执", this::refreshTaskerResultStatus),
                button("清除最近执行回执", this::confirmClearTaskerReceipt),
                taskerResultStatus);

        card(body, "界面、主题与语言",
                "FX 已合并为单一原生应用，界面主题、语言和强调色属于 FX 应用级偏好；不会再创建第二套游龙 Activity 主题配置。");
        card(body, "关于",
                "功能模块：FX Ad。\n"
                        + "当前宿主：FX 1.0.0 / FX Hook。\n"
                        + "网络架构：FX 单一 VPN/TUN + Root DNS Proxy 回退；不安装游龙原版第二个 VpnService。\n"
                        + "配置和备份仅保存在本机，导入导出由用户通过 Android 文件选择器授权。");
        refreshBatteryStatus();
        refreshTaskerResultStatus();
    }

    @Override protected void onResume() {
        super.onResume();
        registerTaskerResultReceiver();
        refreshTaskerResultStatus();
    }

    @Override protected void onPause() {
        unregisterTaskerResultReceiver();
        super.onPause();
    }

    @android.annotation.SuppressLint("UnspecifiedRegisterReceiverFlag")
    private void registerTaskerResultReceiver() {
        if (taskerResultReceiverRegistered) return;
        IntentFilter filter = new IntentFilter(FxYulongAdTaskerReceiver.ACTION_RESULT);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(taskerResultReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                registerReceiver(taskerResultReceiver, filter);
            }
            taskerResultReceiverRegistered = true;
        } catch (RuntimeException error) {
            if (taskerResultStatus != null)
                taskerResultStatus.setText("无法监听自动化实时回执：" + error.getClass().getSimpleName());
        }
    }

    private void unregisterTaskerResultReceiver() {
        if (!taskerResultReceiverRegistered) return;
        try {
            unregisterReceiver(taskerResultReceiver);
        } catch (IllegalArgumentException ignored) { }
        taskerResultReceiverRegistered = false;
    }

    private boolean isAutomationSenderInstalled(String packageName) {
        if (!FxYulongTaskerCallerPolicy.isValidPackageName(packageName)) return false;
        try {
            getPackageManager().getApplicationInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException | SecurityException unavailable) {
            return false;
        }
    }

    private String getAutomationSenderSignerDigest(String packageName) {
        if (!isAutomationSenderInstalled(packageName)) return "";
        try {
            android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(
                    packageName, PackageManager.GET_SIGNING_CERTIFICATES);
            if (info.signingInfo == null) return "";
            android.content.pm.Signature[] signers = info.signingInfo.hasMultipleSigners()
                    ? info.signingInfo.getApkContentsSigners()
                    : info.signingInfo.getSigningCertificateHistory();
            if (signers == null || signers.length == 0) return "";
            // For a single signer, Android returns rotation history oldest-to-newest.
            // Pin only the current signer; multiple-signer apps pin the complete set.
            if (!info.signingInfo.hasMultipleSigners()) {
                signers = new android.content.pm.Signature[]{signers[signers.length - 1]};
            }
            byte[][] certificates = new byte[signers.length][];
            for (int i = 0; i < signers.length; i++) {
                certificates[i] = signers[i] == null ? null : signers[i].toByteArray();
            }
            return FxYulongTaskerCallerPolicy.signerDigest(certificates);
        } catch (PackageManager.NameNotFoundException | SecurityException unavailable) {
            return "";
        }
    }

    /**
     * Lists launcher-visible apps without requesting broad package visibility.
     * Selection only fills the package field; pinning the signer and enabling
     * Root automation remain two separate, explicit user actions.
     */
    private void chooseTaskerSenderApp() {
        if (taskerSenderPackageInput == null) return;
        Intent launcher = new Intent(Intent.ACTION_MAIN);
        launcher.addCategory(Intent.CATEGORY_LAUNCHER);
        final List<android.content.pm.ResolveInfo> resolved;
        try {
            resolved = getPackageManager().queryIntentActivities(
                    launcher, PackageManager.MATCH_DEFAULT_ONLY);
        } catch (RuntimeException unavailable) {
            Toast.makeText(this, "无法读取可见的已安装应用列表；仍可手动输入包名。",
                    Toast.LENGTH_LONG).show();
            return;
        }
        java.util.TreeMap<String, String> choices =
                new java.util.TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        for (android.content.pm.ResolveInfo item : resolved) {
            if (item == null || item.activityInfo == null) continue;
            String packageName = item.activityInfo.packageName;
            if (!FxYulongTaskerCallerPolicy.isValidPackageName(packageName)
                    || getPackageName().equals(packageName)) continue;
            CharSequence rawLabel;
            try {
                rawLabel = item.loadLabel(getPackageManager());
            } catch (RuntimeException unavailableLabel) {
                rawLabel = packageName;
            }
            String label = rawLabel == null ? packageName : rawLabel.toString().trim();
            if (label.isEmpty()) label = packageName;
            String row = label + " · " + packageName;
            choices.put(row, packageName);
        }
        if (choices.isEmpty()) {
            Toast.makeText(this,
                    "没有发现可见且带桌面启动入口的应用；可手动输入完整包名。",
                    Toast.LENGTH_LONG).show();
            return;
        }
        String[] labels = choices.keySet().toArray(new String[0]);
        String[] packages = choices.values().toArray(new String[0]);
        new AlertDialog.Builder(this)
                .setTitle("选择自动化应用")
                .setItems(labels, (dialog, which) -> {
                    if (which < 0 || which >= packages.length
                            || taskerSenderPackageInput == null) return;
                    taskerSenderPackageInput.setText(packages[which]);
                    taskerSenderPackageInput.setSelection(
                            taskerSenderPackageInput.getText().length());
                    Toast.makeText(this, "已填入包名；请继续验证并固定 APK 签名。",
                            Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private boolean isAutomationSenderPinned(String packageName, String expectedDigest) {
        if (expectedDigest == null || expectedDigest.isEmpty()) return false;
        String currentDigest = getAutomationSenderSignerDigest(packageName);
        return !currentDigest.isEmpty() && expectedDigest.equals(currentDigest);
    }

    private void saveTaskerSenderPackage() {
        if (taskerSenderPackageInput == null) return;
        String packageName = taskerSenderPackageInput.getText().toString().trim();
        android.content.SharedPreferences prefs =
                getSharedPreferences(FxYulongAdTaskerReceiver.PREFS_NAME, MODE_PRIVATE);
        if (packageName.isEmpty()) {
            boolean saved = prefs.edit()
                    .remove(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE)
                    .remove(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_CERT_SHA256)
                    .putBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false)
                    .commit();
            if (!saved) {
                Toast.makeText(this, "清除授权包名失败，原设置保持不变。", Toast.LENGTH_LONG).show();
                return;
            }
            updatingTaskerControlSwitch = true;
            taskerExternalControl.setChecked(false);
            updatingTaskerControlSwitch = false;
            taskerExternalControl.setEnabled(false);
            Toast.makeText(this, "已清除自动化发送方授权，外部 Root 控制已关闭。", Toast.LENGTH_LONG).show();
            refreshTaskerResultStatus();
            return;
        }
        if (!FxYulongTaskerCallerPolicy.isValidPackageName(packageName)) {
            Toast.makeText(this, "包名格式无效；请输入完整的 Android 应用包名。", Toast.LENGTH_LONG).show();
            return;
        }
        if (!isAutomationSenderInstalled(packageName)) {
            Toast.makeText(this, "该包名未安装或不可见；请核对自动化应用包名。", Toast.LENGTH_LONG).show();
            return;
        }
        String signerDigest = getAutomationSenderSignerDigest(packageName);
        if (signerDigest.isEmpty()) {
            Toast.makeText(this, "无法读取该自动化应用的签名证书；为安全起见，不保存授权。", Toast.LENGTH_LONG).show();
            return;
        }
        boolean saved = prefs.edit()
                .putString(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE, packageName)
                .putString(FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_CERT_SHA256, signerDigest)
                .putBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false)
                .commit();
        if (!saved) {
            Toast.makeText(this, "授权包名保存失败，原设置保持不变。", Toast.LENGTH_LONG).show();
            return;
        }
        updatingTaskerControlSwitch = true;
        taskerExternalControl.setChecked(false);
        updatingTaskerControlSwitch = false;
        taskerExternalControl.setEnabled(Build.VERSION.SDK_INT >= 34);
        Toast.makeText(this, Build.VERSION.SDK_INT >= 34
                ? "已保存授权发送方 " + packageName + "；请再次手动开启外部控制。"
                : "已保存包名，但当前 Android 版本无法验证发送方身份，因此 Root 自动化不可用。",
                Toast.LENGTH_LONG).show();
        refreshTaskerResultStatus();
    }

    private void refreshTaskerResultStatus() {
        if (taskerResultStatus == null || isFinishing() || isDestroyed()) return;
        android.content.SharedPreferences prefs =
                getSharedPreferences(FxYulongAdTaskerReceiver.PREFS_NAME, MODE_PRIVATE);
        String allowedPackage = prefs.getString(
                FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_PACKAGE, "");
        String allowedSignerDigest = prefs.getString(
                FxYulongAdTaskerReceiver.PREF_ALLOWED_SENDER_CERT_SHA256, "");
        boolean senderInstalled = isAutomationSenderInstalled(allowedPackage);
        boolean signerPinned = senderInstalled
                && isAutomationSenderPinned(allowedPackage, allowedSignerDigest);
        boolean senderReady = Build.VERSION.SDK_INT >= 34 && signerPinned;
        boolean allowed = prefs.getBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false);
        if (taskerExternalControl != null) {
            taskerExternalControl.setEnabled(senderReady);
            if (!senderReady && taskerExternalControl.isChecked()) {
                updatingTaskerControlSwitch = true;
                taskerExternalControl.setChecked(false);
                updatingTaskerControlSwitch = false;
                prefs.edit().putBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false).commit();
                allowed = false;
            }
        }
        if (taskerSecurityStatus != null) {
            String message = Build.VERSION.SDK_INT < 34
                    ? "安全状态：Android 14 以下无法可靠验证广播发起应用，Root 自动化已禁用。"
                    : !senderInstalled
                        ? "安全状态：未指定有效且已安装的自动化发送方；Root 自动化不会执行。"
                        : !signerPinned
                            ? "安全状态：授权应用的签名证书无法读取或已变化；请重新验证并保存包名，再手动授权。"
                            : "安全状态：仅接受包名 " + allowedPackage
                                + "、UID 映射与已固定的签名证书均匹配的广播；仍需手动开启下方授权开关。";
            taskerSecurityStatus.setText(message);
        }
        if (!prefs.contains(FxYulongAdTaskerReceiver.PREF_LAST_AT)) {
            boolean persistedAllowed = prefs.getBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false);
            taskerResultStatus.setText(persistedAllowed
                    ? "已授权发送方 " + allowedPackage + "（包名/UID/签名固定）；尚未收到执行回执。"
                    : "外部自动化控制当前关闭；未授权广播不会执行 Root 操作。尚无最近执行回执。");
            return;
        }
        String action = prefs.getString(FxYulongAdTaskerReceiver.PREF_LAST_ACTION, "未知动作");
        String target = prefs.getString(FxYulongAdTaskerReceiver.PREF_LAST_TARGET, "未知目标");
        boolean requested = prefs.getInt(FxYulongAdTaskerReceiver.PREF_LAST_ENABLED, -1) == 1;
        boolean success = prefs.getBoolean(FxYulongAdTaskerReceiver.PREF_LAST_SUCCESS, false);
        int exitCode = prefs.getInt(FxYulongAdTaskerReceiver.PREF_LAST_EXIT_CODE, -1);
        String detail = prefs.getString(FxYulongAdTaskerReceiver.PREF_LAST_DETAIL, "");
        long timestamp = prefs.getLong(FxYulongAdTaskerReceiver.PREF_LAST_AT, 0L);
        String date = java.text.DateFormat.getDateTimeInstance(
                java.text.DateFormat.MEDIUM, java.text.DateFormat.MEDIUM)
                .format(new java.util.Date(timestamp));
        StringBuilder display = new StringBuilder();
        display.append("最近执行：").append(date)
                .append("\n控制目标：").append("vpn".equals(target) ? "FX VPN" : "广告过滤")
                .append(" · 请求状态：").append(requested ? "开启" : "关闭")
                .append("\n动作：").append(action)
                .append("\n命令结果：").append(success ? "执行成功" : "执行失败")
                .append(" · 退出码：").append(exitCode);
        if (!detail.isEmpty()) display.append("\n回执详情：").append(detail);
        display.append("\n外部自动化授权：")
                .append(prefs.getBoolean(FxYulongAdTaskerReceiver.PREF_ALLOW_EXTERNAL, false)
                        ? "已开启（仅接受 " + allowedPackage + " 且发送包名、UID 映射、固定签名均匹配的请求）"
                        : "已关闭（后续外部请求将在 Root 执行前被拒绝）");
        display.append("\n注意：这是最近一次广播命令回执，不代表该服务当前仍处于运行状态。");
        taskerResultStatus.setText(display.toString());
    }

    private void confirmClearTaskerReceipt() {
        new AlertDialog.Builder(this)
                .setTitle("清除自动化执行回执")
                .setMessage("仅清除最近一次 Tasker / 自动化命令的本地执行记录，不会更改已固定的发送方、授权开关或任何 VPN / 广告过滤运行状态。此操作不可撤销。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清除记录", (dialog, which) -> clearTaskerReceipt())
                .show();
    }

    private void clearTaskerReceipt() {
        android.content.SharedPreferences prefs =
                getSharedPreferences(FxYulongAdTaskerReceiver.PREFS_NAME, MODE_PRIVATE);
        boolean cleared = prefs.edit()
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_ACTION)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_TARGET)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_ENABLED)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_SUCCESS)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_EXIT_CODE)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_DETAIL)
                .remove(FxYulongAdTaskerReceiver.PREF_LAST_AT)
                .commit();
        if (!cleared) {
            Toast.makeText(this, "清除执行回执失败，原记录保持不变。", Toast.LENGTH_LONG).show();
            return;
        }
        refreshTaskerResultStatus();
        Toast.makeText(this, "最近执行回执已清除；自动化授权和服务状态未更改。",
                Toast.LENGTH_SHORT).show();
    }

    private void requestHomeWidgetPin() {
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(this);
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                    || !manager.isRequestPinAppWidgetSupported()) {
                Toast.makeText(this, "当前桌面启动器不支持应用内固定小组件；请长按桌面并从小组件列表添加 FX。", Toast.LENGTH_LONG).show();
                return;
            }
            boolean requested = manager.requestPinAppWidget(
                    new ComponentName(this, FxYulongAdWidgetProvider.class), null, null);
            Toast.makeText(this, requested
                    ? "已向桌面请求添加小组件，请在桌面提示中确认。"
                    : "桌面未接受添加请求；请从桌面小组件列表手动添加 FX。", Toast.LENGTH_LONG).show();
        } catch (RuntimeException error) {
            Toast.makeText(this, "请求添加桌面小组件失败：" + error.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
        }
    }

    private void copyTaskerAction(String label, String action) {
        try {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard == null) throw new IllegalStateException("系统剪贴板不可用");
            clipboard.setPrimaryClip(ClipData.newPlainText("FX Tasker action", action));
            Toast.makeText(this, label + "动作标识已复制。", Toast.LENGTH_SHORT).show();
        } catch (RuntimeException error) {
            Toast.makeText(this, "复制自动化动作失败：" + error.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
        }
    }

    private void requestQuickSettingsTile(Class<? extends TileService> serviceClass, String label) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Toast.makeText(this, "当前 Android 版本不支持应用内添加快捷磁贴；请从系统快捷设置编辑器添加。", Toast.LENGTH_LONG).show();
            return;
        }
        // requestAddTileService() is an instance method on TileService, not an
        // Activity API. Do not invoke a nonexistent static overload or claim the
        // system accepted a request. The service remains registered and usable
        // once the user adds it from the system Quick Settings editor.
        String serviceName = serviceClass == null ? "FX 磁贴" : serviceClass.getSimpleName();
        String message = label + "（" + serviceName + "）已在 FX 中注册。"
                + "\n请下拉系统快捷设置面板，点“编辑 / 铅笔”，在可用磁贴中找到 FX 的"
                + label + "并手动添加。添加完成后即可正常使用。";
        new AlertDialog.Builder(this)
                .setTitle("添加快捷设置磁贴")
                .setMessage(message)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void openPage(String page) {
        startActivity(new Intent(this, FxYulongAdActivity.class).putExtra("suite_page", page));
    }

    private void refreshBatteryStatus() {
        try {
            PowerManager pm = (PowerManager)getSystemService(POWER_SERVICE);
            boolean ignored = pm != null && pm.isIgnoringBatteryOptimizations(getPackageName());
            batteryStatus.setText(ignored
                    ? "FX 当前已被系统豁免电池优化。"
                    : "FX 当前未被系统豁免电池优化；后台调度可能受系统限制。");
        } catch (Throwable error) {
            batteryStatus.setText("无法读取系统电池优化状态：" + error.getClass().getSimpleName());
        }
    }

    private void openBatterySettings() {
        try {
            startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
        } catch (Throwable error) {
            try { startActivity(new Intent(Settings.ACTION_SETTINGS)); }
            catch (Throwable ignored) { batteryStatus.setText("无法打开系统设置。"); }
        }
    }

    private String rootCommand(String args) {
        return FxYulongRootModuleCommand.command("yulong-ad-control.sh", args);
    }

    private RootAccess.Result root(String args) {
        return RootAccess.execute(rootCommand(args), 60000L, 1024 * 1024);
    }

    private JSONObject exportSnapshot() throws Exception {
        RootAccess.Result list = root("list");
        if (list.exitCode != 0) throw new IllegalStateException("读取过滤列表失败：" + safe(list.output));
        RootAccess.Result dns = root("dns-config-get");
        if (dns.exitCode != 0) throw new IllegalStateException("读取 DNS 配置失败：" + safe(dns.output));
        RootAccess.Result schedule = root("schedule-get");
        if (schedule.exitCode != 0) throw new IllegalStateException("读取过滤计划失败：" + safe(schedule.output));

        JSONObject out = new JSONObject();
        out.put("schema", "FX_YULONG_AD_SETTINGS_V1");
        out.put("sourceVersion", "7.0.1");
        out.put("exportedAt", System.currentTimeMillis());
        JSONArray rules = new JSONArray(), allow = new JSONArray(), block = new JSONArray();
        JSONObject dnsFlags = new JSONObject();
        for (String line : lines(list.output)) {
            String[] p = line.split("\\|", -1);
            if (p.length == 2 && "AD_MASTER".equals(p[0])) out.put("adMaster", "1".equals(p[1]));
            else if (p.length >= 4 && "RULE".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("source", p[1]); item.put("title", p[2]);
                item.put("enabled", "1".equals(p[3])); rules.put(item);
            } else if (p.length >= 4 && "ALLOW".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("domain", p[1]); item.put("note", p[2]);
                item.put("enabled", "1".equals(p[3])); allow.put(item);
            } else if (p.length >= 4 && "BLOCK".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("domain", p[1]); item.put("note", p[2]);
                item.put("enabled", "1".equals(p[3])); block.put(item);
            } else if (p.length == 3 && "DNS".equals(p[0])) dnsFlags.put(p[1], "1".equals(p[2]));
        }
        out.put("rules", rules); out.put("allowDomains", allow); out.put("blockDomains", block);
        out.put("dnsFlags", dnsFlags);

        JSONObject dnsConfig = new JSONObject();
        JSONArray custom = new JSONArray(), global = new JSONArray();
        for (String line : lines(dns.output)) {
            String[] p = line.split("\\|", -1);
            if (p.length == 2 && "CUSTOM_ENABLED".equals(p[0])) dnsConfig.put("customEnabled", "1".equals(p[1]));
            else if (p.length == 2 && "GLOBAL_ENABLED".equals(p[0])) dnsConfig.put("globalEnabled", "1".equals(p[1]));
            else if (p.length == 2 && "CUSTOM".equals(p[0])) custom.put(p[1]);
            else if (p.length == 2 && "GLOBAL".equals(p[0])) global.put(p[1]);
            else if (p.length == 2 && "VPN_REMOTE".equals(p[0])) dnsConfig.put("vpnRemote", p[1]);
            else if (p.length == 2 && "VPN_CN".equals(p[0])) dnsConfig.put("vpnCn", p[1]);
        }
        dnsConfig.put("customServers", custom); dnsConfig.put("globalServers", global);
        out.put("dnsConfig", dnsConfig);

        JSONObject plan = new JSONObject();
        for (String line : lines(schedule.output)) {
            int eq = line.indexOf('='); if (eq <= 0) continue;
            String key = line.substring(0, eq), value = line.substring(eq + 1);
            if ("enabled".equals(key)) plan.put(key, "1".equals(value));
            else if ("start".equals(key) || "end".equals(key) || "days".equals(key)) plan.put(key, value);
        }
        out.put("schedule", plan);
        return out;
    }

    private List<String> lines(String text) {
        List<String> out = new ArrayList<>();
        if (text == null) return out;
        for (String line : text.split("\\r?\\n")) {
            String v = line.trim(); if (!v.isEmpty()) out.add(v);
        }
        return out;
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        out.putString(STATE_PENDING_EXPORT, pendingExport);
        out.putBoolean(STATE_IMPORT_PENDING, importRequestPending);
        out.putBoolean(STATE_EXPORT_PENDING, exportRequestPending);
        super.onSaveInstanceState(out);
    }

    private void exportSettings() {
        operationStatus.setText("正在读取 FX 设备端配置…");
        submitWorker(() -> {
            try {
                JSONObject json = exportSnapshot();
                String output = json.toString(2);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    pendingExport = output;
                    exportRequestPending = true;
                    Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("application/json");
                    intent.putExtra(Intent.EXTRA_TITLE, "fx-yulong-ad-settings.json");
                    try { startActivityForResult(intent, EXPORT_REQUEST); }
                    catch (RuntimeException error) {
                        exportRequestPending = false;
                        pendingExport = null;
                        operationStatus.setText("无法打开导出文件选择器，本次导出已取消。");
                    }
                });
            } catch (Throwable error) { showError("导出失败", error); }
        });
    }

    private void pickImport() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        importRequestPending = true;
        try { startActivityForResult(intent, IMPORT_REQUEST); }
        catch (RuntimeException error) {
            importRequestPending = false;
            operationStatus.setText("无法打开导入文件选择器，本次导入已取消。");
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == EXPORT_REQUEST) {
            if (!exportRequestPending) return;
            exportRequestPending = false;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                pendingExport = null;
                if (operationStatus != null) operationStatus.setText("导出已取消，未写入文件。");
                return;
            }
            writeExport(data.getData());
        } else if (requestCode == IMPORT_REQUEST) {
            if (!importRequestPending) return;
            importRequestPending = false;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                if (operationStatus != null) operationStatus.setText("导入已取消，设备配置未更改。");
                return;
            }
            readImport(data.getData());
        }
    }

    private void writeExport(Uri uri) {
        final String output = pendingExport;
        pendingExport = null;
        if (output == null) return;
        operationStatus.setText("正在写入 JSON 备份…");
        submitWorker(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri, "w")) {
                if (stream == null) throw new IllegalStateException("无法创建导出文件。");
                stream.write(output.getBytes(StandardCharsets.UTF_8)); stream.flush();
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) operationStatus.setText("过滤设置备份已导出。"); });
            } catch (Throwable error) { showError("导出失败", error); }
        });
    }

    private void readImport(Uri uri) {
        operationStatus.setText("正在读取 JSON 备份…");
        submitWorker(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选文件。");
                byte[] buffer = new byte[8192]; int n;
                while ((n = input.read(buffer)) != -1) {
                    if (output.size() > MAX_BACKUP_BYTES - n) throw new IllegalArgumentException("备份文件超过 1 MiB。");
                    output.write(buffer, 0, n);
                }
                JSONObject json = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
                validateBackup(json);
                runOnUiThread(() -> fxDialogBuilder()
                        .setTitle("确认导入过滤设置")
                        .setMessage("这会替换当前FX 广告过滤来源、域名白/黑名单、DNS 开关和每周过滤计划。导入失败时会恢复导入前配置。")
                        .setNegativeButton("取消", null)
                        .setPositiveButton("备份并导入", (d, w) -> applyImport(json))
                        .show());
            } catch (Throwable error) { showError("导入文件无效", error); }
        });
    }

    private void validateBackup(JSONObject json) throws Exception {
        if (!"FX_YULONG_AD_SETTINGS_V1".equals(json.optString("schema")))
            throw new IllegalArgumentException("不支持的备份格式。");
        if (json.optJSONArray("rules") == null || json.optJSONArray("allowDomains") == null
                || json.optJSONArray("blockDomains") == null || json.optJSONObject("dnsFlags") == null
                || json.optJSONObject("dnsConfig") == null || json.optJSONObject("schedule") == null)
            throw new IllegalArgumentException("备份缺少必需的数据段。");
        JSONArray rules = json.getJSONArray("rules");
        JSONArray allow = json.getJSONArray("allowDomains");
        JSONArray block = json.getJSONArray("blockDomains");
        if (rules.length() > 500 || allow.length() > 3000 || block.length() > 3000)
            throw new IllegalArgumentException("备份条目超过上限。");
        if (json.has("adMaster") && !(json.opt("adMaster") instanceof Boolean))
            throw new IllegalArgumentException("广告总开关格式错误。");

        for (int i = 0; i < rules.length(); i++) {
            JSONObject row = rules.getJSONObject(i);
            String source = requireOptionalString(row, "source", "");
            String title = requireOptionalString(row, "title", "");
            if (!FxYulongAdBackupValidation.isValidSource(source)
                    || !FxYulongAdBackupValidation.isValidText(title))
                throw new IllegalArgumentException("第 " + (i + 1) + " 条过滤源无效。");
            validateOptionalBoolean(row, "enabled", "过滤源启用状态");
        }
        validateDomainRows(allow, "白名单");
        validateDomainRows(block, "黑名单");

        JSONObject dnsFlags = json.getJSONObject("dnsFlags");
        Set<String> allowedDnsFlags = new HashSet<>(java.util.Arrays.asList(
                "dns_engine_adguardhome", "dns_forward", "custom_dns", "global_dns",
                "block_quic", "block_dot", "block_plain_dns", "block_ipv6",
                "block_track_domains", "vpn_external_dns_proxy", "vpn_external_compat",
                "dns_querylog_enabled"));
        java.util.Iterator<String> flagKeys = dnsFlags.keys();
        while (flagKeys.hasNext()) {
            String key = flagKeys.next();
            if (!allowedDnsFlags.contains(key))
                throw new IllegalArgumentException("不支持的 DNS 开关：" + key);
            if (!(dnsFlags.opt(key) instanceof Boolean))
                throw new IllegalArgumentException("DNS 开关格式错误：" + key);
        }

        JSONObject dns = json.getJSONObject("dnsConfig");
        validateOptionalBoolean(dns, "customEnabled", "自定义 DNS 启用状态");
        validateOptionalBoolean(dns, "globalEnabled", "全局 DNS 启用状态");
        if (dns.optJSONArray("customServers") == null || dns.optJSONArray("globalServers") == null)
            throw new IllegalArgumentException("DNS 服务器列表缺失。");
        validateDnsServers(dns.optJSONArray("customServers"), false, "自定义 DNS");
        validateDnsServers(dns.optJSONArray("globalServers"), true, "全局 DNS");
        validateOptionalIpv4(dns, "vpnRemote", "VPN 远端 DNS");
        validateOptionalIpv4(dns, "vpnCn", "VPN 国内 DNS");

        JSONObject schedule = json.getJSONObject("schedule");
        validateOptionalBoolean(schedule, "enabled", "过滤计划启用状态");
        String startTime = requireOptionalString(schedule, "start", "22:00");
        String endTime = requireOptionalString(schedule, "end", "07:00");
        String days = requireOptionalString(schedule, "days", "1,2,3,4,5,6,7");
        if (!startTime.matches("([01][0-9]|2[0-3]):[0-5][0-9]")
                || !endTime.matches("([01][0-9]|2[0-3]):[0-5][0-9]")
                || !validScheduleDays(days))
            throw new IllegalArgumentException("过滤计划时间/星期格式无效。");
    }

    private void validateDomainRows(JSONArray rows, String label) throws Exception {
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            String domain = requireOptionalString(row, "domain", "");
            String note = requireOptionalString(row, "note", "FX " + label);
            if (!FxYulongAdBackupValidation.isValidDomain(domain)
                    || !FxYulongAdBackupValidation.isValidText(note))
                throw new IllegalArgumentException(label + "第 " + (i + 1) + " 条域名或备注无效。");
            validateOptionalBoolean(row, "enabled", label + "条目启用状态");
        }
    }

    private void validateDnsServers(JSONArray array, boolean ipv4Only, String label) throws Exception {
        if (array == null) return;
        if (array.length() > 3) throw new IllegalArgumentException(label + "最多 3 个端点。");
        for (int i = 0; i < array.length(); i++) {
            Object raw = array.get(i);
            if (!(raw instanceof String)
                    || !FxYulongAdBackupValidation.isValidDnsEndpoint((String) raw, ipv4Only))
                throw new IllegalArgumentException(label + "第 " + (i + 1) + " 个端点无效。");
        }
    }

    private void validateOptionalIpv4(JSONObject object, String key, String label) throws Exception {
        if (!object.has(key)) return;
        Object raw = object.get(key);
        if (!(raw instanceof String) || (!((String) raw).isEmpty()
                && !FxYulongAdBackupValidation.isValidIpv4((String) raw)))
            throw new IllegalArgumentException(label + "地址无效。");
    }

    private void validateOptionalBoolean(JSONObject object, String key, String label) {
        if (object.has(key) && !(object.opt(key) instanceof Boolean))
            throw new IllegalArgumentException(label + "格式错误。");
    }

    private String requireOptionalString(JSONObject object, String key, String fallback) {
        if (!object.has(key)) return fallback;
        Object raw = object.opt(key);
        if (!(raw instanceof String)) throw new IllegalArgumentException(key + " 必须是字符串。");
        return (String) raw;
    }

    private boolean validScheduleDays(String days) {
        if (days == null || days.isEmpty()) return false;
        Set<String> seen = new HashSet<>();
        for (String day : days.split(",", -1)) {
            if (!day.matches("[1-7]") || !seen.add(day)) return false;
        }
        return true;
    }

    private String dnsCsv(JSONArray array, boolean ipv4Only) throws Exception {
        List<String> values = new ArrayList<>();
        if (array == null) return "";
        if (array.length() > 3) throw new IllegalArgumentException("每类 DNS 最多 3 个端点。");
        for (int i = 0; i < array.length(); i++) {
            Object raw = array.get(i);
            if (!(raw instanceof String)
                    || !FxYulongAdBackupValidation.isValidDnsEndpoint((String) raw, ipv4Only))
                throw new IllegalArgumentException("DNS 端点无效：" + String.valueOf(raw));
            values.add((String) raw);
        }
        return String.join(",", values);
    }

    private String quote(String value) { return "'" + value.replace("'", "'\''") + "'"; }
    private boolean validIpv4(String value) {
        if (value == null || !value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")) return false;
        for (String part : value.split("\\.")) if (Integer.parseInt(part)>255) return false;
        return true;
    }
    private String csv(JSONArray array) throws Exception {
        List<String> values=new ArrayList<>();
        for(int i=0;i<array.length();i++){String value=array.getString(i);if(!validIpv4(value))throw new IllegalArgumentException("DNS 地址无效："+value);values.add(value);}
        if(values.size()>3)throw new IllegalArgumentException("每类 DNS 最多 3 个 IPv4 地址。");
        return String.join(",",values);
    }

    private void applyImport(JSONObject json) {
        operationStatus.setText("正在备份并导入设备端配置…");
        try {
            worker.execute(() -> {
                long gateToken = 0L;
                try {
                gateToken = FxYulongAdOperationGate.tryAcquire();
                if (gateToken == 0L) {
                    runOnUiThread(() -> { if (!isFinishing() && !isDestroyed())
                        operationStatus.setText("另一入口正在修改广告过滤，请稍后再导入。"); });
                    return;
                }
                RootAccess.Result current=root("list");
                if(current.exitCode!=0)throw new IllegalStateException("读取现有设置失败："+safe(current.output));
                StringBuilder command=new StringBuilder("set -eu; ");
                command.append(FxYulongRootModuleCommand.prefix("yulong-ad-control.sh"))
                        .append("PG=/data/adb/privacyguard; CONF=$PG/settings.conf; PLAN=$PG/yulong-ad-schedule.conf; ")
                        .append("test -d \"$PG\" && test ! -L \"$PG\" && test -f \"$CONF\" && test ! -L \"$CONF\" || exit 21; ")
                        .append("B1=$(mktemp \"$PG/yulong-ad-import-settings.rollback.XXXXXX\") || exit 22; B2=''; ")
                        .append("cp -p \"$CONF\" \"$B1\" || { rm -f \"$B1\"; exit 23; }; ")
                        .append("HAD_PLAN=0; if [ -L \"$PLAN\" ]; then rm -f \"$B1\"; echo \"refusing symlink schedule file\" >&2; exit 24; fi; ")
                        .append("if [ -f \"$PLAN\" ]; then B2=$(mktemp \"$PG/yulong-ad-import-schedule.rollback.XXXXXX\") || { rm -f \"$B1\"; exit 25; }; ")
                        .append("cp -p \"$PLAN\" \"$B2\" || { rm -f \"$B1\" \"$B2\"; exit 26; }; HAD_PLAN=1; fi; ")
                        .append("COMMITTED=0; rollback(){ rc=$?; trap - EXIT HUP INT TERM; ROLLBACK_FAILED=0; R1=''; R2=''; ")
                        .append("if [ \"$COMMITTED\" != 1 ]; then ")
                        .append("R1=$(mktemp \"$CONF.restore.XXXXXX\") || ROLLBACK_FAILED=1; ")
                        .append("if [ \"$ROLLBACK_FAILED\" = 0 ] && cp -p \"$B1\" \"$R1\" && chmod 600 \"$R1\" && mv -f \"$R1\" \"$CONF\"; then :; else ")
                        .append("[ -z \"$R1\" ] || rm -f \"$R1\"; ROLLBACK_FAILED=1; fi; ")
                        .append("if [ \"$HAD_PLAN\" = 1 ]; then R2=$(mktemp \"$PLAN.restore.XXXXXX\") || ROLLBACK_FAILED=1; ")
                        .append("if [ \"$ROLLBACK_FAILED\" = 0 ] && cp -p \"$B2\" \"$R2\" && chmod 600 \"$R2\" && mv -f \"$R2\" \"$PLAN\"; then :; else ")
                        .append("[ -z \"$R2\" ] || rm -f \"$R2\"; ROLLBACK_FAILED=1; fi; else ")
                        .append("if [ -L \"$PLAN\" ]; then ROLLBACK_FAILED=1; else rm -f \"$PLAN\" || ROLLBACK_FAILED=1; fi; fi; ")
                        .append("if [ \"$ROLLBACK_FAILED\" = 0 ]; then if sh \"$MP/scripts/apply.sh\" fast >/dev/null 2>&1; then ")
                        .append("rm -f \"$B1\"; [ -z \"$B2\" ] || rm -f \"$B2\"; echo \"rollback=restored_and_applied\" >&2; ")
                        .append("else ROLLBACK_FAILED=1; echo \"rollback files restored but runtime apply failed\" >&2; fi; fi; ")
                        .append("if [ \"$ROLLBACK_FAILED\" != 0 ]; then echo \"ROLLBACK_FAILED: preserved backup files $B1 $B2\" >&2; exit 35; fi; exit \"$rc\"; ")
                        .append("fi; rm -f \"$B1\"; [ -z \"$B2\" ] || rm -f \"$B2\"; exit \"$rc\"; }; trap rollback EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; ");
                for(String line:lines(current.output)){
                    String[] p=line.split("\\|",-1); if(p.length<2)continue;
                    if("RULE".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" rule-remove ").append(quote(p[1])).append("; ");
                    else if("ALLOW".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" allow-remove ").append(quote(p[1])).append("; ");
                    else if("BLOCK".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" block-remove ").append(quote(p[1])).append("; ");
                }
                JSONArray rules=json.getJSONArray("rules");
                for(int i=0;i<rules.length();i++){
                    JSONObject row=rules.getJSONObject(i);
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" rule-add ")
                            .append(quote(row.getString("source"))).append(" ")
                            .append(quote(row.getString("title"))).append(" ")
                            .append(row.optBoolean("enabled",true)?"1":"0").append("; ");
                }
                JSONArray allow=json.getJSONArray("allowDomains");
                for(int i=0;i<allow.length();i++){
                    JSONObject row=allow.getJSONObject(i);if(!row.optBoolean("enabled",true))continue;
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" allow-add ")
                            .append(quote(row.getString("domain"))).append(" ")
                            .append(quote(row.optString("note","FX 白名单"))).append("; ");
                }
                JSONArray block=json.getJSONArray("blockDomains");
                for(int i=0;i<block.length();i++){
                    JSONObject row=block.getJSONObject(i);if(!row.optBoolean("enabled",true))continue;
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" block-add ")
                            .append(quote(row.getString("domain"))).append(" ")
                            .append(quote(row.optString("note","FX 黑名单"))).append("; ");
                }
                JSONObject flags=json.getJSONObject("dnsFlags");
                java.util.Iterator<String> keys=flags.keys();
                while(keys.hasNext()){
                    String key=keys.next(); boolean value=flags.optBoolean(key,false);
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-set ")
                            .append(quote(key)).append(" ").append(value?"1":"0").append("; ");
                }
                JSONObject dns=json.getJSONObject("dnsConfig");
                String custom=dnsCsv(dns.optJSONArray("customServers"), false);
                String global=dnsCsv(dns.optJSONArray("globalServers"), true);
                if(!custom.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-config-set custom ").append(quote(custom)).append("; ");
                if(!global.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-config-set global ").append(quote(global)).append("; ");
                String remote=dns.optString("vpnRemote",""), cn=dns.optString("vpnCn","");
                if(!remote.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-vpn-set remote_dns ").append(quote(remote)).append("; ");
                if(!cn.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-vpn-set cn_dns ").append(quote(cn)).append("; ");
                command.append("sh \"$MP/scripts/yulong-ad-control.sh\" ad-master ").append(json.optBoolean("adMaster",true)?"1":"0").append("; ");
                JSONObject schedule=json.getJSONObject("schedule");
                command.append("sh \"$MP/scripts/yulong-ad-control.sh\" schedule-set ")
                        .append(schedule.optBoolean("enabled",false)?"1":"0").append(" ")
                        .append(quote(schedule.optString("start","22:00"))).append(" ")
                        .append(quote(schedule.optString("end","07:00"))).append(" ")
                        .append(quote(schedule.optString("days","1,2,3,4,5,6,7"))).append("; ");
                command.append("COMMITTED=1; rm -f \"$B1\"; [ -z \"$B2\" ] || rm -f \"$B2\"; trap - EXIT; echo import=success");
                if(command.length()>120000)throw new IllegalArgumentException("恢复命令超过安全长度限制。");
                RootAccess.Result result=RootAccess.execute(command.toString(),180000L,1024*1024);
                if(result.exitCode!=0)throw new IllegalStateException("设备端回滚/导入失败："+safe(result.output));
                runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())operationStatus.setText("导入完成。配置已原子备份并逐项应用："+safe(result.output));});
                } catch(Throwable error) {
                    showError("导入失败", error);
                } finally {
                    if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);
                }
            });
        } catch (RejectedExecutionException full) {
            operationStatus.setText("后台任务繁忙，导入未开始。");
        }
    }

    private String safe(String value) { return value==null||value.trim().isEmpty()?"无错误详情":value.trim(); }
    private void showError(String title, Throwable error) {
        String message=error.getMessage()==null?error.getClass().getSimpleName():error.getMessage();
        runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())operationStatus.setText(title+"："+message);});
    }

    @Override protected void onDestroy() {
        unregisterTaskerResultReceiver();
        worker.shutdownNow();
        super.onDestroy();
    }
}
