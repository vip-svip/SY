package de.privacyguard.adhook;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Native viewer for the third-party open-source notices bundled with FX Hook. */
public final class FxOpenSourceLicensesActivity extends Activity {
    private static final String[] FILES = {
            "THIRD_PARTY_NOTICES.txt",
            "Capsule-LICENSE.txt",
            "Kyant-AndroidLiquidGlass-LICENSE.txt",
            "MaterialKolor-MIT-LICENSE.txt",
            "Miuix-LICENSE.txt"
    };
    private static final int MAX_LICENSE_BYTES = 48 * 1024;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> { Thread t = new Thread(r, "fx-open-source-licenses"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private TextView status;
    private volatile boolean destroyed;

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
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("FX Hook · 开源许可", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(4), dp(12), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        body.addView(text(
                "此页面展示随 FX Hook APK 一同分发的第三方组件许可证和版权声明。"
                        + "文本来自 APK 内置 assets/licenses，不需要联网；每份文件按需读取。",
                12, 0xff5c6877, false));
        status = text("选择一份许可证查看完整文本。", 12, 0xff617080, false);
        body.addView(status);
        addLicenseRow(body, "第三方组件总声明", FILES[0]);
        addLicenseRow(body, "Capsule", FILES[1]);
        addLicenseRow(body, "Kyant Android Liquid Glass", FILES[2]);
        addLicenseRow(body, "MaterialKolor · MIT", FILES[3]);
        addLicenseRow(body, "Miuix", FILES[4]);
        setContentView(root);
    }

    private void addLicenseRow(LinearLayout body, String title, String file) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(8), dp(12), dp(8));
        card.setBackgroundColor(0xffeef2f6);
        card.addView(text(title, 14, 0xff17212b, true));
        card.addView(text(file, 11, 0xff6b7785, false));
        card.addView(button("查看许可证文本", () -> openLicense(title, file)));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(4), 0, dp(4));
        body.addView(card, params);
    }

    private String readLicense(String file) throws Exception {
        try (InputStream input = getAssets().open("licenses/" + file);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() > MAX_LICENSE_BYTES - count)
                    throw new IllegalArgumentException("许可证文件超过 48 KiB 安全上限。");
                output.write(buffer, 0, count);
            }
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private void openLicense(String title, String file) {
        status.setText("正在读取 " + file + "…");
        try {
            worker.execute(() -> {
                String content;
                String error = null;
                try {
                    content = readLicense(file);
                } catch (Throwable failure) {
                    content = "";
                    error = failure.getClass().getSimpleName() + ": "
                            + (failure.getMessage() == null ? "读取失败" : failure.getMessage());
                }
                final String result = content;
                final String failure = error;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    if (failure != null) {
                        status.setText("读取失败：" + failure);
                        return;
                    }
                    status.setText(title + " · 已读取 " + result.length() + " 个字符");
                    TextView document = text(result, 12, 0xff263445, false);
                    document.setTextIsSelectable(true);
                    document.setTypeface(android.graphics.Typeface.MONOSPACE);
                    ScrollView viewer = new ScrollView(this);
                    viewer.addView(document);
                    new AlertDialog.Builder(this)
                            .setTitle(title)
                            .setView(viewer)
                            .setPositiveButton("关闭", null)
                            .show();
                });
            });
        } catch (RejectedExecutionException full) {
            status.setText("后台任务繁忙，许可证尚未读取；请稍后重试。");
        }
    }

    @Override protected void onDestroy() {
        destroyed = true;
        worker.shutdownNow();
        super.onDestroy();
    }
}
