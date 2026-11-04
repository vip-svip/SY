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
    private CheckBox hexStack;
    private TextView reportView;
    private TextView statusView;

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
        record = FxDiaCrashStore.read(this);
        FxDiaCrashStore.clearPendingFlag(this);
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
                "只捕获 FX APK 当前应用进程的 Java 未捕获异常；不捕获 LSPosed 目标应用进程、原生 native crash、内核崩溃或其他应用的异常。记录保存在 FX 私有 files/crash.log。原系统异常处理器仍会收到并处理原始异常。",
                12, 0xff617080, false));
        Switch captureSwitch = new Switch(this);
        captureSwitch.setText("启用 FX Java 崩溃捕获");
        captureSwitch.setChecked(FxDiaCrashStore.isCaptureEnabled(this));
        captureSwitch.setOnCheckedChangeListener((button, enabled) ->
                FxDiaCrashStore.setCaptureEnabled(this, enabled));
        body.addView(captureSwitch);
        statusView = text("", 13, 0xff526170, false);
        body.addView(statusView);
        hexStack = new CheckBox(this);
        hexStack.setText("堆栈 HEX 编码（原版称“加密堆栈”）");
        hexStack.setChecked(getSharedPreferences("fx_dia_crash", MODE_PRIVATE)
                .getBoolean("hex_stack", true));
        hexStack.setOnCheckedChangeListener((button, checked) -> {
            getSharedPreferences("fx_dia_crash", MODE_PRIVATE).edit()
                    .putBoolean("hex_stack", checked).apply();
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
        body.addView(button("清除崩溃记录", this::confirmClear));
        body.addView(button("关闭", this::finish));
        setContentView(root);
        render();
    }

    private void render() {
        if (record == null) {
            statusView.setText("目前没有可读取的崩溃记录。启用捕获后，FX 自身进程下次发生 Java 未捕获异常时会在下一次启动显示报告。");
            reportView.setText("(无崩溃记录)");
            return;
        }
        statusView.setText("已读取一条 FX 私有崩溃记录。捕获开关仅影响后续异常。");
        reportView.setText(record.format(hexStack != null && hexStack.isChecked()));
    }

    private String reportText() {
        return record == null ? "" : record.format(hexStack != null && hexStack.isChecked());
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
        clipboard.setPrimaryClip(ClipData.newPlainText("FX crash report", content));
        Toast.makeText(this, "崩溃报告已复制。", Toast.LENGTH_SHORT).show();
    }

    private void shareReport() {
        String content = reportText();
        if (content.isEmpty()) {
            Toast.makeText(this, "没有可分享的崩溃报告。", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "FX 1.0.0 崩溃报告");
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
                .setMessage("将删除 FX 私有 crash.log 和待显示标记。此操作不可撤销。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清除", (dialog, which) -> {
                    FxDiaCrashStore.clear(this);
                    record = null;
                    render();
                    Toast.makeText(this, "崩溃记录已清除。", Toast.LENGTH_SHORT).show();
                })
                .show();
    }
}
