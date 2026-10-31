package de.privacyguard.adhook;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebChromeClient;
import android.webkit.ValueCallback;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.WebView;
import androidx.webkit.WebViewAssetLoader;
import androidx.webkit.WebViewClientCompat;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
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
    private WebView webView;
    private TextView rootStatus;
    private boolean hookUiVisible;
    private ValueCallback<Uri[]> fileChooserCallback;
    private static final int REQUEST_FILE_PICKER = 4101;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        showDashboard();
    }

    private void showDashboard() { showWebDashboard(); }

    private void showWebDashboard() {
        hookUiVisible = false;
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff4f6f8);

        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(14), dp(6), dp(10), dp(6));
        toolbar.setBackgroundColor(0xff101820);
        TextView brand = new TextView(this);
        brand.setText("FX");
        brand.setTextSize(20);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setTextColor(0xffffffff);
        toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
        rootStatus = new TextView(this);
        rootStatus.setText("Root 检查中");
        rootStatus.setTextSize(11);
        rootStatus.setTextColor(0xffd8e0e8);
        rootStatus.setPadding(dp(8), dp(8), dp(8), dp(8));
        rootStatus.setOnClickListener(v -> checkRoot(rootStatus, true));
        toolbar.addView(rootStatus);
        Button hook = new Button(this);
        hook.setText("Hook");
        hook.setTextSize(12);
        hook.setOnClickListener(v -> showAppList());
        toolbar.addView(hook, new LinearLayout.LayoutParams(-2, dp(42)));
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));

        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true); // only user-selected content:// URIs are exposed by the native picker
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setSafeBrowsingEnabled(true);

        WebViewAssetLoader.AssetsPathHandler fallback =
                new WebViewAssetLoader.AssetsPathHandler(getAssets());
        WebViewAssetLoader.PathHandler handler = assetPath -> {
            if ("webroot/index.html".equals(assetPath)) {
                try (InputStream in = getAssets().open(assetPath);
                     ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[8192];
                    int n;
                    while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
                    String html = new String(out.toByteArray(), StandardCharsets.UTF_8);
                    String shim = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'\">"
                        + "<script>(function(){var seq=0;window.ksu={exec:function(cmd,opts,cb){if(typeof cb==='string'){FXRoot.exec(String(cmd),cb);return null;}return new Promise(function(resolve){var n='__fxPromise_'+(++seq);window[n]=function(errno,stdout,stderr){resolve({errno:errno,stdout:stdout,stderr:stderr});};FXRoot.exec(String(cmd),n);});},fullScreen:function(){},enableEdgeToEdge:function(){}};window.KernelSU=window.ksu;window.FXNative={openHookManager:function(){FXRoot.openHookManager();}};window.showSaveFilePicker=async function(opts){var name=(opts&&opts.suggestedName)||'FX-export.txt';return {createWritable:async function(){var value='';return {write:async function(v){value=v;},close:async function(){var blob=value instanceof Blob?value:new Blob([value],{type:'text/plain;charset=utf-8'});var reader=new FileReader();reader.onloadend=function(){var data=String(reader.result||'').split(',').pop();FXRoot.saveBase64(name,data,blob.type||'text/plain');};reader.readAsDataURL(blob);}};}};};})();</script>";
                    int head = html.toLowerCase().indexOf("<head");
                    int close = head >= 0 ? html.indexOf(">", head) : -1;
                    if (close >= 0) html = html.substring(0, close + 1) + shim + html.substring(close + 1);
                    return new WebResourceResponse("text/html", "UTF-8",
                            new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
                } catch (Exception e) {
                    return new WebResourceResponse("text/plain", "UTF-8",
                            new ByteArrayInputStream(("FX UI asset error: " + e).getBytes(StandardCharsets.UTF_8)));
                }
            }
            return fallback.handle(assetPath);
        };
        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", handler).build();
        webView.addJavascriptInterface(new RootBridge(this, webView), "FXRoot");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, JsPromptResult result) {
                EditText input = new EditText(MainActivity.this);
                input.setText(defaultValue);
                new AlertDialog.Builder(MainActivity.this).setMessage(message).setView(input)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm(input.getText().toString()))
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                if (fileChooserCallback != null) fileChooserCallback.onReceiveValue(null);
                fileChooserCallback = callback;
                try {
                    Intent intent = params.createIntent();
                    startActivityForResult(intent, REQUEST_FILE_PICKER);
                    return true;
                } catch (Exception e) {
                    fileChooserCallback = null;
                    Toast.makeText(MainActivity.this, "无法打开文件选择器：" + e.getMessage(),
                            Toast.LENGTH_LONG).show();
                    return false;
                }
            }
        });
        webView.setWebViewClient(new WebViewClientCompat() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return loader.shouldInterceptRequest(request.getUrl());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                return !"https".equals(uri.getScheme())
                        || !"appassets.androidplatform.net".equals(uri.getHost());
            }
        });
        root.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        checkRoot(rootStatus, false);
        webView.loadUrl("https://appassets.androidplatform.net/assets/webroot/index.html");
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_FILE_PICKER && fileChooserCallback != null) {
            Uri[] results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
            fileChooserCallback.onReceiveValue(results);
            fileChooserCallback = null;
        }
    }

    @Override public void onBackPressed() {
        if (hookUiVisible) { showWebDashboard(); return; }
        if (webView != null && webView.canGoBack()) { webView.goBack(); return; }
        super.onBackPressed();
    }

    public void showAppListFromBridge() { showAppList(); }

    private void dashboardItem(String name, String detail, Runnable action) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(18), dp(12), dp(18), dp(12));
        row.setBackgroundColor(0xffffffff);
        TextView title = new TextView(this);
        title.setText(name);
        title.setTextSize(16);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xff17212b);
        TextView sub = new TextView(this);
        sub.setText(detail);
        sub.setTextSize(12);
        sub.setTextColor(0xff697681);
        row.addView(title);
        row.addView(sub);
        row.setOnClickListener(v -> action.run());
        content.addView(row, new LinearLayout.LayoutParams(-1, -2));
        View divider = new View(this);
        divider.setBackgroundColor(0xffe8ebee);
        content.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
    }

    private void showMigrationNotice(String feature) {
        new AlertDialog.Builder(this)
            .setTitle(feature)
            .setMessage("该功能正在从模块 WebUI 迁移到 FX 原生 APP。当前版本尚未完成此功能的原生控制界面与底层接口，不会伪装成已可用。")
            .setPositiveButton("返回", null)
            .show();
    }

    private void checkRoot(TextView state, boolean request) {
        state.setText(request ? "正在请求 KernelSU 授权…" : "正在检查 Root…");
        new Thread(() -> {
            RootAccess.Result result = RootAccess.execute("id -u; test -d /data/adb/modules && echo FX_MODULES_DIR=present || echo FX_MODULES_DIR=missing; (command -v ksud >/dev/null 2>&1 || test -x /data/adb/ksu/bin/ksud) && echo KSU_DAEMON=present || echo KSU_DAEMON=not-found");
            runOnUiThread(() -> {
                if (result.exitCode == 0 && result.output.trim().startsWith("0")) {
                    state.setText("已获得 Root（UID 0）\n" + result.output.trim());
                } else if (result.denied) {
                    state.setText("尚未获得 Root 授权。请在 KernelSU 管理器中允许 FX Hook。");
                } else {
                    state.setText("Root 不可用或请求失败：\n" + result.output);
                }
            });
        }, "fx-root-check").start();
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
        content.addView(title("FX", 25));
        TextView h = title(heading, 18); h.setPadding(dp(18), dp(2), dp(18), dp(12)); content.addView(h);
        scroll.addView(content); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root); this.content = content;
    }
    private LinearLayout content;
    private void showAppList() {
        hookUiVisible = true;
        selectedPackage = null; base("选择应用");
        Button home = new Button(this); home.setText("返回 FX 控制中心"); home.setOnClickListener(v -> showWebDashboard()); content.addView(home);
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
        while (content.getChildCount() > 4) content.removeViewAt(4);
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
        custom.setText("自定义规则仅支持观察目标应用自身的方法调用，不修改返回值、登录状态或会员资格。");
        custom.setTextColor(0xff697681); custom.setPadding(dp(18),dp(4),dp(18),dp(8)); content.addView(custom);
        Button addRule=new Button(this); addRule.setText("添加只读观察规则");
        addRule.setOnClickListener(v->showCustomRuleDialog()); content.addView(addRule);
        renderCustomRules();
        Button save=new Button(this); save.setText("保存并同步到 LSPosed");
        save.setOnClickListener(v -> {
            getPreferences(0).edit().putBoolean(key("draft_saved"),true).apply();
            publishConfig();
        });
        content.addView(save,new LinearLayout.LayoutParams(-1,-2));
        Button back=new Button(this); back.setText("返回应用列表"); back.setOnClickListener(v->showAppList());
        content.addView(back,new LinearLayout.LayoutParams(-1,-2));
    }
 

    private void showCustomRuleDialog() {
        LinearLayout form=new LinearLayout(this); form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20),dp(8),dp(20),0);
        EditText id=new EditText(this); id.setSingleLine(true); id.setHint("规则 ID，例如 observe1");
        EditText descriptor=new EditText(this); descriptor.setSingleLine(true);
        descriptor.setHint("类名#方法()Z 或 L类路径;->方法()返回类型");
        form.addView(id); form.addView(descriptor);
        new AlertDialog.Builder(this).setTitle("新增只读 Hook 规则").setView(form)
            .setNegativeButton("取消",null).setPositiveButton("保存",(d,w)->{
                String ruleId=id.getText().toString().trim();
                String method=descriptor.getText().toString().trim();
                DeveloperHookRule rule=DeveloperHookRule.parse(ruleId+"|"+method+"|OBSERVE|0",selectedPackage);
                if(rule==null) {
                    new AlertDialog.Builder(this).setMessage("规则无效：方法必须属于当前应用包名下的类，且描述符格式正确。")
                        .setPositiveButton("知道了",null).show(); return;
                }
                for(int n=1;n<=64;n++) {
                    String existing=getPreferences(0).getString(selectedPackage+":dev_rule_"+n,null);
                    if(existing!=null && existing.startsWith(rule.id+"|")) {
                        new AlertDialog.Builder(this).setMessage("规则 ID 已存在，请换一个 ID。")
                            .setPositiveButton("知道了",null).show(); return;
                    }
                }
                int slot=1;
                while(slot<=64 && getPreferences(0).contains(selectedPackage+":dev_rule_"+slot)) slot++;
                if(slot>64) {
                    new AlertDialog.Builder(this).setMessage("每个应用最多配置 64 条自定义规则。").setPositiveButton("知道了",null).show(); return;
                }
                getPreferences(0).edit().putString(selectedPackage+":dev_rule_"+slot,
                    rule.id+"|"+rule.descriptor+"|OBSERVE|0").putBoolean(selectedPackage+":dev_hook_enabled",true).apply();
                showTarget(findApp(selectedPackage));
            }).show();
    }

    private ApplicationInfo findApp(String pkg) {
        for(ApplicationInfo ai:apps) if(ai.packageName.equals(pkg)) return ai;
        return null;
    }

    private void renderCustomRules() {
        for(int i=1;i<=64;i++) {
            String value=getPreferences(0).getString(selectedPackage+":dev_rule_"+i,null);
            if(value==null) continue;
            TextView item=new TextView(this); item.setText(value); item.setTextSize(12);
            item.setTextColor(0xff596775); item.setPadding(dp(18),dp(6),dp(18),dp(6));
            content.addView(item);
            Button remove=new Button(this); remove.setText("删除 "+value.substring(0,value.indexOf('|')));
            final int slot=i; remove.setOnClickListener(v->{
                getPreferences(0).edit().remove(selectedPackage+":dev_rule_"+slot).apply();
                ApplicationInfo ai=findApp(selectedPackage); if(ai!=null) showTarget(ai);
            });
            content.addView(remove);
        }
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
                boolean customEnabled=false;
                for(int n=1;n<=64;n++) {
                    String rule=getPreferences(0).getString(p+":dev_rule_"+n,null);
                    if(rule!=null) {
                        if(!customEnabled) { row.append(",dev_hook_enabled=1"); customEnabled=true; }
                        row.append(",dev_rule_").append(n).append('=').append(rule);
                        has=true;
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
            String temp=remote+".tmp";
            String command="mkdir -p "+moduleDir+" && echo "+encoded+" | base64 -d > "+temp+" && chmod 600 "+temp+" && mv "+temp+" "+remote;
            new Thread(() -> {
                RootAccess.Result result = RootAccess.execute(command);
                runOnUiThread(() -> {
                    if(result.exitCode==0) {
                        new AlertDialog.Builder(this).setMessage("配置已写入 LSPosed Remote Files。请确认 LSPosed Manager 已将 FX Hook 作用域包含目标应用，并强制停止后重新打开目标应用。")
                            .setPositiveButton("知道了",null).show();
                    } else {
                        new AlertDialog.Builder(this).setMessage("Root 发布失败（退出码 "+result.exitCode+"）。"+result.output+"请确认 KernelSU 已授予 FX Hook Root 权限。配置仍保存在本机草稿。")
                            .setPositiveButton("知道了",null).show();
                    }
                });
            }, "fx-config-publisher").start();
        } catch(Exception e) {
            new AlertDialog.Builder(this).setMessage("配置同步失败："+e.getClass().getSimpleName()+"。本机草稿仍已保存。")
                .setPositiveButton("知道了",null).show();
        }
    }

    private void section(String s) {
        TextView t=title(s,16); t.setBackgroundColor(0xffe9eef3); content.addView(t,new LinearLayout.LayoutParams(-1,-2));
    }
    private void toggle(String label,String feature,boolean def) {
        Switch sw=new Switch(this); sw.setText(label); sw.setTextSize(15); sw.setPadding(dp(18),dp(12),dp(18),dp(12));
        sw.setBackgroundColor(0xffffffff); sw.setChecked(getPreferences(0).getBoolean(key(feature),def));
        sw.setOnCheckedChangeListener((b,on)->getPreferences(0).edit().putBoolean(key(feature),on).apply());
        content.addView(sw,new LinearLayout.LayoutParams(-1,-2));
    }
}