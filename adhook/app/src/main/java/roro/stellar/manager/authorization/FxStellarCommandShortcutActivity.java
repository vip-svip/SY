package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Typeface;
import android.os.Bundle;
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

/** FX replacement for Stellar's pinned read-only command shortcut. */
public final class FxStellarCommandShortcutActivity extends Activity {
    public static final String ACTION_EXECUTE_COMMAND_SHORTCUT =
            "roro.stellar.manager.action.EXECUTE_COMMAND_SHORTCUT";
    private static final String PREFS = "fx_stellar_command_shortcuts";
    private static final long COMMAND_TIMEOUT_MS = 60000L;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-stellar-command-shortcut"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private String packageName, scope, command;
    private TextView status, output;
    private Button execute;
    private boolean running;

    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
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
    private Button button(String value, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(value);
        view.setOnClickListener(v -> action.run());
        return view;
    }
    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
    private boolean validPackage(String value) {
        return value != null && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }
    private boolean validScope(String value) {
        return "SHELL_ID_COMMAND".equals(value)
                || "PACKAGE_LIST_COMMAND".equals(value)
                || "PROCESS_LIST_COMMAND".equals(value)
                || "PROPERTY_READ_COMMAND".equals(value)
                || "SETTINGS_READ_COMMAND".equals(value)
                || "SELINUX_STATUS_COMMAND".equals(value)
                || "FILESYSTEM_READ_COMMAND".equals(value)
                || "SERVICE_LIST_COMMAND".equals(value);
    }
    private boolean validReadOnlyCommand(String value) {
        if (value == null || value.isEmpty() || value.length() > 512) return false;
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (ch < 0x20 || ch == 0x7f) return false;
        }
        if ("getprop".equals(value) || "id".equals(value) || "id -u".equals(value)
                || "whoami".equals(value) || "ps".equals(value) || "ps -A".equals(value)
                || "ps -ef".equals(value) || "getenforce".equals(value)
                || "service list".equals(value)) return true;
        return value.matches("getprop [A-Za-z0-9_.-]{1,128}")
                || value.matches("pm list packages( -3|-s|-f|-U)?")
                || value.matches("cmd package list packages( -3|-s|-f|-U)?")
                || value.matches("dumpsys package [A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                || value.matches("settings get (secure|global|system) [A-Za-z0-9_.-]{1,128}")
                || value.matches("cat /proc/(version|uptime)")
                || value.matches("cat /sys/fs/selinux/enforce")
                || value.matches("ls (/system|/product|/vendor|/apex|/proc|/sys)(/[A-Za-z0-9_.-]+)*");
    }
    private String moduleShell(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; "
                + "then MP=\\"$d\\"; break; fi; done; "
                + "[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-stellar-control.sh\\" " + args;
    }

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        android.content.Intent intent = getIntent();
        if (intent == null || !ACTION_EXECUTE_COMMAND_SHORTCUT.equals(intent.getAction())) {
            showInvalid("快捷方式来源无效。");
            return;
        }
        String id = intent.getStringExtra("command_id");
        if (id == null || !id.matches("[A-Fa-f0-9]{32}")) {
            showInvalid("快捷方式 ID 无效。");
            return;
        }
        android.content.SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        packageName = prefs.getString(id + ".package", "");
        scope = prefs.getString(id + ".scope", "");
        command = prefs.getString(id + ".command", "");
        if (!validPackage(packageName) || !validScope(scope) || !validReadOnlyCommand(command)) {
            showInvalid("快捷方式数据缺失或不符合只读命令白名单。请回到 Stellar 管理器重新创建。");
            return;
        }

        String label = packageName;
        try {
            android.content.pm.ApplicationInfo app =
                    getPackageManager().getApplicationInfo(packageName, 0);
            label = String.valueOf(getPackageManager().getApplicationLabel(app));
        } catch (Throwable ignored) { }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(button("‹ 关闭", this::finish));
        header.addView(text("Stellar · 命令快捷方式", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(6), dp(14), dp(16));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        body.addView(text("目标应用", 15, 0xff17212b, true));
        body.addView(text(label + "\\n" + packageName, 13, 0xff536273, false));
        body.addView(text("只读能力作用域", 15, 0xff17212b, true));
        body.addView(text(scope, 13, 0xff536273, false));
        body.addView(text("已授权命令", 15, 0xff17212b, true));
        body.addView(text(command, 14, 0xff17212b, true));
        body.addView(text("快捷方式不会直接执行命令。每次触发都必须在此页明确确认；FX 后端还会重新检查应用白名单、能力作用域和始终允许命令。", 12, 0xff8a5b12, false));
        status = text("等待本次执行确认。", 12, 0xff526170, false);
        body.addView(status);
        output = text("", 12, 0xff334155, false);
        body.addView(output);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(dp(12), dp(5), dp(12), dp(12));
        actions.addView(button("取消", this::finish));
        execute = button("确认执行只读命令", () -> new AlertDialog.Builder(this)
                .setTitle("确认执行命令")
                .setMessage(packageName + "\\n" + scope + "\\n\\n" + command
                        + "\\n\\nFX 将通过 Root 执行一次只读查询。")
                .setNegativeButton("取消", null)
                .setPositiveButton("执行", (dialog, which) -> executeCommand())
                .show());
        actions.addView(execute);
        root.addView(actions);
        setContentView(root);
    }

    private void showInvalid(String message) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(18), dp(18), dp(18));
        root.addView(text("Stellar 快捷方式不可用", 18, 0xffa32620, true));
        root.addView(text(message, 13, 0xff526170, false));
        root.addView(button("关闭", this::finish));
        setContentView(root);
    }

    private void executeCommand() {
        if (running || isFinishing() || isDestroyed()) return;
        running = true;
        execute.setEnabled(false);
        status.setText("正在请求 FX Root 后端复核并执行…");
        output.setText("");
        String args = "run " + quote(packageName) + " " + quote(scope) + " " + quote(command);
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(moduleShell(args),
                        COMMAND_TIMEOUT_MS, 256 * 1024);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    running = false;
                    execute.setEnabled(true);
                    status.setText(result.exitCode == 0
                            ? "执行完成 · 退出码 0"
                            : "未执行或执行失败 · 退出码 " + result.exitCode);
                    output.setText(result.output == null ? "" : result.output);
                });
            });
        } catch (RejectedExecutionException full) {
            running = false;
            execute.setEnabled(true);
            status.setText("后台任务繁忙，本次执行未开始；请稍后重试。");
        }
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
