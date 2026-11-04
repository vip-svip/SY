package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/** Native Dia crash report viewer; copy and share are explicit user actions. */
public final class FxDiaCrashReportActivity extends Activity {
    private FxDiaCrashRecord record;
    private boolean unreadablePendingReport;
    private CheckBox hexStack;
    private TextView reportView;
    private TextView statusView;
    private TextView nativeCaptureStatus;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
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
        boolean hadPendingReport = FxDiaCrashStore.hasPendingReport(this);
        record = FxDiaCrashStore.read(this);
        unreadablePendingReport = hadPendingReport && record == null;
        if (hadPendingReport) FxDiaCrashStore.clearPendingFlag(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · 崩溃报告", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(8), dp(14), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        body.addView(text("崩溃捕获范围", 16, 0xff17212b, true));
        body.addView(text(
                "捕获范围：FX APK 当前应用进程内的 Java 未捕获异常，以及可用 ABI 上由 Dia 原版 Breakpad 捕获的 Native 崩溃。不会捕获 LSPosed 目标应用进程、内核崩溃或其他应用的异常。Native minidump 保存在 FX 私有 files/dia-native-crash/，报告保存在 FX 私有 files/crash.log。",
                12, 0xff617080, false));
        Switch captureSwitch = new Switch(this);
        captureSwitch.setText("启用 FX Java + Native 崩溃捕获");
        captureSwitch.setChecked(FxDiaCrashStore.isCaptureEnabled(this));
        captureSwitch.setOnCheckedChangeListener((button, enabled) -> {
            if (!FxDiaCrashStore.setCaptureEnabled(this, enabled)) {
                button.setChecked(!enabled);
                Toast.makeText(this, "无法保存崩溃捕获设置，请检查应用存储空间。",
                        Toast.LENGTH_LONG).show();
            }
            updateNativeCaptureStatus();
        });
        body.addView(captureSwitch);
        nativeCaptureStatus = text("", 12, 0xff617080, false);
        body.addView(nativeCaptureStatus);
        statusView = text("", 13, 0xff526170, false);
        body.addView(statusView);
        hexStack = new CheckBox(this);
        hexStack.setText("堆栈 HEX 编码（原版称“加密堆栈”）");
        hexStack.setChecked(getSharedPreferences("fx_dia_crash", MODE_PRIVATE)
                .getBoolean("encrypt_stack", true));
        hexStack.setOnCheckedChangeListener((button, checked) -> {
            getSharedPreferences("fx_dia_crash", MODE_PRIVATE).edit()
                    .putBoolean("encrypt_stack", checked).apply();
            render();
        });
        body.addView(hexStack);
        body.addView(text(
                "说明：原版 ByteUtil 将堆栈 UTF-8 字节转换为小写十六进制文本。这只是可逆编码，不是密码学加密；分享前请检查报告内容。",
                12, 0xff8a5b12, false));
        reportView = text("", 12, 0xff344054, false);
        reportView.setTypeface(android.graphics.Typeface.MONOSPACE);
        reportView.setTextIsSelectable(true);
        body.addView(text("报告内容", 16, 0xff17212b, true));
        body.addView(reportView);
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(button("复制报告", this::copyReport),
                new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("分享报告", this::shareReport),
                new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(actions);
        body.addView(text(
                "复制和分享会自动脱敏常见令牌、密码、Cookie、Authorization 和 URL 凭据；本地报告视图仍保留原始内容供诊断。脱敏不能识别所有自定义秘密，分享前仍应检查。",
                11, 0xff607080, false));
        body.addView(button("清除崩溃记录", this::confirmClear));
        body.addView(button("关闭", this::finish));
        setContentView(root);
        updateNativeCaptureStatus();
        render();
    }

    private void updateNativeCaptureStatus() {
        if (nativeCaptureStatus != null) {
            nativeCaptureStatus.setText(FxDiaNativeCrashCapture.statusLine(this));
        }
    }

    private void render() {
        if (record == null) {
            if (unreadablePendingReport) {
                statusView.setText("检测到上次启动留下的崩溃标记，但私有 crash.log 无法解析或超过 512 KiB 上限。原始文件已保留，没有把这次崩溃误显示为“无记录”；你可以清除损坏记录后继续使用。");
                reportView.setText("(崩溃记录不可读取；原始 crash.log 保留在 FX 私有 files 目录)");
            } else {
                statusView.setText("目前没有可读取的崩溃记录。启用捕获后，FX 自身进程下次发生 Java 未捕获异常时会在下一次启动显示报告。");
                reportView.setText("(无崩溃记录)");
            }
            return;
        }
        statusView.setText("已读取一条 FX 私有崩溃记录。捕获开关仅影响后续异常。");
        reportView.setText(record.format(hexStack != null && hexStack.isChecked()));
    }

    private String reportText() {
        return FxDiaCrashExportFormatter.format(
                record, hexStack != null && hexStack.isChecked());
    }

    private void copyReport() {
        String content = reportText();
        if (content.isEmpty()) {
            Toast.makeText(this, "没有可复制的崩溃报告。", Toast.LENGTH_SHORT).show();
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null) {
            Toast.makeText(this, "剪贴板服务不可用。", Toast.LENGTH_LONG).show();
            return;
        }
        clipboard.setPrimaryClip(ClipData.newPlainText("FX crash report (redacted)", content));
        Toast.makeText(this, "已复制自动脱敏的崩溃报告。", Toast.LENGTH_SHORT).show();
    }

    private void shareReport() {
        String content = reportText();
        if (content.isEmpty()) {
            Toast.makeText(this, "没有可分享的崩溃报告。", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "FX 1.0.0 崩溃报告（已自动脱敏）");
        send.putExtra(Intent.EXTRA_TEXT, content);
        try {
            startActivity(Intent.createChooser(send, "选择分享方式"));
        } catch (RuntimeException unavailable) {
            Toast.makeText(this, "系统分享面板不可用。", Toast.LENGTH_LONG).show();
        }
    }

    private void confirmClear() {
        new AlertDialog.Builder(this)
                .setTitle("清除崩溃记录？")
                .setMessage("将删除 FX 私有 crash.log、待显示标记，以及 dia-native-crash/ 下的 Native minidump。若发现符号链接或意外子目录，将拒绝清理并保留崩溃报告。此操作不可撤销。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清除", (dialog, which) -> {
                    if (FxDiaCrashStore.clear(this)) {
                        record = null;
                        unreadablePendingReport = false;
                        render();
                        Toast.makeText(this, "崩溃记录与 Native minidump 已清除。",
                                Toast.LENGTH_SHORT).show();
                    } else {
                        Toast.makeText(this,
                                "未能确认全部清除：可能已有部分文件被删除。请检查 FX 私有目录和待显示状态后再重试；本次不会报告清除成功。",
                                Toast.LENGTH_LONG).show();
                    }
                })
                .show();
    }
}
