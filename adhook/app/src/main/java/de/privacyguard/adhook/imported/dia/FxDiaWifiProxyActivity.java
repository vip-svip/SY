package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.net.IDN;
import java.util.Locale;
import java.util.function.Consumer;

/**
 * Dia 23.11 system Wi-Fi/HTTP proxy settings migrated into the single FX app.
 *
 * The original function changes Android's global http_proxy setting. This
 * migration keeps it independent from the FX VPN and Root Proxy runtimes,
 * defaults to disabled, stores the previous system value, verifies writes,
 * and refuses to restore over a change made by another app or the user.
 */
public final class FxDiaWifiProxyActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String PREFS = "fx_dia_wifi_proxy";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(4),
            r -> { Thread t = new Thread(r, "fx-dia-wifi-proxy"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
            });
        }
    }
    private EditText hostInput;
    private EditText portInput;
    private TextView status;
    private Button applyButton;
    private Button restoreButton;
    private boolean busy;
    private FxDiaWifiProxyState.Status proxyStatus = FxDiaWifiProxyState.Status.UNKNOWN;

    private SharedPreferences prefs() { return getSharedPreferences(PREFS, MODE_PRIVATE); }

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }

    private Button button(String value, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(value);
        b.setOnClickListener(v -> action.run()); return b;
    }

    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private void runRoot(String command, Consumer<RootAccess.Result> callback) {
        if (busy) return;
        busy = true;
        updateButtons();
        submitWorker(() -> {
            RootAccess.Result result = RootAccess.execute(command, 30000L, 16384);
            runOnUiThread(() -> {
                busy = false;
                updateButtons();
                if (!isFinishing() && !isDestroyed()) callback.accept(result);
            });
        });
    }

    private void updateButtons() {
        boolean managed = prefs().getBoolean("active", false);
        if (applyButton != null) applyButton.setEnabled(!busy);
        if (restoreButton != null) {
            restoreButton.setEnabled(!busy && managed
                    && FxDiaWifiProxyState.mayRestore(proxyStatus));
        }
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
        header.addView(text("Dia · 系统 HTTP 代理", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        android.widget.ScrollView scroll = new android.widget.ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(12), dp(8), dp(12), dp(22));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        body.addView(text("该功能会修改 Android 全局 HTTP 代理设置，影响系统中使用系统代理的应用。它与 FX VPN、节点代理和 Root DNS Proxy 相互独立。默认关闭；关闭时仅在系统值仍等于 FX 本次写入值的情况下恢复旧值。", 13, 0xff617080, false));

        status = text("正在读取当前系统代理…", 13, 0xff526170, false);
        body.addView(text("当前系统代理", 16, 0xff17212b, true));
        body.addView(status);

        hostInput = new EditText(this);
        hostInput.setSingleLine(true);
        hostInput.setHint("代理主机，例如 127.0.0.1 或 proxy.example.com");
        hostInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        hostInput.setText(prefs().getString("draft_host", prefs().getString("host", "127.0.0.1")));
        body.addView(hostInput);

        portInput = new EditText(this);
        portInput.setSingleLine(true);
        portInput.setHint("代理端口 1–65535");
        portInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        portInput.setText(prefs().getString("draft_port", prefs().getString("port", "8080")));
        body.addView(portInput);
        // Keep non-secret host/port drafts recoverable; credentials are never stored here.
        hostInput.addTextChangedListener(new android.text.TextWatcher() {
            @Override public void beforeTextChanged(CharSequence value, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence value, int start, int before, int count) {
                prefs().edit().putString("draft_host", value == null ? "" : value.toString()).apply();
            }
            @Override public void afterTextChanged(android.text.Editable value) { }
        });
        portInput.addTextChangedListener(new android.text.TextWatcher() {
            @Override public void beforeTextChanged(CharSequence value, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence value, int start, int before, int count) {
                prefs().edit().putString("draft_port", value == null ? "" : value.toString()).apply();
            }
            @Override public void afterTextChanged(android.text.Editable value) { }
        });

        applyButton = button("启用并应用系统 HTTP 代理", () -> confirmApply());
        restoreButton = button("关闭并恢复原系统代理", () -> restoreProxy());
        body.addView(applyButton);
        body.addView(restoreButton);
        body.addView(button("解除 FX 管理（保留当前系统值）", () -> forgetProxyManagement()));
        body.addView(button("刷新系统代理状态", () -> refreshStatus()));

        body.addView(text("快捷设置", 16, 0xff17212b, true));
        body.addView(text("可在系统快捷设置编辑页手动添加“FX 系统代理”磁贴。磁贴只切换本页面配置的系统 HTTP 代理，不会启动 VPN。", 12, 0xff718091, false));
        body.addView(text("安全处理", 16, 0xff17212b, true));
        body.addView(text("启用前记录当前 global http_proxy；每次写入后重新读取核对。关闭时若发现系统代理已被其他程序改写，不会覆盖它，而是提示冲突。Root 命令仅通过 KernelSU 授权执行。", 12, 0xff718091, false));
        setContentViewWithNativeTabs(root, 5);
        updateButtons();
        refreshStatus();
    }

    private String normalizedHost() {
        String raw = hostInput.getText() == null ? "" : hostInput.getText().toString().trim();
        if (raw.startsWith("[") && raw.endsWith("]")) {
            String ipv6 = raw.substring(1, raw.length() - 1);
            if (!ipv6.matches("[0-9A-Fa-f:.]+") || ipv6.indexOf(':') < 0)
                throw new IllegalArgumentException("IPv6 地址格式无效。");
            return "[" + ipv6 + "]";
        }
        String ascii;
        try { ascii = IDN.toASCII(raw, IDN.USE_STD3_ASCII_RULES).toLowerCase(Locale.ROOT); }
        catch (IllegalArgumentException invalid) { throw new IllegalArgumentException("代理主机名无效。"); }
        if (ascii.isEmpty() || ascii.length() > 253
                || !ascii.matches("[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?"))
            throw new IllegalArgumentException("代理主机名无效。");
        for (String label : ascii.split("\\\\.", -1)) {
            if (label.isEmpty() || label.length() > 63
                    || label.startsWith("-") || label.endsWith("-"))
                throw new IllegalArgumentException("代理主机名包含无效标签。");
        }
        return ascii;
    }

    private String targetProxy() {
        String host = normalizedHost();
        String portText = portInput.getText() == null ? "" : portInput.getText().toString().trim();
        int port;
        try { port = Integer.parseInt(portText); }
        catch (NumberFormatException invalid) { throw new IllegalArgumentException("端口必须是数字。"); }
        if (port < 1 || port > 65535) throw new IllegalArgumentException("端口必须在 1–65535。");
        return host + ":" + port;
    }

    private void confirmApply() {
        final String target;
        try { target = targetProxy(); }
        catch (Exception invalid) {
            status.setText(invalid.getMessage());
            return;
        }
        new AlertDialog.Builder(this).setTitle("启用全局 HTTP 代理？")
                .setMessage("将 Android 全局 http_proxy 设置为：\n" + target
                        + "\n\n所有使用系统代理的应用都可能受到影响。FX 会保存旧值，并在关闭时尝试恢复。")
                .setNegativeButton("取消", null)
                .setPositiveButton("启用", (dialog, which) -> applyProxy(target))
                .show();
    }

    private void applyProxy(String target) {
        boolean alreadyActive = prefs().getBoolean("active", false);
        String previous = prefs().getString("previous", "");
        String previousApplied = prefs().getString("applied", "");
        String restorePrevious = alreadyActive ? previous : "";
        String expectedCurrent = alreadyActive ? previousApplied : "";

        String command = "set -eu; current=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                + "if [ " + (alreadyActive ? "1" : "0") + " = 1 ]; then "
                + "[ \"$current\" = " + quote(expectedCurrent) + " ] || { echo FX_PROXY_CONFLICT; exit 30; }; "
                + "old=" + quote(restorePrevious) + "; "
                + "else old=\"$current\"; [ -n \"$old\" ] || old=null; fi; "
                + "settings put global http_proxy " + quote(target) + "; "
                + "actual=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                + "if [ \"$actual\" != " + quote(target) + " ]; then "
                + "if [ \"$old\" = null ]; then settings delete global http_proxy; "
                + "else settings put global http_proxy \"$old\"; fi; "
                + "echo FX_PROXY_WRITE_FAILED; exit 31; fi; "
                + "printf 'PREVIOUS=%s\\nAPPLIED=%s\\n' \"$old\" \"$actual\"";
        runRoot(command, result -> {
            if (result.exitCode != 0 || result.output == null
                    || !result.output.contains("APPLIED=" + target)) {
                status.setText(result.output != null && result.output.contains("FX_PROXY_CONFLICT")
                        ? "检测到系统代理被其他程序更改，未覆盖其设置。"
                        : "系统代理应用失败：" + safe(result.output));
                refreshStatus();
                return;
            }
            String newPrevious = extract(result.output, "PREVIOUS=");
            boolean saved = prefs().edit().putBoolean("active", true)
                    .putString("host", hostInput.getText().toString().trim())
                    .putString("port", portInput.getText().toString().trim())
                    .putString("previous", newPrevious)
                    .putString("applied", target)
                    .remove("draft_host").remove("draft_port").commit();
            if (!saved) {
                // The OS setting has already changed. Roll it back only if it still
                // equals the value FX just wrote; never overwrite a concurrent user change.
                String rollback = "set -eu; current=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                        + "[ \"$current\" = " + quote(target) + " ] || { echo FX_PROXY_CONFLICT; exit 30; }; "
                        + "if [ " + quote(newPrevious) + " = null ]; then settings delete global http_proxy; "
                        + "else settings put global http_proxy " + quote(newPrevious) + "; fi; "
                        + "actual=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                        + "[ \"$actual\" = " + quote(newPrevious) + " ] || { echo FX_PROXY_ROLLBACK_FAILED; exit 31; }";
                runRoot(rollback, rollbackResult -> {
                    if (rollbackResult.exitCode == 0) {
                        status.setText("FX 本地状态保存失败；已安全恢复修改前的系统代理。");
                    } else {
                        status.setText(rollbackResult.output != null && rollbackResult.output.contains("FX_PROXY_CONFLICT")
                                ? "FX 本地状态保存失败，且系统代理已被其他程序更改；未覆盖外部修改，请手动核对。"
                                : "FX 本地状态保存失败，自动恢复未能确认；请立即刷新并核对系统代理：" + safe(rollbackResult.output));
                    }
                    refreshStatus();
                });
                return;
            }
            proxyStatus = FxDiaWifiProxyState.Status.ACTIVE;
            status.setText("系统全局 HTTP 代理已启用并核对成功： " + target);
            updateButtons();
        });
    }

    private void restoreProxy() {
        if (!prefs().getBoolean("active", false)) {
            status.setText("FX 当前没有启用系统代理。");
            return;
        }
        new AlertDialog.Builder(this).setTitle("恢复原系统代理？")
                .setMessage("仅当当前 global http_proxy 仍为 FX 上次写入值时恢复保存的旧值。")
                .setNegativeButton("取消", null)
                .setPositiveButton("恢复", (dialog, which) -> restoreProxyConfirmed())
                .show();
    }

    private void restoreProxyConfirmed() {
        String expected = prefs().getString("applied", "");
        String previous = prefs().getString("previous", "null");
        String command = "set -eu; current=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                + "[ \"$current\" = " + quote(expected) + " ] || { echo FX_PROXY_CONFLICT; exit 30; }; "
                + "if [ " + quote(previous) + " = null ]; then settings delete global http_proxy; "
                + "else settings put global http_proxy " + quote(previous) + "; fi; "
                + "actual=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                + "if [ " + quote(previous) + " = null ]; then "
                + "[ -z \"$actual\" ] || [ \"$actual\" = null ] || exit 31; "
                + "else [ \"$actual\" = " + quote(previous) + " ] || exit 31; fi; "
                + "echo FX_PROXY_RESTORED";
        runRoot(command, result -> {
            if (result.exitCode != 0 || result.output == null
                    || !result.output.contains("FX_PROXY_RESTORED")) {
                status.setText(result.output != null && result.output.contains("FX_PROXY_CONFLICT")
                        ? "系统代理已被外部更改。为避免覆盖其他程序设置，FX 未执行恢复。"
                        : "系统代理恢复失败：" + safe(result.output));
                refreshStatus();
                return;
            }
            prefs().edit().putBoolean("active", false)
                    .remove("previous").remove("applied").apply();
            proxyStatus = FxDiaWifiProxyState.Status.DISABLED;
            status.setText("已恢复启用 FX 前保存的系统代理值。");
            updateButtons();
        });
    }

    private void forgetProxyManagement() {
        if (!prefs().getBoolean("active", false)) {
            status.setText("FX 当前没有正在管理的系统代理。");
            return;
        }
        new AlertDialog.Builder(this).setTitle("解除 FX 代理管理？")
                .setMessage("只清除 FX 保存的旧值和管理标记，不会修改 Android 当前 global http_proxy。"
                        + "\n\n如果系统代理已被其他程序更改，请使用此项解除冲突。")
                .setNegativeButton("取消", null)
                .setPositiveButton("解除管理", (dialog, which) -> {
                    prefs().edit().putBoolean("active", false)
                            .remove("previous").remove("applied").apply();
                    proxyStatus = FxDiaWifiProxyState.Status.DISABLED;
                    status.setText("已解除 FX 管理；系统当前代理值保持不变。");
                    updateButtons();
                }).show();
    }

    private void refreshStatus() {
        final boolean managed = prefs().getBoolean("active", false);
        final String expected = prefs().getString("applied", "");
        runRoot("settings get global http_proxy 2>/dev/null | tr -d '\\r'", result -> {
            if (result.exitCode != 0) {
                proxyStatus = FxDiaWifiProxyState.Status.UNKNOWN;
                status.setText("无法读取系统代理：" + safe(result.output)
                        + "\n为避免覆盖外部代理，恢复操作已暂时禁用。");
                updateButtons();
                return;
            }

            String current = result.output == null ? "" : result.output.trim();
            proxyStatus = FxDiaWifiProxyState.evaluate(managed, current, expected, true);
            String shown = current.isEmpty() || "null".equals(current) ? "(未设置)" : current;
            String stateText;
            switch (proxyStatus) {
                case ACTIVE:
                    stateText = "FX 管理状态：启用，系统值与 FX 写入记录一致";
                    break;
                case EXTERNALLY_CHANGED:
                    stateText = "管理冲突：系统代理已被外部更改，FX 不会覆盖当前值；可解除 FX 管理";
                    break;
                case UNKNOWN:
                    stateText = "状态未知：无法读取系统值";
                    break;
                default:
                    stateText = "FX 管理状态：未启用";
                    break;
            }
            status.setText("global http_proxy = " + shown + "\n" + stateText);
            updateButtons();
        });
    }

    private String extract(String output, String prefix) {
        for (String line : output.split("\\r?\\n")) if (line.startsWith(prefix)) return line.substring(prefix.length());
        return "";
    }

    private String safe(String output) {
        return output == null || output.trim().isEmpty() ? "请确认 FX Hook 已获得 KernelSU Root 授权。" : output.trim();
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
