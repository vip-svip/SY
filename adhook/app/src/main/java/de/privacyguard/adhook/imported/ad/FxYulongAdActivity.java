package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputFilter;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Native control screens for migrated Yulong AdBlock 7.0.1. */
public final class FxYulongAdActivity extends de.privacyguard.adhook.FxNativeTabActivity {
 private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
         TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
         r -> new Thread(r, "fx-yulong-ad-ui"), new ThreadPoolExecutor.AbortPolicy());
 private LinearLayout body,entries; private TextView status; private EditText search,domainSearch;
 private ScrollView pageScroll;
 private int pendingPageScrollY;
 private boolean pendingPageScrollRestore;
 private String page="首页与防护",snapshot="";
 private long pageGeneration;
 private static final String STATE_PAGE="fx_yulong_ad_page";
 private static final String STATE_DRAFTS="fx_yulong_ad_drafts";
 private static final String STATE_SCROLL_Y="fx_yulong_ad_scroll_y";
 private final java.util.Map<String,EditText> draftFields=new java.util.LinkedHashMap<>();
  private LinearLayout proxyWhitelistRows;
  private TextView proxyWhitelistStatus;
  private EditText proxyWhitelistSearch;
  private final List<ApplicationInfo> proxyWhitelistApps=new ArrayList<>();
  private final Map<String,String> proxyWhitelistLabels=new HashMap<>();
  private final Set<String> proxyWhitelistSelected=new HashSet<>();
  private int proxyWhitelistPage=1;
  private long proxyWhitelistGeneration;
  private Switch trustedPauseSwitch;
  private LinearLayout trustedSsidRows;
  private TextView trustedNetworkStatus;
  private EditText trustedSsidInput;
  private String trustedCurrentSsid = "";
  private long trustedNetworkGeneration;
  private boolean trustedNetworkSyncing;
  private TextView rootProxyStatus;
  private long rootProxyStatusGeneration;
 private static final int DNS_PROFILE_OPEN_REQUEST=4202;
 private static final int DNS_PROFILE_SAVE_REQUEST=4203;
 private static final int DNS_PROFILE_SHARE_REQUEST=4204;
 private static final int DNS_DIAGNOSTIC_SAVE_REQUEST=4205;
 private String pendingDnsDiagnosticExport="";
 private EditText dnsProfileImportField;
 private String pendingDnsProfileExport="";
 private Bundle pendingRestoredDrafts;
 private Bundle retainedDrafts=new Bundle();
 private static final class Row {String kind,value,title;boolean enabled;Row(String k,String v,String t,boolean e){kind=k;value=v;title=t;enabled=e;}}
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView txt(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button btn(String s,Runnable r){Button b=new Button(this);b.setTag("fx-action-row");b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private EditText draftField(String key){
  EditText field=new EditText(this);
  field.setTag("fx-yulong-ad-draft:"+key);
  draftFields.put(key,field);
  return field;
 }
 private void restoreDrafts(Bundle saved){
  if(saved==null)return;
  for(java.util.Map.Entry<String,EditText> entry:draftFields.entrySet()){
   if(saved.containsKey(entry.getKey()))entry.getValue().setText(saved.getString(entry.getKey(),""));
  }
 }
 private void card(String title,String detail,View... views){LinearLayout p=new LinearLayout(this);p.setTag("fx-card");p.setOrientation(1);p.setPadding(dp(14),dp(10),dp(14),dp(10));p.setBackgroundColor(0xfff0f3f7);TextView heading=txt(title,15,0xff17212b,true);heading.setTag("fx-card-title");p.addView(heading);TextView description=txt(detail,12,0xff617080,false);description.setTag("fx-card-detail");p.addView(description);for(View v:views)p.addView(v);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(5),dp(12),dp(5));body.addView(p,lp);}
 private String q(String s){return "'"+(s==null?"":s.replace("'","'\\''"))+"'";}
 private String cmd(String args){
   return FxYulongRootModuleCommand.command("yulong-ad-control.sh", args);
  }
  private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){
  final long requestGeneration=pageGeneration;
  final String requestPage=page;
  Runnable task=()->{
   RootAccess.Result result=RootAccess.execute(cmd(args),90000L,Integer.MAX_VALUE);
   runOnUiThread(()->{
    if(isFinishing()||isDestroyed()||requestGeneration!=pageGeneration
       ||!requestPage.equals(page))return;
    if(cb!=null)cb.accept(result);
   });
  };
  try{
   worker.execute(task);
  }catch(RejectedExecutionException full){
   RootAccess.Result busy=RootAccess.failure(125,"后台任务繁忙，请稍后重试。");
   runOnUiThread(()->{
    if(isFinishing()||isDestroyed()||requestGeneration!=pageGeneration
       ||!requestPage.equals(page))return;
    status.setText("后台任务繁忙，请稍后重试。");
    if(cb!=null)cb.accept(busy);
   });
  }
 }
 private String safe(String s){return s==null||s.trim().isEmpty()?"请确认 FX Hook Root 权限。":s.trim();}
 private void apply(String args,String label){
  final long requestGeneration=pageGeneration;
  final String requestPage=page;
  final boolean masterWrite = args != null && args.matches("^ad-master\\s+[01]$");
  try{
   worker.execute(()->{
    long gateToken = 0L;
    RootAccess.Result result;
    try{
     if(masterWrite){
      gateToken=FxYulongAdOperationGate.tryAcquire();
      if(gateToken==0L){
       runOnUiThread(()->{if(!isFinishing()&&!isDestroyed()
        &&requestGeneration==pageGeneration&&requestPage.equals(page))
         status.setText("另一入口正在修改广告过滤，请稍后重试。");});
       return;
      }
     }
     result=RootAccess.execute(cmd(args),90000L,Integer.MAX_VALUE);
    }catch(Throwable failure){
     runOnUiThread(()->{if(!isFinishing()&&!isDestroyed()
        &&requestGeneration==pageGeneration&&requestPage.equals(page))
         status.setText(label+"失败："+failure.getClass().getSimpleName());});
     return;
    }finally{
     if(gateToken!=0L)FxYulongAdOperationGate.release(gateToken);
    }
    runOnUiThread(()->{
     if(isFinishing()||isDestroyed())return;
     boolean samePage=requestGeneration==pageGeneration&&requestPage.equals(page);
     if(result.exitCode==0)FxYulongAdWidgetProvider.refreshAll(this);
     if(samePage){
      if(result.exitCode==0){
       status.setText(label+"：已保存并应用。");
      }else{
       status.setText(label+"失败："+safe(result.output));
       fxDialogBuilder().setTitle("配置未应用").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
      }
     }
     load();
     if(samePage&&"VPN 与 Root Proxy".equals(page))refreshRootProxyStatus();
    });
   });
  }catch(RejectedExecutionException full){
   // The writer lock is acquired only inside the queued worker. A rejected
   // submission never acquired it, so releasing here could unlock another
   // entry point's in-flight operation.
   if(requestGeneration==pageGeneration&&requestPage.equals(page))
    status.setText("后台任务繁忙，请稍后重试。");
  }
 }
 @Override protected void onCreate(Bundle b){
  super.onCreate(b);
  if(b!=null){
   page=b.getString(STATE_PAGE,"首页与防护");
   pendingRestoredDrafts=b.getBundle(STATE_DRAFTS);
   if(pendingRestoredDrafts!=null)retainedDrafts=new Bundle(pendingRestoredDrafts);
   pendingPageScrollY=Math.max(0,b.getInt(STATE_SCROLL_Y,0));
   pendingPageScrollRestore=true;
  }else{
   page=getIntent().getStringExtra("suite_page");
   if(page==null)page="首页与防护";
  }
  LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xfff7f8fa);LinearLayout h=new LinearLayout(this);h.setGravity(Gravity.CENTER_VERTICAL);h.setPadding(dp(10),dp(6),dp(12),dp(6));h.addView(btn("‹ 返回 Ad",this::finish));TextView adTitle=txt("Ad · 广告过滤控制中心",18,0xff17212b,true);adTitle.setTag("fx-title:18");h.addView(adTitle,new LinearLayout.LayoutParams(0,-2,1));root.addView(h);pageScroll=new ScrollView(this);pageScroll.setFillViewport(true);body=new LinearLayout(this);body.setOrientation(1);body.setPadding(0,dp(4),0,dp(20));pageScroll.addView(body);root.addView(pageScroll,new LinearLayout.LayoutParams(-1,0,1));setContentViewWithNativeTabs(root, 1);render();restoreDrafts(pendingRestoredDrafts);pendingRestoredDrafts=null;load();}
 private Bundle captureDrafts(){
  Bundle drafts=new Bundle(retainedDrafts);
  for(java.util.Map.Entry<String,EditText> entry:draftFields.entrySet()){
   EditText field=entry.getValue();
   drafts.putString(entry.getKey(),field.getText()==null?"":field.getText().toString());
  }
  return drafts;
 }
 @Override protected void onSaveInstanceState(Bundle out){
  out.putString(STATE_PAGE,page);
  retainedDrafts=captureDrafts();
  out.putBundle(STATE_DRAFTS,retainedDrafts);
  if(pageScroll!=null)out.putInt(STATE_SCROLL_Y,Math.max(0,pageScroll.getScrollY()));
  super.onSaveInstanceState(out);
 }
 private void render(){pageGeneration++;trustedNetworkGeneration++;trustedPauseSwitch=null;trustedSsidRows=null;trustedNetworkStatus=null;rootProxyStatus=null;rootProxyStatusGeneration++;draftFields.clear();body.removeAllViews();status=txt("正在读取 FX 配置…",12,0xff526170,false);card("运行架构","游龙原版 AdBlockVpnService / RootProxyService 不会启动；过滤、DNS 和代理继续由 FX 单一网络入口处理。",btn("应用级网络拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));card("状态","设备端真实配置与应用结果",status);LinearLayout nav=new LinearLayout(this);nav.setTag("fx-card-group");nav.setOrientation(0);nav.addView(btn("首页",()->open("首页与防护")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("过滤",()->open("过滤列表")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("DNS",()->open("DNS 设置")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("名单",()->open("域名名单")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("计划",()->open("计划任务")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("配置档",()->open("保护配置档")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("可信",()->open("信任的网络")),new LinearLayout.LayoutParams(0,-2,1));body.addView(nav);TextView currentPage=txt("当前页面："+page,13,0xff617080,true);currentPage.setTag("fx-card-detail");body.addView(currentPage);if("过滤列表".equals(page))renderRules();else if("DNS 设置".equals(page))renderDns();else if("域名名单".equals(page))renderDomains();else if("信任的网络".equals(page))renderTrustedNetworks();else if("VPN 与 Root Proxy".equals(page)){
  rootProxyStatus=txt("正在读取 Root Proxy 实际运行状态…",12,0xff617080,false);
  card("FX 唯一 VPN/TUN","节点、直连/全局/规则由 FX 管理。游龙原版第二个 VpnService 不会启动。",
    dnsSwitch("允许第三方 VPN 下启用 FX Root DNS Proxy","vpn_external_dns_proxy"),
    dnsSwitch("第三方 VPN 兼容路由开关","vpn_external_compat"),
    rootProxyStatus,
    btn("刷新 Root Proxy 实际状态",this::refreshRootProxyStatus),
    btn("应用级网络拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));
  card("工作条件","仅当检测到唯一活动第三方 VPN、VPN 接口/所属 UID/出口路由可验证，Unbound 与 AdGuard Home 健康探测通过后才接管明文 DNS；任何验证失败都会撤销 FX 自有重定向规则并保留原 VPN DNS。配置开关已启用不代表 DNS 已接管，必须以此页的实际运行状态为准。");
renderRootProxyWhitelist();
refreshRootProxyStatus();}else if("计划任务".equals(page))renderSchedule();else if("保护配置档".equals(page))renderProfiles();else if("日志与诊断".equals(page))renderLogs();else renderHome();}

  private String profileCmd(String args) {
    return FxYulongRootModuleCommand.command("yulong-profiles.sh", args);
  }

  private boolean isTrustedNetworkPageCurrent(TextView target) {
    return target != null && target == trustedNetworkStatus
            && "信任的网络".equals(page) && !isFinishing() && !isDestroyed();
  }

  private void renderTrustedNetworks() {
    trustedPauseSwitch = new Switch(this);
     trustedPauseSwitch.setTag("fx-switch-row");
    trustedPauseSwitch.setText("连接可信 Wi-Fi 时自动暂停FX 广告过滤");
    trustedPauseSwitch.setTextSize(14);
    trustedPauseSwitch.setOnCheckedChangeListener((button, enabled) -> {
      if (trustedNetworkSyncing) return;
      root("trusted-pause-set " + (enabled ? "1" : "0"), result -> {
        if (!isTrustedNetworkPageCurrent(trustedNetworkStatus)) return;
        status.setText(result.exitCode == 0
                ? (enabled ? "可信网络自动暂停已启用。" : "可信网络自动暂停已关闭。")
                : "可信网络设置失败：" + safe(result.output));
        refreshTrustedNetworks();
      });
    });
    trustedNetworkStatus = txt("正在读取当前 Wi-Fi 和可信网络列表…",12,0xff617080,false);
     trustedNetworkStatus.setTag("fx-card-detail");
    trustedSsidInput = draftField("trusted_ssid");
    trustedSsidInput.setSingleLine(true);
    trustedSsidInput.setHint("输入 Wi-Fi SSID（最多 32 字节）");
    trustedSsidRows = new LinearLayout(this);
     trustedSsidRows.setTag("fx-card-group");
    trustedSsidRows.setOrientation(LinearLayout.VERTICAL);
    card("可信网络自动暂停",
        "仅当自动暂停已启用、当前 SSID 命中名单、游龙广告总开关开启且周计划处于活动时，才暂停游龙广告规则列表。退出可信网络后只恢复本功能自己暂停的门控；不会修改 FX Hosts、96110、VPN/TUN 或用户手动广告开关。",
        trustedPauseSwitch, trustedNetworkStatus,
        btn("读取当前状态并立即检测",this::refreshTrustedNetworks));
    card("可信 Wi-Fi SSID",
        "支持读取当前 SSID 或手动输入。名单保存在 root 私有文件中，不写入运行日志。",
        trustedSsidInput,
        btn("填入当前 Wi-Fi SSID",() -> {          if (trustedCurrentSsid == null || trustedCurrentSsid.isEmpty()) {
            status.setText("当前没有可读取的 Wi-Fi SSID；请手动输入。");
          } else {
            trustedSsidInput.setText(trustedCurrentSsid);
            trustedSsidInput.setSelection(trustedSsidInput.length());
          }
        }),
        btn("添加可信网络",this::addTrustedSsid));
    card("已保存的可信网络",
        "命中名单后只暂停游龙广告 [list:rule] 过滤源；Hosts 和 FX 96110 反诈规则继续工作。",
        trustedSsidRows);
    refreshTrustedNetworks();
  }

  private void refreshTrustedNetworks() {
    final TextView target = trustedNetworkStatus;
    if (!isTrustedNetworkPageCurrent(target)) return;
    final long generation = ++trustedNetworkGeneration;
    target.setText("正在读取当前 Wi-Fi 和可信网络状态…");
    root("trusted-refresh", result -> {
      if (!isTrustedNetworkPageCurrent(target) || generation != trustedNetworkGeneration) return;
      if (result.exitCode != 0) {
        target.setText("读取可信网络状态失败：" + safe(result.output));
        return;
      }
      String enabled="0", current="", matched="0", paused="0", gate="1", watcher="0";
      java.util.List<String> ssids = new java.util.ArrayList<>();
      for (String line : (result.output == null ? "" : result.output).split("\\r?\\n")) {
        if (line.startsWith("SSID|")) {
          String value = line.substring(5);
          if (!value.isEmpty() && value.length() <= 64) ssids.add(value);
          continue;
        }
        int at = line.indexOf('=');
        if (at <= 0) continue;
        String key=line.substring(0,at), value=line.substring(at+1);
        switch (key) {
          case "pause_enabled": enabled=value; break;
          case "current_ssid": current=value; break;
          case "trusted_match": matched=value; break;
          case "paused_by_trusted": paused=value; break;
          case "trusted_gate": gate=value; break;
          case "watcher": watcher=value; break;
        }
      }
      trustedCurrentSsid = current;
      trustedNetworkSyncing = true;
      if (trustedPauseSwitch != null) trustedPauseSwitch.setChecked("1".equals(enabled));
      trustedNetworkSyncing = false;
      StringBuilder detail = new StringBuilder();
      detail.append("当前 Wi-Fi：").append(current.isEmpty() ? "未连接或系统未提供 SSID" : current)
              .append("\n可信名单命中：").append("1".equals(matched) ? "是" : "否")
              .append("\n自动暂停：").append("1".equals(enabled) ? "已启用" : "已关闭")
              .append("  ·  watcher：").append("1".equals(watcher) ? "运行中" : "未运行")
              .append("\n游龙广告规则门控：").append("0".equals(gate) ? "已暂停" : "正常");
      if ("1".equals(paused)) detail.append("\n暂停来源：可信网络（FX 所有权标记）");
      target.setText(detail.toString());
      trustedSsidRows.removeAllViews();
      if (ssids.isEmpty()) trustedSsidRows.addView(txt("暂无可信 Wi-Fi。",12,0xff718091,false));
      else for (String ssid : ssids) {
        LinearLayout row = new LinearLayout(this);
        row.setTag("fx-list-row");
         row.setGravity(Gravity.CENTER_VERTICAL);
        TextView ssidLabel=txt(ssid,13,0xff17212b,true);ssidLabel.setTag("fx-list-title");row.addView(ssidLabel,new LinearLayout.LayoutParams(0,-2,1));
        row.addView(btn("移除",() -> removeTrustedSsid(ssid)));
        trustedSsidRows.addView(row);
      }
    });
  }

  private void addTrustedSsid() {
    String ssid = trustedSsidInput == null || trustedSsidInput.getText() == null
            ? "" : trustedSsidInput.getText().toString().trim();
    if (ssid.isEmpty()) { status.setText("请输入 SSID，或先读取当前 Wi-Fi。"); return; }
    root("trusted-ssid-add " + q(ssid), result -> {
      if (!isTrustedNetworkPageCurrent(trustedNetworkStatus)) return;
      if (result.exitCode != 0) status.setText("添加可信 Wi-Fi 失败：" + safe(result.output));
      else { status.setText("可信 Wi-Fi 已保存。"); trustedSsidInput.setText(""); }
      refreshTrustedNetworks();
    });
  }

  private void removeTrustedSsid(String ssid) {
    fxDialogBuilder().setTitle("移除可信 Wi-Fi")
            .setMessage("移除后，连接此 SSID 将不再自动暂停FX 广告过滤。")
            .setNegativeButton("取消",null)
            .setPositiveButton("移除",(dialog,which) -> root("trusted-ssid-remove " + q(ssid), result -> {
              if (!isTrustedNetworkPageCurrent(trustedNetworkStatus)) return;
              status.setText(result.exitCode == 0 ? "可信 Wi-Fi 已移除。" : "移除失败：" + safe(result.output));
              refreshTrustedNetworks();
            })).show();
  }

  private boolean isRootProxyStatusCurrent(TextView target) {
    return target != null && target == rootProxyStatus
            && "VPN 与 Root Proxy".equals(page)
            && !isFinishing() && !isDestroyed();
  }

  private void refreshRootProxyStatus() {
    final TextView target = rootProxyStatus;
    if (!isRootProxyStatusCurrent(target)) return;
    final long generation = ++rootProxyStatusGeneration;
    target.setText("正在读取 Root Proxy 实际状态…");
    root("rootproxy-status", result -> {
      if (!isRootProxyStatusCurrent(target) || generation != rootProxyStatusGeneration) return;
      if (result.exitCode != 0) {
        target.setText("Root Proxy 状态读取失败（退出码 " + result.exitCode + "）："
                + safe(result.output));
        return;
      }
      Map<String,String> values = new HashMap<>();
      String output = result.output == null ? "" : result.output;
      for (String line : output.split("\\r?\\n")) {
        int separator = line.indexOf('=');
        if (separator <= 0) continue;
        String key = line.substring(0, separator).trim();
        String value = line.substring(separator + 1).trim();
        if (key.matches("[a-z_]+")) values.put(key, value);
      }
      String enabled = values.getOrDefault("enabled", "unknown");
      String active = values.getOrDefault("active", "unknown");
      StringBuilder message = new StringBuilder();
      message.append("配置开关：")
              .append("1".equals(enabled) ? "已启用" : "0".equals(enabled) ? "已关闭" : "未知")
              .append("  ·  实际 DNS 接管：")
              .append("1".equals(active) ? "运行中" : "0".equals(active) ? "未运行" : "未知")
              .append("\\nDNS 例外应用：")
              .append(values.getOrDefault("whitelist_count", "0"));
      if ("1".equals(active)) {
        message.append("\\n活动接口：").append(values.getOrDefault("interface", "未知"))
                .append("  ·  VPN UID：").append(values.getOrDefault("vpn_uid", "未知"))
                .append("\\n已验证 DNS 出口：").append(values.getOrDefault("egress_ipv4", "未知"))
                .append("\\n激活时间：").append(values.getOrDefault("activated_at", "未知"));
      } else if ("1".equals(enabled)) {
        message.append("\\n配置已启用，但当前没有可验证的第三方 VPN DNS 接管路径；FX 保持 fail-open，不会抢占 VPN 或改写未验证的路由。");
      } else {
        message.append("\\n当前已关闭。启用后仍需通过 VPN 接口、所属 UID、出口路由和本地 DNS 健康检查才会接管。");
      }
      target.setText(message.toString());
    });
  }

   private void renderRootProxyWhitelist(){
   proxyWhitelistStatus=txt("正在读取 Root Proxy DNS 例外名单…",12,0xff617080,false);
   proxyWhitelistSearch=draftField("rootproxy_whitelist_search");
   proxyWhitelistSearch.setSingleLine(true);
   proxyWhitelistSearch.setHint("搜索应用名称或包名");
   proxyWhitelistRows=new LinearLayout(this);proxyWhitelistRows.setTag("fx-card-group");
   proxyWhitelistRows.setOrientation(1);
   card("应用 DNS 例外名单",
       "被选中的应用及共享同一 Android UID 的应用，其明文 DNS 不会被 FX Root Proxy 重定向；不改变应用 VPN 路由。卸载后保留包名，重装时重新解析新 UID。",
       proxyWhitelistStatus,proxyWhitelistSearch,
       btn("刷新应用名单",()->loadRootProxyWhitelist()));
   body.addView(proxyWhitelistRows);
   proxyWhitelistSearch.addTextChangedListener(new TextWatcher(){
    public void beforeTextChanged(CharSequence s,int st,int count,int after){}
    public void onTextChanged(CharSequence s,int st,int before,int count){proxyWhitelistPage=1;renderRootProxyWhitelistRows();}
    public void afterTextChanged(Editable e){}
   });
   loadRootProxyWhitelist();
  }
  private boolean isRootProxyPage(){
   return "VPN 与 Root Proxy".equals(page)&&proxyWhitelistRows!=null&&!isFinishing()&&!isDestroyed();
  }
  private void loadRootProxyWhitelist(){
   final long generation=++proxyWhitelistGeneration;
   if(proxyWhitelistStatus!=null)proxyWhitelistStatus.setText("正在读取保存的包名名单…");
   root("rootproxy-whitelist-list",result->{
    if(!isRootProxyPage()||generation!=proxyWhitelistGeneration)return;
    if(result.exitCode!=0){
     proxyWhitelistStatus.setText("读取 Root Proxy 名单失败："+safe(result.output));
     return;
    }
    Set<String> selected=new HashSet<>();
    for(String line:(result.output==null?"":result.output).split("\\r?\\n")){
     String[] p=line.split("\\|",-1);
     if(p.length==2&&"PACKAGE".equals(p[0])&&isPackageName(p[1]))selected.add(p[1]);
    }
    try{
     worker.execute(()->{
      List<ApplicationInfo> loaded=new ArrayList<>();
      Map<String,String> labels=new HashMap<>();
      Throwable failure=null;
      try{
       PackageManager pm=getPackageManager();
       loaded.addAll(pm.getInstalledApplications(0));
       loaded.removeIf(info->info.packageName==null||info.packageName.equals(getPackageName()));
       for(ApplicationInfo info:loaded){
        String label;
        try{label=String.valueOf(pm.getApplicationLabel(info));}
        catch(Throwable ignored){label=info.packageName;}
        labels.put(info.packageName,label);
       }
       loaded.sort(Comparator.comparing(info->
           labels.getOrDefault(info.packageName,info.packageName).toLowerCase(Locale.ROOT)));
      }catch(Throwable error){failure=error;}
      final Throwable loadFailure=failure;
      runOnUiThread(()->{
       if(!isRootProxyPage()||generation!=proxyWhitelistGeneration)return;
       if(loadFailure!=null){
        proxyWhitelistStatus.setText("读取已安装应用失败："+loadFailure.getClass().getSimpleName());
        return;
       }
       proxyWhitelistSelected.clear();
       proxyWhitelistSelected.addAll(selected);
       proxyWhitelistApps.clear();
       proxyWhitelistApps.addAll(loaded);
       proxyWhitelistLabels.clear();
       proxyWhitelistLabels.putAll(labels);
       int installedSelected=0;
       for(ApplicationInfo info:loaded)
        if(proxyWhitelistSelected.contains(info.packageName))installedSelected++;
       int retained=proxyWhitelistSelected.size()-installedSelected;
       proxyWhitelistStatus.setText("已读取 "+loaded.size()+" 个应用；已选 "+proxyWhitelistSelected.size()
           +" 个包名"+(retained>0?"，其中 "+retained+" 个当前未安装，保留到重装后":"")
           +"。这些应用只绕过 Root Proxy DNS 重定向，不会解除 VPN 路由。");
       proxyWhitelistPage=1;
       renderRootProxyWhitelistRows();
      });
     });
    }catch(RejectedExecutionException full){
     proxyWhitelistStatus.setText("后台任务繁忙，暂时无法读取应用名单。");
    }
   });
  }
  private boolean isPackageName(String value){
   return value!=null&&value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
  }
  private void renderRootProxyWhitelistRows(){
   if(!isRootProxyPage()||proxyWhitelistRows==null)return;
   proxyWhitelistRows.removeAllViews();
   String filter=proxyWhitelistSearch==null||proxyWhitelistSearch.getText()==null?""
       :proxyWhitelistSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
   int shown=0,matched=0,limit=Math.max(1,proxyWhitelistPage)*50;
   for(ApplicationInfo info:proxyWhitelistApps){
    String pkg=info.packageName,label=proxyWhitelistLabels.getOrDefault(pkg,pkg);
    if(!filter.isEmpty()&&!label.toLowerCase(Locale.ROOT).contains(filter)
        &&!pkg.toLowerCase(Locale.ROOT).contains(filter))continue;
    matched++;
    if(shown>=limit)continue;
    LinearLayout row=new LinearLayout(this);row.setTag("fx-list-row");
    row.setOrientation(1);
    row.setPadding(dp(8),dp(5),dp(8),dp(5));
    TextView appLabel=txt(label,13,0xff17212b,true);appLabel.setTag("fx-list-title");row.addView(appLabel);
    TextView packageIdentity=txt(pkg+" · UID "+info.uid,10,0xff718091,false);packageIdentity.setTag("fx-list-subtitle");row.addView(packageIdentity);
    Switch allow=new Switch(this);allow.setTag("fx-switch-row");
    allow.setText("DNS 不经过 Root Proxy");
    allow.setChecked(proxyWhitelistSelected.contains(pkg));
    final boolean[] suppress={false};    allow.setOnCheckedChangeListener((button,checked)->{
     if(suppress[0])return;
     button.setEnabled(false);
     root("rootproxy-whitelist-set "+q(pkg)+" "+(checked?"1":"0"),result->{
      button.setEnabled(true);
      if(result.exitCode==0){
       if(checked)proxyWhitelistSelected.add(pkg);else proxyWhitelistSelected.remove(pkg);
       proxyWhitelistStatus.setText((checked?"已加入":"已移出")+" Root Proxy DNS 例外名单："+pkg
           +"。代理未启动时会在下次验证成功后生效。");
       renderRootProxyWhitelistRows();
      }else{
       boolean saved=result.output!=null&&result.output.contains("saved=1");
       if(saved){
        if(checked)proxyWhitelistSelected.add(pkg);else proxyWhitelistSelected.remove(pkg);
       }else{
        suppress[0]=true;
        button.setChecked(!checked);
        suppress[0]=false;
       }
       proxyWhitelistStatus.setText(saved
           ?"包名已保存，但 Root Proxy 重新验证失败；代理已 fail-open，不会使用旧 UID。下次启动/包事件会重新核对。"
           :"白名单修改失败："+safe(result.output));
       if(saved)renderRootProxyWhitelistRows();
      }
     });
    });
    row.addView(allow);
    proxyWhitelistRows.addView(row);
    shown++;
   }
   if(shown==0)proxyWhitelistRows.addView(txt("没有匹配的已安装应用。",12,0xff718091,false));
   if(matched>limit)proxyWhitelistRows.addView(btn("加载更多（剩余 "+(matched-limit)+" 个）",()->{
    proxyWhitelistPage++;renderRootProxyWhitelistRows();
   }));
   if(!proxyWhitelistSelected.isEmpty()){
    Set<String> missing=new HashSet<>(proxyWhitelistSelected);
    for(ApplicationInfo info:proxyWhitelistApps)missing.remove(info.packageName);
    for(String pkg:missing){
     LinearLayout row=new LinearLayout(this);row.setTag("fx-list-row");
     row.setOrientation(1);
     TextView missingTitle=txt("未安装的已保存包名",12,0xff718091,true);missingTitle.setTag("fx-list-title");row.addView(missingTitle);
     TextView missingPackage=txt(pkg,11,0xff718091,false);missingPackage.setTag("fx-list-subtitle");row.addView(missingPackage);
     row.addView(btn("移除已保存例外",()->root("rootproxy-whitelist-set "+q(pkg)+" 0",result->{
      if(result.exitCode==0)loadRootProxyWhitelist();
      else proxyWhitelistStatus.setText("移除失败："+safe(result.output));
     })));
     proxyWhitelistRows.addView(row);
    }
   }
  }
  private void renderHome(){
  Switch master=new Switch(this);master.setText("广告过滤主开关状态未知（暂不可切换）");master.setTag("ad-master");master.setEnabled(false);
  master.setOnCheckedChangeListener((b,on)->{if(!syncing)apply("ad-master "+(on?"1":"0"),"广告过滤主开关");});
  card("广告过滤","总开关只控制 FX [list:rule] 中的过滤来源；白名单、黑名单、反诈规则和 VPN 路由保持独立。",master,btn("管理过滤列表",()->open("过滤列表")));
  card("DNS 设置","管理本地 AdGuard Home、DNS 转发与 QUIC/DoT 策略。",btn("DNS 设置",()->open("DNS 设置")));
  card("域名白/黑名单","白名单优先放行；黑名单只阻断明确域名。",btn("域名名单",()->open("域名名单")));
  card("应用网络拦截","与 VPN 路由分离的 IPv4/IPv6 OUTPUT 阻断。",btn("按应用管理",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));
  card("Tasker 与自动化","发送启用/停用广播，接收端会向系统广播成功状态、退出码和请求来源，不包含其他应用数据。",
    btn("复制启用 Action",()->copyAutomationAction("de.privacyguard.adhook.AD_FILTER_ENABLE")),
    btn("复制停用 Action",()->copyAutomationAction("de.privacyguard.adhook.AD_FILTER_DISABLE")),
    btn("复制结果 Action",()->copyAutomationAction("de.privacyguard.adhook.AD_FILTER_RESULT")),
    btn("复制原版 Tasker 启用 Action",()->copyAutomationAction("app.pwhs.blockads.TASKER_START")),
    btn("复制原版 Tasker 停用 Action",()->copyAutomationAction("app.pwhs.blockads.TASKER_STOP")));
}
 private void setFilteredRules(boolean enabled){
  String filter=search==null||search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);
  java.util.LinkedHashSet<String> sources=new java.util.LinkedHashSet<>();
  for(Row row:rows("RULE")){
   if(filter.isEmpty()||(row.value+" "+row.title).toLowerCase(Locale.ROOT).contains(filter))sources.add(row.value);
  }
  if(sources.isEmpty()){status.setText("当前筛选没有可批量更新的过滤列表。");return;}
  StringBuilder lines=new StringBuilder();
  for(String source:sources)lines.append(source).append('\n');
  String encoded=android.util.Base64.encodeToString(lines.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8),android.util.Base64.NO_WRAP);
  String action=enabled?"启用":"暂停";
  fxDialogBuilder().setTitle(action+"当前筛选列表")
    .setMessage("将"+action+"当前搜索筛选命中的 "+sources.size()+" 个过滤列表。此操作不修改订阅地址或列表名称，并作为一个配置事务提交。是否继续？")
    .setNegativeButton("取消",null)
    .setPositiveButton(action,(d,w)->apply("rule-set-many "+(enabled?"1":"0")+" "+encoded,"批量"+action+"过滤列表"))
    .show();
 }
 private void renameRule(Row rule){
   EditText name=new EditText(this);
   name.setSingleLine(true);
   name.setText(rule.title==null?"":rule.title);
   name.setSelection(name.length());
   name.setHint("过滤列表名称");
   fxDialogBuilder().setTitle("重命名过滤列表")
     .setMessage(rule.value)
     .setView(name)
     .setNegativeButton("取消",null)
     .setPositiveButton("保存",(d,w)->{
      String value=name.getText()==null?"":name.getText().toString().trim();
      if(value.isEmpty()){status.setText("过滤列表名称不能为空。");return;}
      apply("rule-rename "+q(rule.value)+" "+q(value),"过滤列表重命名");
     }).show();
  }
 private void removeFilteredRules(){
   String filter=search==null||search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);
   java.util.LinkedHashSet<String> sources=new java.util.LinkedHashSet<>();
   for(Row row:rows("RULE")){
    if(filter.isEmpty()||(row.value+" "+row.title).toLowerCase(Locale.ROOT).contains(filter))sources.add(row.value);
   }
   if(sources.isEmpty()){status.setText("当前筛选没有可移除的过滤列表。");return;}
   StringBuilder lines=new StringBuilder();
   for(String source:sources)lines.append(source).append('\n');
   String encoded=android.util.Base64.encodeToString(lines.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8),android.util.Base64.NO_WRAP);
   fxDialogBuilder().setTitle("移除当前筛选列表")
     .setMessage("将永久移除当前搜索筛选命中的 "+sources.size()+" 个过滤订阅来源及其启用状态。不会删除其他列表、DNS 上游或域名白/黑名单。此操作无法自动恢复，建议先分享订阅清单备份。是否继续？")
     .setNegativeButton("取消",null)
     .setPositiveButton("移除",(d,w)->apply("rule-remove-many "+encoded,"批量移除过滤列表"))
     .show();
  }
  private void shareRuleSubscriptions(){
   List<Row> configured=rows("RULE");
   if(configured.isEmpty()){status.setText("当前没有已配置的过滤订阅可导出。");return;}
   StringBuilder payload=new StringBuilder();
   payload.append("# FX Ad filter subscription export\n")
       .append("# format: source|name\n")
       .append("# importing adds sources enabled by default\n");
   int included=0;
   for(Row row:configured){
    String source=row.value==null?"":row.value.trim();
    String name=row.title==null?"":row.title.trim();
    if(source.isEmpty())continue;
    String line=source.replace('|',' ').replace('\r',' ').replace('\n',' ')
        +"|"+name.replace('|',' ').replace('\r',' ').replace('\n',' ')+"\n";
    payload.append(line);included++;
   }
   if(included==0){status.setText("没有可导出的有效过滤订阅。");return;}
   try{
    Intent send=new Intent(Intent.ACTION_SEND);send.setType("text/plain");
    send.putExtra(Intent.EXTRA_SUBJECT,"FX Ad 过滤订阅备份");
    send.putExtra(Intent.EXTRA_TEXT,payload.toString());
    startActivity(Intent.createChooser(send,"分享过滤订阅"));
    status.setText("已准备分享 "+included+" 个过滤订阅。");
   }catch(RuntimeException unavailable){status.setText("无法打开系统分享面板："+safe(unavailable.getMessage()));}
  }
  private void importRuleSubscriptions(EditText input){
  String raw=input==null||input.getText()==null?"":input.getText().toString();
  java.util.LinkedHashMap<String,String> parsed=new java.util.LinkedHashMap<>();
  for(String line:raw.split("\\r?\\n")){
   String row=line.trim();if(row.isEmpty()||row.startsWith("#"))continue;
   int split=row.indexOf('|');
   if(split<=0||split==row.length()-1||row.indexOf('|',split+1)>=0){status.setText("格式错误：每行使用 HTTPS或builtin来源|列表名称。");return;}
   String source=row.substring(0,split).trim(),name=row.substring(split+1).trim();
   if(parsed.put(source,name)!=null){status.setText("存在重复来源："+source);return;}
  }
  if(parsed.isEmpty()){status.setText("没有可导入的过滤列表。");return;}
  StringBuilder normalized=new StringBuilder();
  for(java.util.Map.Entry<String,String> entry:parsed.entrySet())normalized.append(entry.getKey()).append('|').append(entry.getValue()).append('\n');
  byte[] bytes=normalized.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  fxDialogBuilder().setTitle("批量导入过滤列表")
   .setMessage("将新增 "+parsed.size()+" 个过滤订阅，导入条目默认启用。已存在的来源会被拒绝，不会覆盖现有名称或状态。是否继续？")
   .setNegativeButton("取消",null)
   .setPositiveButton("导入",(d,w)->apply("rule-add-many "+encoded,"批量导入过滤列表"))
   .show();
 }
 private void renderRules(){EditText url=draftField("rule_url");url.setSingleLine(true);url.setHint("https://… 或 builtin://…");EditText name=draftField("rule_name");name.setSingleLine(true);name.setHint("列表名称");card("添加过滤列表","仅允许 HTTPS 订阅及 FX 本地资源。",url,name,btn("添加并应用",()->{String u=url.getText().toString().trim(),n=name.getText().toString().trim();if(!u.isEmpty()&&!n.isEmpty())apply("rule-add "+q(u)+" "+q(n)+" 1","规则添加");}));EditText ruleImport=draftField("rule_import_text");ruleImport.setSingleLine(false);ruleImport.setMinLines(4);ruleImport.setHint("每行：HTTPS或builtin来源|列表名称");card("批量导入过滤列表","支持多行来源|名称；空行和 # 注释行忽略。新订阅默认启用，已存在来源不会被覆盖。",ruleImport,btn("批量导入",()->importRuleSubscriptions(ruleImport)),btn("分享全部过滤订阅",()->shareRuleSubscriptions()));search=draftField("rule_search");search.setSingleLine(true);search.setHint("搜索过滤列表");card("搜索","输入来源或列表名称",search,btn("启用当前筛选全部列表",()->setFilteredRules(true)),btn("暂停当前筛选全部列表",()->setFilteredRules(false)),btn("移除当前筛选全部列表",()->removeFilteredRules()));search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int be,int co){bind();}public void afterTextChanged(Editable e){}});entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
 private static boolean isValidDnsQueryLogRetention(String value){
  if(value==null)return false;
  String normalized=value.trim().toLowerCase(java.util.Locale.ROOT);
  boolean days=normalized.endsWith("d");
  boolean hours=normalized.endsWith("h");
  if(!days&&!hours)return false;
  String number=normalized.substring(0,normalized.length()-1);
  if(!number.matches("[0-9]+"))return false;
  try{
   java.math.BigInteger amount=new java.math.BigInteger(number);
   java.math.BigInteger maximum=new java.math.BigInteger(days?"365":"8760");
   return amount.signum()>0&&amount.compareTo(maximum)<=0;
  }catch(NumberFormatException invalid){return false;}
 }
 private void saveDnsQueryLogRetention(String value){
  root("dns-querylog-retention-set "+q(value),result->{
    if(result.exitCode==0)status.setText("DNS 查询日志轮转周期已更新为 "+value+"；有效范围为 1 小时至 8760 小时。请留意本地存储空间。");
    else fxDialogBuilder().setTitle("保留期限未更新").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
  });
 }
 private void promptDnsQueryLogRetentionDuration(String currentValue){
  EditText duration=new EditText(this);
  duration.setSingleLine(true);
  duration.setInputType(android.text.InputType.TYPE_CLASS_TEXT
      |android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
  duration.setHint("例如 12h、90d（范围 1h–8760h）");
  duration.setText(isValidDnsQueryLogRetention(currentValue)?currentValue:"7d");
  fxDialogBuilder().setTitle("自定义 DNS 查询日志轮转周期")
    .setMessage("使用 h 表示小时、d 表示天。允许范围为 1h 至 8760h（最长 365d）。")
    .setView(duration)
    .setNegativeButton("取消",null)
    .setPositiveButton("保存",(dialog,which)->{
      String value=duration.getText()==null?""
          :duration.getText().toString().trim().toLowerCase(java.util.Locale.ROOT);
      if(!isValidDnsQueryLogRetention(value)){
        status.setText("轮转周期须为 1h–8760h 或 1d–365d 的正整数时长，未修改配置。");
        return;
      }
      saveDnsQueryLogRetention(value);
    }).show();
 }
 private static boolean isValidDnsQueryLogMemorySize(String value){
  return value!=null&&value.matches("[0-9]+");
 }
 private void chooseDnsQueryLogMemorySize(){
  root("dns-querylog-runtime-get",current->{
    if(current.exitCode!=0){status.setText("读取查询日志缓冲设置失败："+safe(current.output));return;}
    String raw=current.output==null?"":current.output.trim();
    String[] lines=raw.split("\\r?\\n");
    if(lines.length<3||!"FXYULONGDNSQUERYLOG1".equals(lines[0].trim())){
      status.setText("查询日志缓冲响应格式错误，拒绝使用默认上限。");
      return;
    }
    java.util.Map<String,String> values=new java.util.HashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||split==line.length()-1){
        status.setText("查询日志缓冲响应字段格式错误。");return;
      }
      String key=line.substring(0,split);
      if(!"memory_size".equals(key)&&!"memory_max".equals(key)){
        status.setText("查询日志缓冲响应包含未知字段："+key);return;
      }
      if(values.put(key,line.substring(split+1))!=null){
        status.setText("查询日志缓冲响应包含重复字段："+key);return;
      }
    }
    String currentSize=values.get("memory_size"),maximum=values.get("memory_max");
    if(!isValidDnsQueryLogMemorySize(currentSize)||!isValidDnsQueryLogMemorySize(maximum)){
      status.setText("设备内存上限或当前缓冲值不可用；未应用固定回退值。");
      return;
    }
    java.math.BigInteger maximumValue=new java.math.BigInteger(maximum);
    java.math.BigInteger currentValue=new java.math.BigInteger(currentSize);
    EditText input=new EditText(this);
    input.setSingleLine(true);
    input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
    input.setHint("0 表示每条记录立即写盘；本机动态上限 "+maximum);
    input.setText(currentSize);
    String detail="达到指定记录数后，AdGuard Home 会把缓冲记录写入本地文件。0 表示每条记录立即写盘；较大批量可减少写入频率，但日志页看到新记录的延迟会增加。当前设备动态上限："+maximum+"。";
    if(currentValue.compareTo(maximumValue)>0){
      detail+="\n当前保存值已超过本次读取的设备上限；请调低后保存。";
    }
    fxDialogBuilder().setTitle("DNS 查询日志内存刷盘批量")
      .setMessage(detail)
      .setView(input)
      .setNegativeButton("取消",null)
      .setPositiveButton("保存",(dialog,which)->{
        String value=input.getText()==null?"":input.getText().toString().trim();
        if(!isValidDnsQueryLogMemorySize(value)){
          status.setText("缓冲批量必须为非负整数，未修改。");return;
        }
        try{
          java.math.BigInteger amount=new java.math.BigInteger(value);
          if(amount.compareTo(maximumValue)>0){
            status.setText("缓冲批量超过本机内存安全范围（"+maximum+"），未修改。");return;
          }
        }catch(NumberFormatException invalid){
          status.setText("缓冲批量格式无效，未修改。");return;
        }
        root("dns-querylog-runtime-set "+q(value),result->{
          if(result.exitCode==0)status.setText("DNS 查询日志内存刷盘批量已更新为 "+value+"。0 表示每条记录立即写盘。");
          else fxDialogBuilder().setTitle("缓冲批量未更新").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
        });
      }).show();
  });
 }
 private String normalizeDnsStatisticsDomains(String raw,boolean rejectDuplicates){
  java.util.LinkedHashSet<String> domains=new java.util.LinkedHashSet<>();
  String supplied=raw==null?"":raw;
  for(String token:supplied.split("[,\\r\\n]",-1)){
   String domain=token.trim().toLowerCase(java.util.Locale.ROOT);
   if(domain.isEmpty())continue;
   if(domain.length()>253||domain.startsWith(".")||domain.endsWith(".")||domain.contains("..")
       ||!domain.matches("[a-z0-9.-]+")){
    throw new IllegalArgumentException("域名格式无效："+domain);
   }
   for(String label:domain.split("\\.",-1)){
    if(label.isEmpty()||label.length()>63
        ||!label.matches("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")){
     throw new IllegalArgumentException("域名标签格式无效："+domain);
    }
   }
   if(!domains.add(domain)&&rejectDuplicates){
    throw new IllegalArgumentException("域名重复："+domain);
   }
  }
  return android.text.TextUtils.join(",",domains);
 }
  private boolean isValidDnsRewriteIpv4(String value){
  if(value==null||!value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}"))return false;
  for(String part:value.split("\\.")){
   try{
    if(part.length()>1&&part.startsWith("0"))return false;
    if(Integer.parseInt(part)>255)return false;
   }catch(NumberFormatException invalid){return false;}
  }
  return true;
 }
 private boolean isValidDnsRewriteIpv6(String value){
  if(value==null||!value.matches("[0-9A-Fa-f:]+")||!value.contains(":")||value.contains(":::"))return false;
  try{
   return java.net.InetAddress.getByName(value) instanceof java.net.Inet6Address;
  }catch(Exception invalid){return false;}
 }
 private String normalizeDnsRewriteSource(String raw){
  String source=raw==null?"":raw.trim().toLowerCase(java.util.Locale.ROOT);
  if(source.startsWith("*.")){
   String suffix=normalizeDnsStatisticsDomains(source.substring(2),true);
   if(source.length()>253||suffix.contains("*"))
    throw new IllegalArgumentException("通配重写仅支持 *.example.com 格式："+source);
   return "*."+suffix;
  }
  if(source.contains("*"))
   throw new IllegalArgumentException("通配符只能出现在域名前缀 *. ："+source);
  return normalizeDnsStatisticsDomains(source,true);
 }
 private String normalizeDnsRewrites(String raw){
  java.util.LinkedHashMap<String,String> rewrites=new java.util.LinkedHashMap<>();
  String supplied=raw==null?"":raw;
  for(String token:supplied.split("[,\\r\\n]",-1)){
   String row=token.trim();
   if(row.isEmpty()||row.startsWith("#"))continue;
   String[] pair=row.split("\\|",-1);
   if((pair.length!=2&&pair.length!=3)||pair[0].trim().isEmpty()||pair[1].trim().isEmpty())
    throw new IllegalArgumentException("每行必须使用 source.example|answer 或 source.example|answer|1/0。");
   String domain=normalizeDnsRewriteSource(pair[0]);
   if(domain.matches("[0-9.]+"))
    throw new IllegalArgumentException("重写源必须是域名，不能是 IP 地址："+domain);
   String answer=pair[1].trim();
   if("A".equalsIgnoreCase(answer)||"AAAA".equalsIgnoreCase(answer)){
    answer=answer.toUpperCase(java.util.Locale.ROOT);
   }else if(answer.matches("[0-9.]+")){
    if(!isValidDnsRewriteIpv4(answer))
     throw new IllegalArgumentException("DNS 重写 IPv4 地址无效："+answer);
   }else if(answer.contains(":")){
    if(!isValidDnsRewriteIpv6(answer))
     throw new IllegalArgumentException("DNS 重写 IPv6 地址无效："+answer);
    answer=answer.toLowerCase(java.util.Locale.ROOT);
   }else{
    answer=normalizeDnsStatisticsDomains(answer,true);
   }
   String enabled=pair.length==2?"1":pair[2].trim();
   if(!"0".equals(enabled)&&!"1".equals(enabled))
    throw new IllegalArgumentException("DNS 重写启用状态只能是 1（启用）或 0（停用）："+domain);
   if(rewrites.containsKey(domain))
    throw new IllegalArgumentException("DNS 重写源域名重复："+domain);
   rewrites.put(domain,answer+"|"+enabled);
  }
  java.util.ArrayList<String> rows=new java.util.ArrayList<>();
  for(java.util.Map.Entry<String,String> entry:rewrites.entrySet())
   rows.add(entry.getKey()+"|"+entry.getValue());
  return android.text.TextUtils.join(",",rows);
 }
 private void chooseDnsRewrites(){
  root("dns-rewrites-get",current->{
   if(current.exitCode!=0){
    status.setText("读取 DNS 域名重写配置失败："+safe(current.output));return;
   }
   String[] lines=(current.output==null?"":current.output.trim()).split("\\r?\\n");
   if(lines.length<1||(!"FXYULONGDNSRW1".equals(lines[0].trim())&&
       !"FXYULONGDNSRW2".equals(lines[0].trim()))){
    status.setText("DNS 域名重写响应格式错误。");return;
   }
   StringBuilder raw=new StringBuilder();
   for(int i=1;i<lines.length;i++){
    String line=lines[i].trim();
    if(line.isEmpty())continue;
    if(raw.length()>0)raw.append('\n');
    raw.append(line);
   }
   String normalized;
   try{
    normalized=normalizeDnsRewrites(raw.toString());
   }catch(IllegalArgumentException invalid){
    status.setText("当前 DNS 重写配置异常："+invalid.getMessage());return;
   }
   EditText input=new EditText(this);
   input.setSingleLine(false);
   input.setMinLines(5);
   input.setGravity(android.view.Gravity.TOP|android.view.Gravity.START);
   input.setHint("每行一条：域名或 *.example.com|IPv4/IPv6/CNAME/A/AAAA|1启用/0停用；旧两列默认启用");
   input.setText(normalized.replace(",", "\n"));
   fxDialogBuilder().setTitle("DNS 域名重写")
    .setMessage("支持精确域名和 *.example.com 通配子域名；答案可为 IPv4、IPv6、CNAME 目标或 A/AAAA。每行格式：域名|答案|1（启用）/0（停用）；兼容旧两列规则并默认启用。同一来源模式只能有一条规则，规则条数不设应用层上限。留空会清除全部重写。")
    .setView(input)
    .setNegativeButton("取消",null)
    .setPositiveButton("保存",(dialog,which)->{
     String next;
     try{
      next=normalizeDnsRewrites(input.getText()==null?"":input.getText().toString());
     }catch(IllegalArgumentException invalid){
      status.setText("DNS 域名重写无效："+invalid.getMessage());return;
     }
     StringBuilder rows=new StringBuilder();
     if(!next.isEmpty())for(String row:next.split(","))rows.append(row).append('\n');
     String encoded=android.util.Base64.encodeToString(
         rows.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8),
         android.util.Base64.NO_WRAP);
     root("dns-rewrites-set "+q(encoded),result->{
      if(result.exitCode==0){
       status.setText("DNS 域名重写规则已保存并应用："+(next.isEmpty()?0:next.split(",").length)+" 条。");
       load();
      }else{
       fxDialogBuilder().setTitle("DNS 域名重写未应用")
        .setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
      }
     });
    }).show();
  });
 }
 private void chooseDnsStatisticsSettings(){
  root("dns-statistics-get",current->{
    if(current.exitCode!=0){
      status.setText("读取本地 DNS 聚合统计设置失败："+safe(current.output));return;
    }
    String raw=current.output==null?"":current.output.trim();
    String[] lines=raw.split("\\r?\\n");
    if(lines.length<5||!"FXYULONGDNSSTAT1".equals(lines[0].trim())){
      status.setText("DNS 聚合统计响应格式错误，未修改配置。");return;
    }
    java.util.Map<String,String> values=new java.util.HashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||(split==line.length()-1&&!"STATISTICS_IGNORED".equals(line.substring(0,split)))){
        status.setText("DNS 聚合统计响应字段格式错误。");return;
      }
      String key=line.substring(0,split);
      if(!"STATISTICS_ENABLED".equals(key)&&!"STATISTICS_INTERVAL".equals(key)
          &&!"STATISTICS_IGNORED_ENABLED".equals(key)&&!"STATISTICS_IGNORED".equals(key)){
        status.setText("DNS 聚合统计响应包含未知字段："+key);return;
      }
      if(values.put(key,line.substring(split+1))!=null){
        status.setText("DNS 聚合统计响应包含重复字段："+key);return;
      }
    }
    if(values.size()!=4){
      status.setText("DNS 聚合统计响应字段不完整（"+values.size()+"/4）。");return;
    }
    String enabledValue=values.get("STATISTICS_ENABLED");
    String intervalValue=values.get("STATISTICS_INTERVAL");
    String ignoredEnabledValue=values.get("STATISTICS_IGNORED_ENABLED");
    String ignoredDomainsValue=values.get("STATISTICS_IGNORED");
    if(!"0".equals(enabledValue)&&!"1".equals(enabledValue)){
      status.setText("DNS 聚合统计开关值非法。");return;
    }
    if(!"0".equals(ignoredEnabledValue)&&!"1".equals(ignoredEnabledValue)){
      status.setText("DNS 统计排除域名开关值非法。");return;
    }
    if(!isValidDnsQueryLogRetention(intervalValue)){
      status.setText("DNS 聚合统计周期不可用或超出 AdGuard Home 支持范围。");return;
    }
    try{
      ignoredDomainsValue=normalizeDnsStatisticsDomains(ignoredDomainsValue,true);
    }catch(IllegalArgumentException invalid){
      status.setText("当前 DNS 统计排除域名配置异常："+invalid.getMessage());
      return;
    }
    android.widget.Switch enabled=new android.widget.Switch(this);
    enabled.setText("在本机启用 DNS 聚合统计数据库");
    enabled.setChecked("1".equals(enabledValue));
    EditText interval=new EditText(this);
    interval.setSingleLine(true);
    interval.setInputType(android.text.InputType.TYPE_CLASS_TEXT
        |android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
    interval.setHint("例如 24h、7d、30d");
    interval.setText(intervalValue);
    android.widget.Switch ignoredEnabled=new android.widget.Switch(this);
    ignoredEnabled.setText("启用统计排除域名");
    ignoredEnabled.setChecked("1".equals(ignoredEnabledValue));
    EditText ignoredDomains=new EditText(this);
    ignoredDomains.setSingleLine(false);
    ignoredDomains.setMinLines(3);
    ignoredDomains.setGravity(android.view.Gravity.TOP|android.view.Gravity.START);
    ignoredDomains.setHint("每行一个域名，也可逗号分隔；例如 example.com");
    ignoredDomains.setText(ignoredDomainsValue.isEmpty()?""
        :ignoredDomainsValue.replace(",", "\\n"));
    LinearLayout form=new LinearLayout(this);
    form.setOrientation(LinearLayout.VERTICAL);
    form.addView(enabled);
    form.addView(txt("统计周期（1h–8760h 或 1d–365d）",12,0xff617080,false));
    form.addView(interval);
    form.addView(ignoredEnabled);
    form.addView(txt("被排除的域名不会进入聚合统计；不影响逐条查询日志、DNS 拦截或放行。域名条数不设应用层上限。",12,0xff617080,false));
    form.addView(ignoredDomains);
    fxDialogBuilder().setTitle("DNS 聚合统计数据库")
      .setMessage("逐条查询日志与聚合统计独立控制。排除列表只作用于聚合统计数据库，不会删除逐条查询日志或改变 DNS 过滤结果。")
      .setView(form)
      .setNegativeButton("取消",null)
      .setPositiveButton("保存",(dialog,which)->{
        String duration=interval.getText()==null?""
            :interval.getText().toString().trim().toLowerCase(java.util.Locale.ROOT);
        if(!isValidDnsQueryLogRetention(duration)){
          status.setText("统计周期须为 1h–8760h 或 1d–365d，未修改配置。");
          return;
        }
        String domains;
        try{
          domains=normalizeDnsStatisticsDomains(
              ignoredDomains.getText()==null?"":ignoredDomains.getText().toString(),false);
        }catch(IllegalArgumentException invalid){
          status.setText("DNS 统计排除域名无效："+invalid.getMessage());
          return;
        }
        String flag=enabled.isChecked()?"1":"0";
        String ignoredFlag=ignoredEnabled.isChecked()?"1":"0";
        root("dns-statistics-config-set "+flag+" "+q(duration)+" "+ignoredFlag+" "+q(domains),result->{
          if(result.exitCode==0){
            status.setText("本地 DNS 聚合统计已"+(flag.equals("1")?"开启":"关闭")
                +"；周期 "+duration+"；排除域名 "+(ignoredFlag.equals("1")?"已启用":"已关闭")
                +"，已配置 "+(domains.isEmpty()?0:domains.split(",").length)+" 个。");
            load();
          }else{
            fxDialogBuilder().setTitle("DNS 聚合统计设置未更新")
              .setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
          }
        });
      }).show();
  });
 }
 private void chooseDnsQueryLogIgnoredDomains(){
  root("dns-querylog-ignored-get",current->{
   if(current.exitCode!=0){
    status.setText("读取逐条 DNS 查询日志排除域名失败："+safe(current.output));return;
   }
   String[] lines=(current.output==null?"":current.output.trim()).split("\\r?\\n");
   if(lines.length<3||!"FXYULONGDNSQIGNORE1".equals(lines[0].trim())){
    status.setText("逐条 DNS 查询日志排除域名响应格式错误。");return;
   }
   java.util.Map<String,String> values=new java.util.HashMap<>();
   for(int i=1;i<lines.length;i++){
    String line=lines[i].trim();int split=line.indexOf('=');
    if(split<=0||(split==line.length()-1&&!"QUERYLOG_IGNORED".equals(line.substring(0,split)))){
     status.setText("逐条 DNS 查询日志排除域名字段格式错误。");return;
    }
    String key=line.substring(0,split);
    if(!"QUERYLOG_IGNORED_ENABLED".equals(key)&&!"QUERYLOG_IGNORED".equals(key)){
     status.setText("逐条 DNS 查询日志排除域名响应包含未知字段："+key);return;
    }
    if(values.put(key,line.substring(split+1))!=null){
     status.setText("逐条 DNS 查询日志排除域名响应包含重复字段："+key);return;
    }
   }
   if(values.size()!=2){
    status.setText("逐条 DNS 查询日志排除域名响应不完整。");return;
   }
   String flag=values.get("QUERYLOG_IGNORED_ENABLED");
   String rawDomains=values.get("QUERYLOG_IGNORED");
   if(!"0".equals(flag)&&!"1".equals(flag)){
    status.setText("逐条 DNS 查询日志排除域名开关值非法。");return;
   }
   try{
    rawDomains=normalizeDnsStatisticsDomains(rawDomains,true);
   }catch(IllegalArgumentException invalid){
    status.setText("当前逐条日志排除域名配置异常："+invalid.getMessage());return;
   }
   Switch enabled=new Switch(this);
   enabled.setText("启用逐条查询日志排除域名");
   enabled.setChecked("1".equals(flag));
   EditText domains=new EditText(this);
   domains.setSingleLine(false);
   domains.setMinLines(4);
   domains.setGravity(android.view.Gravity.TOP|android.view.Gravity.START);
   domains.setHint("每行一个域名，也可逗号分隔；例如 login.example.com");
   domains.setText(rawDomains.replace(",", "\\n"));
   LinearLayout form=new LinearLayout(this);
   form.setOrientation(LinearLayout.VERTICAL);
   form.addView(enabled);
   form.addView(txt("命中的域名不会写入逐条 DNS 查询日志。该列表不影响 DNS 拦截/放行，也不影响聚合统计的独立排除列表；域名数量不设应用层上限。",12,0xff617080,false));
   form.addView(domains);
   fxDialogBuilder().setTitle("逐条 DNS 查询日志排除域名")
    .setMessage("用于避免将指定域名写入本机逐条查询日志。关闭排除开关时保留列表，之后可重新启用。")
    .setView(form)
    .setNegativeButton("取消",null)
    .setPositiveButton("保存",(dialog,which)->{
     String normalized;
     try{
      normalized=normalizeDnsStatisticsDomains(
          domains.getText()==null?"":domains.getText().toString(),true);
     }catch(IllegalArgumentException invalid){
      status.setText("逐条查询日志排除域名无效："+invalid.getMessage());return;
     }
     String nextFlag=enabled.isChecked()?"1":"0";
     root("dns-querylog-ignored-set "+nextFlag+" "+q(normalized),result->{
      if(result.exitCode==0){
       status.setText("逐条查询日志排除域名已"+(nextFlag.equals("1")?"启用":"关闭")
           +"；已配置 "+(normalized.isEmpty()?0:normalized.split(",").length)+" 个域名。");
       load();
      }else{
       fxDialogBuilder().setTitle("逐条日志排除域名未更新")
        .setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
      }
     });
    }).show();
  });
 }
 private void chooseDnsQueryLogRetention(){
  final String[] values={"1d","3d","7d","30d"};
  final String[] labels={"保留 1 天","保留 3 天","保留 7 天","保留 30 天","自定义时长…"};
  root("dns-querylog-retention-get",current->{
    String selectedValue="7d";
    if(current.exitCode==0&&current.output!=null)
      for(String line:current.output.split("\\r?\\n"))
        if(line.startsWith("querylog_retention="))selectedValue=line.substring("querylog_retention=".length()).trim();
    int selected=-1;
    for(int i=0;i<values.length;i++)if(values[i].equals(selectedValue))selected=i;
    final String currentRetention=selectedValue;
    new AlertDialog.Builder(this).setTitle("DNS 查询日志轮转周期")
      .setSingleChoiceItems(labels,selected,(dialog,which)->{
        dialog.dismiss();
        if(which>=values.length){
          promptDnsQueryLogRetentionDuration(currentRetention);
          return;
        }
        saveDnsQueryLogRetention(values[which]);
      }).setNegativeButton("取消",null).show();
  });
 }
 private static boolean isValidUnboundCacheSize(String value){
  if(value==null||!value.matches("[0-9]+[kKmMgG]?"))return false;
  String digits=value.replaceFirst("[kKmMgG]$","");
  try{return new java.math.BigInteger(digits).signum()>=0;}
  catch(NumberFormatException invalid){return false;}
 }
 private static boolean isValidDnsRuntimeUint32(String value,boolean allowZero){
  if(value==null||!value.matches("[0-9]+"))return false;
  try{
   java.math.BigInteger number=new java.math.BigInteger(value);
   return (allowZero?number.signum()>=0:number.signum()>0)
       &&number.compareTo(new java.math.BigInteger("4294967295"))<=0;
  }catch(NumberFormatException failure){return false;}
 }
 private static boolean isValidDnsRuntimeCacheSize(String value){
  return isValidDnsRuntimeUint32(value,false);
 }
 private static boolean isValidDnsRuntimeCacheTtl(String minimum,String maximum){
  if(!isValidDnsRuntimeUint32(minimum,true)||!isValidDnsRuntimeUint32(maximum,true))return false;
  return new java.math.BigInteger(minimum).compareTo(new java.math.BigInteger(maximum))<=0;
 }
 private static boolean isValidDnsRuntimeOptimisticAnswerTtl(String value){
  if(!isValidDnsRuntimeDuration(value))return false;
  String unit;
  String number;
  if(value.endsWith("ms")){unit="ms";number=value.substring(0,value.length()-2);}
  else if(value.endsWith("s")){unit="s";number=value.substring(0,value.length()-1);}
  else if(value.endsWith("m")){unit="m";number=value.substring(0,value.length()-1);}
  else if(value.endsWith("h")){unit="h";number=value.substring(0,value.length()-1);}
  else return false;
  java.math.BigInteger factor="ms".equals(unit)?java.math.BigInteger.ONE
      :"s".equals(unit)?java.math.BigInteger.valueOf(1000L)
      :"m".equals(unit)?java.math.BigInteger.valueOf(60000L)
      :java.math.BigInteger.valueOf(3600000L);
  java.math.BigInteger millis=new java.math.BigInteger(number).multiply(factor);
  return millis.compareTo(java.math.BigInteger.valueOf(1000L))>=0
      &&millis.compareTo(new java.math.BigInteger("4294967295000"))<=0;
 }
 private static boolean isValidDnsRuntimeMode(String value){
  return "load_balance".equals(value)||"parallel".equals(value)||"fastest_addr".equals(value);
 }
 private static boolean isValidDnsRuntimeDuration(String value){
  if(value==null)return false;
  String unit;
  String number;
  if(value.endsWith("ms")){unit="ms";number=value.substring(0,value.length()-2);}
  else if(value.endsWith("s")){unit="s";number=value.substring(0,value.length()-1);}
  else if(value.endsWith("m")){unit="m";number=value.substring(0,value.length()-1);}
  else if(value.endsWith("h")){unit="h";number=value.substring(0,value.length()-1);}
  else return false;
  if(!number.matches("[0-9]+"))return false;
  try{
    java.math.BigInteger amount=new java.math.BigInteger(number);
    if(amount.signum()<=0)return false;
    String limit="ms".equals(unit)?"9223372036854"
        :"s".equals(unit)?"9223372036"
        :"m".equals(unit)?"153722867":"2562047";
    return amount.compareTo(new java.math.BigInteger(limit))<=0;
  }catch(NumberFormatException invalid){return false;}
 }
 private static boolean isValidDnsRuntimeFastestTimeout(String value){
  return isValidDnsRuntimeDuration(value);
 }
 private static boolean isValidDnsRuntimeUpstreamTimeout(String value){
  return isValidDnsRuntimeDuration(value);
 }
 private void loadDnsRuntimeControls(EditText mode,EditText fastest,EditText upstream,
      EditText cacheSize,EditText cacheTtlMin,EditText cacheTtlMax,
      EditText optimisticAnswerTtl,EditText optimisticMaxAge,
      Switch cacheEnabled,Switch cacheOptimistic,Switch dnssec,TextView state){
  root("dns-runtime-get",result->{
    if(result.exitCode!=0){state.setText("读取 AdGuard Home 引擎参数失败："+safe(result.output));return;}
    java.util.Map<String,String> values=new java.util.LinkedHashMap<>();
    String[] lines=(result.output==null?"":result.output).split("\\r?\\n");
    if(lines.length==0||!"FXYULONGDNSRUNTIME1".equals(lines[0].trim())){
      state.setText("DNS 引擎参数响应版本错误，未更新界面。");return;
    }
    for(int i=1;i<lines.length;i++){
      int split=lines[i].indexOf('=');
      if(split<=0||values.put(lines[i].substring(0,split),lines[i].substring(split+1))!=null){
        state.setText("DNS 引擎参数响应有格式错误或重复字段，未更新界面。");return;
      }
    }
    String[] required={"UPSTREAM_MODE","FASTEST_TIMEOUT","UPSTREAM_TIMEOUT","CACHE_SIZE",
        "CACHE_TTL_MIN","CACHE_TTL_MAX","CACHE_OPTIMISTIC_ANSWER_TTL","CACHE_OPTIMISTIC_MAX_AGE",
        "CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC"};
    for(String key:required)if(!values.containsKey(key)){
      state.setText("DNS 引擎参数响应缺少字段："+key+"。");return;
    }
    if(!isValidDnsRuntimeMode(values.get("UPSTREAM_MODE"))
        ||!isValidDnsRuntimeFastestTimeout(values.get("FASTEST_TIMEOUT"))
        ||!isValidDnsRuntimeUpstreamTimeout(values.get("UPSTREAM_TIMEOUT"))
        ||!isValidDnsRuntimeCacheSize(values.get("CACHE_SIZE"))
        ||!isValidDnsRuntimeCacheTtl(values.get("CACHE_TTL_MIN"),values.get("CACHE_TTL_MAX"))
        ||!isValidDnsRuntimeOptimisticAnswerTtl(values.get("CACHE_OPTIMISTIC_ANSWER_TTL"))
        ||!isValidDnsRuntimeDuration(values.get("CACHE_OPTIMISTIC_MAX_AGE"))){
      state.setText("DNS 引擎参数响应的策略、超时、缓存容量或 TTL 无效。");return;
    }
    for(String key:new String[]{"CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC"})
      if(!"0".equals(values.get(key))&&!"1".equals(values.get(key))){
        state.setText("DNS 引擎开关值无效："+key+"。");return;
      }
    mode.setText(values.get("UPSTREAM_MODE"));
    fastest.setText(values.get("FASTEST_TIMEOUT"));
    upstream.setText(values.get("UPSTREAM_TIMEOUT"));
    cacheSize.setText(values.get("CACHE_SIZE"));
    cacheTtlMin.setText(values.get("CACHE_TTL_MIN"));
    cacheTtlMax.setText(values.get("CACHE_TTL_MAX"));
    optimisticAnswerTtl.setText(values.get("CACHE_OPTIMISTIC_ANSWER_TTL"));
    optimisticMaxAge.setText(values.get("CACHE_OPTIMISTIC_MAX_AGE"));
    cacheEnabled.setChecked("1".equals(values.get("CACHE_ENABLED")));
    cacheOptimistic.setChecked("1".equals(values.get("CACHE_OPTIMISTIC")));
    dnssec.setChecked("1".equals(values.get("ENABLE_DNSSEC")));
    state.setText("已读取完整 AdGuard Home 参数。上游策略、超时、缓存和 DNSSEC 将由运行 YAML 实际应用。");
  });
 }


private void loadUnboundRuntimeControls(EditText cacheMaxTtl,EditText cacheMinTtl,
      EditText msgCacheSize,EditText rrsetCacheSize,EditText keyCacheSize,EditText negCacheSize,
      Switch serveExpired,EditText serveExpiredTtl,EditText serveExpiredReplyTtl,
      EditText serveExpiredClientTimeout,Switch serveExpiredTtlReset,Switch prefetch,Switch prefetchKey,Switch qnameMinimisation,EditText numThreads,TextView state){
  root("unbound-runtime-get",result->{
    if(result.exitCode!=0){state.setText("读取 Unbound 递归缓存参数失败："+safe(result.output));return;}
    String raw=result.output==null?"":result.output;
    String[] lines=raw.split("\\r?\\n");
    if(lines.length==0||!"FXYULONGUNBOUND1".equals(lines[0].trim())){
      state.setText("Unbound 参数响应版本错误，未更新界面。");return;
    }
    java.util.Map<String,String> values=new java.util.LinkedHashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();
      if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||values.put(line.substring(0,split),line.substring(split+1))!=null){
        state.setText("Unbound 参数响应包含格式错误或重复字段，未更新界面。");return;
      }
    }
    String[] required={"UNBOUND_CACHE_MAX_TTL","UNBOUND_CACHE_MIN_TTL",
        "UNBOUND_SERVE_EXPIRED","UNBOUND_SERVE_EXPIRED_TTL",
        "UNBOUND_SERVE_EXPIRED_REPLY_TTL","UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT",
        "UNBOUND_SERVE_EXPIRED_TTL_RESET","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION",
        "UNBOUND_MSG_CACHE_SIZE","UNBOUND_RRSET_CACHE_SIZE","UNBOUND_KEY_CACHE_SIZE","UNBOUND_NEG_CACHE_SIZE","UNBOUND_NUM_THREADS","UNBOUND_THREADS_MAX"};
    for(String key:required)if(!values.containsKey(key)){
      state.setText("Unbound 参数响应缺少字段："+key+"。");return;
    }
    if(!isValidDnsRuntimeUint32(values.get("UNBOUND_CACHE_MAX_TTL"),false)
        ||!isValidDnsRuntimeUint32(values.get("UNBOUND_CACHE_MIN_TTL"),true)
        ||new java.math.BigInteger(values.get("UNBOUND_CACHE_MIN_TTL"))
            .compareTo(new java.math.BigInteger(values.get("UNBOUND_CACHE_MAX_TTL")))>0
        ||!isValidDnsRuntimeUint32(values.get("UNBOUND_SERVE_EXPIRED_TTL"),true)
        ||!isValidDnsRuntimeUint32(values.get("UNBOUND_SERVE_EXPIRED_REPLY_TTL"),false)
        ||!isValidDnsRuntimeUint32(values.get("UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT"),true)){
      state.setText("Unbound 缓存 TTL 或 serve-expired 时长超出有效范围。");return;
    }
    for(String key:new String[]{"UNBOUND_SERVE_EXPIRED","UNBOUND_SERVE_EXPIRED_TTL_RESET","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION"})
      if(!"0".equals(values.get(key))&&!"1".equals(values.get(key))){
        state.setText("Unbound 开关值无效："+key+"。");return;
      }
    for(String key:new String[]{"UNBOUND_MSG_CACHE_SIZE","UNBOUND_RRSET_CACHE_SIZE","UNBOUND_KEY_CACHE_SIZE","UNBOUND_NEG_CACHE_SIZE"})
      if(!isValidUnboundCacheSize(values.get(key))){
        state.setText("Unbound 内存缓存池大小无效："+key+"。");return;
      }
    if(!isValidDnsRuntimeUint32(values.get("UNBOUND_NUM_THREADS"),false)
        ||!isValidDnsRuntimeUint32(values.get("UNBOUND_THREADS_MAX"),false)
        ||new java.math.BigInteger(values.get("UNBOUND_NUM_THREADS"))
            .compareTo(new java.math.BigInteger(values.get("UNBOUND_THREADS_MAX")))>0){
      state.setText("Unbound worker 线程数必须为正整数且不得超过设备在线 CPU 核心数。");return;
    }
    cacheMaxTtl.setText(values.get("UNBOUND_CACHE_MAX_TTL"));
    cacheMinTtl.setText(values.get("UNBOUND_CACHE_MIN_TTL"));
    serveExpired.setChecked("1".equals(values.get("UNBOUND_SERVE_EXPIRED")));
    serveExpiredTtlReset.setChecked("1".equals(values.get("UNBOUND_SERVE_EXPIRED_TTL_RESET")));
    serveExpiredTtl.setText(values.get("UNBOUND_SERVE_EXPIRED_TTL"));
    serveExpiredReplyTtl.setText(values.get("UNBOUND_SERVE_EXPIRED_REPLY_TTL"));
    serveExpiredClientTimeout.setText(values.get("UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT"));
    prefetch.setChecked("1".equals(values.get("UNBOUND_PREFETCH")));
    prefetchKey.setChecked("1".equals(values.get("UNBOUND_PREFETCH_KEY")));
    qnameMinimisation.setChecked("1".equals(values.get("UNBOUND_QNAME_MINIMISATION")));
    msgCacheSize.setText(values.get("UNBOUND_MSG_CACHE_SIZE"));
    rrsetCacheSize.setText(values.get("UNBOUND_RRSET_CACHE_SIZE"));
    keyCacheSize.setText(values.get("UNBOUND_KEY_CACHE_SIZE"));
    negCacheSize.setText(values.get("UNBOUND_NEG_CACHE_SIZE"));
    numThreads.setText(values.get("UNBOUND_NUM_THREADS"));
    numThreads.setTag(values.get("UNBOUND_THREADS_MAX"));
    numThreads.setHint("设备在线 CPU 核心数上限："+values.get("UNBOUND_THREADS_MAX"));
    state.setText("已读取 Unbound 递归缓存、CPU 自适应线程与隐私参数；当前工作线程 "
        +values.get("UNBOUND_NUM_THREADS")+"，设备在线核心数 "+values.get("UNBOUND_THREADS_MAX")+"。");
  });
}

  private void loadUnboundAnchorStatus(TextView target){
  target.setText("正在读取 DNSSEC 根信任锚与 Root Hints 状态…");
  root("unbound-anchor-status",result->{
    if(result.exitCode!=0){target.setText("DNSSEC 根信任锚状态读取失败："+safe(result.output));return;}
    String raw=result.output==null?"":result.output.trim();
    String[] lines=raw.split("\\r?\\n");
    if(lines.length<8||!"FXYUNBOUNDANCHOR2".equals(lines[0].trim())){
      target.setText("DNSSEC 信任锚状态协议错误，拒绝显示不完整信息。");return;
    }
    java.util.Map<String,String> values=new java.util.HashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||split==line.length()-1){target.setText("DNSSEC 信任锚状态字段格式错误。");return;}
      String key=line.substring(0,split),value=line.substring(split+1);
      if(!"anchor_state".equals(key)&&!"anchor_bytes".equals(key)&&!"anchor_age".equals(key)
          &&!"refresh_route".equals(key)&&!"resolver_state".equals(key)
          &&!"root_hints_state".equals(key)&&!"root_hints_bytes".equals(key)
          &&!"root_hints_refresh".equals(key)){
        target.setText("DNSSEC 信任锚状态包含未知字段："+key);return;
      }
      if(values.put(key,value)!=null){target.setText("DNSSEC 信任锚状态包含重复字段："+key);return;}
    }
    if(values.size()!=7&&values.size()!=8){target.setText("DNSSEC 信任锚状态字段不完整。");return;}
    String refreshResult=values.get("root_hints_refresh");
    if(refreshResult!=null&&!"updated".equals(refreshResult)){
      target.setText("Root Hints 更新回执值异常，拒绝显示。");return;
    }
    String state=values.get("anchor_state"),age=values.get("anchor_age");
    String bytes=values.get("anchor_bytes"),route=values.get("refresh_route");
    String resolver=values.get("resolver_state");
    String hintsState=values.get("root_hints_state"),hintsBytes=values.get("root_hints_bytes");
    if(!("valid".equals(state)||"missing".equals(state)||"invalid".equals(state)||"unsafe".equals(state))
        ||(!android.text.TextUtils.isDigitsOnly(bytes)&&!"unknown".equals(bytes))
        ||!("stale".equals(age)||"current".equals(age)||"unknown".equals(age))
        ||!("system_default".equals(route)||"vpn_bound".equals(route)||"unsafe".equals(route))
        ||!("running".equals(resolver)||"stopped".equals(resolver)||"unknown".equals(resolver))
        ||!("valid".equals(hintsState)||"missing".equals(hintsState)||"invalid".equals(hintsState)||"unsafe".equals(hintsState))
        ||(!android.text.TextUtils.isDigitsOnly(hintsBytes)&&!"unknown".equals(hintsBytes))){
      target.setText("DNSSEC 信任锚或 Root Hints 状态值异常，拒绝显示。");return;
    }
    target.setText("DNSSEC 信任锚："+state+"；文件大小："+bytes+" 字节；更新状态："+age
        +"；Unbound："+resolver+"；刷新出口："+route
        +("stale".equals(age)?"。信任锚超过 14 天未更新；在线 Unbound 会继续执行 RFC5011 维护。":"。")
        +"\nRoot Hints："+hintsState+"；文件大小："+hintsBytes+" 字节（SHA-256 与 13 个根服务器结构校验）。"
        +( "updated".equals(refreshResult)?"\n最近操作：Root Hints 已更新。":""));
  });
}
 private void renderDns(){
  EditText dnsProfileImport=draftField("dns_profile_import");dnsProfileImport.setSingleLine(false);dnsProfileImport.setMinLines(5);dnsProfileImport.setHint("粘贴完整 FXYULONGDNSPROFILE1 快照文本");dnsProfileImportField=dnsProfileImport;
  card("DNS 配置备份与恢复","快照导入会完整替换 DNS 引擎开关、过滤策略、三组上游、VPN DNS、拦截响应模式、自定义 IPv4/IPv6 响应地址与 TTL、查询日志保留期限/内存批量/逐条日志排除域名/DNS 域名重写、多上游策略与超时、缓存容量/模式及 DNSSEC；兼容旧版快照并为新增字段补齐默认值，提交前由 Root 后端再次校验，应用失败时回滚原配置。",btn("分享 DNS 配置快照",()->shareDnsProfile()),btn("保存 DNS 快照到文件",()->saveDnsProfileToFile()),btn("从文件读取 DNS 快照",()->openDnsProfileFile()),dnsProfileImport,btn("校验并恢复 DNS 配置快照",()->restoreDnsProfile(dnsProfileImport)));
  TextView dnsRuntimeState=txt("DNS 运行状态尚未读取。",12,0xff617080,false);
  card("DNS 引擎运行状态","读取 AdGuard Home、Unbound、第三方 VPN Root Proxy、DNS 过滤覆盖范围与 VPN 共存判定。此操作只读取状态，不会更改服务或网络路由。",dnsRuntimeState,
       btn("刷新 DNS 运行状态",()->loadDnsRuntimeStatus(dnsRuntimeState)),
       btn("执行完整 DNS 链路诊断",()->runDnsDiagnostics()),
       btn("立即尝试修复 DNS 服务",()->fxDialogBuilder().setTitle("恢复 FX 本地 DNS 服务")
         .setMessage("将按当前开关和上游配置，尝试恢复 FX 自有 Unbound 与 AdGuard Home。不会改写 DNS 配置、接管第三方 VPN、修改 Android 私有 DNS 或清理查询日志。恢复过程中的 DNS 查询可能短暂重试。是否继续？")
         .setNegativeButton("取消",null)
         .setPositiveButton("立即修复",(d,w)->root("dns-repair",result->{
           if(result.exitCode==0){
             status.setText("FX 本地 DNS 恢复完成。");
             loadDnsRuntimeStatus(dnsRuntimeState);
           }else{
             fxDialogBuilder().setTitle("DNS 恢复未完成").setMessage(safe(result.output))
               .setPositiveButton("关闭",null).show();
             loadDnsRuntimeStatus(dnsRuntimeState);
           }
         })).show()));
  card("本地 DNS 引擎",
       "启用时使用 FX 自有 AdGuard Home 过滤服务；关闭后按 FX 当前安全 DNS 回退配置处理。",
       dnsSwitch("启用本地 AdGuard Home","dns_engine_adguardhome"));
  card("本地 DNS 架构",
       "默认由本地 AdGuard Home 过滤并交给 Unbound 递归解析；不固定使用公共 DNS。启用“全局 DNS 替换”时优先使用全局列表；否则启用“自定义 DNS”时使用自定义列表；两项都关闭时恢复本地 Unbound。备用 DNS 仅在主上游无响应时用于回退；外部自定义/全局上游未配置备用列表时，FX 自动使用本地 Unbound 作为故障回退，填写备用列表后则按用户列表回退。",
       dnsSwitch("DNS 兜底转发","dns_forward"),
       dnsSwitch("启用自定义 DNS","custom_dns"),
       dnsSwitch("启用全局 DNS 替换","global_dns"),
       btn("一键启用本地 DNS 引擎组",()->setDnsEngineProfile(true)),
       btn("一键关闭本地 DNS 引擎组",()->setDnsEngineProfile(false)));
  EditText dnsRuntimeMode=draftField("dns_runtime_upstream_mode");
  dnsRuntimeMode.setSingleLine(true);
  dnsRuntimeMode.setHint("load_balance / parallel / fastest_addr");
  EditText dnsRuntimeFastest=draftField("dns_runtime_fastest_timeout");
  dnsRuntimeFastest.setSingleLine(true);
  dnsRuntimeFastest.setHint("自定义正整数时长，例如 500ms、3s、2m");
  EditText dnsRuntimeTimeout=draftField("dns_runtime_upstream_timeout");
  dnsRuntimeTimeout.setSingleLine(true);
  dnsRuntimeTimeout.setHint("自定义正整数时长，例如 5s、45s、2m");
  EditText dnsRuntimeCacheSize=draftField("dns_runtime_cache_size");
  dnsRuntimeCacheSize.setSingleLine(true);
  dnsRuntimeCacheSize.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  dnsRuntimeCacheSize.setHint("缓存容量（字节），例如 4194304");
  EditText dnsRuntimeCacheTtlMin=draftField("dns_runtime_cache_ttl_min");
  dnsRuntimeCacheTtlMin.setSingleLine(true);
  dnsRuntimeCacheTtlMin.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  dnsRuntimeCacheTtlMin.setHint("0 表示不强制提高缓存 TTL");
  EditText dnsRuntimeCacheTtlMax=draftField("dns_runtime_cache_ttl_max");
  dnsRuntimeCacheTtlMax.setSingleLine(true);
  dnsRuntimeCacheTtlMax.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  dnsRuntimeCacheTtlMax.setHint("0 表示不限制缓存 TTL 上限");
  EditText dnsRuntimeOptimisticAnswerTtl=draftField("dns_runtime_optimistic_answer_ttl");
  dnsRuntimeOptimisticAnswerTtl.setSingleLine(true);
  dnsRuntimeOptimisticAnswerTtl.setHint("例如 30s，至少 1 秒");
  EditText dnsRuntimeOptimisticMaxAge=draftField("dns_runtime_optimistic_max_age");
  dnsRuntimeOptimisticMaxAge.setSingleLine(true);
  dnsRuntimeOptimisticMaxAge.setHint("例如 12h，过期缓存最大年龄");
  Switch dnsCacheEnabled=new Switch(this);
  dnsCacheEnabled.setText("启用 AdGuard Home DNS 缓存");
  Switch dnsCacheOptimistic=new Switch(this);
  dnsCacheOptimistic.setText("缓存过期时先返回旧答案并后台刷新");
  Switch dnssecEnabled=new Switch(this);
  dnssecEnabled.setText("AdGuard Home 上游启用 DNSSEC 校验");
  TextView adguardRuntimeState=txt("正在读取 AdGuard Home 引擎参数…",12,0xff617080,false);
  card("AdGuard Home 解析策略与性能",
       "上游策略：load_balance 按健康与响应表现选择；parallel 并发请求全部上游；fastest_addr 按地址响应延迟选择。fastest 与上游请求超时都支持自定义正整数 ms/s/m/h 时长，并遵守运行时 duration 范围。缓存容量以字节计；乐观缓存可在过期数据刷新期间优先返回旧答案。DNSSEC 会对上游 DNSSEC 响应执行验证。EDNS Client Subnet 保持关闭，避免向上游泄露客户端网段。",
       txt("多上游选择策略",12,0xff617080,true),dnsRuntimeMode,
       txt("fastest_addr 探测超时",12,0xff617080,true),dnsRuntimeFastest,
       txt("上游请求超时",12,0xff617080,true),dnsRuntimeTimeout,
       txt("DNS 缓存容量（字节）",12,0xff617080,true),dnsRuntimeCacheSize,
       txt("缓存最小 TTL（秒）",12,0xff617080,true),dnsRuntimeCacheTtlMin,
       txt("缓存最大 TTL（秒）",12,0xff617080,true),dnsRuntimeCacheTtlMax,
       txt("乐观缓存答复 TTL",12,0xff617080,true),dnsRuntimeOptimisticAnswerTtl,
       txt("乐观缓存最大年龄",12,0xff617080,true),dnsRuntimeOptimisticMaxAge,
       dnsCacheEnabled,dnsCacheOptimistic,dnssecEnabled,
       btn("保存并应用 AdGuard Home 引擎参数",()->{
         String modeValue=dnsRuntimeMode.getText()==null?"":dnsRuntimeMode.getText().toString().trim();
         String fastestValue=dnsRuntimeFastest.getText()==null?"":dnsRuntimeFastest.getText().toString().trim();
         String timeoutValue=dnsRuntimeTimeout.getText()==null?"":dnsRuntimeTimeout.getText().toString().trim();
         String cacheValue=dnsRuntimeCacheSize.getText()==null?"":dnsRuntimeCacheSize.getText().toString().trim();
         String cacheMin=dnsRuntimeCacheTtlMin.getText()==null?"":dnsRuntimeCacheTtlMin.getText().toString().trim();
         String cacheMax=dnsRuntimeCacheTtlMax.getText()==null?"":dnsRuntimeCacheTtlMax.getText().toString().trim();
         String optimisticAnswer=dnsRuntimeOptimisticAnswerTtl.getText()==null?"":dnsRuntimeOptimisticAnswerTtl.getText().toString().trim();
         String optimisticMaxAge=dnsRuntimeOptimisticMaxAge.getText()==null?"":dnsRuntimeOptimisticMaxAge.getText().toString().trim();
         if(!isValidDnsRuntimeMode(modeValue)||!isValidDnsRuntimeFastestTimeout(fastestValue)
             ||!isValidDnsRuntimeUpstreamTimeout(timeoutValue)||!isValidDnsRuntimeCacheSize(cacheValue)
             ||!isValidDnsRuntimeCacheTtl(cacheMin,cacheMax)
             ||!isValidDnsRuntimeOptimisticAnswerTtl(optimisticAnswer)
             ||!isValidDnsRuntimeDuration(optimisticMaxAge)){
           status.setText("策略、超时、缓存容量或 TTL 格式/范围无效；未提交任何变更。");
           return;
         }
         String command="dns-runtime-set "+q(modeValue)+" "+q(fastestValue)+" "+q(timeoutValue)+" "
             +q(cacheValue)+" "+(dnsCacheEnabled.isChecked()?"1":"0")+" "
             +(dnsCacheOptimistic.isChecked()?"1":"0")+" "+(dnssecEnabled.isChecked()?"1":"0")+" "
             +q(cacheMin)+" "+q(cacheMax)+" "+q(optimisticAnswer)+" "+q(optimisticMaxAge);
         root(command,result->{
           if(result.exitCode==0){adguardRuntimeState.setText("AdGuard Home 引擎参数已保存并应用。");load();}
           else fxDialogBuilder().setTitle("DNS 引擎参数未应用").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
         });
       }),
       adguardRuntimeState);
  loadDnsRuntimeControls(dnsRuntimeMode,dnsRuntimeFastest,dnsRuntimeTimeout,dnsRuntimeCacheSize,
      dnsRuntimeCacheTtlMin,dnsRuntimeCacheTtlMax,dnsRuntimeOptimisticAnswerTtl,dnsRuntimeOptimisticMaxAge,
      dnsCacheEnabled,dnsCacheOptimistic,dnssecEnabled,adguardRuntimeState);

  EditText unboundCacheMaxTtl=draftField("unbound_cache_max_ttl");
  unboundCacheMaxTtl.setSingleLine(true);
  unboundCacheMaxTtl.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundCacheMaxTtl.setHint("最大 TTL（秒），例如 86400");
  EditText unboundCacheMinTtl=draftField("unbound_cache_min_ttl");
  unboundCacheMinTtl.setSingleLine(true);
  unboundCacheMinTtl.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundCacheMinTtl.setHint("最小 TTL（秒），0 表示不强制提高");
  EditText unboundMsgCacheSize=draftField("unbound_msg_cache_size");
  unboundMsgCacheSize.setSingleLine(true);
  unboundMsgCacheSize.setHint("消息缓存池大小，例如 8m 或字节数");
  EditText unboundRrsetCacheSize=draftField("unbound_rrset_cache_size");
  unboundRrsetCacheSize.setSingleLine(true);
  unboundRrsetCacheSize.setHint("RRset 缓存池大小，例如 16m 或字节数");
  EditText unboundKeyCacheSize=draftField("unbound_key_cache_size");
  unboundKeyCacheSize.setSingleLine(true);
  unboundKeyCacheSize.setHint("DNSSEC Key 缓存池大小，例如 4m");
  EditText unboundNegCacheSize=draftField("unbound_neg_cache_size");
  unboundNegCacheSize.setSingleLine(true);
  unboundNegCacheSize.setHint("否定响应缓存池大小，例如 2m");
  EditText unboundNumThreads=draftField("unbound_num_threads");
  unboundNumThreads.setSingleLine(true);
  unboundNumThreads.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundNumThreads.setHint("正整数，不得超过当前在线 CPU 核心数");
  Switch unboundServeExpired=new Switch(this);
  unboundServeExpired.setText("上游故障时提供过期缓存答案");
  Switch unboundServeExpiredTtlReset=new Switch(this);
  unboundServeExpiredTtlReset.setText("上游刷新失败后重置过期缓存年龄");
  EditText unboundServeExpiredTtl=draftField("unbound_serve_expired_ttl");
  unboundServeExpiredTtl.setSingleLine(true);
  unboundServeExpiredTtl.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundServeExpiredTtl.setHint("过期缓存最大年龄（秒），0 表示不限制");
  EditText unboundServeExpiredReplyTtl=draftField("unbound_serve_expired_reply_ttl");
  unboundServeExpiredReplyTtl.setSingleLine(true);
  unboundServeExpiredReplyTtl.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundServeExpiredReplyTtl.setHint("过期答案返回 TTL（秒）");
  EditText unboundServeExpiredClientTimeout=draftField("unbound_serve_expired_client_timeout");
  unboundServeExpiredClientTimeout.setSingleLine(true);
  unboundServeExpiredClientTimeout.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  unboundServeExpiredClientTimeout.setHint("等待上游响应时间（毫秒）");
  Switch unboundPrefetch=new Switch(this);
  unboundPrefetch.setText("启用高频域名预取");
  Switch unboundPrefetchKey=new Switch(this);
  unboundPrefetchKey.setText("启用 DNSSEC 密钥预取");
  Switch unboundQnameMinimisation=new Switch(this);
  unboundQnameMinimisation.setText("启用 QNAME minimisation（减少递归查询泄露）");
  TextView unboundRuntimeState=txt("正在读取 Unbound 递归参数…",12,0xff617080,false);
  card("Unbound 递归缓存与隐私",
       "独立控制递归解析器缓存 TTL、过期缓存服务和预取策略。serve-expired 只在递归上游暂不可用时改善可用性；QNAME minimisation 减少向上游权威服务器暴露的查询名称。所有时间参数均以秒或毫秒输入并受 uint32 范围校验。",
       txt("缓存最大 TTL（秒）",12,0xff617080,true),unboundCacheMaxTtl,
       txt("缓存最小 TTL（秒）",12,0xff617080,true),unboundCacheMinTtl,
       txt("消息缓存池",12,0xff617080,true),unboundMsgCacheSize,
       txt("RRset 缓存池",12,0xff617080,true),unboundRrsetCacheSize,
       txt("DNSSEC Key 缓存池",12,0xff617080,true),unboundKeyCacheSize,
       txt("否定响应缓存池",12,0xff617080,true),unboundNegCacheSize,
       txt("Unbound worker 线程数（在线 CPU 核心内）",12,0xff617080,true),unboundNumThreads,
       unboundServeExpired,unboundServeExpiredTtlReset,
       txt("过期缓存最大年龄（秒）",12,0xff617080,true),unboundServeExpiredTtl,
       txt("过期答案返回 TTL（秒）",12,0xff617080,true),unboundServeExpiredReplyTtl,
       txt("serve-expired 客户端等待时间（毫秒）",12,0xff617080,true),unboundServeExpiredClientTimeout,
       unboundPrefetch,unboundPrefetchKey,unboundQnameMinimisation,
       btn("保存并应用 Unbound 递归参数",()->{
         String maxTtl=unboundCacheMaxTtl.getText()==null?"":unboundCacheMaxTtl.getText().toString().trim();
         String minTtl=unboundCacheMinTtl.getText()==null?"":unboundCacheMinTtl.getText().toString().trim();
         String msgCache=unboundMsgCacheSize.getText()==null?"":unboundMsgCacheSize.getText().toString().trim();
         String rrsetCache=unboundRrsetCacheSize.getText()==null?"":unboundRrsetCacheSize.getText().toString().trim();
         String keyCache=unboundKeyCacheSize.getText()==null?"":unboundKeyCacheSize.getText().toString().trim();
         String negCache=unboundNegCacheSize.getText()==null?"":unboundNegCacheSize.getText().toString().trim();
         String numThreads=unboundNumThreads.getText()==null?"":unboundNumThreads.getText().toString().trim();
          String threadLimit=unboundNumThreads.getTag()==null?"":String.valueOf(unboundNumThreads.getTag());
         String expiredTtl=unboundServeExpiredTtl.getText()==null?"":unboundServeExpiredTtl.getText().toString().trim();
         String replyTtl=unboundServeExpiredReplyTtl.getText()==null?"":unboundServeExpiredReplyTtl.getText().toString().trim();
         String clientTimeout=unboundServeExpiredClientTimeout.getText()==null?"":unboundServeExpiredClientTimeout.getText().toString().trim();
         if(!isValidDnsRuntimeUint32(maxTtl,false)||!isValidDnsRuntimeUint32(minTtl,true)
             ||new java.math.BigInteger(minTtl).compareTo(new java.math.BigInteger(maxTtl))>0
             ||!isValidDnsRuntimeUint32(expiredTtl,true)
             ||!isValidDnsRuntimeUint32(replyTtl,false)
             ||!isValidDnsRuntimeUint32(clientTimeout,true)
             ||!isValidUnboundCacheSize(msgCache)||!isValidUnboundCacheSize(rrsetCache)
             ||!isValidUnboundCacheSize(keyCache)||!isValidUnboundCacheSize(negCache)
             ||!isValidDnsRuntimeUint32(numThreads,false)
             ||!isValidDnsRuntimeUint32(threadLimit,false)
             ||new java.math.BigInteger(numThreads).compareTo(new java.math.BigInteger(threadLimit))>0){
           unboundRuntimeState.setText("Unbound 工作线程数必须在 1 至 "+threadLimit+" 之间；TTL/时长须为有效 uint32，且缓存最小 TTL 不得大于最大 TTL；未提交。");
           return;
         }
         String command="unbound-runtime-set "+q(maxTtl)+" "+q(minTtl)+" "
             +(unboundServeExpired.isChecked()?"1":"0")+" "+q(expiredTtl)+" "+q(replyTtl)+" "
             +q(clientTimeout)+" "+(unboundServeExpiredTtlReset.isChecked()?"1":"0")+" "
             +(unboundPrefetch.isChecked()?"1":"0")+" "
             +(unboundPrefetchKey.isChecked()?"1":"0")+" "
             +(unboundQnameMinimisation.isChecked()?"1":"0")+" "
             +q(msgCache)+" "+q(rrsetCache)+" "+q(keyCache)+" "+q(negCache)+" "+q(numThreads);
         root(command,result->{
           if(result.exitCode==0){unboundRuntimeState.setText("Unbound 递归参数已保存并应用。");load();}
           else fxDialogBuilder().setTitle("Unbound 参数未应用").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
         });
       }),
       unboundRuntimeState);
  loadUnboundRuntimeControls(unboundCacheMaxTtl,unboundCacheMinTtl,
      unboundMsgCacheSize,unboundRrsetCacheSize,unboundKeyCacheSize,unboundNegCacheSize,
      unboundServeExpired,unboundServeExpiredTtl,unboundServeExpiredReplyTtl,unboundServeExpiredClientTimeout,
      unboundServeExpiredTtlReset,unboundPrefetch,unboundPrefetchKey,unboundQnameMinimisation,unboundNumThreads,unboundRuntimeState);

    TextView anchorState=txt("DNSSEC 根信任锚状态尚未读取。",12,0xff617080,false);
    card("DNSSEC 根信任锚维护",
        "显示本地 Unbound root.key 的有效性与维护状态。在线 Unbound 继续使用 RFC5011 自动维护；手动刷新仅允许在解析器已停止、且未配置 VPN 绑定出口时执行，并使用 5 秒超时及失败回滚，避免刷新请求绕过 VPN 出口策略。",
        anchorState,
        btn("刷新信任锚状态",()->loadUnboundAnchorStatus(anchorState)),
        btn("安全条件下手动刷新信任锚",()->fxDialogBuilder().setTitle("手动刷新 DNSSEC 根信任锚")
          .setMessage("此操作需要 Unbound 当前已停止，且没有 VPN 绑定出口；不满足条件会拒绝执行。刷新最长等待 5 秒，失败会恢复原 root.key。解析器运行时由其 RFC5011 机制在线维护，不需要手动停止服务。是否继续？")
          .setNegativeButton("取消",null)
          .setPositiveButton("刷新",(dialog,which)->root("unbound-anchor-refresh",refresh->{
            if(refresh.exitCode==0)status.setText("DNSSEC 根信任锚已刷新并通过格式校验。");
            else fxDialogBuilder().setTitle("DNSSEC 信任锚未刷新")
              .setMessage(safe(refresh.output)).setPositiveButton("关闭",null).show();
            loadUnboundAnchorStatus(anchorState);
          })).show()));
    loadUnboundAnchorStatus(anchorState);

    card("DNSSEC Root Hints 更新",
        "通过 HTTPS 从 InterNIC 获取当前 named.root；更新前校验 A–M 13 个根服务器的 NS/A 记录，并生成新的 SHA-256 sidecar。仅允许 Unbound 已停止且没有 VPN egress 绑定时更新；失败会恢复原文件。此流程不执行 PGP detached-signature 校验。",
        btn("安全条件下更新 Root Hints",()->fxDialogBuilder().setTitle("更新 DNSSEC Root Hints")
          .setMessage("将通过 HTTPS 从 InterNIC 下载当前 named.root，并检查 13 个根服务器的 NS/A 记录后原子替换本地文件及 SHA-256 sidecar。要求 Unbound 已停止且不存在 VPN egress 绑定；失败时恢复旧文件。此流程不执行 PGP detached-signature 校验。是否继续？")
          .setNegativeButton("取消",null)
          .setPositiveButton("下载并更新",(dialog,which)->root("unbound-root-hints-refresh",refresh->{
            if(refresh.exitCode==0)status.setText("DNSSEC Root Hints 已更新。");
            else fxDialogBuilder().setTitle("Root Hints 未更新")
              .setMessage(safe(refresh.output)).setPositiveButton("关闭",null).show();
            loadUnboundAnchorStatus(anchorState);
          })).show()));

    card("过滤策略","DNS 和网络策略开关；与 DNS 上游地址分开保存。批量操作会一次性更新以下五项策略。",
       dnsSwitch("阻止 QUIC","block_quic"),
       dnsSwitch("阻止 DNS-over-TLS","block_dot"),
       dnsSwitch("阻止明文 DNS","block_plain_dns"),
       dnsSwitch("阻止 IPv6","block_ipv6"),
       dnsSwitch("跟踪域名保护","block_track_domains"),
       btn("一键启用全部过滤策略",()->setDnsFilterPolicy(true)),
       btn("一键关闭全部过滤策略",()->setDnsFilterPolicy(false)));
  android.widget.RadioGroup responseGroup=new android.widget.RadioGroup(this);
  responseGroup.setOrientation(android.widget.RadioGroup.VERTICAL);
  android.widget.RadioButton responseNx=new android.widget.RadioButton(this);
  responseNx.setText("NXDOMAIN（标准不存在响应）");
  responseNx.setId(View.generateViewId());
  android.widget.RadioButton responseRefused=new android.widget.RadioButton(this);
  responseRefused.setText("REFUSED（拒绝查询）");
  responseRefused.setId(View.generateViewId());
  android.widget.RadioButton responseNull=new android.widget.RadioButton(this);
  responseNull.setText("返回自定义 A/AAAA 地址");
  responseNull.setId(View.generateViewId());
  responseGroup.addView(responseNx);
  responseGroup.addView(responseRefused);
  responseGroup.addView(responseNull);
  responseGroup.check(responseNx.getId());
  EditText responseIpv4=draftField("dns_blocking_ipv4");
  responseIpv4.setSingleLine(true);
  responseIpv4.setHint("被拦截 A 查询返回地址，例如 0.0.0.0");
  EditText responseIpv6=draftField("dns_blocking_ipv6");
  responseIpv6.setSingleLine(true);
  responseIpv6.setHint("被拦截 AAAA 查询返回地址，例如 ::");
  EditText responseTtl=draftField("dns_blocked_response_ttl");
  responseTtl.setSingleLine(true);
  responseTtl.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
  responseTtl.setHint("拦截响应 TTL（秒），0 表示不缓存");
  TextView responseState=txt("正在读取 DNS 返回模式…",12,0xff617080,false);
  card("DNS 拦截返回模式",
       "选择被广告/黑名单规则拦截的域名如何响应。NXDOMAIN 与 REFUSED 不返回地址；自定义模式按下方 IPv4/IPv6 地址返回 A/AAAA 答案。TTL 为 0 至 4294967295 秒。",
       responseGroup,
       txt("自定义 IPv4（A 记录）",12,0xff617080,true),responseIpv4,
       txt("自定义 IPv6（AAAA 记录）",12,0xff617080,true),responseIpv6,
       txt("拦截响应 TTL（秒）",12,0xff617080,true),responseTtl,
       btn("保存并应用 DNS 返回策略",()->{
         int chosen=responseGroup.getCheckedRadioButtonId();
         String mode=chosen==responseRefused.getId()?"refused"
             :chosen==responseNull.getId()?"custom_ip":"nxdomain";
         String ipv4=responseIpv4.getText()==null?"":responseIpv4.getText().toString().trim();
         String ipv6=responseIpv6.getText()==null?"":responseIpv6.getText().toString().trim();
         String ttl=responseTtl.getText()==null?"":responseTtl.getText().toString().trim();
         if(!isValidDnsBlockingIpv4(ipv4)||!isValidDnsBlockingIpv6(ipv6)
             ||!isValidDnsBlockingTtl(ttl)){
           responseState.setText("自定义 IPv4/IPv6 地址或 TTL 无效，未提交。");
           return;
         }
         root("dns-response-config-set "+mode+" "+q(ipv4)+" "+q(ipv6)+" "+q(ttl),result->{
           if(result.exitCode==0){
             responseState.setText("已保存并应用："+mode+"；A="+ipv4+"；AAAA="+ipv6+"；TTL="+ttl+" 秒。");
             load();
           }else{
             responseState.setText("保存失败："+safe(result.output));
           }
         });
       }),
       btn("一键应用严格 DNS 保护配置",()->applyDnsSecurityProfile("nxdomain",true,responseState,responseGroup,responseNx,responseRefused,responseNull)),
       btn("恢复基础 DNS 拦截配置",()->applyDnsSecurityProfile("nxdomain",false,responseState,responseGroup,responseNx,responseRefused,responseNull)),
       responseState);
  root("dns-response-get",r->{
    if(r.exitCode!=0){responseState.setText("读取失败："+safe(r.output));return;}
    String[] lines=(r.output==null?"":r.output).split("\\r?\\n");
    if(lines.length<5||!"FXYULONGDNSRESP1".equals(lines[0].trim())){
      responseState.setText("DNS 返回策略响应格式错误，拒绝使用默认值。");return;
    }
    java.util.Map<String,String> values=new java.util.HashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||split==line.length()-1){
        responseState.setText("DNS 返回策略响应字段格式错误。");return;
      }
      String key=line.substring(0,split);
      if(!"mode".equals(key)&&!"blocking_ipv4".equals(key)
          &&!"blocking_ipv6".equals(key)&&!"blocked_response_ttl".equals(key)){
        responseState.setText("DNS 返回策略响应包含未知字段："+key);return;
      }
      if(values.put(key,line.substring(split+1))!=null){
        responseState.setText("DNS 返回策略响应包含重复字段："+key);return;
      }
    }
    String mode=values.get("mode"),ipv4=values.get("blocking_ipv4");
    String ipv6=values.get("blocking_ipv6"),ttl=values.get("blocked_response_ttl");
    if(values.size()!=4||!("nxdomain".equals(mode)||"refused".equals(mode)||"custom_ip".equals(mode))
        ||!isValidDnsBlockingIpv4(ipv4)||!isValidDnsBlockingIpv6(ipv6)
        ||!isValidDnsBlockingTtl(ttl)){
      responseState.setText("DNS 返回策略响应字段不完整或数值非法。");return;
    }
    responseGroup.check("refused".equals(mode)?responseRefused.getId()
        :"custom_ip".equals(mode)?responseNull.getId():responseNx.getId());
    responseIpv4.setText(ipv4);
    responseIpv6.setText(ipv6);
    responseTtl.setText(ttl);
    responseState.setText("当前模式："+mode+"；A="+ipv4+"；AAAA="+ipv6+"；TTL="+ttl+" 秒。");
  });
  EditText customServers=draftField("dns_custom_servers");
  customServers.setSingleLine(false);customServers.setMinLines(2);
  customServers.setHint("IPv4 / IPv6 / [IPv6]:端口 / https://DoH / tls://DoT / quic://DoQ");
  EditText fallbackServers=draftField("dns_fallback_servers");
  fallbackServers.setSingleLine(false);fallbackServers.setMinLines(2);
  fallbackServers.setHint("备用 DNS IPv4[:端口] / IPv6 / [IPv6]:端口");
  EditText globalServers=draftField("dns_global_servers");
  globalServers.setSingleLine(false);globalServers.setMinLines(2);
  globalServers.setHint("IPv4[:端口] / IPv6 / [IPv6]:端口");
  card("自定义/全局/备用 DNS 服务器",
       "自定义 DNS 支持任意多条上游地址（保留逐条格式与协议校验，不设置应用层条数上限），可混合 IPv4[:端口]、IPv6、[IPv6]:端口、DoH、DoT、DoQ；全局 DNS 和备用 DNS 均支持任意多条可路由 IPv4[:端口]、IPv6 和 [IPv6]:端口；留空时，启用自定义/全局外部上游会自动以 FX 本地 Unbound 作为故障回退。加密上游的域名引导解析经 FX 本地 Unbound 递归服务完成，不固定依赖公共 DNS；仅在 FX 本地 AdGuard Home 过滤引擎运行时生效；启用“阻止 DoT/QUIC”会阻断对应传输协议。",
       btn("一次性保存三组 DNS 上游",()->saveDnsServerLists(customServers,globalServers,fallbackServers)),
       txt("自定义 DNS 上游",12,0xff617080,true),customServers,
       btn("保存自定义 DNS",()->saveDnsServerList("custom",customServers)),
       btn("清除自定义 DNS",()->clearDnsSection("custom",customServers)),
       txt("备用 DNS（故障回退）",12,0xff617080,true),fallbackServers,
       btn("保存备用 DNS",()->saveDnsServerList("fallback",fallbackServers)),
       btn("清除备用 DNS",()->clearDnsSection("fallback",fallbackServers)),
       txt("全局 DNS 替换",12,0xff617080,true),globalServers,
       btn("保存全局 DNS",()->saveDnsServerList("global",globalServers)),
       btn("清除全局 DNS",()->clearDnsSection("global",globalServers)));
  EditText remoteDns=draftField("vpn_remote_dns");
  remoteDns.setSingleLine(true);remoteDns.setHint("VPN 远端 DNS，例如 1.1.1.1");
  EditText cnDns=draftField("vpn_cn_dns");
  cnDns.setSingleLine(true);cnDns.setHint("国内直连 DNS，例如 223.5.5.5");
  card("VPN 节点 DNS",
       "编辑 FX VPN 配置中的 remote_dns/cn_dns；它们不会替换本地 Unbound 递归模式，只有 VPN DNS 劫持/分流使用时生效。",
       txt("远端 DNS",12,0xff617080,true),remoteDns,
       btn("保存远端 DNS",()->saveVpnDns("remote_dns",remoteDns)),
       txt("国内直连 DNS",12,0xff617080,true),cnDns,
       btn("保存国内直连 DNS",()->saveVpnDns("cn_dns",cnDns)),
       btn("一次性保存两组 VPN DNS",()->saveVpnDnsPair(remoteDns,cnDns)),
       btn("恢复 VPN DNS 默认值",()->fxDialogBuilder().setTitle("恢复 VPN DNS 默认值")
         .setMessage("将远端 DNS 恢复为 1.1.1.1，国内直连 DNS 恢复为 223.5.5.5。两项在同一配置事务中写入，失败时回滚。是否继续？")
         .setNegativeButton("取消",null).setPositiveButton("恢复",(d,w)->root("dns-vpn-reset",r->{
           if(r.exitCode==0){remoteDns.setText("1.1.1.1");cnDns.setText("223.5.5.5");status.setText("VPN DNS 默认值已恢复。");load();}
           else fxDialogBuilder().setTitle("恢复失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
         })).show()));
  card("DNS 域名重写","为指定域名固定返回 IPv4、IPv6 地址或 CNAME 目标；仅影响匹配的 DNS 查询，不改变其他域名的上游解析。",btn("编辑 DNS 域名重写规则",()->chooseDnsRewrites()));
   card("DNS 查询日志","默认关闭。启用后仅在本机保存逐条查询记录；客户端 IP 始终匿名化且不会写入查询日志；可独立设置日志轮转周期和内存刷盘批量。",
       dnsSwitch("启用本地 DNS 查询日志","dns_querylog_enabled"),
       btn("设置日志保留期限",()->chooseDnsQueryLogRetention()),
       btn("设置日志内存刷盘批量",()->chooseDnsQueryLogMemorySize()),
       btn("设置逐条日志排除域名",()->chooseDnsQueryLogIgnoredDomains()),
       btn("查看 DNS 查询日志",()->startActivity(new Intent(this,FxYulongDnsActivity.class))));
  card("DNS 聚合统计数据库","与逐条查询日志独立控制。可设置本机统计开关、轮转周期和排除域名列表；排除域名只影响聚合统计，不改变 DNS 拦截/放行，也不会清理逐条查询日志。",
       btn("设置本地 DNS 聚合统计",()->chooseDnsStatisticsSettings()));
  card("DNS 缓存管理","可分别刷新 FX 自有 AdGuard Home 或 Unbound，也可同时刷新两者。所选解析服务会短暂重启；第三方 VPN 和它的规则不会被停止。",
       btn("刷新 AdGuard Home 缓存",()->refreshDnsCache("adguardhome","AdGuard Home")),
       btn("刷新 Unbound 缓存",()->refreshDnsCache("unbound","Unbound")),
       btn("刷新全部本地 DNS 缓存",()->refreshDnsCache("all","全部本地 DNS")));
  card("第三方 VPN DNS 过滤回退",
       "只有在系统确认唯一活动第三方 VPN、接口/所属 UID/出口路由有效，且 Unbound/AdGuard Home 健康探测通过后才接管明文 DNS。失败会撤销 FX 自有规则并保留第三方 VPN DNS。",
       dnsSwitch("第三方 VPN 下启用 Root DNS 过滤","vpn_external_dns_proxy"),
       btn("刷新 Root Proxy 状态",()->root("rootproxy-status",r->{fxDialogBuilder().setTitle("Root Proxy 状态").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})),
       btn("立即检查并重绑 VPN DNS 路由",()->root("rootproxy-reconcile-route",r->{fxDialogBuilder().setTitle(r.exitCode==0?"VPN DNS 路由检查完成":"VPN DNS 路由检查未完成").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})));
  loadDnsLists(customServers,globalServers,fallbackServers,remoteDns,cnDns);
}
 private void refreshDnsCache(String target,String label){
   fxDialogBuilder().setTitle("刷新"+label+"缓存")
     .setMessage("FX 将仅重启所选的自有 DNS 解析服务并重新应用路由。刷新期间相关 DNS 查询可能短暂重试；不会操作第三方 VPN。若所选引擎未启用，FX 会拒绝操作。是否继续？")
     .setNegativeButton("取消",null).setPositiveButton("刷新",(d,w)->root("cache-flush "+target,r->{
       fxDialogBuilder().setTitle(r.exitCode==0?"DNS 缓存已刷新":"DNS 刷新未完全成功")
         .setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
     })).show();
 }
private void shareDnsProfile(){
  root("dns-profile-get",r->{
    if(r.exitCode!=0){status.setText("DNS 配置快照读取失败："+safe(r.output));return;}
    String raw=r.output==null?"":r.output.trim();
    if(!raw.startsWith("FXYULONGDNSPROFILE1")){status.setText("DNS 配置快照格式不受支持，未生成备份。");return;}
    String payload="FXYULONGDNSPROFILE1\n"+raw.substring("FXYULONGDNSPROFILE1".length()).trim()+"\n";
    pendingDnsProfileExport=payload;
    try{
      Intent create=new Intent(Intent.ACTION_CREATE_DOCUMENT);
      create.addCategory(Intent.CATEGORY_OPENABLE);
      create.setType("text/plain");
      create.putExtra(Intent.EXTRA_TITLE,"FX-DNS-profile.txt");
      startActivityForResult(create,DNS_PROFILE_SHARE_REQUEST);
      status.setText("请选择临时分享文件的位置；保存后将通过文件 URI 打开系统分享面板，不再把完整 DNS 快照塞进跨进程文本参数。");
    }catch(RuntimeException unavailable){
      pendingDnsProfileExport="";
      status.setText("无法打开系统文件保存器："+safe(unavailable.getMessage()));
    }
  });
}
private void saveDnsProfileToFile(){
  root("dns-profile-get",r->{
    if(r.exitCode!=0){status.setText("DNS 配置快照读取失败："+safe(r.output));return;}
    String raw=r.output==null?"":r.output.trim();
    if(!raw.startsWith("FXYULONGDNSPROFILE1")){status.setText("DNS 配置快照格式不受支持，未导出。");return;}
    String payload="FXYULONGDNSPROFILE1\n"
        +raw.substring("FXYULONGDNSPROFILE1".length()).trim()+"\n";
    pendingDnsProfileExport=payload;
    try{
      Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);
      intent.addCategory(Intent.CATEGORY_OPENABLE);
      intent.setType("text/plain");
      intent.putExtra(Intent.EXTRA_TITLE,"FX-DNS-profile.txt");
      startActivityForResult(intent,DNS_PROFILE_SAVE_REQUEST);
    }catch(RuntimeException unavailable){
      pendingDnsProfileExport="";
      status.setText("无法打开系统文件保存器："+safe(unavailable.getMessage()));
    }
  });
}
private void openDnsProfileFile(){
  try{
    Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("text/*");
    startActivityForResult(intent,DNS_PROFILE_OPEN_REQUEST);
  }catch(RuntimeException unavailable){
    status.setText("无法打开系统文件选择器："+safe(unavailable.getMessage()));
  }
}
@Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
  super.onActivityResult(requestCode,resultCode,data);
  if(requestCode==DNS_DIAGNOSTIC_SAVE_REQUEST){
     String report=pendingDnsDiagnosticExport;
     pendingDnsDiagnosticExport="";
     if(resultCode!=Activity.RESULT_OK||data==null||data.getData()==null){
       status.setText("已取消 DNS 诊断报告文件保存。");
       return;
     }
     if(report.isEmpty()){
       status.setText("DNS 诊断报告内容已失效，请重新执行诊断。");
       return;
     }
     try(java.io.OutputStream stream=getContentResolver().openOutputStream(data.getData(),"w")){
       if(stream==null)throw new java.io.IOException("无法打开目标文件");
       stream.write(report.getBytes(java.nio.charset.StandardCharsets.UTF_8));
       stream.flush();
       status.setText("DNS 诊断报告已保存到所选文件。报告不包含查询域名、客户端 IP 或原始查询日志。");
     }catch(Exception failure){
       status.setText("DNS 诊断报告保存失败："+safe(failure.getMessage()));
     }
     return;
   }
   if(requestCode==DNS_PROFILE_SAVE_REQUEST||requestCode==DNS_PROFILE_SHARE_REQUEST){
    boolean shareAfterSave=requestCode==DNS_PROFILE_SHARE_REQUEST;
    String payload=pendingDnsProfileExport;
    pendingDnsProfileExport="";
    if(resultCode!=Activity.RESULT_OK||data==null||data.getData()==null){
      status.setText(shareAfterSave?"已取消 DNS 快照分享文件选择。":"已取消 DNS 快照文件保存。");return;
    }
    if(payload.isEmpty()){status.setText("DNS 快照导出内容已失效，请重新操作。");return;}
    android.net.Uri targetUri=data.getData();
    try(java.io.OutputStream stream=getContentResolver().openOutputStream(targetUri,"w")){
      if(stream==null)throw new java.io.IOException("无法打开目标文件");
      stream.write(payload.getBytes(java.nio.charset.StandardCharsets.UTF_8));
      stream.flush();
    }catch(Exception failure){
      status.setText("DNS 快照文件保存失败："+safe(failure.getMessage()));
      return;
    }
    if(shareAfterSave){
      try{
        Intent send=new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT,"FX Hook DNS 配置备份");
        send.putExtra(Intent.EXTRA_STREAM,targetUri);
        send.setClipData(android.content.ClipData.newUri(getContentResolver(),"FX DNS profile",targetUri));
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(Intent.createChooser(send,"分享 DNS 配置快照"));
        status.setText("DNS 配置快照已写入文件并通过文件 URI 打开系统分享面板。");
      }catch(RuntimeException unavailable){
        status.setText("DNS 快照文件已保存，但无法打开系统分享面板："+safe(unavailable.getMessage()));
      }
    }else{
      status.setText("DNS 配置快照已保存到所选文件。");
    }
    return;
  }
  if(requestCode==DNS_PROFILE_OPEN_REQUEST){
    if(resultCode!=Activity.RESULT_OK||data==null||data.getData()==null){
      status.setText("已取消 DNS 快照文件读取。");return;
    }
    try(java.io.InputStream stream=getContentResolver().openInputStream(data.getData())){
      if(stream==null)throw new java.io.IOException("无法读取所选文件");
      java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();
      byte[] buffer=new byte[4096];int count;
      while((count=stream.read(buffer))!=-1){
        bytes.write(buffer,0,count);
      }
      String content=java.nio.charset.StandardCharsets.UTF_8.newDecoder()
          .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
          .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
          .decode(java.nio.ByteBuffer.wrap(bytes.toByteArray())).toString();
      if(dnsProfileImportField==null)throw new java.io.IOException("DNS 配置页面已关闭");
      dnsProfileImportField.setText(content);
      dnsProfileImportField.setSelection(dnsProfileImportField.length());
      status.setText("DNS 快照文件已读取；请先检查内容，再点击“校验并恢复”。");
    }catch(Exception failure){
      status.setText("DNS 快照文件读取失败："+safe(failure.getMessage()));
    }
  }
}
private void restoreDnsProfile(EditText input){
  String supplied=input.getText()==null?"":input.getText().toString();
  if(supplied.trim().isEmpty()){status.setText("请先粘贴 DNS 配置快照。");return;}
  StringBuilder normalized=new StringBuilder();
  for(String line:supplied.split("\\r?\\n")){
    String trimmed=line.trim();
    if(trimmed.isEmpty()||trimmed.startsWith("#"))continue;
    if(normalized.length()>0)normalized.append('\n');
    normalized.append(trimmed);
  }
  String raw=normalized.toString();
  if(!raw.startsWith("FXYULONGDNSPROFILE1\n")&&!raw.equals("FXYULONGDNSPROFILE1")){
    status.setText("快照版本头不匹配，未修改配置。");return;
  }
  byte[] bytes=raw.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String[] allowed={"dns_engine_adguardhome","dns_forward","custom_dns","global_dns",
      "block_quic","block_dot","block_plain_dns","block_ipv6","block_track_domains",
      "vpn_external_dns_proxy","vpn_external_compat","dns_querylog_enabled",
      "CUSTOM_SERVERS","GLOBAL_SERVERS","FALLBACK_SERVERS","VPN_REMOTE","VPN_CN","RESPONSE_MODE","RESPONSE_IPV4","RESPONSE_IPV6","RESPONSE_TTL","QUERYLOG_RETENTION","QUERYLOG_MEMORY_SIZE","QUERYLOG_IGNORED_ENABLED","QUERYLOG_IGNORED","DNS_REWRITES","STATISTICS_ENABLED","STATISTICS_INTERVAL","STATISTICS_IGNORED_ENABLED","STATISTICS_IGNORED",
      "UPSTREAM_MODE","FASTEST_TIMEOUT","UPSTREAM_TIMEOUT","CACHE_SIZE","CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC",
      "CACHE_TTL_MIN","CACHE_TTL_MAX","CACHE_OPTIMISTIC_ANSWER_TTL","CACHE_OPTIMISTIC_MAX_AGE",
      "UNBOUND_CACHE_MAX_TTL","UNBOUND_CACHE_MIN_TTL","UNBOUND_SERVE_EXPIRED","UNBOUND_SERVE_EXPIRED_TTL",
      "UNBOUND_SERVE_EXPIRED_REPLY_TTL","UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION",
      "UNBOUND_MSG_CACHE_SIZE","UNBOUND_RRSET_CACHE_SIZE","UNBOUND_KEY_CACHE_SIZE","UNBOUND_NEG_CACHE_SIZE","UNBOUND_NUM_THREADS"};
  java.util.Set<String> keys=new java.util.HashSet<>(java.util.Arrays.asList(allowed));
  java.util.Map<String,String> preview=new java.util.LinkedHashMap<>();
  for(String line:raw.split("\\n")){
    if("FXYULONGDNSPROFILE1".equals(line))continue;
    int split=line.indexOf('=');
    if(split<=0){status.setText("快照字段格式错误，未提交。");return;}
    String key=line.substring(0,split);
    if(!keys.contains(key)||preview.containsKey(key)){
      status.setText("快照包含未知或重复字段："+key+"；未提交。");return;
    }
    preview.put(key,line.substring(split+1));
  }
  for(String key:allowed)if(!preview.containsKey(key)){
    if("RESPONSE_IPV4".equals(key))preview.put(key,"0.0.0.0");
    else if("RESPONSE_IPV6".equals(key))preview.put(key,"::");
    else if("RESPONSE_TTL".equals(key))preview.put(key,"10");
    else if("QUERYLOG_RETENTION".equals(key))preview.put(key,"7d");
    else if("QUERYLOG_MEMORY_SIZE".equals(key))preview.put(key,"1000");
    else if("QUERYLOG_IGNORED_ENABLED".equals(key))preview.put(key,"0");
    else if("QUERYLOG_IGNORED".equals(key))preview.put(key,"");
    else if("DNS_REWRITES".equals(key))preview.put(key,"");
    else if("STATISTICS_ENABLED".equals(key))preview.put(key,"0");
    else if("STATISTICS_INTERVAL".equals(key))preview.put(key,"10d");
    else if("STATISTICS_IGNORED_ENABLED".equals(key))preview.put(key,"0");
    else if("STATISTICS_IGNORED".equals(key))preview.put(key,"");
    else if("UPSTREAM_MODE".equals(key))preview.put(key,"load_balance");
    else if("FASTEST_TIMEOUT".equals(key))preview.put(key,"1s");
    else if("UPSTREAM_TIMEOUT".equals(key))preview.put(key,"10s");
    else if("CACHE_SIZE".equals(key))preview.put(key,"4194304");
    else if("CACHE_ENABLED".equals(key))preview.put(key,"1");
    else if("CACHE_OPTIMISTIC".equals(key))preview.put(key,"0");
    else if("ENABLE_DNSSEC".equals(key))preview.put(key,"1");
    else if("CACHE_TTL_MIN".equals(key))preview.put(key,"0");
    else if("CACHE_TTL_MAX".equals(key))preview.put(key,"0");
    else if("CACHE_OPTIMISTIC_ANSWER_TTL".equals(key))preview.put(key,"30s");
    else if("CACHE_OPTIMISTIC_MAX_AGE".equals(key))preview.put(key,"12h");
    else if("UNBOUND_CACHE_MAX_TTL".equals(key))preview.put(key,"86400");
    else if("UNBOUND_CACHE_MIN_TTL".equals(key))preview.put(key,"0");
    else if("UNBOUND_SERVE_EXPIRED".equals(key))preview.put(key,"1");
    else if("UNBOUND_SERVE_EXPIRED_TTL".equals(key))preview.put(key,"86400");
    else if("UNBOUND_SERVE_EXPIRED_REPLY_TTL".equals(key))preview.put(key,"30");
    else if("UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT".equals(key))preview.put(key,"1800");
    else if("UNBOUND_PREFETCH".equals(key))preview.put(key,"1");
    else if("UNBOUND_PREFETCH_KEY".equals(key))preview.put(key,"1");
    else if("UNBOUND_QNAME_MINIMISATION".equals(key))preview.put(key,"1");
    else if("UNBOUND_MSG_CACHE_SIZE".equals(key))preview.put(key,"8m");
    else if("UNBOUND_RRSET_CACHE_SIZE".equals(key))preview.put(key,"16m");
    else if("UNBOUND_KEY_CACHE_SIZE".equals(key))preview.put(key,"4m");
    else if("UNBOUND_NEG_CACHE_SIZE".equals(key))preview.put(key,"2m");
    else if("UNBOUND_NUM_THREADS".equals(key))preview.put(key,"1");
    else {status.setText("快照缺少字段："+key+"；未提交。");return;}
  }
  for(String key:new String[]{"dns_engine_adguardhome","dns_forward","custom_dns","global_dns",
      "block_quic","block_dot","block_plain_dns","block_ipv6","block_track_domains",
      "vpn_external_dns_proxy","vpn_external_compat","dns_querylog_enabled","QUERYLOG_IGNORED_ENABLED","STATISTICS_ENABLED","STATISTICS_IGNORED_ENABLED"}){
    String value=preview.get(key);
    if(!"0".equals(value)&&!"1".equals(value)){
      status.setText("快照开关值非法："+key+"；未提交。");return;
    }
  }
  for(String key:new String[]{"VPN_REMOTE","VPN_CN"}){
    if(!isValidProfileIpv4(preview.get(key))){
      status.setText("快照 VPN DNS 地址不是有效 IPv4："+key+"；未提交。");return;
    }
  }
  String responseMode=preview.get("RESPONSE_MODE");
  if(!"nxdomain".equals(responseMode)&&!"refused".equals(responseMode)&&!"custom_ip".equals(responseMode)){
    status.setText("快照拦截响应模式非法；未提交。");return;
  }
  if(!isValidDnsBlockingIpv4(preview.get("RESPONSE_IPV4"))
      ||!isValidDnsBlockingIpv6(preview.get("RESPONSE_IPV6"))
      ||!isValidDnsBlockingTtl(preview.get("RESPONSE_TTL"))){
    status.setText("快照 DNS 拦截 IPv4/IPv6 地址或 TTL 无效；未提交。");return;
  }
  String querylogRetention=preview.get("QUERYLOG_RETENTION");
  if(!isValidDnsQueryLogRetention(querylogRetention)){
    status.setText("快照 DNS 查询日志保留期限非法；未提交。");return;
  }
  if(!isValidDnsQueryLogMemorySize(preview.get("QUERYLOG_MEMORY_SIZE"))){
    status.setText("快照 DNS 查询日志缓冲批量非法；未提交。");return;
  }
  if(!isValidDnsQueryLogRetention(preview.get("STATISTICS_INTERVAL"))){
    status.setText("快照 DNS 聚合统计周期非法；未提交。");return;
  }
  try{
    preview.put("QUERYLOG_IGNORED",
        normalizeDnsStatisticsDomains(preview.get("QUERYLOG_IGNORED"),true));
  }catch(IllegalArgumentException invalid){
    status.setText("快照逐条日志排除域名列表非法："+invalid.getMessage()+"；未提交。");
    return;
  }
  try{
    preview.put("DNS_REWRITES",normalizeDnsRewrites(preview.get("DNS_REWRITES")));
  }catch(IllegalArgumentException invalid){
    status.setText("快照 DNS 域名重写规则非法："+invalid.getMessage()+"；未提交。");
    return;
  }
  try{
    preview.put("STATISTICS_IGNORED",
        normalizeDnsStatisticsDomains(preview.get("STATISTICS_IGNORED"),true));
  }catch(IllegalArgumentException invalid){
    status.setText("快照 DNS 统计排除域名列表非法："+invalid.getMessage()+"；未提交。");
    return;
  }
  if(!isValidDnsRuntimeMode(preview.get("UPSTREAM_MODE"))
      ||!isValidDnsRuntimeFastestTimeout(preview.get("FASTEST_TIMEOUT"))
      ||!isValidDnsRuntimeUpstreamTimeout(preview.get("UPSTREAM_TIMEOUT"))
      ||!isValidDnsRuntimeCacheSize(preview.get("CACHE_SIZE"))){
    status.setText("快照包含无效的 DNS 上游策略、超时或缓存容量；未提交。");return;
  }
  for(String key:new String[]{"CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC"})
    if(!"0".equals(preview.get(key))&&!"1".equals(preview.get(key))){
      status.setText("快照 DNS 引擎开关值非法："+key+"；未提交。");return;
    }
  if(!isValidDnsRuntimeCacheTtl(preview.get("CACHE_TTL_MIN"),preview.get("CACHE_TTL_MAX"))
      ||!isValidDnsRuntimeOptimisticAnswerTtl(preview.get("CACHE_OPTIMISTIC_ANSWER_TTL"))
      ||!isValidDnsRuntimeDuration(preview.get("CACHE_OPTIMISTIC_MAX_AGE"))){
    status.setText("快照 DNS 缓存 TTL 或乐观缓存期限非法；未提交。");return;
  }
  if(!isValidDnsRuntimeUint32(preview.get("UNBOUND_CACHE_MAX_TTL"),false)
      ||!isValidDnsRuntimeUint32(preview.get("UNBOUND_CACHE_MIN_TTL"),true)
      ||new java.math.BigInteger(preview.get("UNBOUND_CACHE_MIN_TTL"))
          .compareTo(new java.math.BigInteger(preview.get("UNBOUND_CACHE_MAX_TTL")))>0
      ||!isValidDnsRuntimeUint32(preview.get("UNBOUND_SERVE_EXPIRED_TTL"),true)
      ||!isValidDnsRuntimeUint32(preview.get("UNBOUND_SERVE_EXPIRED_REPLY_TTL"),false)
      ||!isValidDnsRuntimeUint32(preview.get("UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT"),true)){
    status.setText("快照 Unbound TTL 或 serve-expired 时长非法；未提交。");return;
  }
  for(String key:new String[]{"UNBOUND_SERVE_EXPIRED","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION"})
    if(!"0".equals(preview.get(key))&&!"1".equals(preview.get(key))){
      status.setText("快照 Unbound 开关值非法："+key+"；未提交。");return;
    }
  for(String key:new String[]{"UNBOUND_MSG_CACHE_SIZE","UNBOUND_RRSET_CACHE_SIZE","UNBOUND_KEY_CACHE_SIZE","UNBOUND_NEG_CACHE_SIZE"})
    if(!isValidUnboundCacheSize(preview.get(key))){
      status.setText("快照 Unbound 内存缓存池大小无效："+key+"；未提交。");return;
    }
  if(!isValidDnsRuntimeUint32(preview.get("UNBOUND_NUM_THREADS"),false)){
    status.setText("快照 Unbound worker 线程数必须为正整数；未提交。");return;
  }
  for(String key:new String[]{"CUSTOM_SERVERS","GLOBAL_SERVERS","FALLBACK_SERVERS"}){
    String value=preview.get(key);
    boolean encrypted="CUSTOM_SERVERS".equals(key);
    if(!isValidProfileDnsCsv(value,encrypted)){
      status.setText("快照 DNS 上游格式非法或存在重复项："+key+"；未提交。");return;
    }
  }
  if("1".equals(preview.get("global_dns"))&&countDnsEndpoints(preview.get("GLOBAL_SERVERS"))==0){
    status.setText("快照启用了全局 DNS，但全局上游列表为空；未提交。");return;
  }
  if("1".equals(preview.get("custom_dns"))&&countDnsEndpoints(preview.get("CUSTOM_SERVERS"))==0){
    status.setText("快照启用了自定义 DNS，但自定义上游列表为空；未提交。");return;
  }
  int enabled=0;
  for(String key:new String[]{"dns_engine_adguardhome","dns_forward","custom_dns","global_dns",
      "block_quic","block_dot","block_plain_dns","block_ipv6","block_track_domains",
      "vpn_external_dns_proxy","vpn_external_compat","dns_querylog_enabled"})
    if("1".equals(preview.get(key)))enabled++;
  for(String key:new String[]{"CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC"})if("1".equals(preview.get(key)))enabled++;
  for(String key:new String[]{"UNBOUND_SERVE_EXPIRED","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION"})
    if("1".equals(preview.get(key)))enabled++;
  if("1".equals(preview.get("QUERYLOG_IGNORED_ENABLED")))enabled++;
  if("1".equals(preview.get("STATISTICS_ENABLED")))enabled++;
  if("1".equals(preview.get("STATISTICS_IGNORED_ENABLED")))enabled++;
  String summary="快照包含 "+allowed.length+" 项字段、22 个开关（启用 "+enabled+" 项）。\n"
      +"自定义上游："+countDnsEndpoints(preview.get("CUSTOM_SERVERS"))+" 条；"
      +"全局上游："+countDnsEndpoints(preview.get("GLOBAL_SERVERS"))+" 条；"
      +"备用上游："+countDnsEndpoints(preview.get("FALLBACK_SERVERS"))+" 条。\n"
      +"VPN 远端 DNS："+preview.get("VPN_REMOTE")+"；国内 DNS："+preview.get("VPN_CN")+"。\n"
      +"拦截响应模式："+preview.get("RESPONSE_MODE")+"（IPv4 "+preview.get("RESPONSE_IPV4")+"；IPv6 "+preview.get("RESPONSE_IPV6")+"；TTL "+preview.get("RESPONSE_TTL")+" 秒）；查询日志保留："+querylogRetention
      +"；内存刷盘批量："+preview.get("QUERYLOG_MEMORY_SIZE")+"（0 表示逐条写盘）；逐条日志排除："+preview.get("QUERYLOG_IGNORED_ENABLED")+"（"+(preview.get("QUERYLOG_IGNORED").isEmpty()?0:preview.get("QUERYLOG_IGNORED").split(",").length)+" 个）；DNS 重写："+(preview.get("DNS_REWRITES").isEmpty()?0:preview.get("DNS_REWRITES").split(",").length)+" 条；聚合统计："+preview.get("STATISTICS_ENABLED")+"，周期 "+preview.get("STATISTICS_INTERVAL")+"；统计排除："+preview.get("STATISTICS_IGNORED_ENABLED")+"（"+(preview.get("STATISTICS_IGNORED").isEmpty()?0:preview.get("STATISTICS_IGNORED").split(",").length)+" 个）。\n"
      +"上游策略："+preview.get("UPSTREAM_MODE")+"；fastest 超时："+preview.get("FASTEST_TIMEOUT")+"；上游超时："+preview.get("UPSTREAM_TIMEOUT")+"。\n"
      +"DNS 缓存："+preview.get("CACHE_SIZE")+" 字节；缓存 TTL："+preview.get("CACHE_TTL_MIN")+"~"+preview.get("CACHE_TTL_MAX")+" 秒；乐观缓存："+preview.get("CACHE_OPTIMISTIC")+"（答复 TTL "+preview.get("CACHE_OPTIMISTIC_ANSWER_TTL")+"，最大年龄 "+preview.get("CACHE_OPTIMISTIC_MAX_AGE")+"）；DNSSEC："+preview.get("ENABLE_DNSSEC")+"。\n"
      +"Unbound 工作线程："+preview.get("UNBOUND_NUM_THREADS")+"（设备在线核心数由 Root 恢复时再次校验）；缓存 TTL："+preview.get("UNBOUND_CACHE_MIN_TTL")+"~"+preview.get("UNBOUND_CACHE_MAX_TTL")+" 秒；消息/RRset/Key/否定缓存池："+preview.get("UNBOUND_MSG_CACHE_SIZE")+"/"+preview.get("UNBOUND_RRSET_CACHE_SIZE")+"/"+preview.get("UNBOUND_KEY_CACHE_SIZE")+"/"+preview.get("UNBOUND_NEG_CACHE_SIZE")+"；serve-expired："+preview.get("UNBOUND_SERVE_EXPIRED")+"（最大年龄 "+preview.get("UNBOUND_SERVE_EXPIRED_TTL")+" 秒、答复 TTL "+preview.get("UNBOUND_SERVE_EXPIRED_REPLY_TTL")+" 秒、客户端等待 "+preview.get("UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT")+" 毫秒）；预取："+preview.get("UNBOUND_PREFETCH")+"；DNSSEC 密钥预取："+preview.get("UNBOUND_PREFETCH_KEY")+"；QNAME minimisation："+preview.get("UNBOUND_QNAME_MINIMISATION")+"。\n\n"
      +"这是本地结构预览，不代表端点及配置语义已通过后端校验；继续后仍由 FX Root 后端完整校验。";
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  root("dns-profile-get",currentResult->{
    if(currentResult.exitCode!=0){
      status.setText("无法读取当前 DNS 配置，已停止恢复预览："+safe(currentResult.output));return;
    }
    java.util.Map<String,String> current=new java.util.LinkedHashMap<>();
    String currentRaw=currentResult.output==null?"":currentResult.output.trim();
    String[] currentLines=currentRaw.split("\\r?\\n");
    if(currentLines.length==0||!"FXYULONGDNSPROFILE1".equals(currentLines[0].trim())){
      status.setText("当前 DNS 配置快照格式异常，已停止恢复预览。");return;
    }
    for(int index=1;index<currentLines.length;index++){
      String line=currentLines[index].trim();int split=line.indexOf('=');
      if(split<=0||current.put(line.substring(0,split),line.substring(split+1))!=null){
        status.setText("当前 DNS 配置包含异常或重复字段，已停止恢复预览。");return;
      }
    }
    String[] labels={"dns_engine_adguardhome","dns_forward","custom_dns","global_dns",
      "block_quic","block_dot","block_plain_dns","block_ipv6","block_track_domains",
      "vpn_external_dns_proxy","vpn_external_compat","dns_querylog_enabled",
      "CUSTOM_SERVERS","GLOBAL_SERVERS","FALLBACK_SERVERS","VPN_REMOTE","VPN_CN","RESPONSE_MODE","RESPONSE_IPV4","RESPONSE_IPV6","RESPONSE_TTL","QUERYLOG_RETENTION","QUERYLOG_MEMORY_SIZE","QUERYLOG_IGNORED_ENABLED","QUERYLOG_IGNORED","DNS_REWRITES","STATISTICS_ENABLED","STATISTICS_INTERVAL","STATISTICS_IGNORED_ENABLED","STATISTICS_IGNORED",
      "UPSTREAM_MODE","FASTEST_TIMEOUT","UPSTREAM_TIMEOUT","CACHE_SIZE","CACHE_ENABLED","CACHE_OPTIMISTIC","ENABLE_DNSSEC",
      "CACHE_TTL_MIN","CACHE_TTL_MAX","CACHE_OPTIMISTIC_ANSWER_TTL","CACHE_OPTIMISTIC_MAX_AGE",
      "UNBOUND_CACHE_MAX_TTL","UNBOUND_CACHE_MIN_TTL","UNBOUND_SERVE_EXPIRED","UNBOUND_SERVE_EXPIRED_TTL",
      "UNBOUND_SERVE_EXPIRED_REPLY_TTL","UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT","UNBOUND_PREFETCH","UNBOUND_PREFETCH_KEY","UNBOUND_QNAME_MINIMISATION",
      "UNBOUND_MSG_CACHE_SIZE","UNBOUND_RRSET_CACHE_SIZE","UNBOUND_KEY_CACHE_SIZE","UNBOUND_NEG_CACHE_SIZE","UNBOUND_NUM_THREADS"};
    StringBuilder changes=new StringBuilder();
    for(String key:labels){
      String oldValue=current.get(key),newValue=preview.get(key);
      if(oldValue==null){status.setText("当前 DNS 配置缺少字段："+key+"，已停止恢复预览。");return;}
      if(!oldValue.equals(newValue))changes.append(key).append("：").append(oldValue)
          .append(" → ").append(newValue).append('\n');
    }
    String changeText=changes.length()==0?"与当前 DNS 配置完全一致，无字段变化。":
        "将变更以下字段：\n"+changes;
    fxDialogBuilder().setTitle("DNS 快照导入预览")
      .setMessage(summary+"\n\n"+changeText)
      .setNegativeButton("取消",null)
      .setPositiveButton("继续恢复",(d,w)->fxDialogBuilder().setTitle("确认完整替换 DNS 配置")
        .setMessage("将完整替换当前 DNS 引擎开关、过滤策略、全部上游服务器、VPN DNS、拦截响应模式、自定义 IPv4/IPv6 响应地址与 TTL、日志保留期限/内存刷盘批量/逐条日志排除域名/DNS 域名重写规则、DNS 聚合统计开关/周期/排除域名、上游选择/超时、AdGuard Home 缓存容量/TTL/乐观缓存策略、DNSSEC，以及 Unbound 缓存 TTL、消息/RRset/DNSSEC Key/否定响应四类缓存池、serve-expired、域名预取、DNSSEC 密钥预取和 QNAME minimisation。后端会再次校验全部字段；恢复应用失败会回滚原配置。不会修改 VPN 节点或其他 FX 模块设置。")
        .setNegativeButton("取消",null)
        .setPositiveButton("恢复",(dialog,which)->root("dns-profile-restore "+encoded,r->{
          if(r.exitCode==0){status.setText("DNS 配置快照已恢复并应用。");input.setText("");load();}
          else fxDialogBuilder().setTitle("DNS 快照恢复失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
        })).show()).show();
  });
private boolean isValidDnsBlockingIpv4(String value){
  if(value==null||!value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}"))return false;
  for(String part:value.split("\\.",-1)){
    try{
      if(part.length()>1&&part.charAt(0)=='0')return false;
      int octet=Integer.parseInt(part);
      if(octet<0||octet>255)return false;
    }catch(NumberFormatException invalid){return false;}
  }
  return true;
}
private boolean isValidDnsBlockingIpv6(String value){
  return isValidProfileDnsIpv6(value);
}
private boolean isValidDnsBlockingTtl(String value){
  if(value==null||!value.matches("[0-9]+"))return false;
  try{
    java.math.BigInteger ttl=new java.math.BigInteger(value);
    return ttl.signum()>=0&&ttl.compareTo(new java.math.BigInteger("4294967295"))<=0;
  }catch(NumberFormatException invalid){return false;}
}
private boolean isValidProfileIpv4(String value){
  if(value==null||!value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")||
      "0.0.0.0".equals(value)||"255.255.255.255".equals(value))return false;
  String[] parts=value.split("\\.");
  try{
    int first=Integer.parseInt(parts[0]),second=Integer.parseInt(parts[1]);
    for(String part:parts){
      int octet=Integer.parseInt(part);
      if(octet>255||(part.length()>1&&part.charAt(0)=='0'))return false;
    }
    return first!=0&&first!=127&&first<224&&!(first==169&&second==254);
  }catch(NumberFormatException invalid){return false;}
}
private boolean isValidProfileDnsIpv6(String address){
  if(address==null||address.isEmpty()||!address.matches("[0-9A-Fa-f:]+")||address.contains(":::"))return false;
  int compressed=address.indexOf("::");
  if(compressed>=0&&address.indexOf("::",compressed+2)>=0)return false;
  if(compressed<0){
    String[] groups=address.split(":",-1);
    if(groups.length!=8)return false;
    for(String group:groups)if(group.isEmpty()||group.length()>4)return false;
    return true;
  }
  String left=address.substring(0,compressed),right=address.substring(compressed+2);
  int count=0;
  if(!left.isEmpty()){
    String[] groups=left.split(":",-1);
    for(String group:groups)if(group.isEmpty()||group.length()>4)return false;
    count+=groups.length;
  }
  if(!right.isEmpty()){
    String[] groups=right.split(":",-1);
    for(String group:groups)if(group.isEmpty()||group.length()>4)return false;
    count+=groups.length;
  }
  return count<8;
}
private boolean isValidProfileDnsIpv6Port(String value){
  if(value==null||!value.startsWith("["))return false;
  int close=value.indexOf(']');
  if(close<3||!isValidProfileDnsIpv6(value.substring(1,close)))return false;
  String tail=value.substring(close+1);
  if(tail.isEmpty())return true;
  return tail.matches(":[0-9]{1,5}")&&validProfilePort(value);
}
private boolean isValidProfileRoutableDnsIpv6Endpoint(String value){
  String address=value;
  if(value==null)return false;
  if(value.startsWith("[")){
    int close=value.indexOf(']');
    if(close<0||!isValidProfileDnsIpv6Port(value))return false;
    address=value.substring(1,close);
  }else if(!isValidProfileDnsIpv6(value)){
    return false;
  }
  try{
    java.net.InetAddress parsed=java.net.InetAddress.getByName(address);
    return parsed instanceof java.net.Inet6Address
        &&!parsed.isAnyLocalAddress()
        &&!parsed.isLoopbackAddress()
        &&!parsed.isLinkLocalAddress()
        &&!parsed.isMulticastAddress();
  }catch(java.net.UnknownHostException invalid){return false;}
}
private boolean isValidProfileDnsHost(String host){
  if(host==null||host.isEmpty()||host.length()>253)return false;
  if(host.matches("[0-9.]+"))return isValidProfileIpv4(host);
  String[] labels=host.split("\\.",-1);
  for(String label:labels){
    if(label.isEmpty()||label.length()>63||
        !label.matches("[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?"))return false;
  }
  return true;
}
private boolean isValidProfileDnsHostPort(String authority){
  if(authority==null)return false;
  if(authority.startsWith("["))return isValidProfileDnsIpv6Port(authority);
  String hostPort="[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?";
  int colon=authority.lastIndexOf(':');
  String host=colon<0?authority:authority.substring(0,colon);
  return authority.matches(hostPort)&&isValidProfileDnsHost(host)&&validProfilePort(authority);
}
private boolean isValidProfileDnsIpv4Port(String value){
  int colon=value==null?-1:value.lastIndexOf(':');
  return colon>0&&isValidProfileIpv4(value.substring(0,colon))&&validProfilePort(value);
}
private boolean isValidProfileDnsCsv(String value,boolean encryptedAllowed){
  if(value==null||value.isEmpty())return true;
  String[] entries=value.split(",",-1);
  java.util.Set<String> seen=new java.util.HashSet<>();
  for(String entry:entries){
    if(entry.isEmpty()||!seen.add(entry.toLowerCase(java.util.Locale.ROOT)))return false;
    if(isValidProfileIpv4(entry)||isValidProfileDnsIpv4Port(entry))continue;
    if(isValidProfileRoutableDnsIpv6Endpoint(entry))continue;
    if(!encryptedAllowed)return false;
    if(isValidProfileDnsIpv6(entry)||isValidProfileDnsIpv6Port(entry))continue;
    if(entry.startsWith("tls://")||entry.startsWith("quic://")){
      String authority=entry.substring(entry.indexOf("://")+3);
      if(!isValidProfileDnsHostPort(authority))return false;
    }else if(entry.startsWith("https://")){
      String rest=entry.substring(8);
      int slash=rest.indexOf('/');
      String authority=slash<0?rest:rest.substring(0,slash);
      String path=slash<0?"":rest.substring(slash);
      if(!isValidProfileDnsHostPort(authority)||
          !path.matches("(/[A-Za-z0-9._~!    if(entry.startsWith("tls://")||entry.startsWith("quic://")){
      String authority=entry.substring(entry.indexOf("://")+3);
      if(!isValidProfileDnsHostPort(authority))return false;
    }else if(entry.startsWith("https://")){
      String rest=entry.substring(8);
      int slash=rest.indexOf('/');
      String authority=slash<0?rest:rest.substring(0,slash);
      String path=slash<0?"":rest.substring(slash);
      if(!isValidProfileDnsHostPort(authority)||
          !path.matches("(/[A-Za-z0-9._~!    String hostPort="[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?";
    if(entry.startsWith("tls://")||entry.startsWith("quic://")){
      String authority=entry.substring(entry.indexOf("://")+3);
      if(!authority.matches(hostPort)||!validProfilePort(authority))return false;
    }else if(entry.startsWith("https://")){
      String rest=entry.substring(8);
      int slash=rest.indexOf('/');
      String authority=slash<0?rest:rest.substring(0,slash);
      String path=slash<0?"":rest.substring(slash);
      if(!authority.matches(hostPort)||!validProfilePort(authority)||
          !path.matches("(/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*)?"))return false;()*+,;=:@%/?#-]*)?"))return false;()*+,;=:@%/?#-]*)?"))return false;
    }else return false;
  }
  return true;
}
private boolean validProfilePort(String authority){
  int colon=authority.lastIndexOf(':');
  if(colon<0)return true;
  try{int port=Integer.parseInt(authority.substring(colon+1));return port>=1&&port<=65535;}
  catch(NumberFormatException e){return false;}
}
private int countDnsEndpoints(String value){
  if(value==null||value.trim().isEmpty())return 0;
  int count=0;
  for(String endpoint:value.split(",",-1))if(!endpoint.trim().isEmpty())count++;
  return count;
}
private void saveDnsDiagnosticsReport(String report){
  if(report==null||report.trim().isEmpty()){
    status.setText("DNS 诊断报告为空，未创建文件。");
    return;
  }
  pendingDnsDiagnosticExport=report;
  try{
    Intent create=new Intent(Intent.ACTION_CREATE_DOCUMENT);
    create.addCategory(Intent.CATEGORY_OPENABLE);
    create.setType("text/plain");
    String stamp=new java.text.SimpleDateFormat("yyyyMMdd-HHmmss",java.util.Locale.ROOT)
        .format(new java.util.Date());
    create.putExtra(Intent.EXTRA_TITLE,"FX-DNS-diagnostics-"+stamp+".txt");
    startActivityForResult(create,DNS_DIAGNOSTIC_SAVE_REQUEST);
    status.setText("请选择 DNS 诊断报告的本地保存位置。");
  }catch(RuntimeException unavailable){
    pendingDnsDiagnosticExport="";
    status.setText("无法打开系统文件保存器："+safe(unavailable.getMessage()));
  }
}
private void runDnsDiagnostics(){
  status.setText("正在执行只读 DNS 链路诊断…");
  root("dns-diagnose",result->{
    if(result.exitCode!=0){
      fxDialogBuilder().setTitle("DNS 链路诊断不可用")
        .setMessage(safe(result.output))
        .setPositiveButton("关闭",null).show();
      return;
    }
    String raw=result.output==null?"":result.output.trim();
    String[] lines=raw.split("\\r?\\n");
    if(lines.length<2||!"FXYULONGDNSDIAG5".equals(lines[0].trim())){
      status.setText("DNS 诊断响应版本或字段数量错误，拒绝显示不完整报告。");
      return;
    }
    String[] allowed={"dns_stack_ready","dns_stack_readiness_reason",
      "unbound_process","unbound_probe","adguardhome_process",
      "adguardhome_ipv4_probe","adguardhome_ipv6_probe","localdns_watchdog",
      "vpn_coexistence_verdict","vpn_route_probe","private_dns_mode",
      "dns_upstream_mode","dns_upstream_state","dns_bootstrap_mode","dns_fallback_mode",
       "rootproxy_cleanup","dns_response_mode","dns_blocking_ipv4","dns_blocking_ipv6",
       "dns_blocked_response_ttl","dns_rewrites_count","dns_rewrites_enabled_count","dns_rewrites_disabled_count","dns_querylog_ignored_enabled",
       "dns_querylog_ignored_count","dns_statistics_ignored_enabled","dns_statistics_ignored_count",
      "dnssec_anchor_state","root_hints_state","root_hints_bytes",
      "dns_querylog_enabled","dns_querylog_retention","dns_querylog_memory_size","dns_querylog_memory_max",
      "dns_statistics_enabled","dns_statistics_interval",
      "adguard_upstream_mode","adguard_fastest_timeout","adguard_upstream_timeout",
      "adguard_cache_size","adguard_cache_ttl_min","adguard_cache_ttl_max",
      "adguard_optimistic_answer_ttl","adguard_optimistic_max_age",
      "adguard_cache_enabled","adguard_cache_optimistic","adguard_dnssec_enabled",
      "unbound_cache_max_ttl","unbound_cache_min_ttl","unbound_serve_expired",
      "unbound_serve_expired_ttl","unbound_serve_expired_reply_ttl",
      "unbound_serve_expired_client_timeout","unbound_prefetch","unbound_prefetch_key",
      "unbound_qname_minimisation","unbound_msg_cache_size","unbound_rrset_cache_size",
      "unbound_key_cache_size","unbound_neg_cache_size","unbound_num_threads","unbound_threads_max",
      "dnssec_anchor_age","dnssec_anchor_bytes","dnssec_refresh_route","dnssec_resolver_state"};
    java.util.Set<String> keys=new java.util.HashSet<>(java.util.Arrays.asList(allowed));
    java.util.Map<String,String> values=new java.util.LinkedHashMap<>();
    for(int i=1;i<lines.length;i++){
      String line=lines[i].trim();
      if(line.isEmpty())continue;
      int split=line.indexOf('=');
      if(split<=0||split==line.length()-1){
        status.setText("DNS 诊断响应字段格式错误。");return;
      }
      String key=line.substring(0,split),value=line.substring(split+1);
      if(!keys.contains(key)||values.put(key,value)!=null){
        status.setText("DNS 诊断响应包含未知或重复字段："+key);return;
      }
    }
    if(values.size()!=allowed.length){
      status.setText("DNS 诊断响应字段不完整（"+values.size()+"/"+allowed.length+"）。");return;
    }
    for(String key:allowed){
      String value=values.get(key);
      boolean valid;
      switch(key){
        case "dns_stack_ready": valid="0".equals(value)||"1".equals(value)||"unknown".equals(value);break;
        case "dns_stack_readiness_reason": valid=value.matches("[A-Za-z0-9_.:-]+");break;
        case "unbound_process":
        case "adguardhome_process": valid="ready".equals(value)||"running_unhealthy".equals(value)
            ||"stopped".equals(value)||"disabled".equals(value)||"unknown".equals(value);break;
        case "unbound_probe":
        case "adguardhome_ipv4_probe":
        case "adguardhome_ipv6_probe": valid="passed".equals(value)||"failed".equals(value)
            ||"disabled".equals(value)||"unavailable".equals(value);break;
        case "localdns_watchdog": valid="running".equals(value)||"stopped".equals(value)
            ||"invalid".equals(value)||"unsafe".equals(value)||"identity_unknown".equals(value)
            ||"unknown".equals(value)||"unavailable".equals(value);break;
        case "vpn_coexistence_verdict": valid="compatible".equals(value)||"incompatible".equals(value)||"unknown".equals(value);break;
        case "vpn_route_probe": valid="passed".equals(value)||"failed".equals(value)
            ||"unavailable".equals(value)||"not_applicable".equals(value)||"unknown".equals(value);break;
        case "private_dns_mode": valid="off".equals(value)||"opportunistic".equals(value)
            ||"hostname".equals(value)||"unknown".equals(value);break;
        case "dns_upstream_mode": valid="local_recursive".equals(value)||"custom".equals(value)
            ||"global".equals(value)||"unknown".equals(value);break;
        case "dns_upstream_state": valid="ready".equals(value)||"missing_primary".equals(value)
            ||"unknown".equals(value);break;
        case "dns_bootstrap_mode": valid="not_required".equals(value)||"local_unbound".equals(value)
            ||"unknown".equals(value);break;
        case "dns_fallback_mode": valid="none".equals(value)||"explicit".equals(value)
            ||"local_unbound".equals(value)||"unknown".equals(value);break;
         case "rootproxy_cleanup": valid="complete".equals(value)||"failed".equals(value)
             ||"not_required".equals(value)||"unknown".equals(value);break;
         case "dns_response_mode": valid="nxdomain".equals(value)||"refused".equals(value)
             ||"custom_ip".equals(value)||"unknown".equals(value);break;
         case "dns_blocking_ipv4": valid="unknown".equals(value)||isValidDnsRewriteIpv4(value);break;
         case "dns_blocking_ipv6": valid="unknown".equals(value)||isValidDnsRewriteIpv6(value);break;
        case "dnssec_anchor_state":
        case "root_hints_state": valid="valid".equals(value)||"missing".equals(value)
            ||"invalid".equals(value)||"unsafe".equals(value)||"unknown".equals(value);break;
        case "root_hints_bytes":
        case "dnssec_anchor_bytes":
        case "dns_querylog_memory_size":
        case "dns_querylog_memory_max":
        case "adguard_cache_size":
        case "adguard_cache_ttl_min":
        case "adguard_cache_ttl_max":
        case "unbound_cache_max_ttl":
        case "unbound_cache_min_ttl":
        case "unbound_serve_expired_ttl":
        case "unbound_serve_expired_reply_ttl":
        case "unbound_serve_expired_client_timeout":
        case "unbound_num_threads":
        case "unbound_threads_max":
            valid=android.text.TextUtils.isDigitsOnly(value)||"unknown".equals(value);break;
         case "dns_blocked_response_ttl":
         case "dns_rewrites_count":
         case "dns_rewrites_enabled_count":
         case "dns_rewrites_disabled_count":
         case "dns_querylog_ignored_count":
         case "dns_statistics_ignored_count":
             valid=android.text.TextUtils.isDigitsOnly(value)||"unknown".equals(value);break;
         case "dns_querylog_ignored_enabled":
         case "dns_statistics_ignored_enabled":
             valid="0".equals(value)||"1".equals(value)||"unknown".equals(value);break;
        case "dns_querylog_enabled":
        case "dns_statistics_enabled":
        case "adguard_cache_enabled":
        case "adguard_cache_optimistic":
        case "adguard_dnssec_enabled":
        case "unbound_serve_expired":
        case "unbound_prefetch":
        case "unbound_prefetch_key":
        case "unbound_qname_minimisation":
            valid="0".equals(value)||"1".equals(value)||"unknown".equals(value);break;
        case "dns_querylog_retention":
        case "dns_statistics_interval":
            valid=value.matches("[0-9]+[hd]")||"unknown".equals(value);break;
        case "adguard_upstream_mode":
            valid="load_balance".equals(value)||"parallel".equals(value)
                ||"fastest_addr".equals(value)||"unknown".equals(value);break;
        case "adguard_fastest_timeout":
        case "adguard_upstream_timeout":
        case "adguard_optimistic_answer_ttl":
        case "adguard_optimistic_max_age":
            valid=value.matches("[0-9]+(ms|s|m|h)")||"unknown".equals(value);break;
        case "unbound_msg_cache_size":
        case "unbound_rrset_cache_size":
        case "unbound_key_cache_size":
        case "unbound_neg_cache_size":
            valid=value.matches("[0-9]+([kKmMgG])?")||"unknown".equals(value);break;
        case "dnssec_anchor_age":
            valid="stale".equals(value)||"current".equals(value)||"unknown".equals(value);break;
        case "dnssec_refresh_route":
            valid="system_default".equals(value)||"vpn_bound".equals(value)
                ||"unsafe".equals(value)||"unknown".equals(value);break;
        case "dnssec_resolver_state":
            valid="running".equals(value)||"stopped".equals(value)||"unknown".equals(value);break;
        default: valid=false;
      }
      if(!valid){status.setText("DNS 诊断字段值非法："+key);return;}
    }
    StringBuilder report=new StringBuilder();
    report.append("DNS 栈就绪：").append("1".equals(values.get("dns_stack_ready"))?"是":"0".equals(values.get("dns_stack_ready"))?"否":"未知").append('\n');
    report.append("未就绪原因：").append(values.get("dns_stack_readiness_reason")).append('\n');
    report.append("Unbound 进程：").append(dnsDiagnosticLabel(values.get("unbound_process"))).append('\n');
    report.append("Unbound 回环查询：").append(dnsDiagnosticLabel(values.get("unbound_probe"))).append('\n');
    report.append("AdGuard Home 进程：").append(dnsDiagnosticLabel(values.get("adguardhome_process"))).append('\n');
    report.append("AdGuard Home IPv4 查询：").append(dnsDiagnosticLabel(values.get("adguardhome_ipv4_probe"))).append('\n');
    report.append("AdGuard Home IPv6 查询：").append(dnsDiagnosticLabel(values.get("adguardhome_ipv6_probe"))).append('\n');
    report.append("本地 DNS 自动恢复守护：").append(dnsDiagnosticLabel(values.get("localdns_watchdog"))).append('\n');
    report.append("VPN 共存判定：").append(dnsDiagnosticLabel(values.get("vpn_coexistence_verdict"))).append('\n');
    report.append("VPN 路由探测：").append(dnsDiagnosticLabel(values.get("vpn_route_probe"))).append('\n');
    report.append("Android 私有 DNS：").append(dnsDiagnosticLabel(values.get("private_dns_mode"))).append('\n');
    report.append("当前上游模式：").append(values.get("dns_upstream_mode"))
        .append("；上游配置：").append(values.get("dns_upstream_state")).append('\n');
     report.append("Root Proxy 清理：").append(values.get("rootproxy_cleanup")).append('\n');
     report.append("DNS 拦截响应：").append(values.get("dns_response_mode"))
         .append("；IPv4/IPv6：").append(values.get("dns_blocking_ipv4")).append("/")
         .append(values.get("dns_blocking_ipv6")).append("；TTL：").append(values.get("dns_blocked_response_ttl")).append('\n');
     report.append("DNS 地址重写：总计 ").append(values.get("dns_rewrites_count"))
         .append(" 条，启用 ").append(values.get("dns_rewrites_enabled_count"))
         .append(" 条，停用 ").append(values.get("dns_rewrites_disabled_count"))
         .append(" 条；逐条日志排除：")
         .append(values.get("dns_querylog_ignored_enabled")).append("（")
         .append(values.get("dns_querylog_ignored_count")).append(" 条）；统计排除：")
         .append(values.get("dns_statistics_ignored_enabled")).append("（")
         .append(values.get("dns_statistics_ignored_count")).append(" 条）。\n");
    report.append("加密上游引导解析：").append(values.get("dns_bootstrap_mode"))
        .append("；故障回退：").append(values.get("dns_fallback_mode")).append('\n');
    report.append("\nDNS 查询日志：").append(values.get("dns_querylog_enabled"))
        .append("；保留：").append(values.get("dns_querylog_retention"))
        .append("；内存刷盘批量/动态上限：").append(values.get("dns_querylog_memory_size"))
        .append("/").append(values.get("dns_querylog_memory_max")).append('\n');
    report.append("DNS 聚合统计：").append(values.get("dns_statistics_enabled"))
        .append("；周期：").append(values.get("dns_statistics_interval")).append('\n');
    report.append("AdGuard 上游策略/超时：").append(values.get("adguard_upstream_mode"))
        .append("；最快/总超时：").append(values.get("adguard_fastest_timeout"))
        .append("/").append(values.get("adguard_upstream_timeout")).append('\n');
    report.append("AdGuard 缓存：").append(values.get("adguard_cache_enabled"))
        .append("；容量：").append(values.get("adguard_cache_size"))
        .append("；TTL：").append(values.get("adguard_cache_ttl_min"))
        .append("~").append(values.get("adguard_cache_ttl_max"))
        .append("；乐观缓存：").append(values.get("adguard_cache_optimistic"))
        .append("；DNSSEC：").append(values.get("adguard_dnssec_enabled")).append('\n');
    report.append("Unbound TTL：").append(values.get("unbound_cache_min_ttl"))
        .append("~").append(values.get("unbound_cache_max_ttl"))
        .append("；线程：").append(values.get("unbound_num_threads"))
        .append("/").append(values.get("unbound_threads_max"))
        .append("；serve-expired：").append(values.get("unbound_serve_expired"))
        .append("；预取/QNAME minimisation：").append(values.get("unbound_prefetch"))
        .append("/").append(values.get("unbound_prefetch_key"))
        .append("/").append(values.get("unbound_qname_minimisation")).append('\n');
    report.append("Unbound 消息/RRset/Key/否定缓存：")
        .append(values.get("unbound_msg_cache_size")).append("/")
        .append(values.get("unbound_rrset_cache_size")).append("/")
        .append(values.get("unbound_key_cache_size")).append("/")
        .append(values.get("unbound_neg_cache_size")).append('\n');
    report.append("DNSSEC 根信任锚：").append(values.get("dnssec_anchor_state"))
        .append("；文件大小：").append(values.get("dnssec_anchor_bytes"))
        .append("；更新：").append(values.get("dnssec_anchor_age"))
        .append("；Unbound：").append(values.get("dnssec_resolver_state"))
        .append("；手动刷新出口：").append(values.get("dnssec_refresh_route")).append('\n');
    report.append("Root Hints：").append(values.get("root_hints_state"))
        .append("；文件大小：").append(values.get("root_hints_bytes")).append(" 字节（SHA-256）。\n\n");
    report.append("本报告只读本地配置与完整性状态，并探测回环监听；不会修改 DNS 配置、重启解析器或更改 VPN 路由。");
    fxDialogBuilder().setTitle("FX DNS 链路诊断报告")
      .setMessage(report.toString())
      .setNegativeButton("保存报告到文件",(dialog,which)->saveDnsDiagnosticsReport(report.toString()))
      .setPositiveButton("关闭",null).show();
  });
}
private String dnsDiagnosticLabel(String value){
  if("ready".equals(value)||"passed".equals(value)||"compatible".equals(value)||"running".equals(value))return "正常 / 通过";
  if("failed".equals(value)||"incompatible".equals(value)||"unsafe".equals(value)||"invalid".equals(value))return "失败 / 异常";
  if("running_unhealthy".equals(value))return "进程存在但健康探测失败";
  if("stopped".equals(value))return "未运行";
  if("disabled".equals(value)||"off".equals(value)||"not_applicable".equals(value))return "未启用 / 不适用";
  if("opportunistic".equals(value))return "自动模式";
  if("hostname".equals(value))return "严格主机名模式";
  if("unavailable".equals(value))return "不可用";
  if("identity_unknown".equals(value))return "进程身份无法确认";
  return "未知";
}

private void loadDnsRuntimeStatus(TextView target){
  target.setText("正在读取 DNS 服务状态…");
  root("dns-runtime-status",r->{
    if(r.exitCode!=0){target.setText("DNS 状态读取失败："+safe(r.output));return;}
    java.util.Map<String,String> values=new java.util.LinkedHashMap<>();
    String[] lines=(r.output==null?"":r.output).split("\\r?\\n");
    if(lines.length==0||!"FXDNS1".equals(lines[0].trim())){
      target.setText("DNS 状态响应版本不匹配，拒绝显示可能不完整的数据。");return;
    }
    java.util.Set<String> allowed=new java.util.HashSet<>(java.util.Arrays.asList(
        "dns_engine_adguardhome","dns_forward","vpn_external_compat",
        "vpn_external_dns_proxy","adguardhome","unbound","root_proxy",
        "rootproxy_reason","rootproxy_cleanup","rootproxy_interface",
        "rootproxy_vpn_uid","rootproxy_egress_ipv4","rootproxy_activated_at",
        "rootproxy_redirects","rootproxy_dns_probe","rootproxy_route",
        "rootproxy_whitelist_count","dns_filter_sources_total",
        "dns_filter_sources_enabled","private_dns_mode","dns_filter_coverage",
        "vpn_coexistence_verdict","vpn_route_probe","dns_stack_enabled",
        "dns_stack_ready",
        "dns_stack_readiness_reason","dns_upstream_mode","dns_upstream_state",
        "dns_custom_upstreams","dns_global_upstreams","dns_fallback_upstreams",
        "dns_encrypted_upstreams","dns_bootstrap_mode","dns_fallback_mode","localdns_watchdog",
        "custom_dns","global_dns","block_quic","block_dot","block_plain_dns",
        "block_ipv6","block_track_domains","dns_querylog_enabled",
        "dns_querylog_memory_size","dns_querylog_memory_max",
        "dns_querylog_ignored_enabled","dns_querylog_ignored_count",
        "dns_statistics_enabled","dns_statistics_interval",
        "dns_statistics_ignored_enabled","dns_statistics_ignored_count"));
    for(int index=1;index<lines.length;index++){
      String line=lines[index].trim();
      if(line.isEmpty())continue;
      int split=line.indexOf('|');
      if(split<=0||split==line.length()-1){
        target.setText("DNS 状态响应包含格式错误的记录，拒绝显示不完整数据。");return;
      }
      String key=line.substring(0,split).trim();
      String value=line.substring(split+1).trim();
      if(!allowed.contains(key)||values.containsKey(key)){
        target.setText("DNS 状态响应包含未知或重复字段："+key+"；拒绝显示不完整数据。");return;
      }
      values.put(key,value);
    }
    if(values.size()!=allowed.size()){
      target.setText("DNS 状态响应字段不完整（"+values.size()+"/"+allowed.size()+"），拒绝显示不完整数据。");return;
    }
    StringBuilder out=new StringBuilder();
    appendDnsStatus(out,"AdGuard Home",values.get("adguardhome"));
    appendDnsStatus(out,"Unbound",values.get("unbound"));
    appendDnsStatus(out,"第三方 VPN Root Proxy",values.get("root_proxy"));
    appendDnsStatus(out,"DNS 过滤覆盖",values.get("dns_filter_coverage"));
    appendDnsStatus(out,"VPN 共存判定",values.get("vpn_coexistence_verdict"));
    appendDnsStatus(out,"DNS 路由探测",values.get("vpn_route_probe"));
    appendDnsStatus(out,"DNS 栈已启用",values.get("dns_stack_enabled"));
    appendDnsStatus(out,"AdGuard Home 开关",values.get("dns_engine_adguardhome"));
    appendDnsStatus(out,"Unbound 开关",values.get("dns_forward"));
    appendDnsStatus(out,"第三方 VPN 兼容开关",values.get("vpn_external_compat"));
    appendDnsStatus(out,"Root Proxy 开关",values.get("vpn_external_dns_proxy"));
    appendDnsStatus(out,"Root Proxy 状态原因",values.get("rootproxy_reason"));
    appendDnsStatus(out,"Root Proxy 清理状态",values.get("rootproxy_cleanup"));
    appendDnsStatus(out,"VPN 接口",values.get("rootproxy_interface"));
    appendDnsStatus(out,"VPN UID",values.get("rootproxy_vpn_uid"));
    appendDnsStatus(out,"VPN DNS 出口 IPv4",values.get("rootproxy_egress_ipv4"));
    appendDnsStatus(out,"Root Proxy 启动时间",values.get("rootproxy_activated_at"));
    appendDnsStatus(out,"DNS 重定向规则",values.get("rootproxy_redirects"));
    appendDnsStatus(out,"Root Proxy DNS 探测",values.get("rootproxy_dns_probe"));
    appendDnsStatus(out,"Root Proxy 路由验证",values.get("rootproxy_route"));
    appendDnsStatus(out,"Android 私有 DNS 模式",values.get("private_dns_mode"));
    appendDnsStatus(out,"Root Proxy 白名单数量",values.get("rootproxy_whitelist_count"));
    appendDnsStatus(out,"DNS 栈就绪",values.get("dns_stack_ready"));
    appendDnsStatus(out,"DNS 栈未就绪原因",values.get("dns_stack_readiness_reason"));
    appendDnsStatus(out,"过滤规则总数",values.get("dns_filter_sources_total"));
    appendDnsStatus(out,"已启用过滤规则",values.get("dns_filter_sources_enabled"));
    appendDnsStatus(out,"当前 DNS 上游模式",values.get("dns_upstream_mode"));
    appendDnsStatus(out,"上游配置状态",values.get("dns_upstream_state"));
    appendDnsStatus(out,"自定义 DNS 上游数量",values.get("dns_custom_upstreams"));
    appendDnsStatus(out,"全局 DNS 上游数量",values.get("dns_global_upstreams"));
    appendDnsStatus(out,"备用 DNS 上游数量",values.get("dns_fallback_upstreams"));
    appendDnsStatus(out,"加密 DNS 上游数量",values.get("dns_encrypted_upstreams"));
    appendDnsStatus(out,"加密上游引导解析",values.get("dns_bootstrap_mode"));
    appendDnsStatus(out,"DNS 故障回退方式",values.get("dns_fallback_mode"));
    appendDnsStatus(out,"本地 DNS 自动恢复守护",values.get("localdns_watchdog"));
    appendDnsStatus(out,"自定义 DNS 开关",values.get("custom_dns"));
    appendDnsStatus(out,"全局 DNS 开关",values.get("global_dns"));
    appendDnsStatus(out,"QUIC 策略开关（配置值）",values.get("block_quic"));
    appendDnsStatus(out,"DoT 策略开关（配置值）",values.get("block_dot"));
    appendDnsStatus(out,"明文 DNS 策略开关（配置值）",values.get("block_plain_dns"));
    appendDnsStatus(out,"IPv6 策略开关（配置值）",values.get("block_ipv6"));
    appendDnsStatus(out,"跟踪域名保护开关（配置值）",values.get("block_track_domains"));
    appendDnsStatus(out,"DNS 查询日志开关",values.get("dns_querylog_enabled"));
    appendDnsStatus(out,"查询日志内存刷盘批量",values.get("dns_querylog_memory_size"));
    appendDnsStatus(out,"查询日志设备缓冲上限",values.get("dns_querylog_memory_max"));
    appendDnsStatus(out,"逐条查询日志排除域名开关",values.get("dns_querylog_ignored_enabled"));
    appendDnsStatus(out,"逐条查询日志排除域名数量",values.get("dns_querylog_ignored_count"));
    appendDnsStatus(out,"聚合统计数据库开关",values.get("dns_statistics_enabled"));
    appendDnsStatus(out,"聚合统计轮转周期",values.get("dns_statistics_interval"));
    appendDnsStatus(out,"聚合统计排除域名开关",values.get("dns_statistics_ignored_enabled"));
    appendDnsStatus(out,"聚合统计排除域名数量",values.get("dns_statistics_ignored_count"));
    target.setText(out.length()==0?"未收到可识别的 DNS 状态字段。":out.toString().trim());
  });
}
private void appendDnsStatus(StringBuilder out,String label,String value){
  if(value==null||value.isEmpty())return;
  out.append(label).append("：").append(value).append('\n');
}
private void loadDnsLists(EditText custom,EditText global,EditText fallback,EditText remote,EditText domestic){
  root("dns-config-get",r->{
    if(r.exitCode!=0){status.setText("DNS 地址读取失败："+safe(r.output));return;}
    String raw=r.output==null?"":r.output;
    String[] lines=raw.split("\\r?\\n",-1);
    if(lines.length==0||!"FXYULONGDNS1".equals(lines[0].trim())){
      status.setText("DNS 配置响应版本不匹配，拒绝显示可能不完整的数据。");return;
    }
    List<String> a=new ArrayList<>(),b=new ArrayList<>(),f=new ArrayList<>();
    java.util.Map<String,String> singleton=new java.util.HashMap<>();
    java.util.Set<String> allowed=new java.util.HashSet<>(java.util.Arrays.asList(
        "CUSTOM_ENABLED","GLOBAL_ENABLED","VPN_REMOTE","VPN_CN"));
    for(int index=1;index<lines.length;index++){
      String line=lines[index].trim();
      if(line.isEmpty())continue;
      int split=line.indexOf('|');
      if(split<=0){status.setText("DNS 配置响应包含格式错误的记录，未更新输入框。");return;}
      String key=line.substring(0,split),value=line.substring(split+1);
      if("CUSTOM".equals(key)){if(value.isEmpty()){status.setText("自定义 DNS 响应包含空服务器记录。");return;}a.add(value);}
      else if("GLOBAL".equals(key)){if(value.isEmpty()){status.setText("全局 DNS 响应包含空服务器记录。");return;}b.add(value);}
      else if("FALLBACK".equals(key)){if(value.isEmpty()){status.setText("备用 DNS 响应包含空服务器记录。");return;}f.add(value);}
      else if(allowed.contains(key)){
        if(singleton.containsKey(key)){status.setText("DNS 配置响应包含重复字段："+key+"。");return;}
        singleton.put(key,value);
      }else{status.setText("DNS 配置响应包含未知字段："+key+"。");return;}
    }
    for(String key:allowed)if(!singleton.containsKey(key)){
      status.setText("DNS 配置响应缺少字段："+key+"，未更新输入框。");return;
    }
    for(String key:new String[]{"CUSTOM_ENABLED","GLOBAL_ENABLED"}){
      String value=singleton.get(key);
      if(!"0".equals(value)&&!"1".equals(value)){
        status.setText("DNS 配置响应开关值非法："+key+"。");return;
      }
    }
    String remoteValue=singleton.get("VPN_REMOTE"),cnValue=singleton.get("VPN_CN");
    if(!remoteValue.isEmpty()&&!isValidProfileIpv4(remoteValue)){
      status.setText("DNS 配置响应中的 VPN 远端地址无效。");return;
    }
    if(!cnValue.isEmpty()&&!isValidProfileIpv4(cnValue)){
      status.setText("DNS 配置响应中的 VPN 国内地址无效。");return;
    }
    custom.setText(android.text.TextUtils.join(",",a));
    global.setText(android.text.TextUtils.join(",",b));
    fallback.setText(android.text.TextUtils.join(",",f));
    remote.setText(remoteValue.isEmpty()?"1.1.1.1":remoteValue);
    domestic.setText(cnValue.isEmpty()?"223.5.5.5":cnValue);
  });
}
private void clearDnsSection(String kind,EditText input){
  String label="custom".equals(kind)?"自定义 DNS":("global".equals(kind)?"全局 DNS":"备用 DNS");
  fxDialogBuilder().setTitle("清除"+label)
      .setMessage("将移除 FX 配置中的"+label+"服务器段；不会自动关闭对应开关，也不会修改 VPN 节点 DNS。是否继续？")
      .setNegativeButton("取消",null)
      .setPositiveButton("清除",(dialog,which)->root("dns-config-clear "+kind,r->{
       if(r.exitCode==0){input.setText("");status.setText(label+"服务器配置已清除。");load();}
       else fxDialogBuilder().setTitle("清除失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
 }
private void setDnsEngineProfile(boolean enabled){
  String action=enabled?"启用":"关闭";
  String command=enabled
      ?"dns-native-set-many dns_engine_adguardhome 1 dns_forward 1"
      :"dns-native-set-many dns_engine_adguardhome 0 dns_forward 0 vpn_external_dns_proxy 0";
  new AlertDialog.Builder(this).setTitle(action+"本地 DNS 引擎组？")
      .setMessage("将通过原生 DNS 依赖管理器，在单次配置事务中调整 AdGuard Home、Unbound 与 Root Proxy 依赖；不会修改上游服务器、过滤规则或 VPN 节点。")
      .setNegativeButton("取消",null)
      .setPositiveButton("确认",(dialog,which)->root(command,r->{
        if(r.exitCode==0){status.setText("本地 DNS 引擎组已"+action+"并应用。");load();}
        else fxDialogBuilder().setTitle("DNS 引擎设置未更新").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
}
private void applyDnsSecurityProfile(String mode,boolean strict,TextView state,
    android.widget.RadioGroup group,android.widget.RadioButton nx,
    android.widget.RadioButton refused,android.widget.RadioButton empty){
  String action=strict?"严格 DNS 保护":"基础 DNS 拦截";
  new AlertDialog.Builder(this).setTitle("应用"+action+"？")
      .setMessage(strict
          ?"统一设置为 NXDOMAIN，并同时启用 QUIC、DNS-over-TLS、明文 DNS、IPv6 与跟踪域名保护五项策略。"
          :"统一设置为 NXDOMAIN，并关闭上述五项附加过滤策略；域名名单与 DNS 上游保持不变。")
      .setNegativeButton("取消",null)
      .setPositiveButton("应用",(dialog,which)->root("dns-security-profile-set "+mode+" "+(strict?"1":"0"),r->{
        if(r.exitCode==0){
          if("nxdomain".equals(mode))group.check(nx.getId());
          else if("refused".equals(mode))group.check(refused.getId());
          else if("custom_ip".equals(mode))group.check(empty.getId());
          state.setText(action+"已在同一配置事务中保存并应用。");
          status.setText(action+"已应用。");
          load();
        }else fxDialogBuilder().setTitle("DNS 配置未更新").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
}
private void setDnsFilterPolicy(boolean enabled){
  String action=enabled?"启用":"关闭";
  new AlertDialog.Builder(this).setTitle(action+"全部 DNS 过滤策略？")
      .setMessage("此操作将以单次配置事务同时"+action+" QUIC、DNS-over-TLS、明文 DNS、IPv6 与跟踪域名保护五项策略。")
      .setNegativeButton("取消",null)
      .setPositiveButton("确认", (dialog,which)->root("dns-filter-policy-set "+(enabled?"1":"0")+" "+(enabled?"1":"0")+" "+(enabled?"1":"0")+" "+(enabled?"1":"0")+" "+(enabled?"1":"0"),r->{
        if(r.exitCode==0){status.setText("五项 DNS 过滤策略已统一"+action+"并应用。");load();}
        else fxDialogBuilder().setTitle("DNS 策略未更新").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
}
private void saveDnsServerLists(EditText custom,EditText global,EditText fallback){
  String customValue=custom.getText()==null?"":custom.getText().toString().trim();
  String globalValue=global.getText()==null?"":global.getText().toString().trim();
  String fallbackValue=fallback.getText()==null?"":fallback.getText().toString().trim();
  String command="dns-config-set-many "+q(customValue.isEmpty()?"-":customValue)+" "+q(globalValue.isEmpty()?"-":globalValue)+" "+q(fallbackValue.isEmpty()?"-":fallbackValue);
  new AlertDialog.Builder(this).setTitle("一次性保存三组 DNS 上游")
      .setMessage("三组服务器将先统一校验，再在同一配置事务中写入并应用。任一组留空表示清除该组服务器段；不会自动关闭对应开关。是否继续？")
      .setNegativeButton("取消",null)
      .setPositiveButton("保存",(dialog,which)->root(command,r->{
        if(r.exitCode==0){status.setText("自定义、全局与备用 DNS 上游已在同一事务中保存并应用。");load();}
        else fxDialogBuilder().setTitle("DNS 上游未更新").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
}
private void saveDnsServerList(String kind,EditText input){
  String value=input.getText()==null?"":input.getText().toString().trim();
  root("dns-config-set "+kind+" "+q(value),r->{
    if(r.exitCode==0){status.setText(("custom".equals(kind)?"自定义 DNS":("fallback".equals(kind)?"备用 DNS":"全局 DNS"))+" 已保存并应用。");load();}
    else fxDialogBuilder().setTitle("DNS 地址未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
  });
}
private void saveVpnDnsPair(EditText remote,EditText cn){
  String remoteValue=remote.getText()==null?"":remote.getText().toString().trim();
  String cnValue=cn.getText()==null?"":cn.getText().toString().trim();
  if(remoteValue.isEmpty()||cnValue.isEmpty()){
    fxDialogBuilder().setTitle("VPN DNS 地址不完整").setMessage("远端 DNS 与国内直连 DNS 都必须填写 IPv4 地址；未提交任何更改。").setPositiveButton("关闭",null).show();
    return;
  }
  fxDialogBuilder().setTitle("一次性保存两组 VPN DNS")
      .setMessage("先同时校验远端 DNS 与国内直连 DNS，再在同一配置事务中写入并应用；任一项无效或写入失败都不会保留部分修改。是否继续？")
      .setNegativeButton("取消",null)
      .setPositiveButton("保存",(dialog,which)->root("dns-vpn-set-many "+q(remoteValue)+" "+q(cnValue),r->{
        if(r.exitCode==0){status.setText("远端 DNS 与国内直连 DNS 已在同一事务中保存并应用。");load();}
        else fxDialogBuilder().setTitle("VPN DNS 未更新").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
}
private void saveVpnDns(String key,EditText input){
  String value=input.getText()==null?"":input.getText().toString().trim();
  root("dns-vpn-set "+key+" "+q(value),r->{
    if(r.exitCode==0)status.setText(("remote_dns".equals(key)?"VPN 远端 DNS":"国内直连 DNS")+" 已保存并应用。");
    else fxDialogBuilder().setTitle("VPN DNS 未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
  });
}
 private boolean syncing;
 private Switch dnsSwitch(String label,String key){Switch s=new Switch(this);s.setText(label);s.setTag(key);s.setEnabled(false);s.setOnCheckedChangeListener((b,on)->{if(!syncing)apply("dns-set "+key+" "+(on?"1":"0"),label);});return s;}
 private void renderDomains(){
  EditText allow=draftField("allow_domain"); allow.setSingleLine(true); allow.setHint("白名单域名");
  EditText allowNote=draftField("allow_note"); allowNote.setSingleLine(true); allowNote.setHint("备注");
  card("域名白名单","精确放行域名及其子域。",
      allow,allowNote,
      btn("添加白名单",()->{
        if(!allow.getText().toString().trim().isEmpty())
          apply("allow-add "+q(allow.getText().toString().trim())+" "+q(allowNote.getText().toString().trim()),"白名单添加");
      }));
  card("白名单维护", "清空操作只移除用户白名单，不影响黑名单、内置规则源或 DNS 上游。",
      btn("清空全部白名单",()->clearAllDomains("allow")));
  EditText allowBulk=draftField("allow_bulk"); allowBulk.setGravity(Gravity.TOP|Gravity.START);
  allowBulk.setMinLines(4); allowBulk.setHint("每行一个域名；可选格式：example.com|备注");
  card("批量导入白名单","不限制名单条目数量；整批验证并通过一次 FX apply 事务，失败会回滚。",
      allowBulk,btn("验证并批量导入白名单",()->importDomains("allow",allowBulk)));

  EditText block=draftField("block_domain"); block.setSingleLine(true); block.setHint("黑名单域名");
  EditText blockNote=draftField("block_note"); blockNote.setSingleLine(true); blockNote.setHint("备注");
  card("域名黑名单","只添加明确需要阻断的域名。",
      block,blockNote,
      btn("添加黑名单",()->{
        if(!block.getText().toString().trim().isEmpty())
          apply("block-add "+q(block.getText().toString().trim())+" "+q(blockNote.getText().toString().trim()),"黑名单添加");
      }));
  card("黑名单维护", "清空操作只移除用户黑名单，不影响白名单、内置规则源或 DNS 上游。",
      btn("清空全部黑名单",()->clearAllDomains("block")));
  EditText blockBulk=draftField("block_bulk"); blockBulk.setGravity(Gravity.TOP|Gravity.START);
  blockBulk.setMinLines(4); blockBulk.setHint("每行一个域名；可选格式：example.com|备注");
  card("批量导入黑名单","不限制名单条目数量；整批验证并通过一次 FX apply 事务，失败会回滚。",
      blockBulk,btn("验证并批量导入黑名单",()->importDomains("block",blockBulk)));

  EditText allowRemoveBulk=draftField("allow_remove_bulk");
  allowRemoveBulk.setGravity(Gravity.TOP|Gravity.START);
  allowRemoveBulk.setMinLines(3);
  allowRemoveBulk.setHint("每行一个域名；仅删除白名单中匹配的条目");
  card("批量移除白名单",
      "完整校验筛选域名，再在单次 FX 配置事务中移除；任何一步失败都会回滚。",
      allowRemoveBulk,
      btn("确认批量移除白名单",()->removeDomains("allow",allowRemoveBulk)));

  EditText blockRemoveBulk=draftField("block_remove_bulk");
  blockRemoveBulk.setGravity(Gravity.TOP|Gravity.START);
  blockRemoveBulk.setMinLines(3);
  blockRemoveBulk.setHint("每行一个域名；仅删除黑名单中匹配的条目");
  card("批量移除黑名单",
      "完整校验域名，再在单次 FX 配置事务中移除；任何一步失败都会回滚。",
      blockRemoveBulk,
      btn("确认批量移除黑名单",()->removeDomains("block",blockRemoveBulk)));

  card("域名名单导出",
      "导出设备端当前保存的用户白名单与黑名单，不包含内置规则源；导出文件可作为备份或供其他工具编辑。",
      btn("分享全部白名单",()->shareDomainList("ALLOW")),
      btn("分享全部黑名单",()->shareDomainList("BLOCK")),
      btn("分享白名单 + 黑名单",()->shareDomainList("BOTH")));
  EditText domainBundle=draftField("domain_bundle_import");
  domainBundle.setGravity(Gravity.TOP|Gravity.START);
  domainBundle.setMinLines(5);
  domainBundle.setHint("粘贴 FX 域名名单备份：allow|domain|note 或 block|domain|note");
  card("白/黑名单合并恢复",
      "可直接导入上方分享导出的合并备份；忽略 # 注释行，白名单与黑名单在同一配置事务中恢复，重复行自动合并。",
      domainBundle,btn("验证并恢复合并名单",()->importDomainBundle(domainBundle)));
  domainSearch=draftField("domain_search");
  domainSearch.setSingleLine(true);
  domainSearch.setHint("筛选白名单/黑名单域名或备注");
  domainSearch.addTextChangedListener(new TextWatcher(){
   @Override public void beforeTextChanged(CharSequence s,int start,int count,int after){}
   @Override public void onTextChanged(CharSequence s,int start,int before,int count){bind();}
   @Override public void afterTextChanged(Editable e){}
  });
  card("域名名单筛选与批量管理",
      "搜索同时匹配域名与备注；下面两项批量移除只作用于当前搜索命中的对应名单。",
      domainSearch,
      btn("批量移除筛选命中的白名单",()->removeFilteredDomains("ALLOW")),
      btn("批量移除筛选命中的黑名单",()->removeFilteredDomains("BLOCK")),
      btn("启用筛选命中的白名单",()->setFilteredAllows(true)),
      btn("停用筛选命中的白名单",()->setFilteredAllows(false)),
      btn("启用筛选命中的黑名单",()->setFilteredBlocks(true)),
      btn("停用筛选命中的黑名单",()->setFilteredBlocks(false)));
  entries=new LinearLayout(this); entries.setOrientation(1); body.addView(entries);
 }

 private void clearAllDomains(String kind){
  String label="allow".equals(kind)?"白名单":"黑名单";
  new AlertDialog.Builder(this).setTitle("清空全部"+label+"？")
      .setMessage("将移除当前 FX 用户"+label+"中的全部域名条目；此操作不影响另一份名单、内置规则源、DNS 上游或过滤策略。")
      .setNegativeButton("取消",null)
      .setPositiveButton("清空",(dialog,which)->root(kind+"-clear-all",r->{
        if(r.exitCode==0){status.setText(label+"已清空。");load();}
        else fxDialogBuilder().setTitle("清空失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
 }

 private void removeFilteredDomains(String kind){
  String filter=domainSearch==null||domainSearch.getText()==null?"":domainSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
  List<String> selected=new ArrayList<>();
  for(Row row:rows(kind)){
   if(filter.isEmpty()||(row.value+" "+row.title).toLowerCase(Locale.ROOT).contains(filter))selected.add(row.value);
  }
  if(selected.isEmpty()){status.setText("当前筛选条件下没有匹配的"+("ALLOW".equals(kind)?"白名单":"黑名单")+"条目。");return;}
  EditText values=new EditText(this);
  StringBuilder joined=new StringBuilder();
  for(String value:selected){if(joined.length()>0)joined.append('\n');joined.append(value);}
  values.setText(joined.toString());
  removeDomains("ALLOW".equals(kind)?"allow":"block",values);
 }

 private void setFilteredAllows(boolean enabled){
  String filter=domainSearch==null||domainSearch.getText()==null?"":domainSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
  List<String> selected=new ArrayList<>();
  for(Row row:rows("ALLOW")){
   if(filter.isEmpty()||(row.value+" "+row.title).toLowerCase(Locale.ROOT).contains(filter))selected.add(row.value);
  }
  if(selected.isEmpty()){status.setText("当前筛选条件下没有匹配的白名单条目。");return;}
  String payload=String.join("\n",selected);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  String action=enabled?"启用":"停用";
  fxDialogBuilder().setTitle(action+"筛选命中的白名单")
      .setMessage("将"+action+"当前筛选命中的 "+selected.size()+" 条白名单域名。记录及备注会保留；后端会再次确认条目仍存在，并在单次 FX 配置事务中统一应用，失败会回滚。")
      .setNegativeButton("取消",null)
      .setPositiveButton(action,(dialog,which)->apply("allow-set-many "+(enabled?"1":"0")+" "+q(encoded),"批量白名单状态"))
      .show();
 }
 private void setFilteredBlocks(boolean enabled){
  String filter=domainSearch==null||domainSearch.getText()==null?"":domainSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
  List<String> selected=new ArrayList<>();
  for(Row row:rows("BLOCK")){
   if(filter.isEmpty()||(row.value+" "+row.title).toLowerCase(Locale.ROOT).contains(filter))selected.add(row.value);
  }
  if(selected.isEmpty()){status.setText("当前筛选条件下没有匹配的黑名单条目。");return;}
   String payload=String.join("\n",selected);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  String action=enabled?"启用":"停用";
  fxDialogBuilder().setTitle(action+"筛选命中的黑名单")
      .setMessage("将"+action+"当前筛选命中的 "+selected.size()+" 条黑名单域名。记录及备注会保留；后端会再次确认条目仍存在，并在单次 FX 配置事务中统一应用，失败会回滚。")
      .setNegativeButton("取消",null)
      .setPositiveButton(action,(dialog,which)->apply("block-set-many "+(enabled?"1":"0")+" "+q(encoded),"批量黑名单状态"))
      .show();
 }
 private void shareDomainList(String kind){
  if(snapshot==null||snapshot.isEmpty()){
   status.setText("尚未读取设备端域名名单；请先刷新页面。");
   return;
  }
  List<Row> allowRows=rows("ALLOW"),blockRows=rows("BLOCK");
  List<Row> selected=new ArrayList<>();
  if("ALLOW".equals(kind)||"BOTH".equals(kind))selected.addAll(allowRows);
  if("BLOCK".equals(kind)||"BOTH".equals(kind))selected.addAll(blockRows);
  if(selected.isEmpty()){
   status.setText("所选域名名单为空，没有可导出的条目。");
   return;
  }
  StringBuilder payload=new StringBuilder();
   payload.append("# FX Ad domain list export\n")
       .append("# format: allow|domain|note or block|domain|note\n");
  int included=0;
  for(Row row:selected){
   String line=row.kind.toLowerCase(Locale.ROOT)+"|"
       +cleanDomainExportField(row.value)+"|"
        +cleanDomainExportField(row.title)+"\n";
    payload.append(line);included++;
  }
  if(included!=selected.size()){
   status.setText("名单导出数量不完整，已取消导出。");return;
  }
  try{
   Intent send=new Intent(Intent.ACTION_SEND);
   send.setType("text/plain");
   send.putExtra(Intent.EXTRA_SUBJECT,"FX Ad 域名名单备份");
   send.putExtra(Intent.EXTRA_TEXT,payload.toString());
   startActivity(Intent.createChooser(send,"分享域名名单"));
    status.setText("已准备分享 "+included+" 条域名名单。");
  }catch(RuntimeException unavailable){
   status.setText("无法打开系统分享面板："+safe(unavailable.getMessage()));
  }
 }
 private static String cleanDomainExportField(String value){
  return value==null?"":value.replace('|',' ').replace('\\t',' ')
      .replace('\\r',' ').replace('\n',' ');
 }
 private void importDomainBundle(EditText input){
  String raw=input.getText()==null?"":input.getText().toString();
  java.util.LinkedHashMap<String,String> unique=new java.util.LinkedHashMap<>();
  for(String line:raw.split("\\r?\\n")){
   String value=line.trim();
   if(value.isEmpty()||value.startsWith("#"))continue;
   String[] fields=value.split("\\|",-1);
   if(fields.length!=3||!("allow".equals(fields[0].trim())||"block".equals(fields[0].trim()))
       ||fields[1].trim().isEmpty()||fields[1].trim().length()>253
       ){
    status.setText("合并备份格式错误：每行必须为 allow|domain|note 或 block|domain|note。");
    return;
   }
   String kind=fields[0].trim(),domain=fields[1].trim(),note=fields[2].trim();
   unique.putIfAbsent(kind+"|"+domain,kind+"|"+domain+"|"+note);
  }
  if(unique.isEmpty()){status.setText("没有可恢复的域名条目。");return;}
  String payload=String.join("\n",unique.values());
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  fxDialogBuilder().setTitle("恢复白名单与黑名单")
      .setMessage("将恢复 "+unique.size()+" 条唯一域名记录；白名单和黑名单通过单次 FX 配置事务写入并统一应用。重复行已合并，任一写入失败会回滚整批。是否继续？")
      .setNegativeButton("取消",null)
      .setPositiveButton("恢复",(dialog,which)->root("domain-import-bundle "+q(encoded),r->{
       if(r.exitCode==0){status.setText("白/黑名单合并恢复完成："+safe(r.output));input.setText("");load();}
       else fxDialogBuilder().setTitle("名单恢复失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
      })).show();
 }
 private void removeDomains(String kind,EditText input){
  String raw=input.getText()==null?"":input.getText().toString();
  java.util.LinkedHashSet<String> domains=new java.util.LinkedHashSet<>();
  for(String line:raw.split("\\r?\\n")){
   String domain=line.trim();
   if(domain.isEmpty()||domain.startsWith("#"))continue;
   if(domain.length()>253||domain.contains("|")){
    status.setText("移除列表格式错误：请使用每行一个域名。");
    return;
   }
   domains.add(domain);
  }
  if(domains.isEmpty()){status.setText("没有可移除的域名。");return;}
  String payload=String.join("\n",domains);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  String label="allow".equals(kind)?"白名单":"黑名单";
  fxDialogBuilder().setTitle("批量移除"+label)
      .setMessage("将从"+label+"中移除 "+domains.size()+" 个指定域名。后端会再次验证全部域名，并在单次 FX 配置事务中执行；失败会回滚。")
      .setNegativeButton("取消",null)
      .setPositiveButton("移除",(dialog,which)->
          apply(kind+"-remove-many "+q(encoded),"批量移除"+label))
      .show();
 }
 private void importDomains(String kind,EditText input){
  String raw=input.getText()==null?"":input.getText().toString();
  java.util.ArrayList<String> lines=new java.util.ArrayList<>();
  for(String line:raw.split("\\r?\\n")){
   String value=line.trim();
   if(value.isEmpty()||value.startsWith("#")) continue;
   String[] fields=value.split("\\|",-1);
   if(fields.length>2 || fields[0].trim().isEmpty() || fields[0].trim().length()>253
       ){
    status.setText("导入格式错误：请使用 domain 或 domain|note，每行一条。");
    return;
   }
   lines.add(fields.length==1?fields[0].trim():fields[0].trim()+"|"+fields[1].trim());
  }
  if(lines.isEmpty()){status.setText("没有可导入的域名。");return;}
  String payload=String.join("\n",lines);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  fxDialogBuilder().setTitle(kind.equals("allow")?"批量导入白名单":"批量导入黑名单")
      .setMessage("共 "+lines.size()+" 条。后端会先验证所有域名，再原子写入配置并应用；任何失败都会回滚整批。")
      .setNegativeButton("取消",null)
      .setPositiveButton("导入", (dialog,which)->
          apply(kind+"-import "+q(encoded),kind.equals("allow")?"批量白名单导入":"批量黑名单导入"))
      .show();
 }
 private void renderSchedule(){
  Switch enabled=new Switch(this);
  enabled.setText("启用每周自动计划");
  EditText start=draftField("schedule_start");
  start.setSingleLine(true);start.setHint("开始时间 HH:MM");start.setText("22:00");
  EditText end=draftField("schedule_end");
  end.setSingleLine(true);end.setHint("结束时间 HH:MM");end.setText("07:00");
  LinearLayout daysBox=new LinearLayout(this);daysBox.setOrientation(1);
  String[] labels={"周一","周二","周三","周四","周五","周六","周日"};
  android.widget.CheckBox[] days=new android.widget.CheckBox[7];
  for(int i=0;i<7;i++){days[i]=new android.widget.CheckBox(this);days[i].setText(labels[i]);days[i].setChecked(true);daysBox.addView(days[i]);}
  TextView state=txt("正在读取计划任务…",12,0xff526170,false);
  card("每周自动计划",
       "按设备本地时间自动启用/暂停FX 广告过滤列表。开始时间晚于结束时间时按跨午夜区间计算；开始时间等于结束时间表示空时间段，不会触发切换。",
       enabled,start,end,daysBox,       btn("保存计划",()->{
         StringBuilder selected=new StringBuilder();
         for(int i=0;i<7;i++)if(days[i].isChecked()){if(selected.length()>0)selected.append(',');selected.append(FxYulongScheduleDayMapping.workerDayForUiIndex(i));}
         if(selected.length()==0){fxDialogBuilder().setMessage("至少选择一天。").setPositiveButton("知道了",null).show();return;}
         String command="schedule-set "+(enabled.isChecked()?"1":"0")+" "+q(start.getText().toString().trim())+" "+q(end.getText().toString().trim())+" "+q(selected.toString());
         root(command,r->{
           if(r.exitCode==0){
             state.setText("计划已保存并立即重新计算。\n"+safe(r.output));
           }else{
             state.setText("计划保存/应用失败："+safe(r.output));
             fxDialogBuilder().setTitle("计划未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
           }
         });
       }),
       btn("重新读取计划",()->loadSchedule(enabled,start,end,days,state)));
  card("当前计划状态",
       "星期编号与原版一致：周日=0、周一=1、周二=2、周三=3、周四=4、周五=5、周六=6。计划只控制FX 广告过滤列表；FX 96110 反诈规则、Hosts 白/黑名单、DNS 上游和 VPN 节点不受影响。",
       state);
  loadSchedule(enabled,start,end,days,state);
 }
 private void loadSchedule(Switch enabled,EditText start,EditText end,
       android.widget.CheckBox[] days,TextView state){
  root("schedule-get",r->{
    if(r.exitCode!=0){state.setText("读取失败："+safe(r.output));return;}
    String en="0",st="22:00",ed="07:00",ds=FxYulongScheduleDayMapping.defaultWeekCsv(),active="1",watcher="0";
    for(String line:r.output.split("\\r?\\n")){
      int pos=line.indexOf('=');if(pos<0)continue;
      String key=line.substring(0,pos),value=line.substring(pos+1);
      if("enabled".equals(key))en=value;
      else if("start".equals(key))st=value;
      else if("end".equals(key))ed=value;
      else if("days".equals(key))ds=value;
      else if("active".equals(key))active=value;
      else if("watcher".equals(key))watcher=value;
    }
    enabled.setChecked("1".equals(en));start.setText(st);end.setText(ed);
    for(int i=0;i<7;i++){
      days[i].setChecked(FxYulongScheduleDayMapping.isUiDaySelected(ds,i));
    }
    state.setText("计划："+("1".equals(en)?"已启用":"已关闭")
       +"；当前游龙过滤："+("1".equals(active)?"生效":"按计划暂停"));
  });
 }
 private void renderLogs(){card("运行日志","显示 FX 当前模块日志，不将全局日志冒充原版逐应用统计。");root("logs",r->card("FX 日志","本机启动与过滤记录",txt(safe(r.output),11,0xff526170,false)));}
 private void load(){root("list",r->{if(r.exitCode!=0){snapshot="";setAdMasterUnknown();status.setText("读取失败："+safe(r.output));restorePageScrollIfNeeded();return;}snapshot=r.output==null?"":r.output;Boolean master=adMaster();status.setText(master==null?"广告过滤主开关状态未知；请刷新并检查 FX 配置快照。":"已读取设备端 FX 配置。");bind();restorePageScrollIfNeeded();});}
 private void restorePageScrollIfNeeded(){
  if(!pendingPageScrollRestore||pageScroll==null)return;
  final int y=pendingPageScrollY;
  pageScroll.post(()->{
   if(isFinishing()||isDestroyed()||!pendingPageScrollRestore||pageScroll==null)return;
   pageScroll.scrollTo(0,y);
   pendingPageScrollRestore=false;
  });
 }
 private List<Row> rows(String kind){List<Row> out=new ArrayList<>();for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length>=4&&kind.equals(p[0]))out.add(new Row(p[0],p[1],p[2],"1".equals(p[3])));}return out;}
 private void bind(){if(snapshot.isEmpty())return;
  if("首页与防护".equals(page)){
   syncing=true;
   for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){
    LinearLayout p=(LinearLayout)body.getChildAt(i);
    for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){
     Switch sw=(Switch)p.getChildAt(j);
     if("ad-master".equals(sw.getTag())){Boolean master=adMaster();if(master==null){sw.setText("广告过滤主开关状态未知（暂不可切换）");sw.setEnabled(false);}else{sw.setText("启用广告过滤主开关");sw.setChecked(master);sw.setEnabled(true);}}
    }
   }
   syncing=false;
  }if("过滤列表".equals(page)&&entries!=null){
    entries.removeAllViews();
    String f=search==null||search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);
    for(Row e:rows("RULE")){
     if(!f.isEmpty()&&!(e.value+" "+e.title).toLowerCase(Locale.ROOT).contains(f))continue;
     LinearLayout r=new LinearLayout(this);r.setTag("fx-list-row");r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));
     TextView ruleName=txt(e.title,13,0xff17212b,true);ruleName.setTag("fx-list-title");r.addView(ruleName);
     TextView ruleSource=txt(e.value,10,0xff718091,false);ruleSource.setTag("fx-list-subtitle");r.addView(ruleSource);
     Switch sw=new Switch(this);sw.setTag("fx-switch-row");sw.setText("启用此列表");sw.setChecked(e.enabled);
     sw.setOnCheckedChangeListener((b,on)->apply("rule-set "+q(e.value)+" "+(on?"1":"0"),"规则状态"));r.addView(sw);
     r.addView(btn("重命名",()->renameRule(e)));r.addView(btn("删除",()->fxDialogBuilder().setTitle("删除过滤列表").setMessage(e.value).setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->apply("rule-remove "+q(e.value),"规则删除")).show()));entries.addView(r);
    }
   }
   else if("DNS 设置".equals(page)||"VPN 与 Root Proxy".equals(page)){syncing=true;for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){LinearLayout p=(LinearLayout)body.getChildAt(i);for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){Switch sw=(Switch)p.getChildAt(j);if(sw.getTag() instanceof String){sw.setChecked(dnsValue((String)sw.getTag()).equals("1"));sw.setEnabled(true);}}}syncing=false;}
 else if("域名名单".equals(page)&&entries!=null){
    entries.removeAllViews();
    String filter=domainSearch==null||domainSearch.getText()==null?"":domainSearch.getText().toString().trim().toLowerCase(Locale.ROOT);
    int shown=0,total=0;
    for(Row e:rows("ALLOW")){total++;if(filter.isEmpty()||(e.value+" "+e.title).toLowerCase(Locale.ROOT).contains(filter)){domainRow(e,true);shown++;}}
    for(Row e:rows("BLOCK")){total++;if(filter.isEmpty()||(e.value+" "+e.title).toLowerCase(Locale.ROOT).contains(filter)){domainRow(e,false);shown++;}}
    if(entries.getChildCount()==0)entries.addView(txt(total==0?"暂无用户自定义域名名单。":"当前筛选没有匹配的域名。",12,0xff718091,false));
    status.setText("域名名单：显示 "+shown+" / "+total+" 条"+(filter.isEmpty()?"。":"（当前筛选）。"));
   }}
 private void copyAutomationAction(String value){
  android.content.ClipboardManager clipboard=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
  if(clipboard!=null){clipboard.setPrimaryClip(android.content.ClipData.newPlainText("FX Tasker action",value));Toast.makeText(this,"广播 Action 已复制。",Toast.LENGTH_SHORT).show();}
}
private Boolean adMaster(){
   return FxYulongAdSnapshotPolicy.parseAdMasterEnabled(snapshot);
  }
  private void setAdMasterUnknown(){
   if(body==null)return;
   for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){
    LinearLayout panel=(LinearLayout)body.getChildAt(i);
    for(int j=0;j<panel.getChildCount();j++)if(panel.getChildAt(j) instanceof Switch){
     Switch control=(Switch)panel.getChildAt(j);
     if("ad-master".equals(control.getTag())){
      control.setText("广告过滤主开关状态未知（暂不可切换）");
      control.setEnabled(false);
     }
    }
   }
  }
private String dnsValue(String key){for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length==3&&p[0].equals("DNS")&&p[1].equals(key))return p[2];}return "0";}
 private void domainRow(Row e,boolean allow){LinearLayout r=new LinearLayout(this);r.setTag("fx-list-row");r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));TextView domain=txt((allow?"白名单 · ":"黑名单 · ")+e.value,13,0xff17212b,true);domain.setTag("fx-list-title");r.addView(domain);TextView source=txt(e.title,10,0xff718091,false);source.setTag("fx-list-subtitle");r.addView(source);Switch enabled=new Switch(this);enabled.setTag("fx-switch-row");enabled.setText(allow?"启用此白名单域名":"启用此黑名单域名");enabled.setChecked(e.enabled);enabled.setOnCheckedChangeListener((button,on)->apply((allow?"allow-set ":"block-set ")+q(e.value)+" "+(on?"1":"0"),allow?"白名单状态":"黑名单状态"));r.addView(enabled);r.addView(btn("编辑备注",()->editDomainNote(e,allow)));if(e.title!=null&&!e.title.trim().isEmpty())r.addView(btn("清除备注",()->fxDialogBuilder().setTitle("清除域名备注").setMessage("仅清除 "+e.value+" 的备注，不改变启用状态或名单归属。").setNegativeButton("取消",null).setPositiveButton("清除",(d,w)->apply((allow?"allow-note-clear ":"block-note-clear ")+q(e.value),"清除名单备注")).show()));r.addView(btn("移除",()->apply((allow?"allow-remove ":"block-remove ")+q(e.value),"名单移除")));entries.addView(r);}
 private void editDomainNote(Row e,boolean allow){
  EditText input=new EditText(this);input.setSingleLine(true);input.setHint("域名备注");input.setText(e.title==null?"":e.title);
  fxDialogBuilder().setTitle("编辑"+(allow?"白名单":"黑名单")+"备注")
   .setMessage("只修改备注，不改变域名、启用状态或其他名单记录。")
   .setView(input).setNegativeButton("取消",null)
   .setPositiveButton("保存",(dialog,which)->{
    String note=input.getText()==null?"":input.getText().toString().trim();
    if(note.isEmpty()){status.setText("备注不能为空；如需清空请使用单个空格以外的明确备注。");return;}
    if(note.indexOf(10)>=0||note.indexOf(13)>=0){status.setText("备注不能包含换行。");return;}
    apply((allow?"allow-note ":"block-note ")+q(e.value)+" "+q(note),allow?"白名单备注":"黑名单备注");
   }).show();
 }
 @Override protected void onDestroy(){pageGeneration++;trustedNetworkGeneration++;trustedNetworkStatus=null;rootProxyStatusGeneration++;rootProxyStatus=null;proxyWhitelistGeneration++;worker.shutdownNow();super.onDestroy();}
 private void profileRoot(String args,java.util.function.Consumer<RootAccess.Result> cb){
  final long requestGeneration=pageGeneration;
  final String requestPage=page;
  Runnable task=()->{
   RootAccess.Result result=RootAccess.execute(profileCmd(args),90000L,Integer.MAX_VALUE);
   runOnUiThread(()->{
    if(isFinishing()||isDestroyed()||requestGeneration!=pageGeneration
       ||!requestPage.equals(page))return;
    if(cb!=null)cb.accept(result);
   });
  };
  try{worker.execute(task);}
  catch(RejectedExecutionException full){
   RootAccess.Result busy=RootAccess.failure(125,"后台任务繁忙，请稍后重试。");
   runOnUiThread(()->{
    if(isFinishing()||isDestroyed()||requestGeneration!=pageGeneration
       ||!requestPage.equals(page))return;
    status.setText("后台任务繁忙，请稍后重试。");
    if(cb!=null)cb.accept(busy);
   });
  }
 }
 private void renderProfiles(){
  EditText profileName=draftField("profile_name");
  profileName.setSingleLine(true);profileName.setHint("配置档名称，例如：儿童上网");
  Switch safeSearch=new Switch(this);safeSearch.setText("启用 SafeSearch（搜索引擎安全搜索）");
  Switch youtubeRestricted=new Switch(this);youtubeRestricted.setText("启用 YouTube 受限模式");
  EditText scheduleStart=draftField("profile_schedule_start");
  scheduleStart.setSingleLine(true);scheduleStart.setText("22:00");scheduleStart.setHint("开始 HH:MM");
  EditText scheduleEnd=draftField("profile_schedule_end");
  scheduleEnd.setSingleLine(true);scheduleEnd.setText("07:00");scheduleEnd.setHint("结束 HH:MM");
  LinearLayout daysBox=new LinearLayout(this);daysBox.setOrientation(1);
  // Original ProfileSchedule stores Calendar weekday - 1: Sunday=0 through Saturday=6.
  String[] dayNames={"周日","周一","周二","周三","周四","周五","周六"};
  android.widget.CheckBox[] days=new android.widget.CheckBox[7];
  for(int i=0;i<7;i++){days[i]=new android.widget.CheckBox(this);days[i].setText(dayNames[i]);days[i].setChecked(true);daysBox.addView(days[i]);}
  LinearLayout profileRows=new LinearLayout(this);profileRows.setOrientation(1);
  LinearLayout scheduleRows=new LinearLayout(this);scheduleRows.setOrientation(1);
  TextView result=txt("正在读取原版保护配置档…",12,0xff526170,false);
  card("保护配置档","此功能与“计划任务”中的广告列表定时开关独立。配置档会保存当前已启用的规则列表、SafeSearch 与 YouTube 受限模式。内置 Default/Strict/Family/Gaming/Strict Family 档保留原版来源集合；缺失的来源不会被伪装为已安装。",profileName,safeSearch,youtubeRestricted,
      btn("创建自定义配置档（保存当前过滤列表）",()->{
       String name=profileName.getText()==null?"":profileName.getText().toString().trim();
       if(name.isEmpty()){result.setText("请先输入配置档名称。");return;}
       profileRoot("profile-create "+q(name)+" "+(safeSearch.isChecked()?"1":"0")+" "+(youtubeRestricted.isChecked()?"1":"0"),r->{
        result.setText(r.exitCode==0?"配置档已创建："+safe(r.output):"创建失败："+safe(r.output));
        loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
       });
      }),result);
  card("原版 ProtectionProfile 配置档","切换时会先保存当前档，再补齐缺失的 HTTPS 来源并切换已有订阅；FX 本地规则和 96110 列表不受影响。SafeSearch 与 YouTube 限制通过 FX 本地 AdGuard Home 引擎应用；DNS 引擎未运行时不会宣称已生效。",profileRows);
  card("原版 ProfileSchedule 周计划","星期编号与原版 Calendar 一致：周日=0、周一=1…周六=6。开始晚于结束时表示跨午夜窗口；相同开始/结束时间不会命中。",scheduleStart,scheduleEnd,daysBox,scheduleRows);
  loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
 }
 private void loadProfileState(LinearLayout profileRows,LinearLayout scheduleRows,TextView result,EditText scheduleStart,EditText scheduleEnd,android.widget.CheckBox[] days){
  profileRoot("list",r->{
   if(r.exitCode!=0){result.setText("读取配置档失败："+safe(r.output));return;}
   profileRows.removeAllViews();scheduleRows.removeAllViews();
   java.util.ArrayList<String[]> profiles=new java.util.ArrayList<>();
   java.util.ArrayList<String[]> schedules=new java.util.ArrayList<>();
   for(String line:(r.output==null?"":r.output).split("\\r?\\n")){
    String[] p=line.split("\\|",-1);
    if(p.length==7&&"PROFILE".equals(p[0]))profiles.add(p);
    else if(p.length==7&&"SCHEDULE".equals(p[0]))schedules.add(p);
   }
   if(profiles.isEmpty())profileRows.addView(txt("当前没有可读取的配置档。",12,0xff718091,false));
   for(String[] p:profiles){
    String id=p[1],kind=p[3],safeFlag=p[4],youtubeFlag=p[5],active=p[6];
    String label=id;
    try{label=new String(android.util.Base64.decode(p[2],android.util.Base64.DEFAULT),java.nio.charset.StandardCharsets.UTF_8);}catch(Throwable ignored){}
    String detail="类型："+kind+"；SafeSearch："+("1".equals(safeFlag)?"开":"关")+"；YouTube 受限："+("1".equals(youtubeFlag)?"开":"关")+"；"+("1".equals(active)?"当前生效":"未激活");
    LinearLayout row=new LinearLayout(this);row.setOrientation(1);row.setPadding(dp(8),dp(6),dp(8),dp(6));
    row.addView(txt(label,14,0xff17212b,true));row.addView(txt(detail,11,0xff617080,false));
    if(!"1".equals(active))row.addView(btn("切换到此配置档",()->profileRoot("profile-switch "+q(id),switched->{
      result.setText(switched.exitCode==0?"配置档已切换："+safe(switched.output):"切换失败并已尝试回滚："+safe(switched.output));
      loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
      load();
    })));
    row.addView(btn("为此档添加每周计划",()->{
      StringBuilder selected=new StringBuilder();
      for(int i=0;i<7;i++)if(days[i].isChecked()){if(selected.length()>0)selected.append(',');selected.append(i);}
      if(selected.length()==0){result.setText("至少选择一天。");return;}
      String start=scheduleStart.getText()==null?"":scheduleStart.getText().toString().trim();
      String end=scheduleEnd.getText()==null?"":scheduleEnd.getText().toString().trim();
      profileRoot("schedule-add "+q(id)+" "+q(start)+" "+q(end)+" "+q(selected.toString()),saved->{
        result.setText(saved.exitCode==0?"周计划已保存："+safe(saved.output):"保存计划失败："+safe(saved.output));
        loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
      });
    }));
    if("CUSTOM".equals(kind))row.addView(btn("删除此自定义配置档",()->fxDialogBuilder().setTitle("删除配置档").setMessage("只删除配置档与其周计划，不删除订阅来源。").setNegativeButton("取消",null).setPositiveButton("删除",(dialog,which)->profileRoot("profile-delete "+q(id),deleted->{
      result.setText(deleted.exitCode==0?"已删除："+safe(deleted.output):"删除失败："+safe(deleted.output));
      loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
    })).show()));
    profileRows.addView(row);
   }
   if(schedules.isEmpty())scheduleRows.addView(txt("暂无 ProtectionProfile 周计划。",12,0xff718091,false));
   for(String[] s:schedules){
    String id=s[1],profile=s[2],start=s[3],end=s[4],enabled=s[5],week=s[6];
    LinearLayout row=new LinearLayout(this);row.setOrientation(1);row.setPadding(dp(8),dp(5),dp(8),dp(5));
    row.addView(txt(profile+" · "+start+"–"+end+" · 星期 "+week,12,0xff17212b,true));
    row.addView(txt("计划状态："+("1".equals(enabled)?"启用":"暂停"),11,0xff617080,false));
    row.addView(btn("使用上方时间/星期更新",()->{
      StringBuilder selected=new StringBuilder();
      for(int i=0;i<7;i++)if(days[i].isChecked()){if(selected.length()>0)selected.append(',');selected.append(i);}
      if(selected.length()==0){result.setText("至少选择一天。");return;}
      String newStart=scheduleStart.getText()==null?"":scheduleStart.getText().toString().trim();
      String newEnd=scheduleEnd.getText()==null?"":scheduleEnd.getText().toString().trim();
      profileRoot("schedule-set "+q(id)+" "+enabled+" "+q(newStart)+" "+q(newEnd)+" "+q(selected.toString()),updated->{
        result.setText(updated.exitCode==0?"周计划时间与星期已更新。":safe(updated.output));
        loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
      });
    }));
    row.addView(btn("暂停/启用计划",()->profileRoot("schedule-set "+q(id)+" "+("1".equals(enabled)?"0":"1")+" "+q(start)+" "+q(end)+" "+q(week),updated->{
      result.setText(updated.exitCode==0?"周计划状态已更新。":safe(updated.output));
      loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
    })));
    row.addView(btn("删除周计划",()->profileRoot("schedule-remove "+q(id),removed->{
      result.setText(removed.exitCode==0?"周计划已删除。":safe(removed.output));
      loadProfileState(profileRows,scheduleRows,result,scheduleStart,scheduleEnd,days);
    })));
    scheduleRows.addView(row);
   }
   result.setText("已读取 "+profiles.size()+" 个保护配置档、"+schedules.size()+" 条独立周计划。");
  });
 }

 private void open(String p){retainedDrafts=captureDrafts();page=p;pendingPageScrollRestore=false;pendingPageScrollY=0;if(pageScroll!=null)pageScroll.scrollTo(0,0);render();restoreDrafts(retainedDrafts);bind();}
}