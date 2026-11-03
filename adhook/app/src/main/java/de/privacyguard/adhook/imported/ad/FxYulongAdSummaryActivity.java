package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;

import org.json.JSONObject;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Local Yulong AdBlock daily protection summary backed by FX's own config and DNS query log. */
public final class FxYulongAdSummaryActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private LinearLayout body;
    private TextView status;
    private static final class Query {
        final boolean blocked;
        final long time;
        Query(boolean blocked, long time) { this.blocked = blocked; this.time = time; }
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label); b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this); panel.setOrientation(1);
        panel.setPadding(dp(14), dp(9), dp(14), dp(9)); panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 15, 0xff17212b, true)); panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); body.addView(panel, lp);
    }
    private String moduleShell(String scriptArgs) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-ad-control.sh\" " + scriptArgs;
    }
    private void root(String args, java.util.function.Consumer<RootAccess.Result> callback) {
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(moduleShell(args), 30000L, 1024 * 1024);
            runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) callback.accept(result); });
        });
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("游龙广告插件 · 每日防护总结", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        status = text("正在读取本机广告过滤配置与 DNS 查询日志…", 13, 0xff526170, false);
        card("本机数据口径",
                "汇总 FX 当前生效的游龙广告过滤主开关、规则源与域名名单；查询统计只读取本机 AdGuard Home 最近 500 条日志样本。若日志关闭，不会推测今日拦截数。",
                status, button("刷新总结", this::load),
                button("查看 DNS 查询日志", () -> startActivity(new Intent(this, FxYulongDnsActivity.class))),
                button("查看分应用流量", () -> startActivity(new Intent(this, FxYulongAppStatsActivity.class))));
        load();
    }

    private void load() {
        body.removeViews(1, Math.max(0, body.getChildCount() - 1));
        status.setText("正在读取配置…");
        root("list", config -> {
            if (config.exitCode != 0) {
                status.setText("读取广告过滤配置失败：" + safe(config.output)); return;
            }
            Summary summary = parseConfig(config.output);
            root("dns-log-tail", logs -> renderSummary(summary, logs));
        });
    }

    private static final class Summary {
        boolean adMaster;
        int enabledRules, totalRules, allowDomains, blockDomains;
    }
    private Summary parseConfig(String raw) {
        Summary out = new Summary();
        for (String line : (raw == null ? "" : raw).split("\\r?\\n")) {
            String[] p = line.split("\\|", -1);
            if (p.length == 2 && "AD_MASTER".equals(p[0])) out.adMaster = "1".equals(p[1]);
            else if (p.length >= 4 && "RULE".equals(p[0])) {
                out.totalRules++; if ("1".equals(p[3])) out.enabledRules++;
            } else if (p.length >= 4 && "ALLOW".equals(p[0]) && "1".equals(p[3])) out.allowDomains++;
            else if (p.length >= 4 && "BLOCK".equals(p[0]) && "1".equals(p[3])) out.blockDomains++;
        }
        return out;
    }

    private long timestamp(String value) {
        if (value == null || value.trim().isEmpty()) return -1L;
        try { return Instant.parse(value.trim()).toEpochMilli(); } catch (Throwable ignored) { }
        try { return ZonedDateTime.parse(value.trim()).toInstant().toEpochMilli(); } catch (Throwable ignored) { }
        return -1L;
    }

    private void renderSummary(Summary config, RootAccess.Result logs) {
        if (isFinishing() || isDestroyed()) return;
        StringBuilder configuration = new StringBuilder();
        configuration.append("广告过滤主开关：").append(config.adMaster ? "已启用" : "已关闭")
                .append("\n已启用规则源：").append(config.enabledRules).append(" / ").append(config.totalRules)
                .append("\n白名单域名：").append(config.allowDomains)
                .append("\n黑名单域名：").append(config.blockDomains);
        card("广告过滤配置", "直接来自设备端 yulong-ad-control.sh list。", text(configuration.toString(), 13, 0xff334155, false));

        if (logs.exitCode != 0) {
            card("DNS 查询样本", "读取本地日志失败。", text(safe(logs.output), 12, 0xff9b2c2c, false));
            status.setText("配置摘要已读取；DNS 查询样本读取失败。");
            return;
        }
        String raw = logs.output == null ? "" : logs.output;
        if (raw.contains("FXDNSLOG_DISABLED")) {
            card("DNS 查询样本", "本地查询日志当前关闭。", text("请在 DNS 设置中开启本地 DNS 查询日志后再查看统计。", 12, 0xff617080, false));
            status.setText("配置摘要已读取；DNS 查询日志未启用。今日拦截数不作推算。");
            return;
        }
        if (raw.contains("FXDNSLOG_EMPTY")) {
            card("DNS 查询样本", "本地暂无查询记录。", text("启用查询日志并产生 DNS 请求后，这里会显示样本摘要。", 12, 0xff617080, false));
            status.setText("配置摘要已读取；本机暂无查询样本。");
            return;
        }

        List<Query> queries = new ArrayList<>();
        int malformed = 0;
        long dayStart = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli();
        long now = System.currentTimeMillis();
        int today = 0, todayBlocked = 0, unknownTime = 0;
        for (String line : raw.split("\\r?\\n")) {
            String value = line.trim();
            if (!value.startsWith("{")) continue;
            try {
                JSONObject item = new JSONObject(value);
                JSONObject result = item.optJSONObject("Result");
                boolean blocked = item.optBoolean("IsFiltered", false)
                        || (result != null && result.optBoolean("IsFiltered", false));
                String reason = result == null ? item.optString("reason", "")
                        : result.optString("Reason", item.optString("reason", ""));
                String logStatus = item.optString("status", "").toLowerCase(java.util.Locale.ROOT);
                if (logStatus.contains("block") || logStatus.contains("filter")
                        || reason.toLowerCase(java.util.Locale.ROOT).startsWith("filtered")) blocked = true;
                long time = timestamp(item.optString("T", item.optString("time", "")));
                if (time < 0) unknownTime++;
                else if (time >= dayStart && time <= now) { today++; if (blocked) todayBlocked++; }
                queries.add(new Query(blocked, time));
            } catch (Throwable error) { malformed++; }
        }
        int blocked = 0; for (Query q : queries) if (q.blocked) blocked++;
        String metrics = "最近 500 条日志样本中解析：" + queries.size() + " 条"
                + "\n其中拦截：" + blocked + " 条"
                + "\n未标记拦截：" + Math.max(0, queries.size() - blocked) + " 条"
                + "\n今日样本（仅日志带可解析时间时）： " + today + " 条 · 拦截 " + todayBlocked + " 条"
                + "\n时间无法解析：" + unknownTime + " 条 · 无效行：" + malformed + " 条";
        card("DNS 查询与拦截样本",
                "本机 AdGuard Home querylog.json 的最近 500 条尾部样本。不是完整历史总量，也不代表每个应用的独立查询计数。",
                text(metrics, 13, 0xff334155, false));
        status.setText("总结已更新。样本仅限最近 500 条本地 DNS 查询日志；完整日累计需以日志保留策略为准。");
    }

    private String safe(String value) {
        return value == null || value.trim().isEmpty() ? "Root 后端没有返回错误详情。" : value.trim();
    }
    @Override protected void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
