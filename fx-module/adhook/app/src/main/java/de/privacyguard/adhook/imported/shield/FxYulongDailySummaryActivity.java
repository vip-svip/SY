package de.privacyguard.adhook.imported.shield;

import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Local daily summary based only on counters written by FX Shield subsystems. */
public final class FxYulongDailySummaryActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String PREFS = "shield_prefs";
    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s,int size,int color,boolean bold) {
        TextView t=new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        t.setPadding(dp(4),dp(5),dp(4),dp(5)); return t;
    }
    private Button button(String s,Runnable r) {
        Button b=new Button(this); b.setTag("fx-action-row"); b.setAllCaps(false); b.setText(s); b.setOnClickListener(v->r.run()); return b;
    }
    private void card(LinearLayout body,String title,String detail) {
        LinearLayout c=new LinearLayout(this); c.setTag("fx-card"); c.setOrientation(1);
        c.setPadding(dp(14),dp(10),dp(14),dp(10)); c.setBackgroundColor(0xfff0f3f7);
        TextView heading=text(title,15,0xff17212b,true); heading.setTag("fx-card-title"); c.addView(heading);
        TextView description=text(detail,13,0xff526170,false); description.setTag("fx-card-detail"); c.addView(description);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12),dp(5),dp(12),dp(5)); body.addView(c,lp);
    }
    @SuppressWarnings("deprecation")
    private boolean isServiceRunning(Class<?> serviceClass) {
        android.app.ActivityManager manager =
                (android.app.ActivityManager) getSystemService(ACTIVITY_SERVICE);
        if (manager == null) return false;
        try {
            for (android.app.ActivityManager.RunningServiceInfo info
                    : manager.getRunningServices(100)) {
                if (info != null && info.service != null
                        && serviceClass.getName().equals(info.service.getClassName())
                        && getPackageName().equals(info.service.getPackageName())) return true;
            }
        } catch (RuntimeException ignored) { }
        return false;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        SharedPreferences p=getSharedPreferences(PREFS,MODE_PRIVATE);
        String today=new SimpleDateFormat("yyyy-MM-dd",Locale.ROOT).format(new Date());
        boolean sameWarn=today.equals(p.getString("protect_warn_day",""));
        boolean sameScan=today.equals(p.getString("automatic_scan_day",""));
        int warnings=sameWarn?p.getInt("protect_warn_count_today",0):0;
        int scans=sameScan?p.getInt("automatic_scan_count_today",0):0;
        int findings=sameScan?p.getInt("automatic_scan_findings_today",0):0;
        boolean sameRescue=today.equals(p.getString("rescue_trigger_day",""));
        int rescueCount=sameRescue?p.getInt("rescue_trigger_count_today",0):0;
        boolean sameOverlay=today.equals(p.getString("overlay_open_day",""));
        int overlayCount=sameOverlay?p.getInt("overlay_open_count_today",0):0;

        LinearLayout root=new LinearLayout(this); root.setOrientation(1);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10),dp(6),dp(10),dp(6));
        header.addView(button("‹ 返回隐私",this::finish));
        TextView pageTitle=text("隐私 · 每日安全总结",18,0xff17212b,true);
        pageTitle.setTag("fx-title:18");
        header.addView(pageTitle,new LinearLayout.LayoutParams(0,-2,1));
        root.addView(header);
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body=new LinearLayout(this); body.setOrientation(1);
        body.setPadding(0,dp(4),0,dp(18)); scroll.addView(body);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1)); setContentViewWithNativeTabs(root, 2);

        card(body,"统计日期",today);
        card(body,"前台管控提醒","今日 "+warnings+" 次 · 累计 "
                +p.getInt("protect_warn_count",0)+" 次");
        card(body,"自动风险扫描应用数",
                "今日检查应用 " + scans + " 个 · 风险名单命中 " + findings
                        + " 项（统计包含前台、安装/更新与病毒库更新后的扫描）");
        card(body,"救援触发与悬浮入口","今日音量键/摇动触发提醒 "+rescueCount
                +" 次 · 悬浮入口打开 "+overlayCount+" 次"
                +"\n最近触发："+p.getString("rescue_trigger_last_time","暂无记录")
                +"\n"+p.getString("rescue_trigger_last_message","暂无救援触发记录。")
                +"\n悬浮入口最近打开："+p.getString("overlay_last_open_time","暂无记录"));
        card(body,"最近一次管控提醒",
                p.getString("protect_last_warn_time","暂无记录")+"\n"
                +p.getString("protect_last_warn_message","尚未触发管控提醒。"));
        card(body,"最近一次安装扫描",
                p.getString("automatic_scan_last_time","暂无记录")+"\n"
                +p.getString("automatic_scan_last_package","")
                +"\n"+p.getString("automatic_scan_last_result","尚无扫描结果。"));
        boolean protectionServiceRunning = isServiceRunning(FxYulongProtectionService.class);
        boolean rescueOverlayRunning = isServiceRunning(FxYulongRescueOverlayService.class);
        boolean notificationPermission = android.os.Build.VERSION.SDK_INT < 33
                || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                == android.content.pm.PackageManager.PERMISSION_GRANTED;
        card(body,"后台守护实际状态",
                (protectionServiceRunning ? "安全守护/救援前台服务：当前运行中" : "安全守护/救援前台服务：当前未运行")
                +"\n"+(rescueOverlayRunning?"悬浮救援服务：当前运行中":"悬浮救援服务：当前未运行")
                +"\n"+(p.getBoolean("protect_on",false)?"名单监测配置：已开启":"名单监测配置：已关闭")
                +"\n"+(p.getBoolean("shake_trigger_on",false)?"摇动触发配置：已开启":"摇动触发配置：已关闭")
                +"\n"+(p.getBoolean("volume_trigger_on",false)?"音量触发配置：已开启":"音量触发配置：已关闭")
                +"\n"+(notificationPermission?"通知权限：已授予":"通知权限：未授予，通知不可显示"));
        card(body,"统计口径",
                "计数仅来自 FX 已迁入的本机扫描和管控提醒事件。没有记录到的事件不会推算；本页不访问第三方统计服务器。");
        body.addView(button("打开完整应用扫描",()->startActivity(new Intent(this,FxYulongScanActivity.class))));
        body.addView(button("返回隐私首页",this::finish));
    }
}
