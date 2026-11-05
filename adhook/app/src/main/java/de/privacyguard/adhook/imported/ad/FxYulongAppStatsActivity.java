package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.TrafficStats;
import android.os.Bundle;
import android.text.TextWatcher;
import android.text.Editable;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicInteger;

/** Per-application cumulative UID traffic counters, independent of VPN and DNS. */
public final class FxYulongAppStatsActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int APP_PAGE_SIZE = 40;
    private static final String STATE_APP_PAGE = "fx_yulong_app_stats_page";
    private static final String STATE_QUERY = "fx_yulong_app_stats_query";
    private static final String STATE_SCROLL_Y = "fx_yulong_app_stats_scroll_y";
    private final List<Row> data = new ArrayList<>();
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-yulong-app-stats"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private final AtomicInteger refreshGeneration = new AtomicInteger();
    private Future<?> refreshTask;
    private volatile boolean destroying;
    private LinearLayout rows;
    private EditText search;
    private TextView summary;
    private ScrollView scroll;
    private int appPage = 1;
    private int pendingScrollY;
    private boolean pendingScrollRestore;
    private int scrollRestoreGeneration;

    private static final class Row {
        final String pkg, label;
        final int uid;
        final long rx, tx;
        Row(String p, String l, int u, long r, long t) { pkg=p; label=l; uid=u; rx=r; tx=t; }
        long total() {
            if (rx < 0 || tx < 0) return -1;
            return tx > Long.MAX_VALUE - rx ? Long.MAX_VALUE : rx + tx;
        }
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private static String bytes(long v) {
        if (v < 0) return "系统未提供";
        if (v < 1024) return v + " B";
        double n=v; String[] units={"B","KiB","MiB","GiB","TiB"}; int i=0;
        while (n>=1024 && i<units.length-1) { n/=1024; i++; }
        return String.format(Locale.ROOT,"%.2f %s",n,units[i]);
    }
    private void card(LinearLayout parent, String title, String detail, android.view.View... children) {
        LinearLayout p=new LinearLayout(this); p.setOrientation(LinearLayout.VERTICAL);
        p.setPadding(dp(14),dp(10),dp(14),dp(10)); p.setBackgroundColor(0xfff0f3f7);
        p.addView(text(title,16,0xff17212b,true)); p.addView(text(detail,12,0xff617080,false));
        for (android.view.View child:children) p.addView(child);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(5),dp(12),dp(5)); parent.addView(p,lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10),dp(6),dp(12),dp(6));
        header.addView(button("‹ 返回 Ad",this::finish));
        header.addView(text("Ad · 应用统计",18,0xff17212b,true),
                new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        scroll=new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body=new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0,dp(4),0,dp(18)); scroll.addView(body);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1)); setContentViewWithNativeTabs(root, 1);

        search=new EditText(this); search.setSingleLine(true); search.setHint("搜索应用名称或包名");
        if (state != null) {
            appPage = Math.max(1, state.getInt(STATE_APP_PAGE, 1));
            search.setText(state.getString(STATE_QUERY, ""));
            pendingScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
            pendingScrollRestore = true;
        }
        summary=text("正在读取 UID 网络计数…",13,0xff526170,false);
        card(body,"统计口径",
                "Android TrafficStats 按应用 UID 提供自本次开机以来的累计收发字节。这不是 DNS 查询数、拦截数或 VPN 独占流量；系统不支持的 UID 计数会明确标记。",
                search,button("刷新统计",this::refresh),summary);
        rows=new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL); body.addView(rows);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s,int st,int c,int a) {}
            @Override public void onTextChanged(CharSequence s,int st,int before,int count) {
                appPage = 1;
                scrollRestoreGeneration++;
                pendingScrollY = 0;
                pendingScrollRestore = false;
                if (scroll != null) scroll.scrollTo(0, 0);
                render();
            }
            @Override public void afterTextChanged(Editable e) {}
        });
        refresh();
    }

    private void refresh() {
        if (scroll != null && !pendingScrollRestore) {
            pendingScrollY = Math.max(0, scroll.getScrollY());
            pendingScrollRestore = true;
        }
        final int generation = refreshGeneration.incrementAndGet();
        if (refreshTask != null) refreshTask.cancel(true);
        summary.setText("正在后台读取 UID 流量计数…");
        final PackageManager packageManager = getApplicationContext().getPackageManager();
        final String ownPackage = getPackageName();
        try {
            refreshTask = worker.submit(() -> {
                List<Row> loaded = new ArrayList<>();
                UidTrafficTotals totals = new UidTrafficTotals();
                String failure = null;
                try {
                    for (ApplicationInfo app : packageManager.getInstalledApplications(0)) {
                        if (Thread.currentThread().isInterrupted()) return;
                        if (app.packageName == null || app.packageName.equals(ownPackage)) continue;
                        String label;
                        try { label = String.valueOf(packageManager.getApplicationLabel(app)); }
                        catch (RuntimeException ignored) { label = app.packageName; }
                        long rx;
                        long tx;
                        try {
                            rx = TrafficStats.getUidRxBytes(app.uid);
                            tx = TrafficStats.getUidTxBytes(app.uid);
                        } catch (RuntimeException unavailable) {
                            rx = -1L;
                            tx = -1L;
                        }
                        loaded.add(new Row(app.packageName, label, app.uid, rx, tx));
                        totals.add(app.uid, rx, tx);
                    }
                    loaded.sort(Comparator.comparingLong((Row row) ->
                            row.total() < 0 ? Long.MIN_VALUE : row.total()).reversed());
                } catch (RuntimeException error) {
                    failure = error.getClass().getSimpleName();
                }
                if (Thread.currentThread().isInterrupted()) return;
                final String failureMessage = failure;
                final List<Row> resultRows = loaded;
                final String resultSummary = "应用数：" + loaded.size()
                        + " · 唯一 UID：" + totals.getUidCount()
                        + " · 可用 UID：" + totals.getAvailableUidCount()
                        + " · 无计数 UID：" + totals.getUnavailableUidCount()
                        + "\n累计接收（按唯一 UID）：" + bytes(totals.getRxBytes())
                        + " · 累计发送：" + bytes(totals.getTxBytes());
                runOnUiThread(() -> {
                    if (destroying || isFinishing() || isDestroyed()
                            || generation != refreshGeneration.get()) return;
                    if (failureMessage != null) {
                        summary.setText("读取失败：" + failureMessage);
                        return;
                    }
                    data.clear();
                    data.addAll(resultRows);
                    summary.setText(resultSummary);
                    render();
                    restoreScrollIfNeeded();
                });
            });
        } catch (RejectedExecutionException rejected) {
            if (!destroying && !isFinishing() && !isDestroyed()) {
                summary.setText("后台统计队列繁忙，本次刷新未提交；当前统计结果保持不变，请稍后重试。");
            }
        }
    }

    private void restoreScrollIfNeeded() {
        if (!pendingScrollRestore || scroll == null) return;
        final int restoreY = pendingScrollY;
        final int generation = ++scrollRestoreGeneration;
        scroll.post(() -> {
            if (destroying || isFinishing() || isDestroyed()
                    || generation != scrollRestoreGeneration
                    || !pendingScrollRestore || scroll == null) return;
            scroll.scrollTo(0, restoreY);
            pendingScrollRestore = false;
        });
    }

    private void render() {
        if (rows==null) return;
        rows.removeAllViews();
        String q=search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched=0;
        int shown=0;
        int limit=Math.max(1,appPage)*APP_PAGE_SIZE;
        for (Row row:data) {
            if (!q.isEmpty() && !row.pkg.toLowerCase(Locale.ROOT).contains(q)
                    && !row.label.toLowerCase(Locale.ROOT).contains(q)) continue;
            matched++;
            if (shown>=limit) continue;
            LinearLayout item=new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL);
            item.setPadding(dp(12),dp(7),dp(12),dp(7)); item.setBackgroundColor(0xffffffff);
            item.addView(text(row.label,14,0xff17212b,true));
            item.addView(text(row.pkg+" · UID "+row.uid,10,0xff718091,false));
            item.addView(text("接收："+bytes(row.rx)+" · 发送："+bytes(row.tx),12,0xff526170,false));
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
            lp.setMargins(dp(10),dp(2),dp(10),dp(2)); rows.addView(item,lp); shown++;
        }
        if (shown==0) {
            rows.addView(text("没有匹配的应用。",13,0xff718091,false));
        } else if (matched>shown) {
            rows.addView(button("加载更多（剩余 "+(matched-shown)+" 个）",() -> {
                pendingScrollY = scroll == null ? 0 : Math.max(0, scroll.getScrollY());
                pendingScrollRestore = true;
                appPage++;
                render();
                restoreScrollIfNeeded();
            }));
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putInt(STATE_APP_PAGE, Math.max(1, appPage));
        if (search != null) outState.putString(STATE_QUERY, search.getText().toString());
        if (scroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, scroll.getScrollY()));
        super.onSaveInstanceState(outState);
    }
    @Override protected void onDestroy() {
        destroying = true;
        scrollRestoreGeneration++;
        refreshGeneration.incrementAndGet();
        if (refreshTask != null) refreshTask.cancel(true);
        worker.shutdownNow();
        super.onDestroy();
    }

}
