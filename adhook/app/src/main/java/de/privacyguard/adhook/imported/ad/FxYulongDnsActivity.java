package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Local-only DNS query log viewer for the migrated Yulong AdBlock page. */
public final class FxYulongDnsActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String STATE_SEARCH = "fx_dns_search";
    private static final String STATE_SCROLL_Y = "fx_dns_scroll_y";
    private final AtomicInteger loadGeneration = new AtomicInteger();
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(16),
            r -> { Thread t = new Thread(r, "fx-yulong-dns-log"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private final List<Entry> data = new ArrayList<>();
    private LinearLayout rows;
    private TextView status;
    private EditText search;
    private Button cacheFlushButton;
    private Button refreshButton;
    private Button clearButton;
    private ScrollView scroll;
    private int pendingScrollY;
    private boolean pendingScrollRestore;

    private static final class Entry {
        final String time, domain, type, reason;
        final boolean blocked;
        Entry(String time, String domain, String type, boolean blocked, String reason) {
            this.time = time; this.domain = domain; this.type = type;
            this.blocked = blocked; this.reason = reason;
        }
        String searchable() { return (time + " " + domain + " " + type + " " + reason).toLowerCase(Locale.ROOT); }
    }

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
    private String shell(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-ad-control.sh\" " + args;
    }
    private void root(String command, java.util.function.Consumer<RootAccess.Result> done) {
        root(command, 30000L, done);
    }
    private void root(String command, long timeoutMs,
                      java.util.function.Consumer<RootAccess.Result> done) {
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(command, timeoutMs, 768 * 1024);
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) done.accept(result); });
            });
        } catch (RejectedExecutionException full) {
            done.accept(RootAccess.failure(75, "DNS 日志后台队列繁忙，本次操作未执行；请稍后重试。"));
        }
    }
    private void card(LinearLayout parent, String title, String desc, View... children) {
        LinearLayout c = new LinearLayout(this); c.setOrientation(1);
        c.setPadding(dp(14), dp(9), dp(14), dp(9)); c.setBackgroundColor(0xfff0f3f7);
        c.addView(text(title, 15, 0xff17212b, true));
        c.addView(text(desc, 12, 0xff617080, false));
        for (View child : children) c.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); parent.addView(c, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(10), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("游龙广告插件 · DNS 查询日志", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1);
        body.setPadding(0, dp(4), 0, dp(18)); scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 1);

        status = text("正在读取本机查询日志…", 13, 0xff526170, false);
        search = new EditText(this); search.setSingleLine(true); search.setHint("搜索域名、类型或拦截原因");
        if (state != null) {
            search.setText(state.getString(STATE_SEARCH, ""));
            pendingScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            pendingScrollRestore = true;
        }
        refreshButton = button("刷新", this::load);
        clearButton = button("清理本地查询日志", this::confirmClear);
        card(body, "本机日志说明",
                "查询日志默认关闭；启用后 AdGuard Home 按本机保留策略保存记录。这里只显示最近 500 条，不显示客户端 IP，也不会上传。",
                status, refreshButton, clearButton);
        cacheFlushButton = button("重启本地 DNS 并清理缓存", this::confirmCacheFlush);
        card(body, "DNS 缓存维护",
                "只重启 FX 管理的本地 Unbound / AdGuard Home。DNS 可能短暂中断；不会清理系统 DNS 缓存、Hosts 或查询日志。",
                cacheFlushButton);
        card(body, "搜索", "输入域名、查询类型或拦截原因", search);
        rows = new LinearLayout(this); rows.setOrientation(1); body.addView(rows);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { render(); }
            @Override public void afterTextChanged(Editable e) {}
        });
        load();
    }

    private void load() {
        final int generation = loadGeneration.incrementAndGet();
        if (refreshButton != null) refreshButton.setEnabled(false);
        status.setText("正在读取最近 500 条 DNS 查询记录…");
        String command = shell("dns-log-tail");
        root(command, result -> {
            if (generation != loadGeneration.get()) return;
            if (refreshButton != null) refreshButton.setEnabled(true);
            if (result.exitCode != 0) {
                status.setText("读取失败：" + safe(result.output));
                data.clear(); render(); restoreScrollIfNeeded(); return;
            }
            parse(result.output);
            restoreScrollIfNeeded();
        });
    }

    private void restoreScrollIfNeeded() {
        if (!pendingScrollRestore || scroll == null) return;
        final int restoreY = pendingScrollY;
        scroll.post(() -> {
            if (isFinishing() || isDestroyed() || !pendingScrollRestore || scroll == null) return;
            scroll.scrollTo(0, restoreY);
            pendingScrollRestore = false;
        });
    }

    private void parse(String output) {
        data.clear();
        int total = 0, blocked = 0;
        String raw = output == null ? "" : output;
        if (raw.contains("FXDNSLOG_DISABLED")) {
            status.setText("DNS 查询日志当前关闭。请返回游龙广告插件 → DNS 设置，手动开启本地日志。");
            render(); return;
        }
        if (raw.contains("FXDNSLOG_EMPTY")) {
            status.setText("本机暂无 DNS 查询记录。开启查询日志并产生 DNS 请求后，这里会出现记录。");
            render(); return;
        }
        for (String line : raw.split("\\r?\\n")) {
            String trimmed = line.trim();
            if (!trimmed.startsWith("{")) continue;
            try {
                JSONObject item = new JSONObject(trimmed);
                JSONObject result = item.optJSONObject("Result");
                JSONObject question = item.optJSONObject("question");
                boolean isBlocked = result != null && result.optBoolean("IsFiltered", false);
                if (item.optBoolean("IsFiltered", false)) isBlocked = true;
                String reason = result == null ? item.optString("reason", "")
                        : result.optString("Reason", item.optString("reason", ""));
                String statusValue = item.optString("status", "").toLowerCase(Locale.ROOT);
                if (statusValue.contains("block") || statusValue.contains("filter")) isBlocked = true;
                if (!isBlocked && reason.toLowerCase(Locale.ROOT).startsWith("filtered")) isBlocked = true;
                String domain = item.optString("QH", "").trim();
                String type = item.optString("QT", "").trim();
                String time = item.optString("T", item.optString("time", ""));
                if (question != null) {
                    if (domain.isEmpty()) domain = question.optString("host", "").trim();
                    if (type.isEmpty()) type = question.optString("type", "").trim();
                }
                if (domain.isEmpty()) continue;
                data.add(new Entry(time, domain, type, isBlocked, reason));
                total++;
                if (isBlocked) blocked++;
            } catch (Exception ignored) { }
        }
        status.setText("最近解析 " + total + " 条 · 拦截 " + blocked + " 条 · 放行/未拦截 "
                + Math.max(0, total - blocked) + " 条。数据仅来自本地查询日志尾部。");
        render();
    }

    private void render() {
        if (rows == null) return;
        rows.removeAllViews();
        String query = search.getText() == null ? "" : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int count = 0;
        for (Entry item : data) {
            if (!query.isEmpty() && !item.searchable().contains(query)) continue;
            LinearLayout row = new LinearLayout(this); row.setOrientation(1);
            row.setPadding(dp(10), dp(6), dp(10), dp(6));
            row.setBackgroundColor(0xffffffff);
            row.addView(text(item.domain, 13, 0xff17212b, true));
            row.addView(text(item.type + " · " + (item.blocked ? "已拦截" : "未拦截")
                    + (item.reason.isEmpty() ? "" : " · " + item.reason), 11,
                    item.blocked ? 0xffb42318 : 0xff526170, false));
            if (!item.time.isEmpty()) row.addView(text(item.time, 10, 0xff718091, false));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(10), dp(2), dp(10), dp(2)); rows.addView(row, lp);
            if (++count >= 200) break;
        }
        if (count == 0) rows.addView(text("没有匹配的 DNS 查询记录。", 13, 0xff718091, false));
        else if (count >= 200) rows.addView(text("仅显示前 200 条匹配项。", 11, 0xff718091, false));
    }

    private void confirmCacheFlush() {
        new AlertDialog.Builder(this).setTitle("清理本机 DNS 缓存")
                .setMessage("将停止并重新启动 FX 管理的本地 Unbound / AdGuard Home，以清空它们的进程内缓存。期间 DNS 可能短暂中断。不会清理 Android 系统 DNS 缓存、Hosts 或查询日志。")
                .setNegativeButton("取消", null)
                .setPositiveButton("重启并清理", (dialog, which) -> {
                    loadGeneration.incrementAndGet();
                    if (refreshButton != null) refreshButton.setEnabled(true);
                    if (cacheFlushButton != null) cacheFlushButton.setEnabled(false);
                    status.setText("正在重启 FX 本地 DNS 服务并清理缓存…");
                    root(shell("cache-flush"), 120000L, result -> {
                        if (cacheFlushButton != null) cacheFlushButton.setEnabled(true);
                        String output = result.output == null ? "" : result.output;
                        if (result.exitCode == 0 && output.contains("cache=flushed")) {
                            status.setText("本地 DNS 缓存已清理，FX DNS 服务重启完成。");
                        } else if (result.exitCode == 0 && output.contains("dns-engine-disabled")) {
                            status.setText("FX 本地 DNS 引擎当前未启用，无需清理。");
                        } else {
                            status.setText("DNS 缓存清理未完成：" + safe(output));
                        }
                    });
                }).show();
    }

    private void confirmClear() {
        new AlertDialog.Builder(this).setTitle("清理本地 DNS 查询日志")
                .setMessage("只清理 FX AdGuard Home 自己的 querylog.json 文件，不修改 DNS 规则、Hosts 或系统日志。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清理", (d, w) -> {
                    loadGeneration.incrementAndGet();
                    if (clearButton != null) clearButton.setEnabled(false);
                    if (refreshButton != null) refreshButton.setEnabled(true);
                    root(shell("dns-log-clear"), result -> {
                        if (clearButton != null) clearButton.setEnabled(true);
                        if (result.exitCode == 0) {
                            status.setText("本地 DNS 查询日志已清理。");
                            data.clear(); render();
                        } else status.setText("清理失败：" + safe(result.output));
                    });
                }).show();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        if (search != null) outState.putString(STATE_SEARCH, search.getText().toString());
        if (scroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, scroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }

    private String safe(String value) {
        return value == null || value.trim().isEmpty() ? "请确认 FX Hook Root 权限。" : value.trim();
    }

    @Override protected void onDestroy() {
        loadGeneration.incrementAndGet();
        worker.shutdownNow();
        super.onDestroy();
    }
}
