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

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Local Yulong AdBlock daily protection summary backed by FX's own config and DNS query log. */
public final class FxYulongAdSummaryActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> { Thread t = new Thread(r, "fx-yulong-ad-summary"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private LinearLayout body;
    private TextView status;
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
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(moduleShell(args), 30000L, 1024 * 1024);
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) callback.accept(result); });
            });
        } catch (RejectedExecutionException full) {
            callback.accept(RootAccess.failure(75, "防护总结后台队列繁忙，本次读取未执行；请稍后重试。"));
        }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回 Ad", this::finish));
        header.addView(text("Ad · 本机防护总结", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 1);

        status = text("正在读取本机广告过滤配置与 DNS 查询日志…", 13, 0xff526170, false);
        card("本机数据口径",
                "汇总 FX 当前生效的游龙广告过滤主开关、规则源与域名名单；DNS 累计只返回本机当前保留日志的数字计数，不返回域名、客户端 IP 或原始记录。日志默认关闭，须由用户主动开启。",
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
            root("dns-log-summary", stats -> renderSummary(summary, stats));
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

    private static long metric(String raw, String key) {
        for (String line : (raw == null ? "" : raw).split("\\r?\\n")) {
            if (!line.startsWith(key + "=")) continue;
            try {
                long value = Long.parseLong(line.substring(key.length() + 1).trim());
                return value < 0 ? -1L : value;
            } catch (NumberFormatException invalid) {
                return -1L;
            }
        }
        return -1L;
    }

    private void renderSummary(Summary config, RootAccess.Result stats) {
        if (isFinishing() || isDestroyed()) return;
        StringBuilder configuration = new StringBuilder();
        configuration.append("广告过滤主开关：").append(config.adMaster ? "已启用" : "已关闭")
                .append("\n已启用规则源：").append(config.enabledRules).append(" / ").append(config.totalRules)
                .append("\n白名单域名：").append(config.allowDomains)
                .append("\n黑名单域名：").append(config.blockDomains);
        card("广告过滤配置", "直接来自设备端 yulong-ad-control.sh list。", text(configuration.toString(), 13, 0xff334155, false));

        if (stats.exitCode != 0) {
            card("DNS 累计统计", "读取本机累计计数失败。", text(safe(stats.output), 12, 0xff9b2c2c, false));
            status.setText("配置摘要已读取；DNS 累计统计读取失败。");
            return;
        }
        String raw = stats.output == null ? "" : stats.output;
        if (raw.contains("FXDNSLOG_DISABLED")) {
            card("DNS 累计统计", "本机查询日志当前关闭。",
                    text("统计保持关闭；返回 DNS 设置后可由用户主动开启。不会为了显示计数而自动启用日志。", 12, 0xff617080, false));
            status.setText("配置摘要已读取；DNS 查询日志未启用，未生成统计。");
            return;
        }
        if (raw.contains("FXDNSLOG_EMPTY")) {
            card("DNS 累计统计", "当前保留日志暂无有效查询记录。",
                    text("日志开启后，统计会按本机当前保留的记录累计；最长保留期由 AdGuard Home 设置为 30 天。", 12, 0xff617080, false));
            status.setText("配置摘要已读取；本机暂无 DNS 累计记录。");
            return;
        }
        long queries = metric(raw, "queries");
        long blocked = metric(raw, "blocked");
        long unblocked = metric(raw, "unblocked");
        if (!raw.contains("FXYULONGDNSSTATS1") || queries < 0 || blocked < 0
                || unblocked < 0 || blocked > queries || unblocked != queries - blocked) {
            card("DNS 累计统计", "统计格式无效或数据不一致。",
                    text("为避免展示错误计数，本次统计没有被采纳。", 12, 0xff9b2c2c, false));
            status.setText("配置摘要已读取；DNS 累计统计格式校验失败。");
            return;
        }
        String metrics = "当前保留日志内 DNS 查询： " + queries + " 条"
                + "\n其中拦截： " + blocked + " 条"
                + "\n未拦截： " + unblocked + " 条";
        card("DNS 累计统计",
                "基于本机 AdGuard Home 当前保留日志流式汇总，最长保留期 30 天。统计接口只返回数字，不返回域名、客户端 IP 或原始查询记录；不代表逐应用查询次数。",
                text(metrics, 13, 0xff334155, false));
        status.setText("统计已更新；范围为当前本机保留日志，日志默认关闭，只有用户主动启用期间才累计。");
    }

    private String safe(String value) {
        return value == null || value.trim().isEmpty() ? "Root 后端没有返回错误详情。" : value.trim();
    }
    @Override protected void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
