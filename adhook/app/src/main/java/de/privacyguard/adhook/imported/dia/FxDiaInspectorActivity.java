package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import de.privacyguard.adhook.RootAccess;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/** Read-only database-schema and process-memory metadata inspector for debuggable apps. */
public final class FxDiaInspectorActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(4),
            r -> { Thread t = new Thread(r, "fx-dia-inspector"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
            });
        }
    }
    private static final class TargetApp {
        final ApplicationInfo info;
        final String label;
        TargetApp(ApplicationInfo app, String text) { info = app; label = text; }
    }
    private final List<TargetApp> apps = new ArrayList<>();
    private String mode="database", targetPackage;
    private TextView target,status,output;
    private boolean appsLoading;
    private boolean appsLoaded;
    private long appLoadGeneration;
    private Runnable appsReadyCallback;
    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color,boolean bold){
        TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);
        if(bold)t.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5));return t;
    }
    private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
    private void card(LinearLayout p,String title,String detail,View... controls){
        LinearLayout c=new LinearLayout(this);c.setOrientation(1);c.setPadding(dp(14),dp(10),dp(14),dp(10));c.setBackgroundColor(0xfff0f3f7);
        c.addView(text(title,16,0xff17212b,true));c.addView(text(detail,12,0xff617080,false));for(View v:controls)c.addView(v);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(5),dp(12),dp(5));p.addView(c,lp);
    }
    private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);mode=getIntent().getStringExtra("dia_mode");if(!"memory".equals(mode))mode="database";
        LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xfff7f8fa);
        LinearLayout h=new LinearLayout(this);h.setGravity(Gravity.CENTER_VERTICAL);h.setPadding(dp(10),dp(6),dp(12),dp(6));
        h.addView(button("‹ 返回",this::finish));
        h.addView(text("memory".equals(mode)?"Dia 23.11 · 内存快照":"Dia 23.11 · 数据库监控",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));
        root.addView(h);ScrollView sc=new ScrollView(this);sc.setFillViewport(true);
        LinearLayout body=new LinearLayout(this);body.setOrientation(1);body.setPadding(0,dp(4),0,dp(18));sc.addView(body);
        root.addView(sc,new LinearLayout.LayoutParams(-1,0,1));setContentViewWithNativeTabs(root, 4);
        target=text("尚未选择目标应用。",13,0xff334155,false);status=text("仅支持用户安装且带 DEBUGGABLE 标记的应用。",13,0xff617080,false);
        output=text("尚无读取结果。",12,0xff344054,false);
        card(body,"目标应用","只检查本机 debuggable 构建；不读取非调试应用私有数据或原始内存。",
            target,button("选择 debuggable 目标",this::chooseTarget),
            button("读取"+("memory".equals(mode)?"进程内存指标":"数据库清单与表结构"),this::inspect));
        card(body,"状态","Root 只读检查",status);
        card(body,"结果","不读取数据库业务行，也不导出任意进程内存内容。",
            output,button("复制结果",this::copyResult));
        if ("memory".equals(mode)) {
            card(body, "HPROF 内存快照",
                    "当前页面显示进程内存指标与有界内存映射。完整 Java 堆快照通过内置 Frida 工具生成；只允许用户安装的 debuggable 测试目标。",
                    button("打开 HPROF 快照工具", () -> startActivity(
                            new android.content.Intent(this, FxDiaFridaActivity.class)
                                    .putExtra("dia_page", "内存快照"))));
        }
        loadApps(null);
    }
    private void loadApps(Runnable whenReady) {
        if (appsLoaded) {
            if (whenReady != null) whenReady.run();
            return;
        }
        if (whenReady != null) appsReadyCallback = whenReady;
        if (appsLoading) {
            status.setText("正在后台读取可调试应用列表…");
            return;
        }
        appsLoading = true;
        final long generation = ++appLoadGeneration;
        status.setText("正在后台读取可调试应用列表…");
        final android.content.pm.PackageManager packageManager = getPackageManager();
        final String ownPackage = getPackageName();
        try {
            worker.execute(() -> {
                List<TargetApp> loaded = new ArrayList<>();
                String failure = null;
                try {
                    for (ApplicationInfo app : packageManager.getInstalledApplications(0)) {
                        if (Thread.currentThread().isInterrupted()) return;
                        if (app.packageName == null || app.packageName.equals(ownPackage)) continue;
                        if ((app.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                                || (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                        String label;
                        try { label = String.valueOf(packageManager.getApplicationLabel(app)); }
                        catch (RuntimeException unavailable) { label = app.packageName; }
                        loaded.add(new TargetApp(app, label));
                    }
                    loaded.sort(Comparator.comparing(item -> item.label.toLowerCase(Locale.ROOT)));
                } catch (RuntimeException error) {
                    failure = error.getClass().getSimpleName();
                }
                if (Thread.currentThread().isInterrupted()) return;
                final String loadFailure = failure;
                final List<TargetApp> result = loaded;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed() || generation != appLoadGeneration) return;
                    appsLoading = false;
                    if (loadFailure != null) {
                        appsReadyCallback = null;
                        status.setText("读取应用列表失败：" + loadFailure);
                        return;
                    }
                    apps.clear();
                    apps.addAll(result);
                    appsLoaded = true;
                    status.setText("可调试用户应用：" + apps.size());
                    Runnable callback = appsReadyCallback;
                    appsReadyCallback = null;
                    if (callback != null) callback.run();
                });
            });
        } catch (RejectedExecutionException full) {
            appsLoading = false;
            appsReadyCallback = null;
            status.setText("后台任务队列繁忙，应用列表未读取；请稍后重试。");
        }
    }
    private void chooseTarget() {
        loadApps(this::showTargetPicker);
    }
    private void showTargetPicker() {
        if (apps.isEmpty()) {
            status.setText("没有可调试的用户应用。");
            return;
        }
        final List<TargetApp> choices = new ArrayList<>(apps);
        String[] labels = new String[choices.size()];
        for (int i = 0; i < choices.size(); i++) {
            TargetApp choice = choices.get(i);
            labels[i] = choice.label + "\n" + choice.info.packageName;
        }
        new AlertDialog.Builder(this).setTitle("选择 debuggable 目标")
                .setItems(labels, (dialog, which) -> {
                    TargetApp selected = choices.get(which);
                    targetPackage = selected.info.packageName;
                    target.setText(labels[which]);
                    status.setText("目标已选择；点击读取。");
                }).setNegativeButton("取消", null).show();
    }
    private void inspect(){
        if(TextUtils.isEmpty(targetPackage)){status.setText("请先选择 debuggable 目标应用。");return;}
        String pkg=targetPackage;
        String command="set -e; pkg="+quote(pkg)+"; case \"$pkg\" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac; ";
        if("database".equals(mode)){
            command+="base=/data/user/0/$pkg/databases; [ -d \"$base\" ] || base=/data/data/$pkg/databases; "
                +"[ -d \"$base\" ] || { echo 'NO_DATABASE_DIRECTORY'; exit 0; }; echo 'DATABASE_FILES'; count=0; "
                +"for db in \"$base\"/*.db \"$base\"/*.sqlite \"$base\"/*.sqlite3; do [ -f \"$db\" ] || continue; count=$((count+1)); "
                +"printf 'DB|%s|%s bytes\\n' \"$(basename \"$db\")\" \"$(wc -c < \"$db\" | tr -d ' ')\"; "
                +"if command -v sqlite3 >/dev/null 2>&1; then echo 'SCHEMA_START'; "
                +"sqlite3 -readonly \"$db\" \"PRAGMA query_only=ON; SELECT type||'|'||name||'|'||coalesce(sql,'') FROM sqlite_master WHERE type IN ('table','index','view','trigger') ORDER BY type,name LIMIT 200;\" 2>&1 || echo 'SCHEMA_READ_FAILED'; "
                +"else echo 'SQLITE3_CLI_UNAVAILABLE; file metadata only'; fi; done; [ \"$count\" -gt 0 ] || echo 'NO_DATABASE_FILES';";
        }else{
            command+="pid=$(pidof \"$pkg\" 2>/dev/null | awk '{print $1}'); case \"$pid\" in ''|*[!0-9]*) echo 'TARGET_NOT_RUNNING'; exit 0;; esac; "
                +"echo 'PROCESS_STATUS'; grep -E '^(Name|Pid|PPid|Threads|VmPeak|VmSize|VmRSS|VmData|VmStk|VmExe|VmLib):' /proc/$pid/status 2>/dev/null || true; "
                +"echo 'SMAPS_ROLLUP'; if [ -r /proc/$pid/smaps_rollup ]; then awk '/^(Rss|Pss|Pss_Anon|Pss_File|Pss_Shmem|Shared_Clean|Shared_Dirty|Private_Clean|Private_Dirty|Swap):/ {print}' /proc/$pid/smaps_rollup; "
                +"else echo 'SMAPS_ROLLUP_UNAVAILABLE'; fi; echo 'MEMORY_MAPS'; sed -n '1,160p' /proc/$pid/maps 2>/dev/null || true; echo 'MAPS_TRUNCATED_AFTER_160_LINES';";
        }
        status.setText("正在读取…");output.setText("");
        final String commandToRun = command;
        submitWorker(()->{RootAccess.Result result=RootAccess.execute(commandToRun,45000L,256*1024);
            runOnUiThread(()->{if(isFinishing()||isDestroyed())return;status.setText("读取完成，退出码："+result.exitCode);output.setText(result.output==null?"（无输出）":result.output);});});
    }
    private void copyResult(){
        android.content.ClipboardManager cb=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);if(cb==null)return;
        cb.setPrimaryClip(android.content.ClipData.newPlainText("Dia inspector",output.getText()));status.setText("结果已复制。");
    }
    @Override protected void onDestroy() {
        appLoadGeneration++;
        appsReadyCallback = null;
        worker.shutdownNow();
        super.onDestroy();
    }
}
