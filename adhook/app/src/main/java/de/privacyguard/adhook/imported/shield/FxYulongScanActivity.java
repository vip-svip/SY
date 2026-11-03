package de.privacyguard.adhook.imported.shield;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Switch;
import android.widget.Toast;

import java.util.concurrent.atomic.AtomicBoolean;

/** Original Yulong Shield manual scan page; scan is read-only and removal is user-confirmed. */
public final class FxYulongScanActivity extends Activity {
    private LinearLayout body;
    private LinearLayout resultRows;
    private TextView status;
    private Button scan;
    private Switch contentScan;
    private final AtomicBoolean running = new AtomicBoolean(false);

    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color,boolean bold){
        TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);
        if(bold)t.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5));return t;
    }
    private Button action(String s,Runnable r){
        Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;
    }
    private void card(String title,View... controls){
        LinearLayout panel=new LinearLayout(this);panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14),dp(10),dp(14),dp(10));panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title,16,0xff17212b,true));for(View v:controls)panel.addView(v);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(5),dp(12),dp(5));body.addView(panel,lp);
    }

    @Override protected void onCreate(Bundle state){
        super.onCreate(state);
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(12),dp(8),dp(12),dp(8));
        header.addView(action("‹ 返回",this::finish));
        header.addView(text("已安装应用扫描",19,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);
        body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);body.setPadding(0,dp(4),0,dp(20));
        scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
        status=text("扫描只读取应用包名和名称，不会自动停用、冻结或卸载应用。",13,0xff5c6877,false);
        contentScan = new Switch(this);
        contentScan.setText("启用 APK 内容特征扫描（第二阶段）");
        contentScan.setTextSize(14);
        contentScan.setChecked(getSharedPreferences("fx_yulong_shield_prefs", MODE_PRIVATE)
                .getBoolean("content_scan_enabled", false));
        contentScan.setOnCheckedChangeListener((button, enabled) ->
                getSharedPreferences("fx_yulong_shield_prefs", MODE_PRIVATE).edit()
                        .putBoolean("content_scan_enabled", enabled).apply());
        scan=action("开始扫描",this::startScan);
        card("扫描状态",status,contentScan,scan);
        body.addView(text("风险结果",16,0xff17212b,true));
        resultRows=new LinearLayout(this);
        resultRows.setOrientation(LinearLayout.VERTICAL);
        resultRows.addView(text("尚未扫描。请先在“病毒库管理”中同步名单。",13,0xff607080,false));
        body.addView(resultRows);
    }

    private void startScan(){
        if(!running.compareAndSet(false,true))return;
        scan.setEnabled(false);scan.setText("扫描中…");status.setText("正在读取已安装应用清单并匹配本地名单…");
        boolean deepScan = contentScan.isChecked();
        FxYulongScanEngine.scan(this, deepScan, result->runOnUiThread(()->{
            running.set(false);scan.setEnabled(true);scan.setText("重新扫描");
            resultRows.removeAllViews();
            status.setText(result.message+" 扫描 "+result.scanned+" 个应用；名单 "+result.databaseEntries
                    +" 条；确定风险 "+result.certainCount+"；可能风险 "+result.suspectCount
                    +"。\n内容特征扫描："+(result.contentScanEnabled
                    ? (result.contentDatabaseReady ? ("已检查 "+result.contentScanned+" 个 APK"
                        +(result.contentTruncated?"（达到 8 秒预算，内容扫描未完成）":""))
                        : "已启用但内容特征库未就绪")
                    : "未启用（默认关闭）"));
            if(result.findings.isEmpty()){
                card("扫描结果",text("没有命中当前名单。这不代表设备绝对安全。",13,0xff607080,false));return;
            }
            for(FxYulongScanEngine.Finding f:result.findings)addFinding(f);
        }));
    }

    private void addFinding(FxYulongScanEngine.Finding finding){
        LinearLayout item=new LinearLayout(this);item.setOrientation(LinearLayout.VERTICAL);
        item.setPadding(dp(12),dp(8),dp(12),dp(8));
        item.setBackgroundColor(finding.severity==FxYulongScanEngine.Severity.CERTAIN?0xffffeeee:0xfffff5e5);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(3),dp(12),dp(4));resultRows.addView(item,lp);
        item.addView(text((finding.severity==FxYulongScanEngine.Severity.CERTAIN?"确定风险 · ":"可能风险 · ")+finding.label,
                14,finding.severity==FxYulongScanEngine.Severity.CERTAIN?0xffa32620:0xff8a5b12,true));
        item.addView(text(finding.packageName+"\n"+finding.reason,12,0xff617080,false));
        item.addView(action("核实后打开系统卸载确认",()->confirmUninstall(finding)));
    }

    private void confirmUninstall(FxYulongScanEngine.Finding finding){
        new AlertDialog.Builder(this).setTitle("请先核实扫描结果")
                .setMessage("病毒库命中可能存在误报：\n\n"+finding.label+"\n"+finding.packageName
                        +"\n\n只有你确认该应用需要移除时，才会继续打开 Android 系统卸载确认界面。FX 不会在后台静默卸载。")
                .setNegativeButton("返回",null)
                .setPositiveButton("打开系统确认",(d,w)->{
                    try{startActivity(new Intent(Intent.ACTION_DELETE,Uri.parse("package:"+finding.packageName)));}
                    catch(Throwable error){Toast.makeText(this,"无法打开系统卸载确认："+error.getClass().getSimpleName(),Toast.LENGTH_LONG).show();}
                }).show();
    }
}
