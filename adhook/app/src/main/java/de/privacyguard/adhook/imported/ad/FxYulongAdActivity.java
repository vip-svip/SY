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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native control screens for migrated Yulong AdBlock 7.0.1. */
public final class FxYulongAdActivity extends Activity {
 private final ExecutorService worker=Executors.newSingleThreadExecutor();
 private LinearLayout body,entries; private TextView status; private EditText search;
 private String page="首页与防护",snapshot="";
 private static final class Row {String kind,value,title;boolean enabled;Row(String k,String v,String t,boolean e){kind=k;value=v;title=t;enabled=e;}}
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView txt(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button btn(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private void card(String title,String detail,View... views){LinearLayout p=new LinearLayout(this);p.setOrientation(1);p.setPadding(dp(14),dp(10),dp(14),dp(10));p.setBackgroundColor(0xfff0f3f7);p.addView(txt(title,15,0xff17212b,true));p.addView(txt(detail,12,0xff617080,false));for(View v:views)p.addView(v);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(dp(12),dp(5),dp(12),dp(5));body.addView(p,lp);}
 private String q(String s){return "'"+(s==null?"":s.replace("'","'\\''"))+"'";}
 private String cmd(String args){return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; [ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" "+args;}
 private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){worker.execute(()->{RootAccess.Result r=RootAccess.execute(cmd(args),90000L,512*1024);runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())cb.accept(r);});});}
 private String safe(String s){return s==null||s.trim().isEmpty()?"请确认 FX Hook Root 权限。":s.trim();}
 private void apply(String args,String label){root(args,r->{if(r.exitCode==0){status.setText(label+"：已保存并应用。");load();}else{status.setText(label+"失败："+safe(r.output));new AlertDialog.Builder(this).setTitle("配置未应用").setMessage(safe(r.output)).setPositiveButton("关闭",null).show();load();}});}
 @Override protected void onCreate(Bundle b){super.onCreate(b);page=getIntent().getStringExtra("suite_page");if(page==null)page="首页与防护";LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xfff7f8fa);LinearLayout h=new LinearLayout(this);h.setGravity(Gravity.CENTER_VERTICAL);h.setPadding(dp(10),dp(6),dp(12),dp(6));h.addView(btn("‹ 返回",this::finish));h.addView(txt("游龙广告插件 7.0.1",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));root.addView(h);ScrollView sc=new ScrollView(this);sc.setFillViewport(true);body=new LinearLayout(this);body.setOrientation(1);body.setPadding(0,dp(4),0,dp(20));sc.addView(body);root.addView(sc,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);render();load();}
 private void render(){body.removeAllViews();status=txt("正在读取 FX 配置…",12,0xff526170,false);card("运行架构","游龙原版 AdBlockVpnService / RootProxyService 不会启动；过滤、DNS 和代理继续由 FX 单一网络入口处理。",btn("应用级网络拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));card("状态","设备端真实配置与应用结果",status);LinearLayout nav=new LinearLayout(this);nav.setOrientation(0);nav.addView(btn("首页",()->open("首页与防护")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("过滤",()->open("过滤列表")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("DNS",()->open("DNS 设置")),new LinearLayout.LayoutParams(0,-2,1));nav.addView(btn("名单",()->open("域名名单")),new LinearLayout.LayoutParams(0,-2,1));body.addView(nav);body.addView(txt("当前页面："+page,13,0xff617080,true));if("过滤列表".equals(page))renderRules();else if("DNS 设置".equals(page))renderDns();else if("域名名单".equals(page))renderDomains();else if("VPN 与 Root Proxy".equals(page))card("FX 唯一 VPN/TUN","节点、直连/全局/规则由 FX 管理。",btn("应用级拦截",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));else if("日志与诊断".equals(page))renderLogs();else renderHome();}
 private void open(String p){page=p;render();bind();}
 private void renderHome(){card("广告过滤","规则保存在 FX [list:rule]，按每条清单独立启停。",btn("管理过滤列表",()->open("过滤列表")));card("DNS 设置","管理本地 AdGuard Home、DNS 转发与 QUIC/DoT 策略。",btn("DNS 设置",()->open("DNS 设置")));card("域名白/黑名单","白名单优先放行；黑名单只阻断明确域名。",btn("域名名单",()->open("域名名单")));card("应用网络拦截","与 VPN 路由分离的 IPv4/IPv6 OUTPUT 阻断。",btn("按应用管理",()->startActivity(new Intent(this,FxYulongFirewallActivity.class))));}
 private void renderRules(){EditText url=new EditText(this);url.setSingleLine(true);url.setHint("https://… 或 builtin://…");EditText name=new EditText(this);name.setSingleLine(true);name.setHint("列表名称");card("添加过滤列表","仅允许 HTTPS 订阅及 FX 本地资源。",url,name,btn("添加并应用",()->{String u=url.getText().toString().trim(),n=name.getText().toString().trim();if(!u.isEmpty()&&!n.isEmpty())apply("rule-add "+q(u)+" "+q(n)+" 1","规则添加");}));search=new EditText(this);search.setSingleLine(true);search.setHint("搜索过滤列表");card("搜索","输入来源或列表名称",search);search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int be,int co){bind();}public void afterTextChanged(Editable e){}});entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
 private void renderDns(){card("DNS 后端","更改后重新应用 FX DNS 配置。",
 dnsSwitch("本地 AdGuard Home","dns_engine_adguardhome"),dnsSwitch("DNS 兜底转发","dns_forward"),dnsSwitch("阻止 QUIC","block_quic"),dnsSwitch("阻止 DNS-over-TLS","block_dot"),dnsSwitch("阻止明文 DNS","block_plain_dns"),dnsSwitch("阻止 IPv6","block_ipv6"),dnsSwitch("跟踪域名保护","block_track_domains"));}
 private boolean syncing;
 private Switch dnsSwitch(String label,String key){Switch s=new Switch(this);s.setText(label);s.setTag(key);s.setEnabled(false);s.setOnCheckedChangeListener((b,on)->{if(!syncing)apply("dns-set "+key+" "+(on?"1":"0"),label);});return s;}
 private void renderDomains(){EditText allow=new EditText(this);allow.setSingleLine(true);allow.setHint("白名单域名");EditText allowNote=new EditText(this);allowNote.setSingleLine(true);allowNote.setHint("备注");card("域名白名单","精确放行域名及其子域。",allow,allowNote,btn("添加白名单",()->{if(!allow.getText().toString().trim().isEmpty())apply("allow-add "+q(allow.getText().toString().trim())+" "+q(allowNote.getText().toString().trim()),"白名单添加");}));EditText block=new EditText(this);block.setSingleLine(true);block.setHint("黑名单域名");EditText blockNote=new EditText(this);blockNote.setSingleLine(true);blockNote.setHint("备注");card("域名黑名单","只添加明确需要阻断的域名。",block,blockNote,btn("添加黑名单",()->{if(!block.getText().toString().trim().isEmpty())apply("block-add "+q(block.getText().toString().trim())+" "+q(blockNote.getText().toString().trim()),"黑名单添加");}));entries=new LinearLayout(this);entries.setOrientation(1);body.addView(entries);}
 private void renderLogs(){card("运行日志","显示 FX 当前模块日志，不将全局日志冒充原版逐应用统计。");root("logs",r->card("FX 日志","本机启动与过滤记录",txt(safe(r.output),11,0xff526170,false)));}
 private void load(){root("list",r->{if(r.exitCode!=0){status.setText("读取失败："+safe(r.output));return;}snapshot=r.output==null?"":r.output;status.setText("已读取设备端 FX 配置。");bind();});}
 private List<Row> rows(String kind){List<Row> out=new ArrayList<>();for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length>=4&&kind.equals(p[0]))out.add(new Row(p[0],p[1],p[2],"1".equals(p[3])));}return out;}
 private void bind(){if(snapshot.isEmpty())return;if("过滤列表".equals(page)&&entries!=null){entries.removeAllViews();String f=search==null||search.getText()==null?"":search.getText().toString().trim().toLowerCase(Locale.ROOT);for(Row e:rows("RULE")){if(!f.isEmpty()&&!(e.value+" "+e.title).toLowerCase(Locale.ROOT).contains(f))continue;LinearLayout r=new LinearLayout(this);r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));r.addView(txt(e.title,13,0xff17212b,true));r.addView(txt(e.value,10,0xff718091,false));Switch sw=new Switch(this);sw.setText("启用此列表");sw.setChecked(e.enabled);sw.setOnCheckedChangeListener((b,on)->apply("rule-set "+q(e.value)+" "+(on?"1":"0"),"规则状态"));r.addView(sw);r.addView(btn("删除",()->new AlertDialog.Builder(this).setTitle("删除过滤列表").setMessage(e.value).setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->apply("rule-remove "+q(e.value),"规则删除")).show()));entries.addView(r);}}
 else if("DNS 设置".equals(page)){syncing=true;for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof LinearLayout){LinearLayout p=(LinearLayout)body.getChildAt(i);for(int j=0;j<p.getChildCount();j++)if(p.getChildAt(j) instanceof Switch){Switch sw=(Switch)p.getChildAt(j);if(sw.getTag() instanceof String){sw.setChecked(dnsValue((String)sw.getTag()).equals("1"));sw.setEnabled(true);}}}syncing=false;}
 else if("域名名单".equals(page)&&entries!=null){entries.removeAllViews();for(Row e:rows("ALLOW"))domainRow(e,true);for(Row e:rows("BLOCK"))domainRow(e,false);if(entries.getChildCount()==0)entries.addView(txt("暂无用户自定义域名名单。",12,0xff718091,false));}}
 private String dnsValue(String key){for(String line:snapshot.split("\\r?\\n")){String[] p=line.split("\\|",-1);if(p.length==3&&p[0].equals("DNS")&&p[1].equals(key))return p[2];}return "0";}
 private void domainRow(Row e,boolean allow){LinearLayout r=new LinearLayout(this);r.setOrientation(1);r.setPadding(dp(8),dp(5),dp(8),dp(5));r.addView(txt((allow?"白名单 · ":"黑名单 · ")+e.value,13,0xff17212b,true));r.addView(txt(e.title,10,0xff718091,false));r.addView(btn("移除",()->apply((allow?"allow-remove ":"block-remove ")+q(e.value),"名单移除")));entries.addView(r);}
 @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
