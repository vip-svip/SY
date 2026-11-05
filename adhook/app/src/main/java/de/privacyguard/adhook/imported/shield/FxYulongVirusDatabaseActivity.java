package de.privacyguard.adhook.imported.shield;

import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.text.DateFormat;
import java.util.Date;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Original Yulong Shield virus database settings page, using its migrated native database engine. */
public final class FxYulongVirusDatabaseActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> { Thread t = new Thread(r, "fx-yulong-virus-db"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());
    private volatile boolean destroyed;

    private void postUi(Runnable update) {
        runOnUiThread(() -> {
            if (destroyed || isFinishing() || isDestroyed()) return;
            update.run();
        });
    }

    private void submitWorker(Button button, TextView target, String busyMessage, Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            button.setEnabled(true);
            if (!destroyed && !isFinishing() && !isDestroyed()) {
                target.setText(busyMessage);
                Toast.makeText(this, "后台同步队列繁忙，本次任务未提交。", Toast.LENGTH_LONG).show();
            }
        }
    }
    private static final String STATE_SCROLL_Y = "fx_shield_virus_db_scroll_y";
    private LinearLayout body;
    private ScrollView databaseScroll;
    private int restoredScrollY;
    private TextView summary;
    private LinearLayout listRows;
    private Button refresh;
    private TextView contentSummary;
    private Button contentRefresh;

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5)); return t;
    }
    private Button action(String s, Runnable r) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(s); b.setOnClickListener(v -> r.run()); return b;
    }
    private void card(String title, View... children) {
        LinearLayout panel = new LinearLayout(this); panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14),dp(10),dp(14),dp(10)); panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title,16,0xff17212b,true));
        for(View child:children) panel.addView(child);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(5),dp(12),dp(5)); body.addView(panel,lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        restoredScrollY = state == null ? 0 : Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL); header.setPadding(dp(12),dp(8),dp(12),dp(8));
        header.addView(action("‹ 返回隐私",this::finish));
        header.addView(text("隐私 · 病毒库管理",19,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this); databaseScroll=scroll; scroll.setFillViewport(true);
        body=new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL); body.setPadding(0,dp(4),0,dp(20));
        scroll.addView(body); root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1)); setContentViewWithNativeTabs(root, 2);

        FxYulongVirusDb.get(this);
        summary=text("",13,0xff455565,false);
        refresh=action("立即同步病毒库",this::refreshDatabase);
        card("同步状态",summary,refresh);
        listRows=new LinearLayout(this); listRows.setOrientation(LinearLayout.VERTICAL);
        card("原版远程名单状态",listRows);
        contentSummary = text("",13,0xff455565,false);
        contentRefresh = action("同步 APK 内容特征库", this::refreshContentDatabase);
        card("高级 APK 内容特征库（原版默认不用于手动扫描）", contentSummary, contentRefresh);
        updateStatus();
        updateContentStatus();
        if (restoredScrollY > 0) {
            final int restoreY = restoredScrollY;
            scroll.post(() -> {
                if (!destroyed && !isFinishing() && !isDestroyed()
                        && databaseScroll == scroll && scroll.getParent() != null)
                    scroll.scrollTo(0, restoreY);
            });
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putInt(STATE_SCROLL_Y, databaseScroll == null
                ? Math.max(0, restoredScrollY) : Math.max(0, databaseScroll.getScrollY()));
    }

    private void updateStatus() {
        FxYulongVirusDb.Data data = FxYulongVirusDb.get(this);
        long attemptTime = FxYulongVirusDb.getLastAttempt();
        long successTime = FxYulongVirusDb.getLastSuccess();
        String attemptDate = attemptTime > 0
                ? DateFormat.getDateTimeInstance().format(new Date(attemptTime)) : "尚未尝试";
        String successDate = successTime > 0
                ? DateFormat.getDateTimeInstance().format(new Date(successTime)) : "尚无成功同步记录";
        summary.setText("本地名单缓存：" + (data.total() > 0 ? "可用（至少部分名单）" : "尚无有效名单缓存")
                + "\n缓存条目：" + data.total()
                + "\n确定风险包名：" + data.certainPkgs.size()
                + "\n确定风险名称：" + data.certainNames.size()
                + "\n可能风险包名：" + data.suspectPkgs.size()
                + "\n可能风险名称：" + data.suspectNames.size()
                + "\n风险关键字：" + data.keys.size()
                + "\n最近同步尝试：" + attemptDate
                + "\n最近成功更新：" + successDate
                + "\n最近一次尝试可达：" + (attemptTime <= 0 || !FxYulongVirusDb.isServerReachabilityKnown()
                        ? "未知" : (FxYulongVirusDb.isServerReachable() ? "是" : "否"))
                + (FxYulongVirusDb.getLastError().isEmpty() ? "" : "\n最近错误：" + FxYulongVirusDb.getLastError()));
        listRows.removeAllViews();
        List<FxYulongVirusDb.ListStatus> items = FxYulongVirusDb.getListStatus();
        for (FxYulongVirusDb.ListStatus item : items) {
            String updated = item.updatedAt > 0
                    ? DateFormat.getDateTimeInstance().format(new Date(item.updatedAt)) : "更新时间未知";
            String attempted = item.lastAttemptAt > 0
                    ? DateFormat.getDateTimeInstance().format(new Date(item.lastAttemptAt)) : "";
            String detail = item.url + (item.mergeUrl == null ? "" : "\n合并源：" + item.mergeUrl);
            String state = item.statusLabel() + " · " + item.count + " 条 · 最近成功更新：" + updated
                    + (attempted.isEmpty() ? "" : " · 最近尝试：" + attempted);
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(8), dp(5), dp(8), dp(5));
            row.addView(text(item.label, 14, 0xff263746, true));
            row.addView(text(state, 12, 0xff607080, false));
            row.addView(text(detail, 11, 0xff778493, false));
            listRows.addView(row, new LinearLayout.LayoutParams(-1, -2));
        }
    }

    private void updateContentStatus() {
        try {
            JSONObject state = new JSONObject(FxYulongVirusContentDb.getContentDatabaseStatusJson(this));
            contentSummary.setText("状态："+(state.optBoolean("ready")?"已就绪":"未就绪")
                    +"\n版本："+state.optString("version","")
                    +"\n证书："+state.optInt("certs")
                    +" · 包名："+state.optInt("packages")
                    +" · APK 哈希："+state.optInt("apkSamples")
                    +"\nDEX："+state.optInt("dexSamples")
                    +" · 资产："+state.optInt("assetSamples")
                    +" · 高特异 token："+state.optInt("highTokens")
                    +" · 弱 token："+state.optInt("lowTokens")
                    +"\n结构特征："+state.optInt("structures")
                    +" · 规则："+state.optInt("rules")
                    +"\n最近成功："+(state.optLong("lastSuccess")>0
                        ? DateFormat.getDateTimeInstance().format(new Date(state.optLong("lastSuccess")))
                        : "尚未成功")
                    +(state.optString("lastError").isEmpty()?"":"\n错误："+state.optString("lastError")));
        } catch(Throwable error) {
            contentSummary.setText("读取内容特征库状态失败："+error.getClass().getSimpleName());
        }
    }

    private void refreshContentDatabase() {
        contentRefresh.setEnabled(false);
        contentSummary.setText("正在同步 virus-db.json 与 virus-db-rules.json…");
        submitWorker(contentRefresh, contentSummary,
                "后台任务繁忙：内容特征库同步未排队，请稍后重试。", () -> {
            try {
                long previousContentSuccess = FxYulongVirusContentDb.getLastSuccessAt();
                FxYulongVirusContentDb.refreshNow(getApplicationContext());
                final boolean contentReady =
                        FxYulongVirusContentDb.isContentDatabaseReady(getApplicationContext());
                // A still-ready old cache is not evidence that this sync succeeded.
                // Refresh (including HTTP 304) updates lastSuccessAt; only then launch
                // the post-update whole-device scan or report a successful sync.
                final boolean contentSyncSucceeded = contentReady
                        && FxYulongVirusContentDb.getLastSuccessAt() > previousContentSuccess;
                if (contentSyncSucceeded) {
                    FxYulongRiskScanDispatcher.onVirusDatabaseUpdated(getApplicationContext(),
                            getSharedPreferences("shield_prefs", MODE_PRIVATE)
                                    .getBoolean("automatic_content_scan_enabled", false));
                }
                postUi(() -> {
                    contentRefresh.setEnabled(true);
                    updateContentStatus();
                    String message = contentSyncSucceeded
                            ? "APK 内容特征库同步成功（含未变化的 304 响应）"
                            : contentReady
                                ? "本次同步未成功；旧版 APK 特征缓存仍可用"
                                : "内容特征库未就绪；本次同步未成功，旧缓存未被覆盖";
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show();
                });
            } catch(Throwable error) {
                postUi(() -> {
                    contentRefresh.setEnabled(true);
                    updateContentStatus();
                    Toast.makeText(this,"内容特征库同步失败："+error.getClass().getSimpleName(),
                            Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    private void refreshDatabase() {
        refresh.setEnabled(false);
        summary.setText("正在同步五类逻辑名单及其兼容旧名单…");
        submitWorker(refresh, summary,
                "后台任务繁忙：病毒库同步未排队，请稍后重试。", () -> {
            try {
                FxYulongVirusDb.refreshNow(getApplicationContext());
                // The DB adapter marks the current attempt reachable only when at
                // least one remote list/304 succeeded. Offline stale-cache retention
                // must not masquerade as a successful database-update trigger.
                List<FxYulongVirusDb.ListStatus> listResults = FxYulongVirusDb.getListStatus();
                int successfulLists = 0;
                for (FxYulongVirusDb.ListStatus item : listResults) if (item.ok) successfulLists++;
                final int successCount = successfulLists;
                final int totalCount = listResults.size();
                final boolean anyListSucceeded = successCount > 0;
                if (anyListSucceeded && FxYulongVirusDb.getLastSuccess() > 0L) {
                    FxYulongRiskScanDispatcher.onVirusDatabaseUpdated(getApplicationContext(),
                            getSharedPreferences("shield_prefs", MODE_PRIVATE)
                                    .getBoolean("automatic_content_scan_enabled", false));
                }
                postUi(() -> {
                    refresh.setEnabled(true); updateStatus();
                    String message = successCount == totalCount && totalCount > 0
                            ? "病毒库完整同步完成（" + successCount + "/" + totalCount + "）"
                            : successCount > 0
                                ? "病毒库部分同步（" + successCount + "/" + totalCount + "），失败名单保留旧缓存"
                                : "病毒库同步失败，原有缓存已保留";
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show();
                });
            } catch(Throwable error) {
                postUi(() -> {
                    refresh.setEnabled(true); updateStatus();
                    Toast.makeText(this,"同步失败："+error.getClass().getSimpleName(),Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    @Override protected void onDestroy(){destroyed=true;worker.shutdownNow();super.onDestroy();}
}
