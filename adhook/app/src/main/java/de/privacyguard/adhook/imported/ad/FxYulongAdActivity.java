package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Native control screens for migrated Yulong AdBlock 7.0.1. */
public final class FxYulongAdActivity extends Activity {
 private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
         TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
         r -> new Thread(r, "fx-yulong-ad-ui"), new ThreadPoolExecutor.AbortPolicy());
 private LinearLayout body,entries; private TextView status; private EditText search;
 private String page="首页与防护",snapshot="";
 private static final class Row {String kind,value,title;boolean enabled;Row(String k,String v,String t,boolean e){kind=k;value=v;title=t;enabled=e;}}
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView txt(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button btn(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private void card(String title,String detail,View... views){LinearLayout p=new LinearLayout(this);p.setOrientation(1);p.setPadding(dp(14),dp(10),dp(14),dp(10));p.setBackgroundColor(0xfff0f3f7);p.addView(txt(title,15,0xff17212b,true));p.addView(txt(detail,12,0xff617080,false));for(View v:views)p.addView(v);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(5),dp(12),dp(5));body.addView(p,lp);}
 private String q(String s){return "'"+(s==null?"":s.replace("'","'\\''"))+"'";}
 private String cmd(String args){return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; [ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" "+args;}
 private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){
  Runnable task=()->{
   RootAccess.Result result=RootAccess.execute(cmd(args),90000L,512*1024);
   runOnUiThread(()->{if(!isFinishing()&&!isDestroyed()&&cb!=null)cb.accept(result);});
  };
  try{
   worker.execute(task);
  }catch(RejectedExecutionException full){
   RootAccess.Result busy=RootAccess.failure(125,"后台任务繁忙，请稍后重试。");
   runOnUiThread(()->{
    if(isFinishing()||isDestroyed())return;
    status.setText("后台任务繁忙，请稍后重试。");
    if(cb!=null)cb.accept(busy);
   });
  }
 }
 private String safe(String s){return s==null||s.trim().isEmpty()?"请确认 FX Hook Root 权限。":s.trim();}
 private void apply(String args,String label){
  final boolean masterWrite = args != null && args.matches("^ad-master\\s+[01]$");
  try{
   worker.execute(()->{
    boolean gateAcquired = false;
    RootAccess.Result result;
    try{
     if(masterWrite){
      gateAcquired=FxYulongAdOperationGate.tryAcquire();
      if(!gateAcquired){
       runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())status.setText("另一入口正在修改广告过滤，请稍后重试。");});
       return;
      }
     }
     result=RootAccess.execute(cmd(args),90000L,512*1024);
    }catch(Throwable failure){
     runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())status.setText(label+"失败："+failure.getClass().getSimpleName());});
     return;
    }finally{
     if(gateAcquired)FxYulongAdOperationGate.release();
    }
    runOnUiThread(()->{
     if(isFinishing()||isDestroyed())return;
     if(result.exitCode==0){
      FxYulongAdWidgetProvider.refreshAll(this);
      status.setText(label+"：已保存并应用。");
     }else{
      status.setText(label+"失败："+safe(result.output));
      new AlertDialog.Builder(this).setTitle("配置未应用").setMessage(safe(result.output)).setPositiveButton("关闭",null).show();
     }
     load();
    });
   });
  }catch(RejectedExecutionException full){
   // The writer lock is acquired only inside the queued worker. A rejected
   // submission never acquired it, so releasing here could unlock another
   // entry point's in-flight operation.
   status.setText("后台任务繁忙，请稍后重试。");
  }
 }
 @Override protected void onCreate(Bundle b){super.onCreate(b);page=getIntent().getStringExtra("suite_page");if(page==null)page="首页与防护";LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xfff7f8fa);LinearLayout h=new LinearLayout(this);h.setGravity(Gravity.CENTER_VERTICAL);h.setPadding(dp(10),dp(6),dp(12),dp(6));h.addView(btn("‹ 返回",this::finish));h.addView(txt("游龙广告插件 7.0.1",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));root.addView(h);ScrollView sc=new ScrollView(this);sc.setFillViewport(true);body=new LinearLayout(this);body.setOrientation(1);body.setPadding(0,dp(4),0,dp(20));sc.addView(body);root.addView(sc,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);render();load();}
 private void render(){body.removeAllViews();status=txt("正在读取 FX 配置…",12,0xff526170,false);card("运行架构","游龙原版 AdBlockVpnService / RootProxyService 不会启动；过滤、DNS 和代理继续由 FX 单一网络入口处理。",btn("应用级网络拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));card("状态","设备端真实配置与应用结果",status);LinearLayout nav=new LinearLayout(this);nav.setOrientation(0);nav.addView(btn("首页",()->open("首页与防护")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("过滤",()->open("过滤列表")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("DNS",()->open("DNS 设置")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("名单",()->open("域名名单")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("计划",()->open("计划任务")),new LinearLayout.LayoutParams(0,-2,1));body.addView(nav);body.addView(txt("当前页面："+page,13,0xff617080,true));if("过滤列表".equals(page))renderRules();else if("DNS 设置".equals(page))renderDns();else if("域名名单".equals(page))renderDomains();else if("VPN 与 Root Proxy".equals(page)){
  card("FX 唯一 VPN/TUN","节点、直连/全局/规则由 FX 管理。游龙原版第二个 VpnService 不会启动。",
    dnsSwitch("允许第三方 VPN 下启用 FX Root DNS Proxy","vpn_external_dns_proxy"),
    dnsSwitch("第三方 VPN 兼容路由开关","vpn_external_compat"),
    btn("刷新 Root Proxy 运行状态",()->root("rootproxy-status",r->{new AlertDialog.Builder(this).setTitle("Root Proxy 状态").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})),
    btn("应用级网络拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));
  card("工作条件","仅当检测到唯一活动第三方 VPN、VPN 接口/所属 UID/出口路由可验证，Unbound 与 AdGuard Home 健康探测通过后才接管 DNS；任何验证失败都会撤销 FX 自有重定向规则并保留原 VPN DNS。");
}else if("计划任务".equals(page))renderSchedule();else if("日志与诊断".equals(page))renderLogs();else renderHome();}
 private void open(String p){page=p;render();bind();}
 private void renderHome(){
  Switch master=new Switch(this);master.setText("启用广告过滤主开关");master.setTag("ad-master");master.setEnabled(false);
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
 private void renderRules(){EditText url=new EditText(this);url.setSingleLine(true);url.setHint("https://… 或 builtin://…");EditText name=new EditText(this);name.setSingleLine(true);name.setHint("列表名称");card("添加过滤列表","仅允许 HTTPS 订阅及 FX 本地资源。",url,name,btn("添加并应用",()->{String u=url.getText().toString().trim(),n=name.getText().toString().trim();if(!u.isEmpty()&&!n.isEmpty())apply("rule-add "+q(u)+" "+q(n)+" 1","规则添加");}));search=new EditText(this);search.setSingleLine(true);search.setHint("搜索过滤列表");card("搜索","输入来源或列表名称",search);search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int be,int co){bind();}public void afterTextChanged(Editable e){}});entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
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
    for(String line:r.output.split("\\\\r?\\\\n"))
      if(line.startsWith("mode="))mode=line.substring(5).trim();
    responseGroup.check("refused".equals(mode)?responseRefused.getId()
        :"custom_ip".equals(mode)?responseNull.getId():responseNx.getId());
    responseState.setText("当前模式："+mode);
  });
  EditText customServers=new EditText(this);
  customServers.setSingleLine(false);customServers.setMinLines(2);
  customServers.setHint("IPv4 / https://DoH / tls://DoT / quic://DoQ");
  EditText fallbackServers=new EditText(this);
  fallbackServers.setSingleLine(false);fallbackServers.setMinLines(2);
  fallbackServers.setHint("备用 DNS IPv4，例如：1.1.1.1,8.8.8.8");
  EditText globalServers=new EditText(this);
  globalServers.setSingleLine(false);globalServers.setMinLines(2);
  globalServers.setHint("例如：8.8.8.8,1.1.1.1");
  card("自定义/全局/备用 DNS 服务器",
       "自定义 DNS 最多 3 个上游，可混合 IPv4、DoH、DoT、DoQ；备用 DNS 只支持 IPv4。加密上游只在 FX 本地 AdGuard Home 过滤引擎运行时生效；启用“阻止 DoT/QUIC”会阻断对应传输协议。",
       txt("自定义 DNS 上游",12,0xff617080,true),customServers,
       btn("保存自定义 DNS",()->saveDnsServerList("custom",customServers)),
       txt("备用 DNS（故障回退）",12,0xff617080,true),fallbackServers,
       btn("保存备用 DNS",()->saveDnsServerList("fallback",fallbackServers)),
       btn("清除备用 DNS",()->new AlertDialog.Builder(this).setTitle("清除备用 DNS")
         .setMessage("清除故障回退服务器后，AdGuard Home 将不再使用备用 DNS。是否继续？")
         .setNegativeButton("取消",null).setPositiveButton("清除",(d,w)->root("dns-config-clear fallback",r->{
           if(r.exitCode==0){fallbackServers.setText("");status.setText("备用 DNS 已清除。");}
           else new AlertDialog.Builder(this).setTitle("清除失败").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
         })).show()),
       txt("全局 DNS 替换",12,0xff617080,true),globalServers,
       btn("保存全局 DNS",()->saveDnsServerList("global",globalServers)));
  EditText remoteDns=new EditText(this);
  remoteDns.setSingleLine(true);remoteDns.setHint("VPN 远端 DNS，例如 1.1.1.1");
  EditText cnDns=new EditText(this);
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
       btn("刷新本地 DNS 缓存",()->new AlertDialog.Builder(this).setTitle("刷新本地 DNS 缓存")
         .setMessage("本地 DNS 查询可能短暂重试。FX 会重启自有解析服务并重新应用当前规则；不会操作第三方 VPN。")
         .setNegativeButton("取消",null).setPositiveButton("刷新",(d,w)->root("cache-flush",r->{
           new AlertDialog.Builder(this).setTitle(r.exitCode==0?"DNS 缓存已刷新":"DNS 刷新未完全成功")
             .setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
         })).show()));
  card("第三方 VPN DNS 过滤回退",
       "只有在系统确认唯一活动第三方 VPN、接口/所属 UID/出口路由有效，且 Unbound/AdGuard Home 健康探测通过后才接管明文 DNS。失败会撤销 FX 自有规则并保留第三方 VPN DNS。",
       dnsSwitch("第三方 VPN 下启用 Root DNS 过滤","vpn_external_dns_proxy"),
       btn("刷新 Root Proxy 状态",()->root("rootproxy-status",r->{new AlertDialog.Builder(this).setTitle("Root Proxy 状态").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();})));
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
    else new AlertDialog.Builder(this).setTitle("DNS 地址未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
  });
}
private void saveVpnDns(String key,EditText input){
  String value=input.getText()==null?"":input.getText().toString().trim();
  root("dns-vpn-set "+key+" "+q(value),r->{
    if(r.exitCode==0)status.setText(("remote_dns".equals(key)?"VPN 远端 DNS":"国内直连 DNS")+" 已保存并应用。");
    else new AlertDialog.Builder(this).setTitle("VPN DNS 未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
  });
}
 private boolean syncing;
 private Switch dnsSwitch(String label,String key){Switch s=new Switch(this);s.setText(label);s.setTag(key);s.setEnabled(false);s.setOnCheckedChangeListener((b,on)->{if(!syncing)apply("dns-set "+key+" "+(on?"1":"0"),label);});return s;}
 private void renderDomains(){
  EditText allow=new EditText(this); allow.setSingleLine(true); allow.setHint("白名单域名");
  EditText allowNote=new EditText(this); allowNote.setSingleLine(true); allowNote.setHint("备注");
  card("域名白名单","精确放行域名及其子域。",
      allow,allowNote,
      btn("添加白名单",()->{
        if(!allow.getText().toString().trim().isEmpty())
          apply("allow-add "+q(allow.getText().toString().trim())+" "+q(allowNote.getText().toString().trim()),"白名单添加");
      }));
  EditText allowBulk=new EditText(this); allowBulk.setGravity(Gravity.TOP|Gravity.START);
  allowBulk.setMinLines(4); allowBulk.setHint("每行一个域名；可选格式：example.com|备注");
  card("批量导入白名单","最多 2000 条、64 KiB。整批验证并通过一次 FX apply 事务；失败会回滚。",
      allowBulk,btn("验证并批量导入白名单",()->importDomains("allow",allowBulk)));

  EditText block=new EditText(this); block.setSingleLine(true); block.setHint("黑名单域名");
  EditText blockNote=new EditText(this); blockNote.setSingleLine(true); blockNote.setHint("备注");
  card("域名黑名单","只添加明确需要阻断的域名。",
      block,blockNote,
      btn("添加黑名单",()->{
        if(!block.getText().toString().trim().isEmpty())
          apply("block-add "+q(block.getText().toString().trim())+" "+q(blockNote.getText().toString().trim()),"黑名单添加");
      }));
  EditText blockBulk=new EditText(this); blockBulk.setGravity(Gravity.TOP|Gravity.START);
  blockBulk.setMinLines(4); blockBulk.setHint("每行一个域名；可选格式：example.com|备注");
  card("批量导入黑名单","最多 2000 条、64 KiB。整批验证并通过一次 FX apply 事务；失败会回滚。",
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
  new AlertDialog.Builder(this).setTitle(kind.equals("allow")?"批量导入白名单":"批量导入黑名单")
      .setMessage("共 "+lines.size()+" 条。后端会先验证所有域名，再原子写入配置并应用；任何失败都会回滚整批。")
      .setNegativeButton("取消",null)
      .setPositiveButton("导入", (dialog,which)->
          apply(kind+"-import "+q(encoded),kind.equals("allow")?"批量白名单导入":"批量黑名单导入"))
      .show();
 }
 private void renderSchedule(){
  Switch enabled=new Switch(this);
  enabled.setText("启用每周自动计划");
  EditText start=new EditText(this);
  start.setSingleLine(true);start.setHint("开始时间 HH:MM");start.setText("22:00");
  EditText end=new EditText(this);
  end.setSingleLine(true);end.setHint("结束时间 HH:MM");end.setText("07:00");
  LinearLayout daysBox=new LinearLayout(this);daysBox.setOrientation(1);
  String[] labels={"周一","周二","周三","周四","周五","周六","周日"};
  android.widget.CheckBox[] days=new android.widget.CheckBox[7];
  for(int i=0;i<7;i++){days[i]=new android.widget.CheckBox(this);days[i].setText(labels[i]);days[i].setChecked(true);daysBox.addView(days[i]);}
  TextView state=txt("正在读取计划任务…",12,0xff526170,false);
  card("每周自动计划",
       "按设备本地时间自动启用/暂停游龙广告过滤列表。开始时间晚于结束时间时按跨午夜区间计算；开始时间等于结束时间表示所选日期全天。",
       enabled,start,end,daysBox,
       btn("保存计划",()->{
         StringBuilder selected=new StringBuilder();
         for(int i=0;i<7;i++)if(days[i].isChecked()){if(selected.length()>0)selected.append(',');selected.append(i+1);}
         if(selected.length()==0){new AlertDialog.Builder(this).setMessage("至少选择一天。").setPositiveButton("知道了",null).show();return;}
         String command="schedule-set "+(enabled.isChecked()?"1":"0")+" "+q(start.getText().toString().trim())+" "+q(end.getText().toString().trim())+" "+q(selected.toString());
         root(command,r->{
           if(r.exitCode==0){
             state.setText("计划已保存并立即重新计算。\\n"+safe(r.output));
           }else{
             state.setText("计划保存/应用失败："+safe(r.output));
             new AlertDialog.Builder(this).setTitle("计划未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();
           }
         });
       }),
       btn("重新读取计划",()->loadSchedule(enabled,start,end,days,state)));
  card("当前计划状态",
       "星期编号：周一=1 至周日=7。计划只控制游龙广告过滤列表；FX 96110 反诈规则、Hosts 白/黑名单、DNS 上游和 VPN 节点不受影响。",
       state);
  loadSchedule(enabled,start,end,days,state);
 }
 private void loadSchedule(Switch enabled,EditText start,EditText end,
       android.widget.CheckBox[] days,TextView state){
  root("schedule-get",r->{
    if(r.exitCode!=0){state.setText("读取失败："+safe(r.output));return;}
    String en="0",st="22:00",ed="07:00",ds="1,2,3,4,5,6,7",active="1",watcher="0";
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
    String[] selected=ds.split(",");
    for(int i=0;i<7;i++){
      days[i].setChecked(false);
      for(String d:selected)if(String.valueOf(i+1).equals(d.trim()))days[i].setChecked(true);
    }
    state.setText("计划："+("1".equals(en)?"已启用":"已关闭")
       +"；当前游龙过滤："+("1".equals(active)?"生效":"按计划暂停"));
  });
 }
 private void renderLogs(){card("运行日志","显示 FX 当前模块日志，不将全局日志冒充原版逐应用统计。");root("logs",r->card("FX 日志","本机启动与过滤记录",txt(safe(r.output),11,0xff526170,false)));}
 private void load(){root("list",r->{if(r.exitCode!=0){status.setText("读取失败："+safe(r.output));return;}snapshot=r.output==null?"":r.output;status.setText("已读取设备端 FX 配置。");bind();});}
 private List<Row> rows(String kind){List<Row> out=new ArrayList<>();for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length>=4&&kind.equals(p[0]))out.add(new Row(p[0],p[1],p[2],"1".equals(p[3])));}return out;}
 private void bind(){if(snapshot.isEmpty())return;
  if("首页与防护".equals(page)){
   syncing=true;
   for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){
    LinearLayout p=(LinearLayout)body.getChildAt(i);
    for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){
     Switch sw=(Switch)p.getChildAt(j);
     if("ad-master".equals(sw.getTag())){sw.setChecked(adMaster());sw.setEnabled(true);}
    }
   }
   syncing=false;
  }if("过滤列表".equals(page)&&entries!=null){entries.removeAllViews();String f=search==null||search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);for(Row e:rows("RULE")){if(!f.isEmpty()&&!(e.value+" "+e.title).toLowerCase(Locale.ROOT).contains(f))continue;LinearLayout r=new LinearLayout(this);r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));r.addView(txt(e.title,13,0xff17212b,true));r.addView(txt(e.value,10,0xff718091,false));Switch sw=new Switch(this);sw.setText("启用此列表");sw.setChecked(e.enabled);sw.setOnCheckedChangeListener((b,on)->apply("rule-set "+q(e.value)+" "+(on?"1":"0"),"规则状态"));r.addView(sw);r.addView(btn("删除",()->new AlertDialog.Builder(this).setTitle("删除过滤列表").setMessage(e.value).setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->apply("rule-remove "+q(e.value),"规则删除")).show()));entries.addView(r);}}
 else if("DNS 设置".equals(page)||"VPN 与 Root Proxy".equals(page)){syncing=true;for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){LinearLayout p=(LinearLayout)body.getChildAt(i);for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){Switch sw=(Switch)p.getChildAt(j);if(sw.getTag() instanceof String){sw.setChecked(dnsValue((String)sw.getTag()).equals("1"));sw.setEnabled(true);}}}syncing=false;}
 else if("域名名单".equals(page)&&entries!=null){entries.removeAllViews();for(Row e:rows("ALLOW"))domainRow(e,true);for(Row e:rows("BLOCK"))domainRow(e,false);if(entries.getChildCount()==0)entries.addView(txt("暂无用户自定义域名名单。",12,0xff718091,false));}}
 private void copyAutomationAction(String value){
  android.content.ClipboardManager clipboard=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
  if(clipboard!=null){clipboard.setPrimaryClip(android.content.ClipData.newPlainText("FX Tasker action",value));Toast.makeText(this,"广播 Action 已复制。",Toast.LENGTH_SHORT).show();}
}
private boolean adMaster(){
  for(String line:snapshot.split("\\r?\\n")){
   String[] p=line.split("\\|",-1);
   if(p.length==2&&p[0].equals("AD_MASTER"))return p[1].equals("1");
  }
  return true;
}
private String dnsValue(String key){for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length==3&&p[0].equals("DNS")&&p[1].equals(key))return p[2];}return "0";}
 private void domainRow(Row e,boolean allow){LinearLayout r=new LinearLayout(this);r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));r.addView(txt((allow?"白名单 · ":"黑名单 · ")+e.value,13,0xff17212b,true));r.addView(txt(e.title,10,0xff718091,false));r.addView(btn("移除",()->apply((allow?"allow-remove ":"block-remove ")+q(e.value),"名单移除")));entries.addView(r);}
 @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
