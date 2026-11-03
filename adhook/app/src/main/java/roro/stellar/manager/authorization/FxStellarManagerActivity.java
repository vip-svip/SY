package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Stellar authorization manager retained inside Yulong Shield in the single FX APK. */
public final class FxStellarManagerActivity extends Activity {
 private final ExecutorService worker=Executors.newSingleThreadExecutor();
 private final List<ApplicationInfo> apps=new ArrayList<>();
 private final Set<String> packages=new HashSet<>(), scopes=new HashSet<>(), always=new HashSet<>();
 private String target="";
 private LinearLayout body;
 private TextView state, selectedLabel;
 private boolean syncing;
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView text(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
 private String command(String args){return "sh /data/adb/modules/privacyguard/scripts/yulong-stellar-control.sh "+args;}
 private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){worker.execute(()->{RootAccess.Result r=RootAccess.execute(command(args),60000L,256*1024);runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())cb.accept(r);});});}
 private String appLabel(String pkg){try{return String.valueOf(getPackageManager().getApplicationLabel(getPackageManager().getApplicationInfo(pkg,0)));}catch(Throwable ignored){return pkg;}}
 @Override protected void onCreate(Bundle saved){
  super.onCreate(saved);
  LinearLayout root=new LinearLayout(this);root.setOrientation(1);
  LinearLayout head=new LinearLayout(this);head.setPadding(dp(10),dp(6),dp(10),dp(6));
  head.addView(button("‹ 返回安全护盾",this::finish));head.addView(text("Stellar 特权管理",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));root.addView(head);
  ScrollView scroll=new ScrollView(this);body=new LinearLayout(this);body.setOrientation(1);body.setPadding(dp(8),dp(4),dp(8),dp(20));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
  try{apps.addAll(getPackageManager().getInstalledApplications(0));apps.removeIf(a->a.packageName==null||a.packageName.equals(getPackageName()));apps.sort(Comparator.comparing(a->appLabel(a.packageName).toLowerCase(Locale.ROOT)));}catch(Throwable ignored){}
  render();refresh();
 }
 private void render(){
  body.removeAllViews();
  addCard("Stellar 管理器","保留在游龙安全护盾内部。授权数据沿用原版 /data/local/tmp/stellar_guard 文件；不创建 FX 独立主导航标签。");
  state=text("正在读取授权策略…",12,0xff617080,false);body.addView(state);
  body.addView(button("选择授权目标应用",this::chooseTarget));
  addSwitch("允许该应用请求 Stellar 授权","PKG");
  selectedLabel=text("当前目标应用：未选择",13,0xff334155,true);body.addView(selectedLabel);
  addSwitch("读取 Shell 身份","SHELL_ID_COMMAND",false);
  addSwitch("读取已安装包列表","PACKAGE_LIST_COMMAND",false);
  addSwitch("读取进程信息","PROCESS_LIST_COMMAND",false);
  addSwitch("读取系统属性","PROPERTY_READ_COMMAND",false);
  addSwitch("读取系统设置","SETTINGS_READ_COMMAND",false);
  addSwitch("读取 SELinux 状态","SELINUX_STATUS_COMMAND",false);
  addSwitch("只读文件访问","FILESYSTEM_READ_COMMAND",false);
  addSwitch("读取系统服务列表","SERVICE_LIST_COMMAND",false);
  addSwitch("写入安全设置（高权限）","SECURE_SETTINGS_WRITE",true);
  addSwitch("管理 AppOps（高权限）","APPOPS_MANAGE",true);
  addSwitch("管理运行时权限（高权限）","RUNTIME_PERMISSION_MANAGE",true);
  body.addView(button("撤销终端命令作用域",()->{
    if(target.isEmpty())return;
    new AlertDialog.Builder(this).setTitle("撤销终端命令权限").setMessage("移除当前应用的 TERMINAL_COMMAND 作用域？")
      .setNegativeButton("取消",null).setPositiveButton("撤销",(d,w)->apply("scope-set "+quote(target)+" TERMINAL_COMMAND 0","撤销终端命令权限")).show();
  }));
  EditText cmd=new EditText(this);cmd.setSingleLine(true);cmd.setHint("只读命令：getprop / pm list packages / dumpsys package / settings get");
  addCard("始终允许的命令","只接受只读查询；不接受分号、管道、重定向、脚本或写入类命令。",cmd,button("添加当前应用命令",( )->{
    String c=cmd.getText().toString().trim();if(target.isEmpty()||c.isEmpty())return;
    new AlertDialog.Builder(this).setTitle("确认始终允许").setMessage(target+"\n"+c)
      .setNegativeButton("取消",null).setPositiveButton("确认",(d,w)->apply("always-set "+quote(target)+" "+quote(c)+" 1","添加始终允许命令")).show();
  }));
  addCard("授权记录","可查看当前目标应用保存的始终允许命令。",button("刷新",this::refresh));
  body.addView(button("撤销当前应用全部 Stellar 授权",()->{
    if(target.isEmpty())return;
    new AlertDialog.Builder(this).setTitle("撤销授权").setMessage("同时移除应用白名单、能力作用域和始终允许命令？")
      .setNegativeButton("取消",null).setPositiveButton("撤销",(d,w)->apply("pkg-set "+quote(target)+" 0","撤销 Stellar 授权")).show();
  }));
 }
 private void addCard(String title,String detail,View... children){
  LinearLayout p=new LinearLayout(this);p.setOrientation(1);p.setPadding(dp(12),dp(8),dp(12),dp(8));p.setBackgroundColor(0xffeef2f6);
  p.addView(text(title,14,0xff17212b,true));p.addView(text(detail,12,0xff617080,false));for(View v:children)p.addView(v);
  LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.setMargins(0,dp(4),0,dp(4));body.addView(p,lp);
 }
 private void addSwitch(String label,String key,boolean sensitive){
  Switch sw=new Switch(this);sw.setText(label);sw.setTag(key);sw.setEnabled(false);
  sw.setOnCheckedChangeListener((button,on)->{
    if(syncing||target.isEmpty())return;
    if(sensitive&&on){
      new AlertDialog.Builder(this).setTitle("高权限 Stellar 作用域")
        .setMessage("此权限可能修改系统设置或其他应用权限。仅对你完全信任的测试应用授权。")
        .setNegativeButton("取消",(d,w)->{syncing=true;button.setChecked(false);syncing=false;})
        .setPositiveButton("明确授权",(d,w)->apply("scope-set "+quote(target)+" "+key+" 1",label)).show();
      return;
    }
    apply("scope-set "+quote(target)+" "+key+" "+(on?"1":"0"),label);
  });
  body.addView(sw);
 }
 private void chooseTarget(){
  if(apps.isEmpty())return;
  String[] labels=new String[apps.size()];int selected=0;
  for(int i=0;i<apps.size();i++){labels[i]=appLabel(apps.get(i).packageName)+"\n"+apps.get(i).packageName;if(apps.get(i).packageName.equals(target))selected=i;}
  new AlertDialog.Builder(this).setTitle("选择 Stellar 目标应用").setSingleChoiceItems(labels,selected,(d,w)->{target=apps.get(w).packageName;d.dismiss();if(selectedLabel!=null)selectedLabel.setText("当前目标应用："+appLabel(target)+" · "+target);bind();}).setNegativeButton("关闭",null).show();
 }
 private void bind(){
  syncing=true;
  for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof Switch){
    Switch s=(Switch)body.getChildAt(i);String k=String.valueOf(s.getTag());s.setEnabled(!target.isEmpty());
    s.setChecked("PKG".equals(k)?packages.contains(target):scopes.contains(target+"|"+k));
  }
  syncing=false;
 }
 private void apply(String op,String name){root(op,r->{if(r.exitCode==0)state.setText(name+"已保存。");else state.setText(name+"失败："+(r.output==null?"":r.output));refresh();});}
 private void refresh(){
  root("list",r->{
    if(r.exitCode!=0){state.setText("Stellar 策略读取失败："+r.output);return;}
    packages.clear();scopes.clear();always.clear();
    for(String line:(r.output==null?"":r.output).split("\\r?\\n")){
      String[] p=line.split("\\|",3);if(p.length<2)continue;
      if("PKG".equals(p[0]))packages.add(p[1]);
      else if("SCOPE".equals(p[0])&&p.length==3)scopes.add(p[1]+"|"+p[2]);
      else if("ALWAYS".equals(p[0])&&p.length==3)always.add(p[1]+"|"+p[2]);
    }
    state.setText("策略已同步 · 应用 "+packages.size()+" · 能力 "+scopes.size()+" · 始终允许 "+always.size());
    bind();
    for(String item:always){String[] p=item.split("\\|",2);if(p.length==2&&p[0].equals(target)){
      body.addView(text(p[1],11,0xff526170,false));
      body.addView(button("移除此命令",()->apply("always-set "+quote(p[0])+" "+quote(p[1])+" 0","移除始终允许命令")));
    }}
  });
 }
 @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
