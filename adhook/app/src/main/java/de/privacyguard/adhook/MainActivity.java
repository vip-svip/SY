package de.privacyguard.adhook;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.*;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Native launcher and per-target settings UI for the standalone FX Hook APK. */
public final class MainActivity extends Activity {
    private LinearLayout root;
    private EditText search;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final List<ApplicationInfo> filtered = new ArrayList<>();
    private String selectedPackage;
    private String selectedLabel;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        showAppList();
    }

    private int dp(float v) { return (int)(v * getResources().getDisplayMetrics().density + .5f); }
    private TextView title(String value, int size) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD); t.setTextColor(0xff17212b);
        t.setPadding(dp(18), dp(14), dp(18), dp(10)); return t;
    }
    private void base(String heading) {
        root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff4f6f8);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        content.addView(title("FX Hook", 25));
        TextView h = title(heading, 18); h.setPadding(dp(18), dp(2), dp(18), dp(12)); content.addView(h);
        scroll.addView(content); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root); this.content = content;
    }
    private LinearLayout content;
    private void showAppList() {
        selectedPackage = null; base("选择应用");
        search = new EditText(this); search.setSingleLine(true); search.setHint("搜索应用名称或包名");
        search.setPadding(dp(16), dp(10), dp(16), dp(10));
        content.addView(search, new LinearLayout.LayoutParams(-1, -2));
        TextView hint = new TextView(this); hint.setText("点击应用进入独立 Hook 配置"); hint.setTextColor(0xff66727e);
        hint.setPadding(dp(18), dp(8), dp(18), dp(8)); content.addView(hint);
        loadApps(); renderApps("");
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s,int st,int c,int a) {}
            public void onTextChanged(CharSequence s,int st,int before,int count) { renderApps(s.toString()); }
            public void afterTextChanged(Editable e) {}
        });
    }
    private void loadApps() {
        apps.clear();
        PackageManager pm = getPackageManager();
        for (ApplicationInfo ai : pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
            if ((ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0 && ai.packageName.startsWith("com.android.")) continue;
            if (ai.packageName.equals(getPackageName()) || ai.packageName.equals("android")) continue;
            apps.add(ai);
        }
        Collections.sort(apps, new Comparator<ApplicationInfo>() {
            public int compare(ApplicationInfo a, ApplicationInfo b) {
                return pm.getApplicationLabel(a).toString().compareToIgnoreCase(pm.getApplicationLabel(b).toString());
            }
        });
    }
    private void renderApps(String query) {
        while (content.getChildCount() > 3) content.removeViewAt(3);
        filtered.clear(); String q=query.toLowerCase();
        for (ApplicationInfo ai: apps) {
            String label=getPackageManager().getApplicationLabel(ai).toString();
            if (label.toLowerCase().contains(q) || ai.packageName.toLowerCase().contains(q)) filtered.add(ai);
        }
        for (ApplicationInfo ai: filtered) {
            LinearLayout row=new LinearLayout(this); row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(16),dp(10),dp(16),dp(10)); row.setBackgroundColor(0xffffffff);
            ImageView icon=new ImageView(this); icon.setImageDrawable(getPackageManager().getApplicationIcon(ai));
            row.addView(icon,new LinearLayout.LayoutParams(dp(42),dp(42)));
            LinearLayout labels=new LinearLayout(this); labels.setOrientation(LinearLayout.VERTICAL);
            labels.setPadding(dp(12),0,0,0);
            TextView name=new TextView(this); name.setText(getPackageManager().getApplicationLabel(ai)); name.setTextSize(16); name.setTextColor(0xff17212b);
            TextView pkg=new TextView(this); pkg.setText(ai.packageName); pkg.setTextSize(11); pkg.setTextColor(0xff75808a);
            labels.addView(name); labels.addView(pkg);
            row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
            TextView arrow=new TextView(this); arrow.setText("›"); arrow.setTextSize(28); arrow.setTextColor(0xff637080); row.addView(arrow);
            row.setOnClickListener(v -> showTarget(ai)); content.addView(row,new LinearLayout.LayoutParams(-1,-2));
            View divider=new View(this); divider.setBackgroundColor(0xffe8ebee); content.addView(divider,new LinearLayout.LayoutParams(-1,dp(1)));
        }
        if(filtered.isEmpty()){TextView empty=new TextView(this);empty.setText("没有匹配的应用");empty.setPadding(dp(18),dp(20),dp(18),dp(20));content.addView(empty);}
    }
    private String key(String feature) { return selectedPackage + ":" + feature; }
    private boolean get(String feature) { return getPreferences(0).getBoolean(key(feature), false); }
    private void showTarget(ApplicationInfo ai) {
        selectedPackage=ai.packageName; selectedLabel=getPackageManager().getApplicationLabel(ai).toString();
        base(selectedLabel);
        TextView pkg=new TextView(this); pkg.setText(selectedPackage); pkg.setTextColor(0xff687582);
        pkg.setPadding(dp(18),0,dp(18),dp(12)); content.addView(pkg);
        section("广告 Hook");
        toggle("启动页广告", "ads_splash", false);
        toggle("信息流广告", "ads_feed", false);
        toggle("弹窗 / 插屏广告", "ads_overlay", false);
        section("隐私 Hook");
        toggle("隐私保护总开关", "privacy", false);
        toggle("阻止剪贴板读取", "clipboard_read_block", false);
        toggle("隔离剪贴板", "clipboard_isolate", false);
        toggle("限制 Wi-Fi 扫描", "wifi_scan_block", false);
        toggle("限制麦克风访问", "mic_access_block", false);
        toggle("限制摄像头访问", "camera_access_block", false);
        toggle("限制位置访问", "location_access_block", false);
        toggle("清理媒体查询元数据", "media_store_query_block", false);
        section("会员诊断");
        toggle("只读会员状态诊断", "member_diag", false);
        TextView note=new TextView(this);
        note.setText("会员诊断仅记录应用内可观察状态，不修改购买结果、会员资格、令牌或服务端授权。");
        note.setTextColor(0xff697681); note.setPadding(dp(18),dp(2),dp(18),dp(14)); content.addView(note);
        section("自定义 Hook");
        TextView custom=new TextView(this);
        custom.setText("自定义 Hook 规则编辑器将在配置发布链路接通后启用。此处不会伪造第三方会员或登录状态。");
        custom.setTextColor(0xff697681); custom.setPadding(dp(18),dp(4),dp(18),dp(16)); content.addView(custom);
        Button save=new Button(this); save.setText("保存并同步到 LSPosed");
        save.setOnClickListener(v -> {
            getPreferences(0).edit().putBoolean(key("draft_saved"),true).apply();
            publishConfig();
        });
        content.addView(save,new LinearLayout.LayoutParams(-1,-2));
        Button back=new Button(this); back.setText("返回应用列表"); back.setOnClickListener(v->showAppList());
        content.addView(back,new LinearLayout.LayoutParams(-1,-2));
    }
 
    private boolean enabled(String pkg, String feature) {
        return getPreferences(0).getBoolean(pkg + ":" + feature, false);
    }

    private void publishConfig() {
        try {
            StringBuilder cfg = new StringBuilder();
            boolean anyAds=false, anyPrivacy=false, anyWifi=false, anyNotif=false, anyNotifPerm=false, anyClipboardIso=false;
            List<String> rows = new ArrayList<>();
            for (ApplicationInfo ai : apps) {
                String p=ai.packageName;
                String[] keys={"ads_splash","ads_feed","ads_overlay","member_diag","privacy","exif_strip",
                    "clipboard_read_block","clipboard_isolate","wifi_scan_block","notification_listen_block",
                    "notification_permission_hide","mic_silence","camera_access_block","location_access_block",
                    "mic_access_block","media_store_query_block","sensor_accel","sensor_gyro","sensor_light",
                    "sensor_magnet","sensor_pressure","sensor_prox","sensor_rate_limit"};
                StringBuilder row=new StringBuilder(p);
                boolean has=false;
                for(String k:keys) {
                    boolean on=enabled(p,k);
                    if(on) {
                        row.append(',').append(k).append('=').append('1'); has=true;
                        if(k.startsWith("ads_")) anyAds=true;
                        if(k.equals("privacy")||k.equals("exif_strip")||k.equals("clipboard_read_block")||
                           k.equals("clipboard_isolate")||k.equals("mic_silence")||k.equals("camera_access_block")||
                           k.equals("location_access_block")||k.equals("mic_access_block")||
                           k.equals("media_store_query_block")||k.startsWith("sensor_")) anyPrivacy=true;
                        if(k.equals("wifi_scan_block")) anyWifi=true;
                        if(k.equals("notification_listen_block")) anyNotif=true;
                        if(k.equals("notification_permission_hide")) anyNotifPerm=true;
                        if(k.equals("clipboard_isolate")) anyClipboardIso=true;
                    }
                }
                if(has) rows.add(row.toString());
            }
            cfg.append("schema_version=1\n")
               .append("ads_enabled=").append(anyAds?'1':'0').append('\n')
               .append("privacy_enabled=").append(anyPrivacy?'1':'0').append('\n')
               .append("wifi_scan_enabled=").append(anyWifi?'1':'0').append('\n')
               .append("notification_listen_enabled=").append(anyNotif?'1':'0').append('\n')
               .append("notification_permission_hide_enabled=").append(anyNotifPerm?'1':'0').append('\n')
               .append("clipboard_isolate_enabled=").append(anyClipboardIso?'1':'0').append('\n')
               .append("[list:targets]\n");
            for(String row:rows) cfg.append(row).append('\n');
            String encoded=android.util.Base64.encodeToString(cfg.toString().getBytes("UTF-8"),android.util.Base64.NO_WRAP);
            int androidUser=android.os.Process.myUid()/100000;
            String moduleDir="/data/adb/lspd/modules/"+androidUser+"/de.privacyguard.adhook/files";
            String remote=moduleDir+"/fx-hook-targets.conf";
            String command="mkdir -p "+moduleDir+" && echo "+encoded+" | base64 -d > "+remote+" && chmod 600 "+remote;
            Process proc=Runtime.getRuntime().exec(new String[]{"su","-c",command});
            int code=proc.waitFor();
            if(code==0) {
                new AlertDialog.Builder(this).setMessage("配置已写入 LSPosed Remote Files。请确认 LSPosed Manager 已将 FX Hook 作用域包含目标应用，并强制停止后重新打开目标应用。")
                    .setPositiveButton("知道了",null).show();
            } else {
                new AlertDialog.Builder(this).setMessage("root 发布失败（退出码 "+code+"）。请确认已授予 FX Hook root 权限、FX Hook 已安装为 LSPosed 模块，然后重试。配置仍保存在本机草稿。")
                    .setPositiveButton("知道了",null).show();
            }
        } catch(Exception e) {
            new AlertDialog.Builder(this).setMessage("配置同步失败："+e.getClass().getSimpleName()+"。本机草稿仍已保存。")
                .setPositiveButton("知道了",null).show();
        }
    }
\n    private void section(String s) {
        TextView t=title(s,16); t.setBackgroundColor(0xffe9eef3); content.addView(t,new LinearLayout.LayoutParams(-1,-2));
    }
    private void toggle(String label,String feature,boolean def) {
        Switch sw=new Switch(this); sw.setText(label); sw.setTextSize(15); sw.setPadding(dp(18),dp(12),dp(18),dp(12));
        sw.setBackgroundColor(0xffffffff); sw.setChecked(getPreferences(0).getBoolean(key(feature),def));
        sw.setOnCheckedChangeListener((b,on)->getPreferences(0).edit().putBoolean(key(feature),on).apply());
        content.addView(sw,new LinearLayout.LayoutParams(-1,-2));
    }
}