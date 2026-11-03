package de.privacyguard.adhook.imported.shield;

import android.app.Activity;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Original Yulong Shield virus database settings page, using its migrated native database engine. */
public final class FxYulongVirusDatabaseActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private LinearLayout body;
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
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL); header.setPadding(dp(12),dp(8),dp(12),dp(8));
        header.addView(action("‹ 返回",this::finish));
        header.addView(text("病毒库管理",19,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(true);
        body=new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL); body.setPadding(0,dp(4),0,dp(20));
        scroll.addView(body); root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1)); setContentView(root);

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
    }

    private void updateStatus() {
        FxYulongVirusDb.Data data=FxYulongVirusDb.get(this);
        long time=FxYulongVirusDb.getCachedFetchTime();
        String date=time>0?DateFormat.getDateTimeInstance().format(new Date(time)):"尚无缓存时间";
        summary.setText("缓存条目："+data.total()
                +"\n确定风险包名："+data.certainPkgs.size()
                +"\n确定风险名称："+data.certainNames.size()
                +"\n可能风险包名："+data.suspectPkgs.size()
                +"\n可能风险名称："+data.suspectNames.size()
                +"\n风险关键字："+data.keys.size()
                +"\n服务器最近可达："+(FxYulongVirusDb.isServerReachable()?"是":"未知/否")
                +"\n最近缓存时间："+date
                +(FxYulongVirusDb.getLastError().isEmpty()?"":"\n最近错误："+FxYulongVirusDb.getLastError()));
        listRows.removeAllViews();
        List<FxYulongVirusDb.ListStatus> items=FxYulongVirusDb.getListStatus();
        for(FxYulongVirusDb.ListStatus item:items) {
            String updated=item.updatedAt>0?DateFormat.getDateTimeInstance().format(new Date(item.updatedAt)):"尚未成功";
            String detail=item.url+(item.mergeUrl==null?"":"\n合并源："+item.mergeUrl);
            String state=(item.ok?"最近成功 · ":"尚未成功 · ")+item.count+" 条 · "+updated;
            LinearLayout row=new LinearLayout(this); row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(8),dp(5),dp(8),dp(5));
            row.addView(text(item.label,14,0xff263746,true));
            row.addView(text(state,12,0xff607080,false));
            row.addView(text(detail,11,0xff778493,false));
            listRows.addView(row,new LinearLayout.LayoutParams(-1,-2));
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
        worker.execute(() -> {
            try {
                FxYulongVirusContentDb.refreshNow(getApplicationContext());
                runOnUiThread(() -> {
                    contentRefresh.setEnabled(true);
                    updateContentStatus();
                    Toast.makeText(this,
                            FxYulongVirusContentDb.isContentDatabaseReady(this)
                                ? "APK 内容特征库同步完成" : "内容特征库未就绪，旧缓存已保留",
                            Toast.LENGTH_LONG).show();
                });
            } catch(Throwable error) {
                runOnUiThread(() -> {
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
        worker.execute(() -> {
            try {
                FxYulongVirusDb.refreshNow(getApplicationContext());
                runOnUiThread(() -> {
                    refresh.setEnabled(true); updateStatus();
                    Toast.makeText(this,FxYulongVirusDb.isServerReachable()?"病毒库同步完成":"同步不完整，原有缓存已保留",Toast.LENGTH_LONG).show();
                });
            } catch(Throwable error) {
                runOnUiThread(() -> {
                    refresh.setEnabled(true); updateStatus();
                    Toast.makeText(this,"同步失败："+error.getClass().getSimpleName(),Toast.LENGTH_LONG).show();
                });
            }
        });
    }

    @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
