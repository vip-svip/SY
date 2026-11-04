package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * FX port of the original Stellar permission confirmation surface.
 * Preserves original request extras and response Bundle keys. The protected
 * FX Messenger contract is an adapter, not a claim that the original
 * IStellarService daemon has been recreated.
 */
public final class StellarPermissionRequestActivity extends Activity {
    private static final long RESPONSE_TIMEOUT_MS = 30000L;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final AtomicBoolean replied = new AtomicBoolean(false);
    private long requestId = -1L;
    private int uid = -1, pid = -1, requestCode = -1, notificationId;
    private String permission = "stellar", sourcePackage = "", notificationTag = "";
    private Messenger replyMessenger;
    private TextView status;
    private Button deny, allowOnce, allowAlways;
    private final Runnable timeout = () -> reply(false, true, "30 秒未选择；已默认拒绝。");

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        view.setTextIsSelectable(true);
        return view;
    }
    private Button button(String label, Runnable action) {
        Button view = new Button(this); view.setAllCaps(false); view.setText(label);
        view.setOnClickListener(v -> action.run()); return view;
    }
    private void card(LinearLayout parent, String title, String value) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(9), dp(12), dp(9));
        panel.setBackgroundColor(0xffeef2f6);
        panel.addView(text(title, 14, 0xff17212b, true));
        panel.addView(text(value, 12, 0xff526170, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, dp(4), 0, dp(4)); parent.addView(panel, lp);
    }
    private String safe(String value, String fallback, int limit) {
        if (value == null || value.trim().isEmpty()) return fallback;
        String normalized = value.replace("\\r", "").replace("\\n", " ").trim();
        return normalized.length() > limit ? normalized.substring(0, limit) : normalized;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent request = getIntent();
        requestId = request == null ? -1L : request.getLongExtra("request_id", -1L);
        uid = request == null ? -1 : request.getIntExtra("uid", -1);
        pid = request == null ? -1 : request.getIntExtra("pid", -1);
        requestCode = request == null ? -1 : request.getIntExtra("requestCode", -1);
        permission = safe(request == null ? null : request.getStringExtra("permission"), "stellar", 255);
        sourcePackage = safe(request == null ? null : request.getStringExtra("sourcePackage"), "", 255);
        notificationTag = safe(request == null ? null : request.getStringExtra("notification_tag"), "", 80);
        notificationId = request == null ? 0 : request.getIntExtra("notification_id", 0);
        try {
            replyMessenger = request == null ? null
                    : (Messenger) request.getParcelableExtra("reply_messenger");
        } catch (RuntimeException malformed) { replyMessenger = null; }

        if (uid < 0 || pid <= 0 || requestCode < 0 || requestId < 0L
                || !sourcePackage.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                || !permission.matches("[A-Za-z0-9_.]+")) {
            showInvalid();
            return;
        }

        String label = sourcePackage;
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(sourcePackage, 0);
            if (info.uid != uid) { showInvalid(); return; }
            label = String.valueOf(getPackageManager().getApplicationLabel(info));
        } catch (Throwable failure) { showInvalid(); return; }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(text("Stellar · 权限申请", 19, 0xff17212b, true));
        root.addView(header);
        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(4), dp(12), dp(14));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        card(body, "请求应用", label + "\\n" + sourcePackage
                + "\\nUID：" + uid + " · PID：" + pid);
        card(body, "请求权限", permission + "\\n请求代码：" + requestCode
                + "\\n请求 ID：" + requestId);
        status = text("请确认是否允许此应用请求该权限。关闭或超时均默认拒绝。", 12, 0xff8a5b12, true);
        body.addView(status);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(dp(12), dp(4), dp(12), dp(14));
        deny = button("拒绝本次", () -> reply(false, true, "用户拒绝本次请求。"));
        allowOnce = button("仅本次允许", () -> reply(true, true, "用户仅允许本次请求。"));
        allowAlways = button("始终允许", () -> new AlertDialog.Builder(this)
                .setTitle("确认始终允许")
                .setMessage("长期授权可能扩大该应用可使用的能力。请确认来源应用与权限名称可信。")
                .setNegativeButton("取消", null)
                .setPositiveButton("始终允许", (dialog, which) ->
                        reply(true, false, "用户选择始终允许。"))
                .show());
        actions.addView(deny); actions.addView(allowOnce); actions.addView(allowAlways);
        root.addView(actions);
        setContentView(root);
        main.postDelayed(timeout, RESPONSE_TIMEOUT_MS);
    }

    private void showInvalid() {
        reply(false, true, "请求参数无效或 UID/包名不匹配；已默认拒绝。");
        LinearLayout invalid = new LinearLayout(this);
        invalid.setOrientation(LinearLayout.VERTICAL);
        invalid.setPadding(dp(18), dp(18), dp(18), dp(18));
        invalid.addView(text("权限请求无效", 18, 0xffa32620, true));
        invalid.addView(text("请求来源无法验证，未授予或更改任何 Android 权限。", 13, 0xff526170, false));
        invalid.addView(button("关闭", this::finish));
        setContentView(invalid);
    }

    private void setActionsEnabled(boolean enabled) {
        if (deny != null) deny.setEnabled(enabled);
        if (allowOnce != null) allowOnce.setEnabled(enabled);
        if (allowAlways != null) allowAlways.setEnabled(enabled);
    }

    private void reply(boolean allowed, boolean oneTime, String detail) {
        if (!replied.compareAndSet(false, true)) return;
        main.removeCallbacks(timeout);
        setActionsEnabled(false);
        if (status != null) status.setText("正在返回权限决定…");
        Bundle result = new Bundle();
        result.putBoolean("stellar:request-permission-reply-allowed", allowed);
        result.putBoolean("stellar:request-permission-reply-is-onetime", oneTime);
        result.putString("stellar:request-permission-reply-permission", permission);
        Intent resultIntent = new Intent();
        resultIntent.putExtras(result);
        resultIntent.putExtra("uid", uid);
        resultIntent.putExtra("pid", pid);
        resultIntent.putExtra("requestCode", requestCode);
        resultIntent.putExtra("request_id", requestId);
        setResult(RESULT_OK, resultIntent);
        if (replyMessenger != null) {
            Message response = Message.obtain(null, StellarAuthorizationService.MSG_PERMISSION_RESULT);
            Bundle data = new Bundle();
            data.putLong("request_id", requestId);
            data.putInt("uid", uid);
            data.putInt("pid", pid);
            data.putInt("requestCode", requestCode);
            data.putString("detail", detail);
            data.putBundle("permission_reply", result);
            response.setData(data);
            try { replyMessenger.send(response); }
            catch (RemoteException failure) { setResult(RESULT_CANCELED); }
        }
        if (!notificationTag.isEmpty()) {
            NotificationManager manager =
                    (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (manager != null) manager.cancel(notificationTag, notificationId);
        }
        finish();
    }

    @Override public void onBackPressed() {
        reply(false, true, "用户关闭请求；已拒绝。");
    }

    @Override protected void onDestroy() {
        if (!replied.get()) reply(false, true, "确认界面结束；已默认拒绝。");
        main.removeCallbacks(timeout);
        super.onDestroy();
    }
}
