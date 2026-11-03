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

/** Per-application cumulative UID traffic counters, independent of VPN and DNS. */
public final class FxYulongAppStatsActivity extends Activity {
    private final List<Row> data = new ArrayList<>();
    private LinearLayout rows;
    private EditText search;
    private TextView summary;

    private static final class Row {
        final String pkg, label;
        final int uid;
        final long rx, tx;
        Row(String p, String l, int u, long r, long t) { pkg=p; label=l; uid=u; rx=r; tx=t; }
        long total() { return rx < 0 || tx < 0 ? -1 : rx + tx; }
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
    private String bytes(long v) {
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
        header.addView(button("‹ 返回",this::finish));
        header.addView(text("游龙广告插件 · 应用统计",18,0xff17212b,true),
                new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body=new LinearLayout(this); body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0,dp(4),0,dp(18)); scroll.addView(body);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1)); setContentView(root);

        search=new EditText(this); search.setSingleLine(true); search.setHint("搜索应用名称或包名");
        summary=text("正在读取 UID 网络计数…",13,0xff526170,false);
        card(body,"统计口径",
                "Android TrafficStats 按应用 UID 提供自本次开机以来的累计收发字节。这不是 DNS 查询数、拦截数或 VPN 独占流量；系统不支持的 UID 计数会明确标记。",
                search,button("刷新统计",this::refresh),summary);
        rows=new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL); body.addView(rows);
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s,int st,int c,int a) {}
            @Override public void onTextChanged(CharSequence s,int st,int before,int count) { render(); }
            @Override public void afterTextChanged(Editable e) {}
        });
        refresh();
    }

    private void refresh() {
        data.clear();
        PackageManager pm=getPackageManager();
        long sumRx=0,sumTx=0; int unknown=0;
        try {
            for (ApplicationInfo app:pm.getInstalledApplications(0)) {
                if (app.packageName==null || app.packageName.equals(getPackageName())) continue;
                String label;
                try { label=String.valueOf(pm.getApplicationLabel(app)); }
                catch (Throwable ignored) { label=app.packageName; }
                long rx=TrafficStats.getUidRxBytes(app.uid);
                long tx=TrafficStats.getUidTxBytes(app.uid);
                data.add(new Row(app.packageName,label,app.uid,rx,tx));
                if (rx<0 || tx<0) unknown++;
                else { sumRx+=rx; sumTx+=tx; }
            }
            data.sort(Comparator.comparingLong((Row r)->r.total()<0?Long.MIN_VALUE:r.total()).reversed());
            summary.setText("应用数："+data.size()+" · 可用 UID："+(data.size()-unknown)
                    +" · 无计数："+unknown+"\\n累计接收："+bytes(sumRx)+" · 累计发送："+bytes(sumTx));
        } catch (Throwable error) {
            summary.setText("读取失败："+error.getClass().getSimpleName());
        }
        render();
    }

    private void render() {
        if (rows==null) return;
        rows.removeAllViews();
        String q=search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int shown=0;
        for (Row row:data) {
            if (!q.isEmpty() && !row.pkg.toLowerCase(Locale.ROOT).contains(q)
                    && !row.label.toLowerCase(Locale.ROOT).contains(q)) continue;
            LinearLayout item=new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL);
            item.setPadding(dp(12),dp(7),dp(12),dp(7)); item.setBackgroundColor(0xffffffff);
            item.addView(text(row.label,14,0xff17212b,true));
            item.addView(text(row.pkg+" · UID "+row.uid,10,0xff718091,false));
            item.addView(text("接收："+bytes(row.rx)+" · 发送："+bytes(row.tx),12,0xff526170,false));
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
            lp.setMargins(dp(10),dp(2),dp(10),dp(2)); rows.addView(item,lp); shown++;
        }
        if (shown==0) rows.addView(text("没有匹配的应用。",13,0xff718091,false));
    }
}
