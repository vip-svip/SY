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
    private Button batchCleanup;
    private final java.util.LinkedHashMap<String, FxYulongScanEngine.Finding> selectedForCleanup = new java.util.LinkedHashMap<>();
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
        batchCleanup = action("批量清理已选择风险应用（0）", this::openBatchCleanup);
        batchCleanup.setEnabled(false);
        card("批量清理", text("逐项打开 Android 系统卸载确认。FX 不会自动点击确认，也不会在后台静默卸载、强停或冻结应用。",12,0xff617080,false), batchCleanup);
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
            selectedForCleanup.clear(); updateBatchCleanup();
            status.setText(result.message+" 扫描 "+result.scanned+" 个应用；名单 "+result.databaseEntries
                    +" 条；确定风险 "+result.certainCount+"；可能风险 "+result.suspectCount
                    +"。\n内容特征扫描："+(result.contentScanEnabled
                    ? (result.contentDatabaseReady ? ("已检查 "+result.contentScanned+" 个 APK"
                        +(result.contentReadFailures > 0 ? "；读取失败 "+result.contentReadFailures+" 个" : "")
                        +(result.contentTruncated?"；达到预算上限，扫描未完成":""))
                        : "已启用但内容特征库未就绪")
                    : "未启用（默认关闭）"));
            if(result.findings.isEmpty()){
                resultRows.addView(text(
                        FxYulongScanCompleteness.noFindingMessage(result.scanComplete),
                        13, result.scanComplete ? 0xff607080 : 0xffa32620, !result.scanComplete));
                return;
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
        android.widget.CheckBox check = new android.widget.CheckBox(this);
        check.setText("加入批量清理清单");
        check.setOnCheckedChangeListener((button, checked) -> {
            if (checked) selectedForCleanup.put(finding.packageName, finding);
            else selectedForCleanup.remove(finding.packageName);
            updateBatchCleanup();
        });
        item.addView(check);
        item.addView(action("打开风险警告页", () -> {
            Intent warning = new Intent(this, FxYulongWarningActivity.class);
            warning.putExtra("package_name", finding.packageName);
            warning.putExtra("app_label", finding.label);
            warning.putExtra("reason", finding.reason);
            warning.putExtra("severity", finding.severity.name());
            startActivity(warning);
        }));
        item.addView(action("核实后打开系统卸载确认",()->confirmUninstall(finding)));
    }

    private void updateBatchCleanup() {
        if (batchCleanup == null) return;
        batchCleanup.setText("批量清理已选择风险应用（" + selectedForCleanup.size() + "）");
        batchCleanup.setEnabled(!running.get() && !selectedForCleanup.isEmpty());
    }

    private void openBatchCleanup() {
        if (selectedForCleanup.isEmpty()) {
            Toast.makeText(this, "请先勾选需要处理的风险应用。", Toast.LENGTH_SHORT).show();
            return;
        }
        java.util.ArrayList<String> packages = new java.util.ArrayList<>();
        java.util.ArrayList<String> labels = new java.util.ArrayList<>();
        java.util.ArrayList<String> reasons = new java.util.ArrayList<>();
        for (FxYulongScanEngine.Finding finding : selectedForCleanup.values()) {
            packages.add(finding.packageName);
            labels.add(finding.label);
            reasons.add(finding.reason);
        }
        Intent intent = new Intent(this, FxYulongBatchCleanupActivity.class);
        intent.putStringArrayListExtra("packages", packages);
        intent.putStringArrayListExtra("labels", labels);
        intent.putStringArrayListExtra("reasons", reasons);
        startActivity(intent);
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
