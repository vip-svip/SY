package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
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
    private static final int ROW_PAGE_SIZE = 50;
    private static final String STATE_SEARCH = "fx_dns_search";
    private static final String STATE_PAGE = "fx_dns_page";
    private static final String STATE_SCROLL_Y = "fx_dns_scroll_y";
    private static final String STATE_RESULT_FILTER = "fx_dns_result_filter";
    private static final String STATE_TIME_FILTER = "fx_dns_time_filter";
    private static final String STATE_TYPE_FILTER = "fx_dns_type_filter";
    private static final String STATE_RCODE_FILTER = "fx_dns_rcode_filter";
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
    private int page = 1;
    /** 0=all, 1=blocked only, 2=allowed only. */
    private int resultFilter = 0;
    /** 0=all, 1=last hour, 2=last 24 hours, 3=last 7 days. */
    private int timeFilter = 0;
    /** Empty means all DNS RR types; otherwise an uppercase exact RR type. */
    private String typeFilter = "";
    private String rcodeFilter = "";
    private int pendingScrollY;
    private boolean pendingScrollRestore;

    private static final class Entry {
        final String time, domain, type, reason, rcode;
        final boolean blocked;
        Entry(String time, String domain, String type, boolean blocked, String reason, String rcode) {
            this.time = time; this.domain = domain; this.type = type;
            this.blocked = blocked; this.reason = reason; this.rcode = rcode;
        }
        String searchable() { return (time + " " + domain + " " + type + " " + reason + " " + rcode).toLowerCase(Locale.ROOT); }
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
        boolean domainListAdd = args != null && args.matches("(allow-add|block-add) [A-Za-z0-9.-]{1,253}");
        if (!"dns-log-tail".equals(args) && !"cache-flush".equals(args)
                && !"cache-flush adguardhome".equals(args)
                && !"cache-flush unbound".equals(args)
                && !"cache-flush all".equals(args)
                && !"dns-log-clear".equals(args) && !domainListAdd) {
            throw new IllegalArgumentException("Unsupported Yulong DNS operation.");
        }
        return FxYulongRootModuleCommand.command("yulong-ad-control.sh", args);
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
        header.addView(button("‹ 返回 Ad", this::finish));
        header.addView(text("FX Ad · DNS 查询日志", 18, 0xff17212b, true),
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
            page = Math.max(1, state.getInt(STATE_PAGE, 1));
            search.setText(state.getString(STATE_SEARCH, ""));
            pendingScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            resultFilter = Math.max(0, Math.min(2, state.getInt(STATE_RESULT_FILTER, 0)));
            timeFilter = Math.max(0, Math.min(3, state.getInt(STATE_TIME_FILTER, 0)));
            typeFilter = normalizeTypeFilter(state.getString(STATE_TYPE_FILTER, ""));
            rcodeFilter = normalizeRcodeFilter(state.getString(STATE_RCODE_FILTER, ""));
            pendingScrollRestore = true;
        }
        refreshButton = button("刷新", this::load);
        clearButton = button("清理本地查询日志", this::confirmClear);
        Button shareButton = button("分享全部筛选结果", this::shareFilteredResults);
        Button copyDomainsButton = button("复制筛选域名（去重）", this::copyFilteredDomains);
        card(body, "本机日志说明",
                "查询日志默认关闭；启用后 AdGuard Home 按本机保留策略保存记录。这里只显示最近 500 条，不显示客户端 IP，也不会上传。",
                status, refreshButton, clearButton, shareButton, copyDomainsButton);
        cacheFlushButton = button("刷新全部本地 DNS 缓存", () -> confirmCacheFlush("all", "全部本地 DNS"));
        Button aghFlushButton = button("仅刷新 AdGuard Home", () -> confirmCacheFlush("adguardhome", "AdGuard Home"));
        Button unboundFlushButton = button("仅刷新 Unbound", () -> confirmCacheFlush("unbound", "Unbound"));
        card(body, "DNS 缓存维护",
                "可单独刷新 FX 管理的 AdGuard Home 或 Unbound，也可刷新全部已启用引擎。所选服务会短暂重启；不会清理系统 DNS 缓存、Hosts 或查询日志。",
                aghFlushButton, unboundFlushButton, cacheFlushButton);
        card(body, "搜索", "输入域名、查询类型或拦截原因", search);
        LinearLayout resultFilters = new LinearLayout(this);
        resultFilters.setOrientation(LinearLayout.HORIZONTAL);
        resultFilters.addView(button("全部", () -> setResultFilter(0)), new LinearLayout.LayoutParams(0, -2, 1));
        resultFilters.addView(button("仅拦截", () -> setResultFilter(1)), new LinearLayout.LayoutParams(0, -2, 1));
        resultFilters.addView(button("仅放行", () -> setResultFilter(2)), new LinearLayout.LayoutParams(0, -2, 1));
        card(body, "结果状态筛选", "与域名/类型/原因搜索叠加；分享时沿用相同筛选条件。", resultFilters);
        LinearLayout timeFilters = new LinearLayout(this);
        timeFilters.setOrientation(LinearLayout.HORIZONTAL);
        timeFilters.addView(button("全部时间", () -> setTimeFilter(0)), new LinearLayout.LayoutParams(0, -2, 1));
        timeFilters.addView(button("近 1 小时", () -> setTimeFilter(1)), new LinearLayout.LayoutParams(0, -2, 1));
        timeFilters.addView(button("近 24 小时", () -> setTimeFilter(2)), new LinearLayout.LayoutParams(0, -2, 1));
        timeFilters.addView(button("近 7 天", () -> setTimeFilter(3)), new LinearLayout.LayoutParams(0, -2, 1));
        card(body, "时间范围筛选", "按日志时间筛选；无法识别时间格式的记录仍保留显示，避免误隐藏本地日志。分享时同步应用。", timeFilters);
        LinearLayout typeFilters = new LinearLayout(this);
        typeFilters.setOrientation(LinearLayout.HORIZONTAL);
        String[] rrTypes = {"全部", "A", "AAAA", "HTTPS", "TXT", "MX", "CNAME"};
        String[] rrValues = {"", "A", "AAAA", "HTTPS", "TXT", "MX", "CNAME"};
        for (int i = 0; i < rrTypes.length; i++) {
            final String value = rrValues[i];
            typeFilters.addView(button(rrTypes[i], () -> setTypeFilter(value)),
                    new LinearLayout.LayoutParams(0, -2, 1));
        }
        card(body, "DNS 记录类型筛选", "按 DNS 查询记录类型精确筛选；可与域名搜索、拦截状态和时间范围叠加，分享时沿用。", typeFilters);
        LinearLayout rcodeFilters = new LinearLayout(this);
        rcodeFilters.setOrientation(LinearLayout.HORIZONTAL);
        String[] rcodeLabels = {"全部", "NOERROR", "NXDOMAIN", "SERVFAIL", "REFUSED", "其他"};
        String[] rcodeValues = {"", "NOERROR", "NXDOMAIN", "SERVFAIL", "REFUSED", "OTHER"};
        for (int i = 0; i < rcodeLabels.length; i++) {
            final String value = rcodeValues[i];
            rcodeFilters.addView(button(rcodeLabels[i], () -> setRcodeFilter(value)),
                    new LinearLayout.LayoutParams(0, -2, 1));
        }
        card(body, "DNS 响应码筛选", "按本地日志记录的 DNS 响应状态筛选；缺少或无法识别状态的记录归入“其他”，并与现有筛选条件叠加。分享时沿用。", rcodeFilters);
        rows = new LinearLayout(this); rows.setOrientation(1); body.addView(rows);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                page = 1;
                pendingScrollY = 0;
                pendingScrollRestore = false;
                render();
                if (scroll != null) scroll.scrollTo(0, 0);
            }
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
        int total = 0, blocked = 0, malformed = 0;
        String raw = output == null ? "" : output;
        if (raw.contains("FXDNSLOG_DISABLED")) {
            status.setText("DNS 查询日志当前关闭。请返回 Ad → DNS 设置，手动开启本地日志。");
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
                String responseStatus = result == null ? statusValue
                        : result.optString("Status", item.optString("status", ""));
                String rcode = normalizeRcodeValue(responseStatus);
                if (!isBlocked && reason.toLowerCase(Locale.ROOT).startsWith("filtered")) isBlocked = true;
                String domain = item.optString("QH", "").trim();
                String type = item.optString("QT", "").trim();
                String time = item.optString("T", item.optString("time", ""));
                if (question != null) {
                    if (domain.isEmpty()) domain = question.optString("host", "").trim();
                    if (type.isEmpty()) type = question.optString("type", "").trim();
                }
                if (domain.isEmpty()) { malformed++; continue; }
                data.add(new Entry(time, domain, type, isBlocked, reason, rcode));
                total++;
                if (isBlocked) blocked++;
            } catch (Exception ignored) { malformed++; }
        }
        status.setText("本次解析 " + total + " 条 · 拦截 " + blocked + " 条 · 放行/未拦截 "
                + Math.max(0, total - blocked) + " 条 · 无法解析/缺少域名 " + malformed
                + " 条。数据仅来自本地查询日志尾部；若异常数大于 0，请检查本地日志格式。");
        render();
    }

    private void setResultFilter(int filter) {
        resultFilter = Math.max(0, Math.min(2, filter));
        page = 1;
        pendingScrollY = 0;
        pendingScrollRestore = false;
        render();
        if (scroll != null) scroll.scrollTo(0, 0);
    }

    private boolean matchesResultFilter(Entry item) {
        return resultFilter == 0 || (resultFilter == 1 && item.blocked)
                || (resultFilter == 2 && !item.blocked);
    }

    private boolean matchesTimeFilter(Entry item) {
        if (timeFilter == 0) return true;
        long timestamp = parseLogTime(item == null ? null : item.time);
        // Keep records with unrecognized timestamps visible rather than silently dropping them.
        if (timestamp < 0L) return true;
        long window = timeFilter == 1 ? 60L * 60L * 1000L
                : timeFilter == 2 ? 24L * 60L * 60L * 1000L
                : 7L * 24L * 60L * 60L * 1000L;
        long now = System.currentTimeMillis();
        return timestamp >= now - window && timestamp <= now + 5L * 60L * 1000L;
    }

    private long parseLogTime(String value) {
        if (value == null || value.trim().isEmpty()) return -1L;
        String raw = value.trim();
        try {
            android.text.format.Time parsed = new android.text.format.Time();
            if (parsed.parse3339(raw)) return parsed.toMillis(false);
        } catch (RuntimeException ignored) { }
        try {
            long numeric = Long.parseLong(raw);
            return raw.length() <= 10 ? numeric * 1000L : numeric;
        } catch (NumberFormatException ignored) { }
        return -1L;
    }

    private void setTimeFilter(int filter) {
        timeFilter = Math.max(0, Math.min(3, filter));
        page = 1;
        pendingScrollY = 0;
        pendingScrollRestore = false;
        render();
        if (scroll != null) scroll.scrollTo(0, 0);
    }

    private static String normalizeTypeFilter(String value) {
        if (value == null) return "";
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        switch (normalized) {
            case "A": case "AAAA": case "HTTPS": case "TXT": case "MX": case "CNAME":
                return normalized;
            default: return "";
        }
    }

    private boolean matchesTypeFilter(Entry item) {
        return typeFilter.isEmpty() || (item != null && typeFilter.equals(
                item.type == null ? "" : item.type.trim().toUpperCase(Locale.ROOT)));
    }

    private void setTypeFilter(String value) {
        typeFilter = normalizeTypeFilter(value);
        page = 1;
        pendingScrollY = 0;
        pendingScrollRestore = false;
        render();
        if (scroll != null) scroll.scrollTo(0, 0);
    }

    private static String normalizeRcodeValue(String value) {
        if (value == null) return "OTHER";
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        if (normalized.contains("NOERROR") || normalized.equals("0")) return "NOERROR";
        if (normalized.contains("NXDOMAIN") || normalized.equals("3")) return "NXDOMAIN";
        if (normalized.contains("SERVFAIL") || normalized.equals("2")) return "SERVFAIL";
        if (normalized.contains("REFUSED") || normalized.equals("5")) return "REFUSED";
        return "OTHER";
    }
    private static String normalizeRcodeFilter(String value) {
        if (value == null || value.trim().isEmpty()) return "";
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        switch (normalized) {
            case "NOERROR": case "NXDOMAIN": case "SERVFAIL": case "REFUSED": case "OTHER": return normalized;
            default: return "";
        }
    }
    private boolean matchesRcodeFilter(Entry item) {
        return rcodeFilter.isEmpty() || (item != null && rcodeFilter.equals(item.rcode));
    }
    private void setRcodeFilter(String value) {
        rcodeFilter = normalizeRcodeFilter(value);
        page = 1; pendingScrollY = 0; pendingScrollRestore = false;
        render();
        if (scroll != null) scroll.scrollTo(0, 0);
    }
    private void confirmAddDomain(Entry item, boolean allow) {
        String domain = item == null || item.domain == null ? "" : item.domain.trim().toLowerCase(Locale.ROOT);
        if (!domain.matches("[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?") || domain.contains("..")
                || domain.startsWith(".") || domain.endsWith(".")) {
            status.setText("该查询域名不符合域名名单格式，未执行添加。");
            return;
        }
        String listName = allow ? "白名单" : "黑名单";
        fxDialogBuilder().setTitle("加入 DNS " + listName)
                .setMessage("将域名 " + domain + " 添加到 FX " + listName
                        + "。此操作会修改本机域名名单并应用配置；"
                        + (allow ? "白名单优先放行该域名。" : "黑名单将阻断该域名。")
                        + "是否继续？")
                .setNegativeButton("取消", null)
                .setPositiveButton("添加", (dialog, which) -> {
                    String operation = (allow ? "allow-add " : "block-add ") + domain;
                    root(shell(operation), result -> {
                        if (result.exitCode == 0) {
                            status.setText(domain + " 已加入 FX " + listName + "。");
                            load();
                        } else {
                            status.setText("加入" + listName + "失败：" + safe(result.output));
                        }
                    });
                }).show();
    }

    private void render() {
        if (rows == null) return;
        rows.removeAllViews();
        String query = search.getText() == null ? "" : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched = 0;
        for (Entry item : data) {
            if (matchesResultFilter(item) && matchesTimeFilter(item) && matchesTypeFilter(item) && matchesRcodeFilter(item)
                    && (query.isEmpty() || item.searchable().contains(query))) matched++;
        }
        int maxPage = Math.max(1, (matched + ROW_PAGE_SIZE - 1) / ROW_PAGE_SIZE);
        if (page > maxPage) page = maxPage;
        int limit = page * ROW_PAGE_SIZE;
        int shown = 0;
        rows.addView(text("匹配 " + matched + " 条 · 已显示 " + Math.min(matched, limit) + " 条",
                11, 0xff718091, false));
        for (Entry item : data) {
            if (!matchesResultFilter(item) || !matchesTimeFilter(item) || !matchesTypeFilter(item) || !matchesRcodeFilter(item)
                    || (!query.isEmpty() && !item.searchable().contains(query))) continue;
            if (shown >= limit) continue;
            LinearLayout row = new LinearLayout(this); row.setOrientation(1);
            row.setPadding(dp(10), dp(6), dp(10), dp(6));
            row.setBackgroundColor(0xffffffff);
            row.addView(text(item.domain, 13, 0xff17212b, true));
            row.addView(text(item.type + " · " + (item.blocked ? "已拦截" : "未拦截")
                    + " · " + item.rcode + (item.reason.isEmpty() ? "" : " · " + item.reason), 11,
                    item.blocked ? 0xffb42318 : 0xff526170, false));
            if (!item.time.isEmpty()) row.addView(text(item.time, 10, 0xff718091, false));
            LinearLayout actions = new LinearLayout(this);
            actions.setOrientation(LinearLayout.HORIZONTAL);
            actions.addView(button("加入白名单", () -> confirmAddDomain(item, true)),
                    new LinearLayout.LayoutParams(0, -2, 1));
            actions.addView(button("加入黑名单", () -> confirmAddDomain(item, false)),
                    new LinearLayout.LayoutParams(0, -2, 1));
            row.addView(actions);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(10), dp(2), dp(10), dp(2)); rows.addView(row, lp);
            shown++;
        }
        if (matched == 0) {
            rows.addView(text("没有匹配的 DNS 查询记录。", 13, 0xff718091, false));
        } else if (shown < matched) {
            rows.addView(button("加载更多（剩余 " + (matched - shown) + " 条）", () -> {
                int restoreY = scroll == null ? 0 : Math.max(0, scroll.getScrollY());
                page++;
                render();
                if (scroll != null) scroll.post(() -> {
                    if (!isFinishing() && !isDestroyed() && scroll != null) scroll.scrollTo(0, restoreY);
                });
            }));
        }
    }


    /** Copy unique domains from all locally loaded rows matching every active filter. */
    private void copyFilteredDomains() {
        if (data.isEmpty()) {
            status.setText("当前没有可复制的 DNS 查询记录；请先刷新并确认本地日志已启用。");
            return;
        }
        String query = search == null || search.getText() == null ? ""
                : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        List<String> domains = new ArrayList<>();
        int matchedRows = 0;
        int duplicateRows = 0;
        final int maxBytes = 48 * 1024;
        int bytes = 0;
        for (Entry item : data) {
            if (!matchesResultFilter(item) || !matchesTimeFilter(item)
                    || !matchesTypeFilter(item) || !matchesRcodeFilter(item)
                    || (!query.isEmpty() && !item.searchable().contains(query))) continue;
            matchedRows++;
            if (domains.contains(item.domain)) {
                duplicateRows++;
                continue;
            }
            int nextBytes = item.domain.getBytes(java.nio.charset.StandardCharsets.UTF_8).length
                    + (domains.isEmpty() ? 0 : 1);
            if (bytes + nextBytes > maxBytes) {
                status.setText("筛选结果域名清单超过 48 KiB，未复制不完整清单；请缩小筛选范围。");
                return;
            }
            domains.add(item.domain);
            bytes += nextBytes;
        }
        if (domains.isEmpty()) {
            status.setText("当前筛选条件没有可复制的域名。");
            return;
        }
        try {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard == null) {
                status.setText("系统剪贴板不可用，未复制域名。");
                return;
            }
            clipboard.setPrimaryClip(ClipData.newPlainText("FX DNS domains", String.join("\\n", domains)));
            status.setText("已复制 " + domains.size() + " 个去重域名（匹配 " + matchedRows
                    + " 条记录，合并 " + duplicateRows + " 条重复域名）。仅使用当前本地筛选结果。");
        } catch (RuntimeException failure) {
            status.setText("复制域名失败：" + safe(failure.getMessage()));
        }
    }

    /** Share all locally loaded rows matching the current query, independent of pagination. */
    private void shareFilteredResults() {
        if (data.isEmpty()) {
            status.setText("当前没有可分享的 DNS 查询记录；请先刷新并确认本地日志已启用。");
            return;
        }
        String query = search == null || search.getText() == null ? ""
                : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        StringBuilder report = new StringBuilder();
        report.append("FX Ad DNS query log\\n")
                .append("filter=").append(query).append("\\n")
                .append("result=").append(resultFilter == 1 ? "blocked" : resultFilter == 2 ? "allowed" : "all").append("\\n")
                .append("time=").append(timeFilter == 1 ? "1h" : timeFilter == 2 ? "24h" : timeFilter == 3 ? "7d" : "all").append("\\n")
                .append("dns_type=").append(typeFilter.isEmpty() ? "all" : typeFilter).append("\\n")
                .append("rcode=").append(rcodeFilter.isEmpty() ? "all" : rcodeFilter).append("\\n")
                .append("scope=locally retained latest 500 parsed records\\n")
                .append("time\\tdomain\\ttype\\trcode\\tresult\\treason\\n");
        int included = 0;
        int omitted = 0;
        final int maxBytes = 48 * 1024;
        for (Entry item : data) {
            if (!matchesResultFilter(item) || !matchesTimeFilter(item) || !matchesTypeFilter(item) || !matchesRcodeFilter(item)
                    || (!query.isEmpty() && !item.searchable().contains(query))) continue;
            String row = cleanExportField(item.time) + "\\t"
                    + cleanExportField(item.domain) + "\\t"
                    + cleanExportField(item.type) + "\\t"
                    + cleanExportField(item.rcode) + "\\t"
                    + (item.blocked ? "blocked" : "allowed") + "\\t"
                    + cleanExportField(item.reason) + "\\n";
            int used = report.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
            int bytes = row.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
            if (used + bytes > maxBytes) { omitted++; continue; }
            report.append(row);
            included++;
        }
        if (included == 0) {
            status.setText("当前搜索条件没有可分享的 DNS 查询记录。");
            return;
        }
        if (omitted > 0) report.append("# omitted ").append(omitted)
                .append(" matching rows at 48 KiB share limit\\n");
        try {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_SUBJECT, "FX Ad DNS 查询记录（筛选结果）");
            send.putExtra(Intent.EXTRA_TEXT, report.toString());
            startActivity(Intent.createChooser(send, "分享 DNS 查询记录"));
            status.setText("已准备分享 " + included + " 条筛选匹配记录"
                    + (omitted > 0 ? "；另有 " + omitted + " 条因 48 KiB 上限省略。" : "。"));
        } catch (RuntimeException unavailable) {
            status.setText("无法打开系统分享面板：" + safe(unavailable.getMessage()));
        }
    }

    private static String cleanExportField(String value) {
        return value == null ? "" : value.replace('\\t', ' ')
                .replace('\\r', ' ').replace('\\n', ' ');
    }

    private void confirmCacheFlush(String target, String label) {
        fxDialogBuilder().setTitle("刷新" + label + "缓存")
                .setMessage("将只停止并重新启动 FX 管理的 " + label
                        + " 服务，以清空其进程内缓存。期间相关 DNS 查询可能短暂中断。"
                        + "不会操作第三方 VPN、Android 系统 DNS 缓存、Hosts 或查询日志。"
                        + "若所选引擎未启用，FX 会拒绝操作。是否继续？")
                .setNegativeButton("取消", null)
                .setPositiveButton("刷新", (dialog, which) -> {
                    loadGeneration.incrementAndGet();
                    if (refreshButton != null) refreshButton.setEnabled(true);
                    if (cacheFlushButton != null) cacheFlushButton.setEnabled(false);
                    status.setText("正在刷新 " + label + " 缓存…");
                    root(shell("cache-flush " + target), 120000L, result -> {
                        if (cacheFlushButton != null) cacheFlushButton.setEnabled(true);
                        String output = result.output == null ? "" : result.output;
                        if (result.exitCode == 0 && output.contains("cache=flushed")) {
                            status.setText(label + " 缓存已刷新，FX DNS 服务重启完成。");
                        } else if (result.exitCode == 0 && output.contains("dns-engine-disabled")) {
                            status.setText("FX 本地 DNS 引擎当前未启用，无需清理。");
                        } else {
                            status.setText(label + " 缓存刷新未完成：" + safe(output));
                        }
                    });
                }).show();
    }

    private void confirmClear() {
        fxDialogBuilder().setTitle("清理本地 DNS 查询日志")
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
        outState.putInt(STATE_PAGE, Math.max(1, page));
        outState.putInt(STATE_RESULT_FILTER, resultFilter);
        outState.putInt(STATE_TIME_FILTER, timeFilter);
        outState.putString(STATE_TYPE_FILTER, typeFilter);
        outState.putString(STATE_RCODE_FILTER, rcodeFilter);
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
