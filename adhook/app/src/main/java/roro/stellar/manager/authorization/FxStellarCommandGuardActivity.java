package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
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
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Signature-protected bridge for the original Stellar CommandGuard request.
 * Incoming command/script text is shown for user review only and is never executed here.
 */
public final class FxStellarCommandGuardActivity extends Activity {
    public static final String ACTION_COMMAND_GUARD =
            "com.youlong.hd.intent.action.COMMAND_GUARD";
    private static final long REQUEST_TIMEOUT_MS = 30000L;
    private static final long WRITE_TIMEOUT_MS = 15000L;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final AtomicBoolean replied = new AtomicBoolean(false);
    private final AtomicBoolean writing = new AtomicBoolean(false);
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(1),
            r -> {
                Thread thread = new Thread(r, "fx-stellar-command-guard");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    private long requestId = -1L;
    private TextView status;
    private Button allowOnce;
    private Button allowAlways;
    private Button deny;
    private final Runnable timeout = () -> submitDecision("DENY");

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
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

    private void card(LinearLayout parent, String title, String content) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(9), dp(12), dp(9));
        panel.setBackgroundColor(0xffeef2f6);
        panel.addView(text(title, 14, 0xff17212b, true));
        panel.addView(text(content, 12, 0xff526170, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(4), 0, dp(4));
        parent.addView(panel, lp);
    }

    private String extra(Intent intent, String key, int limit) {
        String value = intent == null ? null : intent.getStringExtra(key);
        if (value == null) return "";
        value = value.replace("\r", "").trim();
        return value.length() > limit ? value.substring(0, limit) + "…" : value;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent request = getIntent();
        requestId = request == null ? -1L : request.getLongExtra("id", -1L);
        if (requestId <= 0L) {
            LinearLayout invalid = new LinearLayout(this);
            invalid.setOrientation(LinearLayout.VERTICAL);
            invalid.setPadding(dp(18), dp(18), dp(18), dp(18));
            invalid.addView(text("Stellar 请求无效", 19, 0xffa32620, true));
            invalid.addView(text("缺少有效的数字请求 ID。为避免写入错误请求，本次不会创建授权响应。", 13, 0xff526170, false));
            invalid.addView(button("关闭", this::finish));
            setContentView(invalid);
            return;
        }

        String pkg = extra(request, "packageName", 255);
        String command = extra(request, "command", 4096);
        String reason = extra(request, "reason", 1200);
        String riskKind = extra(request, "riskKind", 120);
        String riskLevel = extra(request, "riskLevel", 80);
        String analysis = extra(request, "analysis", 5000);
        String scope = extra(request, "scope", 160);
        String scopeLabel = extra(request, "scopeLabel", 180);
        String script = extra(request, "script", 12000);
        boolean whitelisted = request.getBooleanExtra("whitelisted", false);
        int score = request.getIntExtra("score", 0);

        String appLabel = pkg;
        try {
            if (!pkg.isEmpty()) {
                android.content.pm.ApplicationInfo info = getPackageManager().getApplicationInfo(pkg, 0);
                appLabel = String.valueOf(getPackageManager().getApplicationLabel(info));
            }
        } catch (Throwable ignored) { }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(text("Stellar · 指令授权确认", 19, 0xff17212b, true));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(4), dp(12), dp(14));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        card(body, "请求应用",
                (appLabel.isEmpty() ? "未知应用" : appLabel)
                        + (pkg.isEmpty() ? "" : "\n" + pkg)
                        + "\n请求 ID：" + requestId
                        + (whitelisted ? "\n应用已存在于 Stellar 白名单" : ""));
        card(body, "待授权命令", command.isEmpty() ? "请求方未提供命令文本" : command);
        card(body, "风险信息",
                (riskLevel.isEmpty() ? "未提供风险等级" : riskLevel)
                        + (riskKind.isEmpty() ? "" : " · " + riskKind)
                        + "\n风险评分：" + score
                        + (scopeLabel.isEmpty() ? "" : "\n能力：" + scopeLabel)
                        + (scope.isEmpty() ? "" : " (" + scope + ")"));
        if (!reason.isEmpty()) card(body, "请求原因", reason);
        if (!analysis.isEmpty()) card(body, "风险分析", analysis);
        if (!script.isEmpty()) card(body, "关联脚本（仅展示）", script);

        status = text("请先核对应用、命令和风险分析。30 秒内未选择将自动拒绝。", 12, 0xff8a5b12, true);
        body.addView(status);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(dp(12), dp(4), dp(12), dp(14));
        deny = button("拒绝", () -> submitDecision("DENY"));
        allowOnce = button("仅允许本次", () -> submitDecision("ALLOW"));
        allowAlways = button("始终允许此命令", () -> new AlertDialog.Builder(this)
                .setTitle("确认始终允许")
                .setMessage("这会把本次请求的授权结果写回 Stellar 响应文件。请确认目标应用和命令完全可信。")
                .setNegativeButton("取消", null)
                .setPositiveButton("始终允许", (dialog, which) -> submitDecision("ALWAYS_ALLOW"))
                .show());
        actions.addView(deny);
        actions.addView(allowOnce);
        actions.addView(allowAlways);
        root.addView(actions);
        setContentView(root);
        main.postDelayed(timeout, REQUEST_TIMEOUT_MS);
    }

    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private String responseCommand(String decision) {
        String directory = "/data/local/tmp/stellar_guard";
        String id = Long.toString(requestId);
        String target = directory + "/" + id + ".resp";
        String lock = directory + "/." + id + ".resp.lock";
        String temporary = directory + "/." + id + ".resp.XXXXXX";
        return "set -eu; D=" + quote(directory)
                + "; P=" + quote(target) + "; L=" + quote(lock) + "; T=; "
                + "cleanup(){ [ -z \"$T\" ] || rm -f \"$T\" 2>/dev/null || :; "
                + "rmdir \"$L\" 2>/dev/null || :; }; trap cleanup EXIT; "
                + "[ ! -L \"$D\" ] || exit 21; mkdir -p \"$D\"; chmod 700 \"$D\"; "
                + "[ -d \"$D\" ] && [ ! -L \"$D\" ] || exit 21; "
                + "mkdir \"$L\" 2>/dev/null || exit 22; "
                + "[ ! -e \"$P\" ] && [ ! -L \"$P\" ] || exit 23; "
                + "T=$(mktemp " + quote(temporary) + "); "
                + "printf '%s' " + quote(decision) + " > \"$T\"; chmod 600 \"$T\"; "
                + "[ ! -e \"$P\" ] && [ ! -L \"$P\" ] || exit 23; "
                + "mv -f \"$T\" \"$P\"; T=; echo response=written";
    }

    private void setActionsEnabled(boolean enabled) {
        if (deny != null) deny.setEnabled(enabled);
        if (allowOnce != null) allowOnce.setEnabled(enabled);
        if (allowAlways != null) allowAlways.setEnabled(enabled);
    }

    private void submitDecision(String decision) {
        if (requestId <= 0L || replied.get() || !writing.compareAndSet(false, true)) return;
        if (!"DENY".equals(decision) && !"ALLOW".equals(decision)
                && !"ALWAYS_ALLOW".equals(decision)) {
            writing.set(false);
            return;
        }
        main.removeCallbacks(timeout);
        setActionsEnabled(false);
        if (status != null) status.setText("正在安全写入授权结果：" + decision + "…");
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(
                        responseCommand(decision), WRITE_TIMEOUT_MS, 4096);
                runOnUiThread(() -> {
                    writing.set(false);
                    if (isFinishing() || isDestroyed()) return;
                    if (result.exitCode == 0 && result.output != null
                            && result.output.contains("response=written")) {
                        replied.set(true);
                        finish();
                    } else {
                        if (status != null) status.setText("响应写入失败，未授予权限："
                                + (result.output == null ? "无错误详情" : result.output));
                        setActionsEnabled(true);
                    }
                });
            });
        } catch (RejectedExecutionException full) {
            writing.set(false);
            if (status != null) status.setText("授权响应任务繁忙；请求仍未授权。");
            setActionsEnabled(true);
        }
    }

    @Override public void onBackPressed() {
        submitDecision("DENY");
    }

    @Override protected void onDestroy() {
        main.removeCallbacks(timeout);
        worker.shutdownNow();
        super.onDestroy();
    }
}
