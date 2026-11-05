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
 private LinearLayout body,entries; private TextView status; private EditText search;
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
  return "[ -d '/data' ] && [ ! -L '/data' ]"
   + " && [ -d '/data/adb' ] && [ ! -L '/data/adb' ]"
   + " && [ -d '/data/adb/modules' ] && [ ! -L '/data/adb/modules' ]"
   + " && [ ! -L '/data/adb/modules_update' ]"
   + " && { [ ! -e '/data/adb/modules_update' ] || [ -d '/data/adb/modules_update' ]; } || exit 71; "
   + "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
   + "if [ -d \"$d\" ] && [ ! -L \"$d\" ]"
   + " && [ -f \"$d/module.prop\" ] && [ ! -L \"$d/module.prop\" ]"
   + " && grep -qx 'id=privacyguard' \"$d/module.prop\""
   + " && grep -qx 'version=1.0.0' \"$d/module.prop\""
   + " && [ -d \"$d/scripts\" ] && [ ! -L \"$d/scripts\" ]"
   + " && [ -f \"$d/scripts/yulong-ad-control.sh\" ]"
   + " && [ ! -L \"$d/scripts/yulong-ad-control.sh\" ]; then MP=\"$d\"; break; fi; done; "
   + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-ad-control.sh\" "+args;
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
        btn("填入当前 Wi-Fi SSID",() -> {
          if (trustedCurrentSsid == null || trustedCurrentSsid.isEmpty()) {
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
    final boolean[] suppress={false};
    allow.setOnCheckedChangeListener((button,checked)->{
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
 private void renderRules(){EditText url=draftField("rule_url");url.setSingleLine(true);url.setHint("https://… 或 builtin://…");EditText name=draftField("rule_name");name.setSingleLine(true);name.setHint("列表名称");card("添加过滤列表","仅允许 HTTPS 订阅及 FX 本地资源。",url,name,btn("添加并应用",()->{String u=url.getText().toString().trim(),n=name.getText().toString().trim();if(!u.isEmpty()&&!n.isEmpty())apply("rule-add "+q(u)+" "+q(n)+" 1","规则添加");}));search=draftField("rule_search");search.setSingleLine(true);search.setHint("搜索过滤列表");card("搜索","输入来源或列表名称",search);search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int be,int co){bind();}public void afterTextChanged(Editable e){}});entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
 private void renderDns(){
  card("本地 DNS 引擎",
       "启用时使用 FX 自有 AdGuard Home 过滤服务；关闭后按 FX 当前安全 DNS 回退配置处理。",
       dnsSwitch("启用本地 AdGuard Home","dns_engine_adguardhome"));
  card("本地 DNS 架构",
       "默认由本地 AdGuard Home 过滤并交给 Unbound 递归解析；不固定使用公共 DNS。只有明确启用自定义 DNS 或全局 DNS 时才会使用下面填写的 IPv4 地址。",
       dnsSwitch("DNS 兜底转发","dns_forward"),
       dnsSwitch("启用自定义 DNS","custom_dns"),
       dnsSwitch("启用全局 DNS 替换","global_dns"));
  card("过滤策略","DNS 和网络策略开关；与 DNS 上游地址分开保存。",
       dnsSwitch("阻止 QUIC","block_quic"),
       dnsSwitch("阻止 DNS-over-TLS","block_dot"),
       dnsSwitch("阻止明文 DNS","block_plain_dns"),
       dnsSwitch("阻止 IPv6","block_ipv6"),
       dnsSwitch("跟踪域名保护","block_track_domains"));
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
       txt("自定义 DNS 上游",12,0xff617080,true),customServers,
       btn("保存自定义 DNS",()->saveDnsServerList("custom",customServers)),
       txt("备用 DNS（故障回退）",12,0xff617080,true),fallbackServers,
       btn("保存备用 DNS",()->saveDnsServerList("fallback",fallbackServers)),
       btn("清除备用 DNS",()->fxDialogBuilder().setTitle("清除备用 DNS")
         .setMessage("清除故障回退服务器后，AdGuard Home 将不再使用备用 DNS。是否继续？")
         .setNegativeButton("取消",null).setPositiveButton("清除",(d,w)->root("dns-config-clear fallback",r->{
           if(r.exitCode==0){fallbackServers.setText("");status.setText("备用 DNS 已清除。");}
           else fxDialogBuilder().setTitle("清除失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
         })).show()),
       txt("全局 DNS 替换",12,0xff617080,true),globalServers,
       btn("保存全局 DNS",()->saveDnsServerList("global",globalServers)));
  EditText remoteDns=draftField("vpn_remote_dns");
  remoteDns.setSingleLine(true);remoteDns.setHint("VPN 远端 DNS，例如 1.1.1.1");
  EditText cnDns=draftField("vpn_cn_dns");
  cnDns.setSingleLine(true);cnDns.setHint("国内直连 DNS，例如 223.5.5.5");
  card("VPN 节点 DNS",
       "编辑 FX VPN 配置中的 remote_dns/cn_dns；它们不会替换本地 Unbound 递归模式，只有 VPN DNS 劫持/分流使用时生效。",
       txt("远端 DNS",12,0xff617080,true),remoteDns,
       btn("保存远端 DNS",()->saveVpnDns("remote_dns",remoteDns)),
       txt("国内直连 DNS",12,0xff617080,true),cnDns,
       btn("保存国内直连 DNS",()->saveVpnDns("cn_dns",cnDns)));
  card("DNS 查询日志","默认关闭。仅本机保存最近 7 天 DNS 查询记录，不会上传查询记录。",
       dnsSwitch("启用本地 DNS 查询日志","dns_querylog_enabled"),
       btn("查看 DNS 查询日志",()->startActivity(new Intent(this,FxYulongDnsActivity.class))));
  card("DNS 缓存管理","刷新 FX 自己的 AdGuard Home / Unbound 缓存会短暂重启本地解析服务；第三方 VPN 和它的规则不会被停止。",
       btn("刷新本地 DNS 缓存",()->fxDialogBuilder().setTitle("刷新本地 DNS 缓存")
         .setMessage("本地 DNS 查询可能短暂重试。FX 会重启自有解析服务并重新应用当前规则；不会操作第三方 VPN。")
         .setNegativeButton("取消",null).setPositiveButton("刷新",(d,w)->root("cache-flush",r->{
           fxDialogBuilder().setTitle(r.exitCode==0?"DNS 缓存已刷新":"DNS 刷新未完全成功")
             .setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
         })).show()));
  card("第三方 VPN DNS 过滤回退",
       "只有在系统确认唯一活动第三方 VPN、接口/所属 UID/出口路由有效，且 Unbound/AdGuard Home 健康探测通过后才接管明文 DNS。失败会撤销 FX 自有规则并保留第三方 VPN DNS。",
       dnsSwitch("第三方 VPN 下启用 Root DNS 过滤","vpn_external_dns_proxy"),
       btn("刷新 Root Proxy 状态",()->root("rootproxy-status",r->{fxDialogBuilder().setTitle("Root Proxy 状态").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})));
  loadDnsLists(customServers,globalServers,fallbackServers,remoteDns,cnDns);
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
private void saveDnsServerList(String kind,EditText input){
  String value=input.getText()==null?"":input.getText().toString().trim();
  root("dns-config-set "+kind+" "+q(value),r->{
    if(r.exitCode==0){status.setText(("custom".equals(kind)?"自定义 DNS":("fallback".equals(kind)?"备用 DNS":"全局 DNS"))+" 已保存并应用。");load();}
    else fxDialogBuilder().setTitle("DNS 地址未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
  });
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
  EditText blockBulk=draftField("block_bulk"); blockBulk.setGravity(Gravity.TOP|Gravity.START);
  blockBulk.setMinLines(4); blockBulk.setHint("每行一个域名；可选格式：example.com|备注");
  card("批量导入黑名单","最多 2000 条、48 Ki 字符（导入字节仍限制为 64 KiB）。整批验证并通过一次 FX apply 事务；失败会回滚。",
      blockBulk,btn("验证并批量导入黑名单",()->importDomains("block",blockBulk)));

  entries=new LinearLayout(this); entries.setOrientation(1); body.addView(entries);
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
       enabled,start,end,daysBox,
       btn("保存计划",()->{
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
     r.addView(btn("删除",()->fxDialogBuilder().setTitle("删除过滤列表").setMessage(e.value).setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->apply("rule-remove "+q(e.value),"规则删除")).show()));entries.addView(r);
    }
   }
   else if("DNS 设置".equals(page)||"VPN 与 Root Proxy".equals(page)){syncing=true;for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){LinearLayout p=(LinearLayout)body.getChildAt(i);for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){Switch sw=(Switch)p.getChildAt(j);if(sw.getTag() instanceof String){sw.setChecked(dnsValue((String)sw.getTag()).equals("1"));sw.setEnabled(true);}}}syncing=false;}
 else if("域名名单".equals(page)&&entries!=null){entries.removeAllViews();for(Row e:rows("ALLOW"))domainRow(e,true);for(Row e:rows("BLOCK"))domainRow(e,false);if(entries.getChildCount()==0)entries.addView(txt("暂无用户自定义域名名单。",12,0xff718091,false));}}
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
 private void domainRow(Row e,boolean allow){LinearLayout r=new LinearLayout(this);r.setTag("fx-list-row");r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));TextView domain=txt((allow?"白名单 · ":"黑名单 · ")+e.value,13,0xff17212b,true);domain.setTag("fx-list-title");r.addView(domain);TextView source=txt(e.title,10,0xff718091,false);source.setTag("fx-list-subtitle");r.addView(source);r.addView(btn("移除",()->apply((allow?"allow-remove ":"block-remove ")+q(e.value),"名单移除")));entries.addView(r);}
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
