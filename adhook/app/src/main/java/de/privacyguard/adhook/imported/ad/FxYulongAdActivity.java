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
 private static final int BULK_DRAFT_MAX_CHARS=48*1024;
 private static final int TEXT_DRAFT_MAX_CHARS=4096;
 private Bundle pendingRestoredDrafts;
 private Bundle retainedDrafts=new Bundle();
 private static final class Row {String kind,value,title;boolean enabled;Row(String k,String v,String t,boolean e){kind=k;value=v;title=t;enabled=e;}}
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView txt(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button btn(String s,Runnable r){Button b=new Button(this);b.setTag("fx-action-row");b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private EditText draftField(String key){
  EditText field=new EditText(this);
  field.setTag("fx-yulong-ad-draft:"+key);
  int maxChars=key.endsWith("_bulk")?BULK_DRAFT_MAX_CHARS:TEXT_DRAFT_MAX_CHARS;
  field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(maxChars)});
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
   RootAccess.Result result=RootAccess.execute(cmd(args),90000L,512*1024);
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
     result=RootAccess.execute(cmd(args),90000L,512*1024);
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
        if (key.matches("[a-z_]+") && value.length() <= 256) values.put(key, value);
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
  if(sources.size()>2000){status.setText("当前筛选超过 2000 个列表，请缩小筛选范围。");return;}
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
      if(value.length()>256){status.setText("过滤列表名称不能超过 256 个字符。");return;}
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
   if(sources.size()>2000){status.setText("当前筛选超过 2000 个列表，请缩小筛选范围。");return;}
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
   int included=0,omitted=0;
   final int maxBytes=64*1024;
   for(Row row:configured){
    String source=row.value==null?"":row.value.trim();
    String name=row.title==null?"":row.title.trim();
    if(source.isEmpty())continue;
    String line=source.replace('|',' ').replace('\r',' ').replace('\n',' ')
        +"|"+name.replace('|',' ').replace('\r',' ').replace('\n',' ')+"\n";
    int used=payload.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
    int bytes=line.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
    if(used+bytes>maxBytes){omitted++;continue;}
    payload.append(line);included++;
   }
   if(included==0){status.setText("没有可导出的有效过滤订阅。");return;}
   if(omitted>0)payload.append("# omitted ").append(omitted).append(" rows at 64 KiB export limit\n");
   try{
    Intent send=new Intent(Intent.ACTION_SEND);send.setType("text/plain");
    send.putExtra(Intent.EXTRA_SUBJECT,"FX Ad 过滤订阅备份");
    send.putExtra(Intent.EXTRA_TEXT,payload.toString());
    startActivity(Intent.createChooser(send,"分享过滤订阅"));
    status.setText("已准备分享 "+included+" 个过滤订阅"
        +(omitted>0?"；另有 "+omitted+" 个因 64 KiB 上限省略。":"。"));
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
   if(parsed.size()>2000){status.setText("单次最多导入 2000 个过滤列表。");return;}
  }
  if(parsed.isEmpty()){status.setText("没有可导入的过滤列表。");return;}
  StringBuilder normalized=new StringBuilder();
  for(java.util.Map.Entry<String,String> entry:parsed.entrySet())normalized.append(entry.getKey()).append('|').append(entry.getValue()).append('\\n');
  byte[] bytes=normalized.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
  if(bytes.length>65536){status.setText("导入内容超过 64 KiB，请拆分后导入。");return;}
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  fxDialogBuilder().setTitle("批量导入过滤列表")
   .setMessage("将新增 "+parsed.size()+" 个过滤订阅，导入条目默认启用。已存在的来源会被拒绝，不会覆盖现有名称或状态。是否继续？")
   .setNegativeButton("取消",null)
   .setPositiveButton("导入",(d,w)->apply("rule-add-many "+encoded,"批量导入过滤列表"))
   .show();
 }
 private void renderRules(){EditText url=draftField("rule_url");url.setSingleLine(true);url.setHint("https://… 或 builtin://…");EditText name=draftField("rule_name");name.setSingleLine(true);name.setHint("列表名称");card("添加过滤列表","仅允许 HTTPS 订阅及 FX 本地资源。",url,name,btn("添加并应用",()->{String u=url.getText().toString().trim(),n=name.getText().toString().trim();if(!u.isEmpty()&&!n.isEmpty())apply("rule-add "+q(u)+" "+q(n)+" 1","规则添加");}));EditText ruleImport=draftField("rule_import_text");ruleImport.setSingleLine(false);ruleImport.setMinLines(4);ruleImport.setHint("每行：HTTPS或builtin来源|列表名称");card("批量导入过滤列表","支持多行来源|名称；空行和 # 注释行忽略。新订阅默认启用，已存在来源不会被覆盖。",ruleImport,btn("批量导入",()->importRuleSubscriptions(ruleImport)),btn("分享全部过滤订阅",()->shareRuleSubscriptions()));search=draftField("rule_search");search.setSingleLine(true);search.setHint("搜索过滤列表");card("搜索","输入来源或列表名称",search,btn("启用当前筛选全部列表",()->setFilteredRules(true)),btn("暂停当前筛选全部列表",()->setFilteredRules(false)),btn("移除当前筛选全部列表",()->removeFilteredRules()));search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int be,int co){bind();}public void afterTextChanged(Editable e){}});entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
 private void renderDns(){
  EditText dnsProfileImport=draftField("dns_profile_import");dnsProfileImport.setSingleLine(false);dnsProfileImport.setMinLines(5);dnsProfileImport.setHint("粘贴完整 FXYULONGDNSPROFILE1 快照文本");
 private void refreshDnsCache(String target,String label){
   fxDialogBuilder().setTitle("刷新"+label+"缓存")
     .setMessage("FX 将仅重启所选的自有 DNS 解析服务并重新应用路由。刷新期间相关 DNS 查询可能短暂重试；不会操作第三方 VPN。若所选引擎未启用，FX 会拒绝操作。是否继续？")
     .setNegativeButton("取消",null).setPositiveButton("刷新",(d,w)->root("cache-flush "+target,r->{
       fxDialogBuilder().setTitle(r.exitCode==0?"DNS 缓存已刷新":"DNS 刷新未完全成功")
         .setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
     })).show();
 }
  card("DNS 配置备份与恢复","快照导入会完整替换 DNS 引擎开关、过滤策略、三组上游、VPN DNS 与拦截响应模式；提交前校验全部字段，失败时恢复原配置。",btn("分享 DNS 配置快照",()->shareDnsProfile()),dnsProfileImport,btn("校验并恢复 DNS 配置快照",()->restoreDnsProfile(dnsProfileImport)));
  TextView dnsRuntimeState=txt("DNS 运行状态尚未读取。",12,0xff617080,false);
  card("DNS 引擎运行状态","读取 AdGuard Home、Unbound、第三方 VPN Root Proxy、DNS 过滤覆盖范围与 VPN 共存判定。此操作只读取状态，不会更改服务或网络路由。",dnsRuntimeState,btn("刷新 DNS 运行状态",()->loadDnsRuntimeStatus(dnsRuntimeState)));
  card("本地 DNS 引擎",
       "启用时使用 FX 自有 AdGuard Home 过滤服务；关闭后按 FX 当前安全 DNS 回退配置处理。",
       dnsSwitch("启用本地 AdGuard Home","dns_engine_adguardhome"));
  card("本地 DNS 架构",
       "默认由本地 AdGuard Home 过滤并交给 Unbound 递归解析；不固定使用公共 DNS。只有明确启用自定义 DNS 或全局 DNS 时才会使用下面填写的 IPv4 地址。",
       dnsSwitch("DNS 兜底转发","dns_forward"),
       dnsSwitch("启用自定义 DNS","custom_dns"),
       dnsSwitch("启用全局 DNS 替换","global_dns"),
       btn("一键启用本地 DNS 引擎组",()->setDnsEngineProfile(true)),
       btn("一键关闭本地 DNS 引擎组",()->setDnsEngineProfile(false)));
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
  responseNull.setText("返回空地址 0.0.0.0 / ::");
  responseNull.setId(View.generateViewId());
  responseGroup.addView(responseNx);
  responseGroup.addView(responseRefused);
  responseGroup.addView(responseNull);
  responseGroup.check(responseNx.getId());
  TextView responseState=txt("正在读取 DNS 返回模式…",12,0xff617080,false);
  card("DNS 拦截返回模式",
       "选择被广告/黑名单规则拦截的域名如何响应。默认 NXDOMAIN；自定义模式返回空地址，不会修改未命中的 DNS 查询。",
       responseGroup,
       btn("保存返回模式",()->{
         int chosen=responseGroup.getCheckedRadioButtonId();
         String mode=chosen==responseRefused.getId()?"refused"
             :chosen==responseNull.getId()?"custom_ip":"nxdomain";
         root("dns-response-set "+mode,r->{
           if(r.exitCode==0)responseState.setText("已保存并应用："+mode);
           else responseState.setText("保存失败："+safe(r.output));
         });
       }),
       btn("一键应用严格 DNS 保护配置",()->applyDnsSecurityProfile("nxdomain",true,responseState,responseGroup,responseNx,responseRefused,responseNull)),
       btn("恢复基础 DNS 拦截配置",()->applyDnsSecurityProfile("nxdomain",false,responseState,responseGroup,responseNx,responseRefused,responseNull)),
       responseState);
  root("dns-response-get",r->{
    if(r.exitCode!=0){responseState.setText("读取失败："+safe(r.output));return;}
    String mode="nxdomain";
    for(String line:r.output.split("\\r?\\n"))
      if(line.startsWith("mode="))mode=line.substring(5).trim();
    responseGroup.check("refused".equals(mode)?responseRefused.getId()
        :"custom_ip".equals(mode)?responseNull.getId():responseNx.getId());
    responseState.setText("当前模式："+mode);
  });
  EditText customServers=draftField("dns_custom_servers");
  customServers.setSingleLine(false);customServers.setMinLines(2);
  customServers.setHint("IPv4 / https://DoH / tls://DoT / quic://DoQ");
  EditText fallbackServers=draftField("dns_fallback_servers");
  fallbackServers.setSingleLine(false);fallbackServers.setMinLines(2);
  fallbackServers.setHint("备用 DNS IPv4，例如：1.1.1.1,8.8.8.8");
  EditText globalServers=draftField("dns_global_servers");
  globalServers.setSingleLine(false);globalServers.setMinLines(2);
  globalServers.setHint("例如：8.8.8.8,1.1.1.1");
  card("自定义/全局/备用 DNS 服务器",
       "自定义 DNS 最多 3 个上游，可混合 IPv4、DoH、DoT、DoQ；备用 DNS 只支持 IPv4。加密上游只在 FX 本地 AdGuard Home 过滤引擎运行时生效；启用“阻止 DoT/QUIC”会阻断对应传输协议。",
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
  card("DNS 查询日志","默认关闭。仅本机保存最近 7 天 DNS 查询记录，不会上传查询记录。",
       dnsSwitch("启用本地 DNS 查询日志","dns_querylog_enabled"),
       btn("查看 DNS 查询日志",()->startActivity(new Intent(this,FxYulongDnsActivity.class))));
  card("DNS 缓存管理","可分别刷新 FX 自有 AdGuard Home 或 Unbound，也可同时刷新两者。所选解析服务会短暂重启；第三方 VPN 和它的规则不会被停止。",
       btn("刷新 AdGuard Home 缓存",()->refreshDnsCache("adguardhome","AdGuard Home")),
       btn("刷新 Unbound 缓存",()->refreshDnsCache("unbound","Unbound")),
       btn("刷新全部本地 DNS 缓存",()->refreshDnsCache("all","全部本地 DNS")));
  card("第三方 VPN DNS 过滤回退",
       "只有在系统确认唯一活动第三方 VPN、接口/所属 UID/出口路由有效，且 Unbound/AdGuard Home 健康探测通过后才接管明文 DNS。失败会撤销 FX 自有规则并保留第三方 VPN DNS。",
       dnsSwitch("第三方 VPN 下启用 Root DNS 过滤","vpn_external_dns_proxy"),
       btn("刷新 Root Proxy 状态",()->root("rootproxy-status",r->{fxDialogBuilder().setTitle("Root Proxy 状态").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})));
  loadDnsLists(customServers,globalServers,fallbackServers,remoteDns,cnDns);
}
private void shareDnsProfile(){
  root("dns-profile-get",r->{
    if(r.exitCode!=0){status.setText("DNS 配置快照读取失败："+safe(r.output));return;}
    String raw=r.output==null?"":r.output.trim();
    if(!raw.startsWith("FXYULONGDNSPROFILE1")){status.setText("DNS 配置快照格式不受支持，未生成备份。");return;}
    String payload="# FX Hook DNS profile backup\\n# format: FXYULONGDNSPROFILE1\\n# Restore only through a compatible FX version.\\n"+raw.substring("FXYULONGDNSPROFILE1".length()).trim()+"\\n";
    int bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
    if(bytes>48*1024){status.setText("DNS 配置快照超过 48 KiB，未打开分享面板。");return;}
    try{
      Intent send=new Intent(Intent.ACTION_SEND);
      send.setType("text/plain");
      send.putExtra(Intent.EXTRA_SUBJECT,"FX Hook DNS 配置备份");
      send.putExtra(Intent.EXTRA_TEXT,payload);
      startActivity(Intent.createChooser(send,"分享 DNS 配置快照"));
      status.setText("已准备 DNS 配置快照（"+bytes+" 字节）；请自行选择安全的保存位置。");
    }catch(RuntimeException unavailable){
      status.setText("无法打开系统分享面板："+safe(unavailable.getMessage()));
    }
  });
}
private void restoreDnsProfile(EditText input){
  String supplied=input.getText()==null?"":input.getText().toString();
  if(supplied.trim().isEmpty()){status.setText("请先粘贴 DNS 配置快照。");return;}
  StringBuilder normalized=new StringBuilder();
  for(String line:supplied.split("\\r?\\n")){
    String trimmed=line.trim();
    if(trimmed.isEmpty()||trimmed.startsWith("#"))continue;
    if(normalized.length()>0)normalized.append('\\n');
    normalized.append(trimmed);
  }
  String raw=normalized.toString();
  if(!raw.startsWith("FXYULONGDNSPROFILE1\\n")&&!raw.equals("FXYULONGDNSPROFILE1")){
    status.setText("快照版本头不匹配，未修改配置。");return;
  }
  byte[] bytes=raw.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  if(bytes.length>48*1024){status.setText("快照超过 48 KiB，未提交。");return;}
  String encoded=android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);
  fxDialogBuilder().setTitle("恢复 DNS 配置快照")
    .setMessage("将完整替换当前 DNS 引擎开关、过滤策略、上游服务器、VPN DNS 与拦截响应模式。所有字段会先校验；恢复应用失败会回滚原配置。此操作不会修改 VPN 节点或其他 FX 模块设置。是否继续？")
    .setNegativeButton("取消",null)
    .setPositiveButton("恢复", (d,w)->root("dns-profile-restore "+encoded,r->{
      if(r.exitCode==0){status.setText("DNS 配置快照已恢复并应用。");input.setText("");load();}
      else fxDialogBuilder().setTitle("DNS 快照恢复失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
    })).show();
}
private void loadDnsRuntimeStatus(TextView target){
  target.setText("正在读取 DNS 服务状态…");
  root("dns-runtime-status",r->{
    if(r.exitCode!=0){target.setText("DNS 状态读取失败："+safe(r.output));return;}
    java.util.Map<String,String> values=new java.util.LinkedHashMap<>();
    for(String line:(r.output==null?"":r.output).split("\\r?\\n")){
      int split=line.indexOf('|');
      if(split>0&&split<line.length()-1)values.put(line.substring(0,split).trim(),line.substring(split+1).trim());
    }
    StringBuilder out=new StringBuilder();
    appendDnsStatus(out,"AdGuard Home",values.get("adguardhome"));
    appendDnsStatus(out,"Unbound",values.get("unbound"));
    appendDnsStatus(out,"第三方 VPN Root Proxy",values.get("root_proxy"));
    appendDnsStatus(out,"DNS 过滤覆盖",values.get("dns_filter_coverage"));
    appendDnsStatus(out,"VPN 共存判定",values.get("vpn_coexistence_verdict"));
    appendDnsStatus(out,"DNS 路由探测",values.get("vpn_route_probe"));    appendDnsStatus(out,"DNS 栈已启用",values.get("dns_stack_enabled"));
    appendDnsStatus(out,"DNS 栈就绪",values.get("dns_stack_ready"));
    appendDnsStatus(out,"过滤规则总数",values.get("dns_filter_sources_total"));
    appendDnsStatus(out,"已启用过滤规则",values.get("dns_filter_sources_enabled"));
    target.setText(out.length()==0?"未收到可识别的 DNS 状态字段。":out.toString().trim());
  });
}
private void appendDnsStatus(StringBuilder out,String label,String value){
  if(value==null||value.isEmpty())return;
  out.append(label).append("：").append(value).append('\\n');
}
private void loadDnsLists(EditText custom,EditText global,EditText fallback,EditText remote,EditText domestic){
  root("dns-config-get",r->{
    if(r.exitCode!=0){status.setText("DNS 地址读取失败："+safe(r.output));return;}
    List<String> a=new ArrayList<>(),b=new ArrayList<>(),f=new ArrayList<>();
    String remoteValue="1.1.1.1",cnValue="223.5.5.5";
    for(String line:r.output.split("\\r?\\n")){
      String[] p=line.split("\\|",-1);
      if(p.length==2&&"CUSTOM".equals(p[0]))a.add(p[1]);
      else if(p.length==2&&"GLOBAL".equals(p[0]))b.add(p[1]);
      else if(p.length==2&&"FALLBACK".equals(p[0]))f.add(p[1]);
      else if(p.length==2&&"VPN_REMOTE".equals(p[0])&&!p[1].isEmpty())remoteValue=p[1];
      else if(p.length==2&&"VPN_CN".equals(p[0])&&!p[1].isEmpty())cnValue=p[1];
    }
    if(!a.isEmpty())custom.setText(android.text.TextUtils.join(",",a));
    if(!b.isEmpty())global.setText(android.text.TextUtils.join(",",b));
    if(!f.isEmpty())fallback.setText(android.text.TextUtils.join(",",f));
    remote.setText(remoteValue);domestic.setText(cnValue);
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
          group.check(nx.getId());
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
  card("批量导入白名单","最多 2000 条、48 Ki 字符（导入字节仍限制为 64 KiB）。整批验证并通过一次 FX apply 事务；失败会回滚。",
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
  card("批量导入黑名单","最多 2000 条、48 Ki 字符（导入字节仍限制为 64 KiB）。整批验证并通过一次 FX apply 事务；失败会回滚。",
      blockBulk,btn("验证并批量导入黑名单",()->importDomains("block",blockBulk)));

  EditText allowRemoveBulk=draftField("allow_remove_bulk");
  allowRemoveBulk.setGravity(Gravity.TOP|Gravity.START);
  allowRemoveBulk.setMinLines(3);
  allowRemoveBulk.setHint("每行一个域名；仅删除白名单中匹配的条目");
  card("批量移除白名单",
      "最多 2000 条。先完整校验域名，再在单次 FX 配置事务中移除；任何一步失败都会回滚。",
      allowRemoveBulk,
      btn("确认批量移除白名单",()->removeDomains("allow",allowRemoveBulk)));

  EditText blockRemoveBulk=draftField("block_remove_bulk");
  blockRemoveBulk.setGravity(Gravity.TOP|Gravity.START);
  blockRemoveBulk.setMinLines(3);
  blockRemoveBulk.setHint("每行一个域名；仅删除黑名单中匹配的条目");
  card("批量移除黑名单",
      "最多 2000 条。先完整校验域名，再在单次 FX 配置事务中移除；任何一步失败都会回滚。",
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
      btn("批量移除筛选命中的黑名单",()->removeFilteredDomains("BLOCK")));
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
  payload.append("# FX Ad domain list export\\n")
      .append("# format: allow|domain|note or block|domain|note\\n");
  int included=0,omitted=0;
  final int maxBytes=64*1024;
  for(Row row:selected){
   String line=row.kind.toLowerCase(Locale.ROOT)+"|"
       +cleanDomainExportField(row.value)+"|"
       +cleanDomainExportField(row.title)+"\\n";
   int used=payload.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
   int bytes=line.getBytes(java.nio.charset.StandardCharsets.UTF_8).length;
   if(used+bytes>maxBytes){omitted++;continue;}
   payload.append(line);included++;
  }
  if(included==0){status.setText("名单内容超过导出限制，没有生成导出数据。");return;}
  if(omitted>0)payload.append("# omitted ").append(omitted)
      .append(" rows at 64 KiB export limit\\n");
  try{
   Intent send=new Intent(Intent.ACTION_SEND);
   send.setType("text/plain");
   send.putExtra(Intent.EXTRA_SUBJECT,"FX Ad 域名名单备份");
   send.putExtra(Intent.EXTRA_TEXT,payload.toString());
   startActivity(Intent.createChooser(send,"分享域名名单"));
   status.setText("已准备分享 "+included+" 条域名名单"
       +(omitted>0?"；另有 "+omitted+" 条因 64 KiB 上限省略。":"。"));
  }catch(RuntimeException unavailable){
   status.setText("无法打开系统分享面板："+safe(unavailable.getMessage()));
  }
 }
 private static String cleanDomainExportField(String value){
  return value==null?"":value.replace('|',' ').replace('\\t',' ')
      .replace('\\r',' ').replace('\\n',' ');
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
       ||fields[2].trim().length()>180){
    status.setText("合并备份格式错误：每行必须为 allow|domain|note 或 block|domain|note。");
    return;
   }
   String kind=fields[0].trim(),domain=fields[1].trim(),note=fields[2].trim();
   unique.putIfAbsent(kind+"|"+domain,kind+"|"+domain+"|"+note);
   if(unique.size()>2000){status.setText("单次最多恢复 2000 条唯一域名。");return;}
  }
  if(unique.isEmpty()){status.setText("没有可恢复的域名条目。");return;}
  String payload=String.join("\n",unique.values());
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  if(bytes.length>65536){status.setText("合并备份超过 64 KiB，请拆分后导入。");return;}
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
   if(domains.size()>2000){status.setText("单次最多移除 2000 条域名。");return;}
  }
  if(domains.isEmpty()){status.setText("没有可移除的域名。");return;}
  String payload=String.join("\\n",domains);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  if(bytes.length>65536){status.setText("批量移除数据超过 64 KiB，请分批处理。");return;}
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
       || (fields.length==2 && fields[1].trim().length()>180)){
    status.setText("导入格式错误：请使用 domain 或 domain|note，每行一条。");
    return;
   }
   lines.add(fields.length==1?fields[0].trim():fields[0].trim()+"|"+fields[1].trim());
   if(lines.size()>2000){status.setText("单次最多导入 2000 条域名。");return;}
  }
  if(lines.isEmpty()){status.setText("没有可导入的域名。");return;}
  String payload=String.join("\n",lines);
  byte[] bytes=payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
  if(bytes.length>65536){status.setText("批量域名数据超过 64 KiB，请分批导入。");return;}
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
 private void domainRow(Row e,boolean allow){LinearLayout r=new LinearLayout(this);r.setTag("fx-list-row");r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));TextView domain=txt((allow?"白名单 · ":"黑名单 · ")+e.value,13,0xff17212b,true);domain.setTag("fx-list-title");r.addView(domain);TextView source=txt(e.title,10,0xff718091,false);source.setTag("fx-list-subtitle");r.addView(source);if(!allow){Switch enabled=new Switch(this);enabled.setTag("fx-switch-row");enabled.setText("启用此黑名单域名");enabled.setChecked(e.enabled);enabled.setOnCheckedChangeListener((button,on)->apply("block-set "+q(e.value)+" "+(on?"1":"0"),"黑名单状态"));r.addView(enabled);}r.addView(btn("移除",()->apply((allow?"allow-remove ":"block-remove ")+q(e.value),"名单移除")));entries.addView(r);}
 @Override protected void onDestroy(){pageGeneration++;trustedNetworkGeneration++;trustedNetworkStatus=null;rootProxyStatusGeneration++;rootProxyStatus=null;proxyWhitelistGeneration++;worker.shutdownNow();super.onDestroy();}
 private void profileRoot(String args,java.util.function.Consumer<RootAccess.Result> cb){
  final long requestGeneration=pageGeneration;
  final String requestPage=page;
  Runnable task=()->{
   RootAccess.Result result=RootAccess.execute(profileCmd(args),90000L,512*1024);
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