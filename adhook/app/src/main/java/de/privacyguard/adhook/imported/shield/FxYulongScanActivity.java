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
public final class FxYulongScanActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int REQUEST_BATCH_CLEANUP = 0x59b2;
    private static final int MAX_SAVED_FINDINGS = 128;
    private static final int MAX_BATCH_SELECTION = 100;
    private static final String STATE_SCAN_SCROLL_Y = "fx_shield_scan_scroll_y";
    private static final String STATE_SCAN_RUNNING = "fx_shield_scan_running";
    private static final String STATE_SCAN_HAS_RESULT = "fx_shield_scan_has_result";
    private static final String STATE_SCAN_STATUS = "fx_shield_scan_status";
    private static final String STATE_SCAN_COMPLETE = "fx_shield_scan_complete";
    private static final String STATE_SCAN_FINDING_COUNT = "fx_shield_scan_finding_count";
    private static final String STATE_SCAN_REQUIRES_RESCAN = "fx_shield_scan_requires_rescan";
    private static final String STATE_FINDING_PACKAGES = "fx_shield_finding_packages";
    private static final String STATE_FINDING_LABELS = "fx_shield_finding_labels";
    private static final String STATE_FINDING_SEVERITIES = "fx_shield_finding_severities";
    private static final String STATE_FINDING_REASONS = "fx_shield_finding_reasons";
    private static final String STATE_FINDING_SOURCES = "fx_shield_finding_sources";
    private static final String STATE_FINDING_MATCHES = "fx_shield_finding_matches";
    private static final String STATE_SELECTED_PACKAGES = "fx_shield_selected_packages";

    private LinearLayout body;
    private LinearLayout resultRows;
    private ScrollView scanScroll;
    private int restoredScanScrollY;
    private TextView status;
    private Button scan;
    private Switch contentScan;
    private Button batchCleanup;
    private final java.util.LinkedHashMap<String, FxYulongScanEngine.Finding> selectedForCleanup = new java.util.LinkedHashMap<>();
    private final java.util.ArrayList<FxYulongScanEngine.Finding> lastFindings = new java.util.ArrayList<>();
    private final AtomicBoolean running = new AtomicBoolean(false);
    private volatile boolean destroyed;
    private int scanGeneration;
    private String lastScanStatus = "";
    private boolean hasScanResult;
    private boolean lastScanComplete;
    private boolean restoreRequiresRescan;


    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color,boolean bold){
        TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);
        if(bold)t.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5));return t;
    }
    private Button action(String s,Runnable r){
        Button b=new Button(this);b.setTag("fx-action-row");b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;
    }
    private void card(String title,View... controls){
        LinearLayout panel=new LinearLayout(this);panel.setTag("fx-card");panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14),dp(10),dp(14),dp(10));panel.setBackgroundColor(0xfff0f3f7);
        TextView heading=text(title,16,0xff17212b,true);heading.setTag("fx-card-title");panel.addView(heading);for(View v:controls)panel.addView(v);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(5),dp(12),dp(5));body.addView(panel,lp);
    }

    @Override protected void onCreate(Bundle state){
        super.onCreate(state);
        restoredScanScrollY = state == null ? 0 : Math.max(0, state.getInt(STATE_SCAN_SCROLL_Y, 0));
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(12),dp(8),dp(12),dp(8));
        header.addView(action("‹ 返回隐私",this::finish));
        header.addView(text("隐私 · 已安装应用扫描",19,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this);scanScroll=scroll;scroll.setFillViewport(true);
        body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);body.setPadding(0,dp(4),0,dp(20));
        scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));setContentViewWithNativeTabs(root, 2);
        status=text("扫描只读取应用包名和名称，不会自动停用、冻结或卸载应用。",13,0xff5c6877,false);
        contentScan = new Switch(this);
        contentScan.setTag("fx-switch-row");
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
        TextView resultHeading = text("风险结果",16,0xff17212b,true);
        resultHeading.setTag("fx-section:风险结果");
        body.addView(resultHeading);
        resultRows=new LinearLayout(this);
        resultRows.setOrientation(LinearLayout.VERTICAL);
        resultRows.addView(text("尚未扫描。请先在“病毒库管理”中同步名单。",13,0xff607080,false));
        body.addView(resultRows);
        if (state != null) restoreScanState(state);
        if (restoredScanScrollY > 0) {
            final int restoreY = restoredScanScrollY;
            scroll.post(() -> {
                if (!isFinishing() && !isDestroyed() && scanScroll == scroll && scroll.getParent() != null)
                    scroll.scrollTo(0, restoreY);
            });
        }
    }

    private void restoreScanState(Bundle state) {
        if (state.getBoolean(STATE_SCAN_RUNNING, false)) {
            status.setText("上次扫描在页面重建时尚未返回结果；为避免展示过期状态，请重新扫描。");
            scan.setText("重新扫描");
            resultRows.removeAllViews();
            selectedForCleanup.clear();
            lastFindings.clear();
            hasScanResult = false;
            restoreRequiresRescan = true;
            updateBatchCleanup();
            return;
        }
        if (!state.getBoolean(STATE_SCAN_HAS_RESULT, false)) return;

        hasScanResult = true;
        lastScanComplete = state.getBoolean(STATE_SCAN_COMPLETE, false);
        lastScanStatus = boundedStateText(state.getString(STATE_SCAN_STATUS, ""));
        status.setText(lastScanStatus.isEmpty() ? "已恢复上次扫描状态。" : lastScanStatus);
        status.setTextColor(lastScanComplete ? 0xff5c6877 : 0xffa32620);
        resultRows.removeAllViews();
        selectedForCleanup.clear();
        lastFindings.clear();

        int findingCount = state.getInt(STATE_SCAN_FINDING_COUNT, 0);
        if (state.getBoolean(STATE_SCAN_REQUIRES_RESCAN, false)
                || findingCount > MAX_SAVED_FINDINGS) {
            restoreRequiresRescan = true;
            status.setText(status.getText() + "\n上次命中 " + findingCount
                    + " 项，超过页面状态恢复上限；为防止丢失部分风险项，请重新扫描后再进行批量处理。");
            resultRows.addView(text("上次扫描结果过多，未恢复不完整列表。请重新扫描以查看全部风险项。",
                    13, 0xffa32620, true));
            updateBatchCleanup();
            return;
        }

        java.util.ArrayList<String> packages = state.getStringArrayList(STATE_FINDING_PACKAGES);
        java.util.ArrayList<String> labels = state.getStringArrayList(STATE_FINDING_LABELS);
        java.util.ArrayList<String> severities = state.getStringArrayList(STATE_FINDING_SEVERITIES);
        java.util.ArrayList<String> reasons = state.getStringArrayList(STATE_FINDING_REASONS);
        java.util.ArrayList<String> sources = state.getStringArrayList(STATE_FINDING_SOURCES);
        java.util.ArrayList<String> matches = state.getStringArrayList(STATE_FINDING_MATCHES);
        java.util.ArrayList<String> selected = state.getStringArrayList(STATE_SELECTED_PACKAGES);
        if (sources == null) sources = new java.util.ArrayList<>();
        if (matches == null) matches = new java.util.ArrayList<>();
        java.util.HashSet<String> selectedPackages = new java.util.HashSet<>();
        if (selected != null && selected.size() <= MAX_BATCH_SELECTION) {
            selectedPackages.addAll(selected);
        }

        if (packages == null || labels == null || severities == null || reasons == null
                || packages.size() != findingCount || labels.size() != findingCount
                || severities.size() != findingCount || reasons.size() != findingCount
                || (!sources.isEmpty() && sources.size() != findingCount)
                || (!matches.isEmpty() && matches.size() != findingCount)
                || packages.size() > MAX_SAVED_FINDINGS) {
            restoreRequiresRescan = true;
            status.setText(status.getText() + "\n上次扫描状态数据不完整，请重新扫描；旧结果不会用于批量处理。");
            resultRows.addView(text("扫描结果状态不完整，已禁用批量处理。请重新扫描。",
                    13, 0xffa32620, true));
            updateBatchCleanup();
            return;
        }

        for (int i = 0; i < packages.size(); i++) {
            String pkg = packages.get(i);
            if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
                restoreRequiresRescan = true;
                continue;
            }
            FxYulongScanEngine.Severity severity;
            try {
                severity = FxYulongScanEngine.Severity.valueOf(severities.get(i));
            } catch (RuntimeException invalid) {
                restoreRequiresRescan = true;
                continue;
            }
            String source = i < sources.size() ? boundedStateText(sources.get(i)) : "";
            String matched = i < matches.size() ? boundedStateText(matches.get(i)) : "";
            FxYulongScanEngine.Finding finding = new FxYulongScanEngine.Finding(
                    pkg, boundedStateText(labels.get(i)), severity, boundedStateText(reasons.get(i)),
                    source, matched);
            lastFindings.add(finding);
            addFinding(finding, selectedPackages.contains(pkg));
        }
        if (lastFindings.isEmpty()) {
            resultRows.addView(text(FxYulongScanCompleteness.noFindingMessage(lastScanComplete),
                    13, lastScanComplete ? 0xff607080 : 0xffa32620, !lastScanComplete));
        }
        if (restoreRequiresRescan) {
            status.setText(status.getText() + "\n部分状态无法恢复；请重新扫描后再执行批量处理。");
        }
        updateBatchCleanup();
    }

    private String boundedStateText(String value) {
        if (value == null) return "";
        String text = value.trim();
        return text.length() > 1024 ? text.substring(0, 1024) : text;
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putBoolean(STATE_SCAN_RUNNING, running.get());
        outState.putInt(STATE_SCAN_SCROLL_Y,
                scanScroll == null ? Math.max(0, restoredScanScrollY) : Math.max(0, scanScroll.getScrollY()));
        outState.putBoolean(STATE_SCAN_HAS_RESULT, hasScanResult);
        if (!hasScanResult) return;

        outState.putString(STATE_SCAN_STATUS, boundedStateText(lastScanStatus));
        outState.putBoolean(STATE_SCAN_COMPLETE, lastScanComplete);
        outState.putInt(STATE_SCAN_FINDING_COUNT, lastFindings.size());
        if (lastFindings.size() > MAX_SAVED_FINDINGS
                || selectedForCleanup.size() > MAX_BATCH_SELECTION) {
            outState.putBoolean(STATE_SCAN_REQUIRES_RESCAN, true);
            return;
        }

        java.util.ArrayList<String> packages = new java.util.ArrayList<>();
        java.util.ArrayList<String> labels = new java.util.ArrayList<>();
        java.util.ArrayList<String> severities = new java.util.ArrayList<>();
        java.util.ArrayList<String> reasons = new java.util.ArrayList<>();
        java.util.ArrayList<String> sources = new java.util.ArrayList<>();
        java.util.ArrayList<String> matches = new java.util.ArrayList<>();
        for (FxYulongScanEngine.Finding finding : lastFindings) {
            packages.add(boundedStateText(finding.packageName));
            labels.add(boundedStateText(finding.label));
            severities.add(finding.severity.name());
            reasons.add(boundedStateText(finding.reason));
            sources.add(boundedStateText(finding.sourceLabel));
            matches.add(boundedStateText(finding.matchedEntry));
        }
        outState.putStringArrayList(STATE_FINDING_PACKAGES, packages);
        outState.putStringArrayList(STATE_FINDING_LABELS, labels);
        outState.putStringArrayList(STATE_FINDING_SEVERITIES, severities);
        outState.putStringArrayList(STATE_FINDING_REASONS, reasons);
        outState.putStringArrayList(STATE_FINDING_SOURCES, sources);
        outState.putStringArrayList(STATE_FINDING_MATCHES, matches);
        outState.putStringArrayList(STATE_SELECTED_PACKAGES,
                new java.util.ArrayList<>(selectedForCleanup.keySet()));
    }

    @Override protected void onDestroy() {
        destroyed = true;
        scanGeneration++;
        super.onDestroy();
    }

    private void startScan() {
        if (destroyed || !running.compareAndSet(false, true)) return;
        final int request = ++scanGeneration;
        restoreRequiresRescan = false;
        scan.setEnabled(false);
        scan.setText("扫描中…");
        batchCleanup.setEnabled(false);
        status.setText("正在读取已安装应用清单并匹配本地名单…");
        boolean deepScan = contentScan.isChecked();
        FxYulongScanEngine.scan(this, deepScan, result -> runOnUiThread(() -> {
            if (destroyed || isFinishing() || isDestroyed() || request != scanGeneration) return;
            running.set(false);
            scan.setEnabled(true);
            scan.setText("重新扫描");
            resultRows.removeAllViews();
            selectedForCleanup.clear();
            lastFindings.clear();
            lastFindings.addAll(result.findings);
            hasScanResult = true;
            lastScanComplete = result.scanComplete;
            status.setText(result.message + " 扫描 " + result.scanned + " 个应用；名单 " + result.databaseEntries
                    + " 条；确定风险 " + result.certainCount + "；可能风险 " + result.suspectCount
                    + "。\n内容特征扫描：" + (result.contentScanEnabled
                    ? (result.contentDatabaseReady ? ("已检查 " + result.contentScanned + " 个 APK"
                        + (result.contentReadFailures > 0 ? "；读取失败 " + result.contentReadFailures + " 个" : "")
                        + (result.contentTruncated ? "；达到预算上限，扫描未完成" : ""))
                        : "已启用但内容特征库未就绪；第二阶段未执行")
                    : "未启用（默认关闭）"));
            status.setTextColor(result.scanComplete ? 0xff5c6877 : 0xffa32620);
            lastScanStatus = status.getText().toString();
            for (FxYulongScanEngine.Finding finding : result.findings) addFinding(finding, false);
            if (result.findings.isEmpty()) {
                resultRows.addView(text(
                        FxYulongScanCompleteness.noFindingMessage(result.scanComplete),
                        13, result.scanComplete ? 0xff607080 : 0xffa32620, !result.scanComplete));
            }
            updateBatchCleanup();
        }));
    }

    private void addFinding(FxYulongScanEngine.Finding finding) {
        addFinding(finding, false);
    }

    private void addFinding(FxYulongScanEngine.Finding finding, boolean initiallySelected) {
        LinearLayout item=new LinearLayout(this);item.setTag(finding.severity==FxYulongScanEngine.Severity.CERTAIN?"fx-risk-certain":"fx-risk-suspect");item.setOrientation(LinearLayout.VERTICAL);
        item.setPadding(dp(12),dp(8),dp(12),dp(8));
        item.setBackgroundColor(finding.severity==FxYulongScanEngine.Severity.CERTAIN?0xffffeeee:0xfffff5e5);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(3),dp(12),dp(4));resultRows.addView(item,lp);
        TextView riskTitle=text((finding.severity==FxYulongScanEngine.Severity.CERTAIN?"确定风险 · ":"可能风险 · ")+finding.label,
                14,finding.severity==FxYulongScanEngine.Severity.CERTAIN?0xffa32620:0xff8a5b12,true);
        riskTitle.setTag(finding.severity==FxYulongScanEngine.Severity.CERTAIN?"fx-risk-title-certain":"fx-risk-title-suspect");
        item.addView(riskTitle);
        item.addView(text(finding.packageName+"\n"+finding.reason,12,0xff617080,false));
        String evidence = finding.sourceLabel.isEmpty() ? "来源：未提供（旧版扫描状态）"
                : "来源：" + finding.sourceLabel;
        if (!finding.matchedEntry.isEmpty()) evidence += "\n匹配条目/特征族：" + finding.matchedEntry;
        item.addView(text(evidence,11,0xff75808a,false));
        android.widget.CheckBox check = new android.widget.CheckBox(this);
        check.setText("加入批量清理清单");
        check.setOnCheckedChangeListener((button, checked) -> {
            if (checked) {
                if (!selectedForCleanup.containsKey(finding.packageName)
                        && selectedForCleanup.size() >= MAX_BATCH_SELECTION) {
                    button.setChecked(false);
                    Toast.makeText(this, "单次批量清理最多选择 "
                            + MAX_BATCH_SELECTION + " 个应用。", Toast.LENGTH_LONG).show();
                    return;
                }
                selectedForCleanup.put(finding.packageName, finding);
            } else {
                selectedForCleanup.remove(finding.packageName);
            }
            updateBatchCleanup();
        });
        item.addView(check);
        if (initiallySelected) check.setChecked(true);
        item.addView(action("打开风险警告页", () -> {
            Intent warning = new Intent(this, FxYulongWarningActivity.class);
            warning.putExtra("package_name", finding.packageName);
            warning.putExtra("app_label", finding.label);
            warning.putExtra("reason", finding.reason);
            warning.putExtra("severity", finding.severity.name());
            warning.putExtra("source_label", finding.sourceLabel);
            warning.putExtra("matched_entry", finding.matchedEntry);
            startActivity(warning);
        }));
        item.addView(action("核实后打开系统卸载确认",()->confirmUninstall(finding)));
    }

    private void updateBatchCleanup() {
        if (batchCleanup == null) return;
        batchCleanup.setText("批量清理已选择风险应用（" + selectedForCleanup.size() + "）");
        batchCleanup.setEnabled(!running.get() && !restoreRequiresRescan
                && !selectedForCleanup.isEmpty());
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_BATCH_CLEANUP) return;
        selectedForCleanup.clear();
        restoreRequiresRescan = true;
        lastScanComplete = false;
        lastScanStatus = "批量清理队列已返回；原扫描结果可能已过期。请重新扫描后再处理。";
        status.setText(lastScanStatus);
        status.setTextColor(0xffa32620);
        updateBatchCleanup();
    }

    private void openBatchCleanup() {
        if (restoreRequiresRescan) {
            Toast.makeText(this, "上次扫描状态未完整恢复，请重新扫描后再进行批量处理。",
                    Toast.LENGTH_LONG).show();
            return;
        }
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
        startActivityForResult(intent, REQUEST_BATCH_CLEANUP);
    }

    private void confirmUninstall(FxYulongScanEngine.Finding finding){
        fxDialogBuilder().setTitle("请先核实扫描结果")
                .setMessage("病毒库命中可能存在误报：\n\n"+finding.label+"\n"+finding.packageName
                        +"\n\n只有你确认该应用需要移除时，才会继续打开 Android 系统卸载确认界面。FX 不会在后台静默卸载。")
                .setNegativeButton("返回",null)
                .setPositiveButton("打开系统确认",(d,w)->{
                    try{startActivity(new Intent(Intent.ACTION_DELETE,Uri.parse("package:"+finding.packageName)));}
                    catch(Throwable error){Toast.makeText(this,"无法打开系统卸载确认："+error.getClass().getSimpleName(),Toast.LENGTH_LONG).show();}
                }).show();
    }
}
