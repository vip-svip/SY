package de.privacyguard.adhook.imported.dia;

import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.io.ByteArrayInputStream;
import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Read-only APK signing certificate and package metadata viewer migrated from Dia. */
public final class FxDiaSignatureActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private TextView target, output;
    private ApplicationInfo selected;

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout c = new LinearLayout(this); c.setOrientation(1);
        c.setPadding(dp(14), dp(10), dp(14), dp(10)); c.setBackgroundColor(0xfff0f3f7);
        c.addView(text(title, 16, 0xff17212b, true));
        c.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) c.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5)); parent.addView(c, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · APK 签名信息", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1);
        body.setPadding(0, dp(4), 0, dp(18)); scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 5);

        target = text("尚未选择应用。", 13, 0xff334155, false);
        output = text("选择应用后读取 APK 签名证书。", 12, 0xff344054, false);
        card(body, "目标 APK", "读取 PackageManager 返回的签名证书和安装元数据，不修改目标应用。",
                target, button("选择已安装应用", this::chooseApp),
                button("读取签名证书", this::inspect));
        card(body, "签名与包信息", "SHA-256 指纹、证书主体/颁发者、签名者数量和包版本。",
                output, button("复制结果", this::copy));
        loadApps();
    }

    private void loadApps() {
        try {
            apps.clear();
            apps.addAll(getPackageManager().getInstalledApplications(0));
            apps.removeIf(a -> a.packageName == null || a.packageName.equals(getPackageName()));
            apps.sort(Comparator.comparing(a -> {
                try { return String.valueOf(getPackageManager().getApplicationLabel(a)).toLowerCase(Locale.ROOT); }
                catch (Throwable ignored) { return a.packageName.toLowerCase(Locale.ROOT); }
            }));
        } catch (Throwable error) {
            output.setText("应用列表读取失败：" + error.getClass().getSimpleName());
        }
    }

    private String label(ApplicationInfo app) {
        try { return String.valueOf(getPackageManager().getApplicationLabel(app)); }
        catch (Throwable ignored) { return app.packageName; }
    }

    private void chooseApp() {
        if (apps.isEmpty()) loadApps();
        if (apps.isEmpty()) return;
        String[] labels = new String[apps.size()];
        for (int i = 0; i < apps.size(); i++)
            labels[i] = label(apps.get(i)) + "\n" + apps.get(i).packageName;
        new AlertDialog.Builder(this).setTitle("选择 APK").setItems(labels, (d, which) -> {
            selected = apps.get(which);
            target.setText(labels[which]);
            output.setText("目标已选择；点击读取签名证书。");
        }).setNegativeButton("取消", null).show();
    }

    private String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 3);
        for (int i = 0; i < bytes.length; i++) {
            if (i > 0) out.append(':');
            out.append(String.format(Locale.ROOT, "%02X", bytes[i] & 0xff));
        }
        return out.toString();
    }

    private String digest(byte[] bytes, String algorithm) throws Exception {
        return hex(MessageDigest.getInstance(algorithm).digest(bytes));
    }

    @SuppressWarnings("deprecation")
    private void inspect() {
        if (selected == null) { output.setText("请先选择应用。"); return; }
        try {
            PackageManager pm = getPackageManager();
            PackageInfo info;
            if (Build.VERSION.SDK_INT >= 28)
                info = pm.getPackageInfo(selected.packageName, PackageManager.GET_SIGNING_CERTIFICATES);
            else
                info = pm.getPackageInfo(selected.packageName, PackageManager.GET_SIGNATURES);

            StringBuilder result = new StringBuilder();
            result.append("应用：").append(label(selected)).append('\n')
                    .append("包名：").append(info.packageName).append('\n')
                    .append("版本名：").append(info.versionName == null ? "" : info.versionName).append('\n')
                    .append("版本号：").append(Build.VERSION.SDK_INT >= 28
                            ? info.getLongVersionCode() : info.versionCode).append('\n')
                    .append("APK 路径：").append(selected.sourceDir).append('\n')
                    .append("首次安装：").append(DateFormat.getDateTimeInstance().format(
                            new Date(info.firstInstallTime))).append('\n')
                    .append("最后更新：").append(DateFormat.getDateTimeInstance().format(
                            new Date(info.lastUpdateTime))).append('\n')
                    .append("是否调试版本：")
                    .append((selected.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0 ? "是" : "否")
                    .append('\n');

            Signature[] signers;
            boolean multipleSigners = false;
            if (Build.VERSION.SDK_INT >= 28 && info.signingInfo != null) {
                SigningInfo signing = info.signingInfo;
                multipleSigners = signing.hasMultipleSigners();
                signers = multipleSigners
                        ? signing.getApkContentsSigners()
                        : signing.getSigningCertificateHistory();
            } else signers = info.signatures;

            if (signers == null || signers.length == 0) {
                result.append("\n没有可读取的签名证书。");
            } else {
                result.append("\n签名者/证书历史数量：").append(signers.length)
                        .append("\n当前多签名 APK：").append(multipleSigners ? "是" : "否").append('\n');
                CertificateFactory factory = CertificateFactory.getInstance("X.509");
                for (int i = 0; i < signers.length; i++) {
                    byte[] bytes = signers[i].toByteArray();
                    result.append("\n[证书 ").append(i + 1).append("]\n")
                            .append("SHA-256：").append(digest(bytes, "SHA-256")).append('\n')
                            .append("SHA-1：").append(digest(bytes, "SHA-1")).append('\n')
                            .append("MD5：").append(digest(bytes, "MD5")).append('\n');
                    try {
                        X509Certificate cert = (X509Certificate) factory.generateCertificate(
                                new ByteArrayInputStream(bytes));
                        result.append("Subject：").append(cert.getSubjectX500Principal()).append('\n')
                                .append("Issuer：").append(cert.getIssuerX500Principal()).append('\n')
                                .append("有效期：").append(cert.getNotBefore()).append(" 至 ")
                                .append(cert.getNotAfter()).append('\n')
                                .append("序列号：").append(cert.getSerialNumber().toString(16)).append('\n');
                    } catch (Throwable ignored) {
                        result.append("证书 X.509 解析失败；原始签名指纹仍可使用。\n");
                    }
                }
            }
            output.setText(result.toString());
        } catch (Throwable error) {
            output.setText("签名读取失败：" + error.getClass().getSimpleName()
                    + (error.getMessage() == null ? "" : "：" + error.getMessage()));
        }
    }

    private void copy() {
        android.content.ClipboardManager clipboard =
                (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                    "APK signing information", output.getText().toString()));
        }
    }
}
