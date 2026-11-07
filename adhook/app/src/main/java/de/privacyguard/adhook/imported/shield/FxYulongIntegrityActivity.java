package de.privacyguard.adhook.imported.shield;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;

import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * Read-only FX signer and KernelSU module integrity report.
 * It deliberately does not reproduce the original Shield's force-stop,
 * package re-enable, permission restoration or self-repair actions.
 */
public final class FxYulongIntegrityActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-yulong-integrity"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private String signerReport = "";
    private TextView moduleStatus;
    private Button checkButton;
    private volatile boolean destroyed;
    private int checkGeneration;

    private int dp(float n) {
        return (int) (n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(null, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(6), dp(4), dp(6));
        return view;
    }
    private Button button(String label, Runnable click) {
        Button view = new Button(this);
        view.setTag("fx-action-row");
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> click.run());
        return view;
    }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        // Retire the worker after its idle keep-alive instead of pinning a thread.
        worker.allowCoreThreadTimeOut(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(10), dp(6));
        header.addView(button("‹ 返回隐私", this::finish));
        TextView pageTitle = text("隐私 · 应用签名与完整性", 18, 0xff17212b, true);
        pageTitle.setTag("fx-title:18");
        header.addView(pageTitle, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(8), dp(14), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        signerReport = buildSignerReport();
        TextView signerHeading = text("FX 当前安装包签名指纹", 18, 0xff17212b, true);
        signerHeading.setTag("fx-section:签名指纹");
        body.addView(signerHeading);
        TextView signer = text(signerReport, 13, 0xff334155, false);
        signer.setTag("fx-card-body");
        signer.setTextIsSelectable(true);
        body.addView(signer);
        body.addView(button("复制签名报告", () -> copy(signerReport)));

        TextView moduleHeading = text("FX KernelSU 模块完整性", 18, 0xff17212b, true);
        moduleHeading.setTag("fx-section:模块完整性");
        body.addView(moduleHeading);
        TextView moduleDescription = text("只读核对模块身份、版本、启用标记、关键迁移脚本和 Shell 语法；不会自动修复、重启、授予权限或修改目标应用。",
                12, 0xff687681, false);
        moduleDescription.setTag("fx-card-body");
        body.addView(moduleDescription);
        moduleStatus = text("尚未检查。", 13, 0xff334155, false);
        moduleStatus.setTag("fx-card-detail");
        moduleStatus.setTextIsSelectable(true);
        body.addView(moduleStatus);
        checkButton = button("检查模块完整性", this::checkModule);
        body.addView(checkButton);
        body.addView(button("复制模块检查报告", () -> copy(
                moduleStatus.getText() == null ? "" : moduleStatus.getText().toString())));

        TextView boundaryHeading = text("迁移边界", 16, 0xff17212b, true);
        boundaryHeading.setTag("fx-section:迁移边界");
        body.addView(boundaryHeading);
        TextView boundaryNote = text("来源应用的固定签名指纹不能直接用于 FX：合并后包名与签名证书已变化，沿用旧指纹会误报 FX 安装包。本页仅报告当前安装包签名与完整性状态。来源版本中的强停、冻结、自动重新启用、无障碍权限恢复和自动修复仍属于未迁移能力，不能把本页状态报告视为这些能力已启用。",
                12, 0xff8a5b12, false);
        body.addView(boundaryNote);

        setContentViewWithNativeTabs(root, 2);
        checkModule();
    }

    private String buildSignerReport() {
        StringBuilder out = new StringBuilder("Package: ").append(getPackageName()).append('\n');
        try {
            PackageInfo info;
            if (Build.VERSION.SDK_INT >= 33) {
                info = getPackageManager().getPackageInfo(getPackageName(),
                        PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES));
            } else {
                info = getPackageManager().getPackageInfo(getPackageName(),
                        PackageManager.GET_SIGNING_CERTIFICATES);
            }
            out.append("Version: ").append(info.versionName).append('\n');
            if (Build.VERSION.SDK_INT >= 28 && info.signingInfo != null) {
                SigningInfo signing = info.signingInfo;
                Signature[] signers = signing.hasMultipleSigners()
                        ? signing.getApkContentsSigners() : signing.getSigningCertificateHistory();
                appendSignatures(out, signers);
            } else if (info.signatures != null) {
                appendSignatures(out, info.signatures);
            }
        } catch (Throwable error) {
            out.append("Signature read failed: ").append(error.getClass().getSimpleName());
        }
        return out.toString();
    }

    private void appendSignatures(StringBuilder out, Signature[] signatures) throws Exception {
        for (int i = 0; signatures != null && i < signatures.length; i++) {
            out.append("Signer ").append(i + 1).append(" SHA-256: ")
                    .append(hex(MessageDigest.getInstance("SHA-256")
                            .digest(signatures[i].toByteArray())))
                    .append('\n');
        }
    }

    private String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) out.append(String.format(Locale.ROOT, "%02X", value));
        return out.toString();
    }

    private String moduleCheckCommand() {
        return "set -u; MP=''; "
                + "for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ ! -L \"$d\" ] && [ -d \"$d\" ] && [ -f \"$d/module.prop\" ] " + "&& [ ! -L \"$d/module.prop\" ] && grep -qx 'id=privacyguard' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "if [ -z \"$MP\" ]; then echo 'MODULE=missing'; exit 20; fi; "
                + "echo 'MODULE=found'; echo \"PATH=$MP\"; "
                + "version=$(sed -n 's/^version=//p' \"$MP/module.prop\" | head -n 1); "
                + "echo \"VERSION=$version\"; "
                + "if [ -f \"$MP/disable\" ] && [ ! -L \"$MP/disable\" ]; then echo 'STATE=disabled'; "
                + "elif [ -f \"$MP/remove\" ] && [ ! -L \"$MP/remove\" ]; then echo 'STATE=marked-for-removal'; "
                + "else echo 'STATE=enabled'; fi; "
                + "for f in scripts/apply.sh scripts/default.conf scripts/util.sh scripts/certmgr.sh "
                + "scripts/vpn-apps.sh scripts/yulong-app-firewall.sh scripts/yulong-stellar-control.sh "
                + "scripts/yulong-ad-control.sh scripts/yulong-ad-schedule.sh; do "
                + "if [ -f \"$MP/$f\" ] && [ ! -L \"$MP/$f\" ]; then "
                + "case \"$f\" in *.sh) if sh -n \"$MP/$f\" 2>/dev/null; "
                + "then echo \"OK|$f|present-and-syntax-valid\"; "
                + "else echo \"BAD|$f|shell-syntax-error\"; fi ;; "
                + "*) echo \"OK|$f|present\" ;; esac; "
                + "else echo \"MISSING|$f|not-found\"; fi; done; "
                + "if [ -f \"$MP/bin/arm64/qjs\" ] && [ ! -L \"$MP/bin/arm64/qjs\" ] " + "&& [ -x \"$MP/bin/arm64/qjs\" ]; then echo 'OK|bin/arm64/qjs|executable'; "
                + "elif [ -f \"$MP/bin/arm64/qjs\" ]; then echo 'BAD|bin/arm64/qjs|not-executable'; "
                + "else echo 'MISSING|bin/arm64/qjs|not-found'; fi; "
                + "echo 'CHECK=complete'";
    }

    private void checkModule() {
        if (destroyed || isFinishing() || isDestroyed()) return;
        final int request = ++checkGeneration;
        checkButton.setEnabled(false);
        moduleStatus.setText("正在通过 Root 读取模块文件与语法状态…");
        try {
            worker.execute(() -> {
                String report;
                try {
                    RootAccess.Result result = RootAccess.execute(moduleCheckCommand(), 30000L, 256 * 1024);
                    report = "Root 退出码：" + result.exitCode + "\n"
                            + (result.output == null ? "" : result.output)
                            + (result.exitCode == 0
                            ? "\n结果：只读检查完成；这不是设备运行或网络行为验证。"
                            : "\n结果：检查未完成，请确认 FX Hook 已获 Root 授权。");
                } catch (Throwable error) {
                    report = "完整性检查执行失败：" + error.getClass().getSimpleName()
                            + (error.getMessage() == null ? "" : "：" + error.getMessage())
                            + "\n请确认 FX Hook 的 Root 授权与模块状态后重试。";
                }
                final String snapshot = report;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()
                            || request != checkGeneration) return;
                    checkButton.setEnabled(true);
                    moduleStatus.setText(snapshot);
                });
            });
        } catch (RejectedExecutionException full) {
            checkButton.setEnabled(true);
            moduleStatus.setText("完整性检查队列繁忙，本次检查未执行；请稍后重试。");
        }
    }

    private void copy(String value) {
        ClipboardManager manager = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (manager != null) {
            manager.setPrimaryClip(ClipData.newPlainText("FX integrity report", value));
            android.widget.Toast.makeText(this, "报告已复制。", android.widget.Toast.LENGTH_SHORT).show();
        }
    }

    @Override protected void onDestroy() {
        destroyed = true;
        checkGeneration++;
        worker.shutdownNow();
        super.onDestroy();
    }
}
