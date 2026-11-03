package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

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

/** Stellar authorization manager retained inside Yulong Shield in the single FX APK. */
public final class FxStellarManagerActivity extends Activity {
 // Root operations are serialized, but a bounded queue prevents rapid UI actions
 // from accumulating an unbounded number of long-running su processes.
 private final ThreadPoolExecutor worker=new ThreadPoolExecutor(
   1,1,0L,TimeUnit.MILLISECONDS,new ArrayBlockingQueue<>(16),r->{
     Thread thread=new Thread(r,"fx-stellar-root");thread.setDaemon(true);return thread;
   },new ThreadPoolExecutor.AbortPolicy());
 private final List<ApplicationInfo> apps=new ArrayList<>();
 private final Map<String,String> appLabels=new HashMap<>();
 private final Set<String> packages=new HashSet<>(), scopes=new HashSet<>(), always=new HashSet<>();
 private String target="";
 private LinearLayout body;
 private TextView state, selectedLabel;
 private LinearLayout alwaysRows;
 private boolean syncing;
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView text(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
 private String command(String args) {
  return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
    + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; then MP=\"$d\"; break; fi; done; "
    + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-stellar-control.sh\" " + args;
 }
 private boolean activityAlive(){return !isFinishing()&&!isDestroyed();}
 private void deliver(java.util.function.Consumer<RootAccess.Result> cb,RootAccess.Result result){
  runOnUiThread(()->{if(activityAlive())cb.accept(result);});
 }
 private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){
  try{
   worker.execute(()->deliver(cb,RootAccess.execute(command(args),60000L,256*1024)));
  }catch(RejectedExecutionException full){
   deliver(cb,RootAccess.failure(75,"Stellar 操作队列已满；本次操作未执行，请等待现有任务完成后重试。"));
  }
 }
 private String appLabel(String pkg){String label=appLabels.get(pkg);return label==null||label.isEmpty()?pkg:label;}
 private void loadApplications(){
  try{
   worker.execute(()->{
    List<ApplicationInfo> loaded=new ArrayList<>();
    Map<String,String> labels=new HashMap<>();
    String error=null;
    try{
     PackageManager pm=getPackageManager();
     loaded.addAll(pm.getInstalledApplications(0));
     loaded.removeIf(a->a.packageName==null||a.packageName.equals(getPackageName()));
     for(ApplicationInfo app:loaded){
      try{labels.put(app.packageName,String.valueOf(pm.getApplicationLabel(app)));}
      catch(RuntimeException ignored){labels.put(app.packageName,app.packageName);}
     }
     loaded.sort(Comparator.comparing(a->labels.getOrDefault(a.packageName,a.packageName).toLowerCase(Locale.ROOT)));
    }catch(RuntimeException failure){error=failure.getClass().getSimpleName()+": "+failure.getMessage();}
    final String loadError=error;
    runOnUiThread(()->{
     if(!activityAlive())return;
     apps.clear();apps.addAll(loaded);appLabels.clear();appLabels.putAll(labels);
     if(!target.isEmpty()&&!appLabels.containsKey(target))target="";
     updateTargetLabel();
     if(loadError!=null)state.setText("安装应用清单读取失败："+loadError);
     else state.setText("应用清单已加载 · "+apps.size()+" 个可选应用");
     bind();
    });
   });
  }catch(RejectedExecutionException full){
   if(activityAlive())state.setText("应用清单任务队列已满，暂时无法加载。");
  }
 }
 private void updateTargetLabel(){
  if(selectedLabel!=null)selectedLabel.setText(target.isEmpty()
    ?"当前目标应用：未选择":"当前目标应用："+appLabel(target)+" · "+target);
 }
 @Override protected void onCreate(Bundle saved){
  super.onCreate(saved);
  LinearLayout root=new LinearLayout(this);root.setOrientation(1);
  LinearLayout head=new LinearLayout(this);head.setPadding(dp(10),dp(6),dp(10),dp(6));
  head.addView(button("‹ 返回安全护盾",this::finish));head.addView(text("Stellar 特权管理",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));root.addView(head);
  ScrollView scroll=new ScrollView(this);body=new LinearLayout(this);body.setOrientation(1);body.setPadding(dp(8),dp(4),dp(8),dp(20));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
  if(saved!=null)target=saved.getString("stellar_target_package","");
  render();
  loadApplications();
  refresh();
 }
 @Override protected void onSaveInstanceState(Bundle out){
  out.putString("stellar_target_package",target);
  super.onSaveInstanceState(out);
 }
 private void render(){
  body.removeAllViews();
  addCard("Stellar 管理器","保留在游龙安全护盾内部。授权数据沿用原版 /data/local/tmp/stellar_guard 文件；不创建 FX 独立主导航标签。");
  state=text("正在读取授权策略…",12,0xff617080,false);body.addView(state);
  body.addView(button("选择授权目标应用",this::chooseTarget));
  addSwitch("允许该应用请求 Stellar 授权","PKG",false);
  selectedLabel=text("当前目标应用：未选择",13,0xff334155,true);body.addView(selectedLabel);
  addSwitch("读取 Shell 身份","SHELL_ID_COMMAND",false);
  addSwitch("读取已安装包列表","PACKAGE_LIST_COMMAND",false);
  addSwitch("读取进程信息","PROCESS_LIST_COMMAND",false);
  addSwitch("读取系统属性","PROPERTY_READ_COMMAND",false);
  addSwitch("读取系统设置","SETTINGS_READ_COMMAND",false);
  addSwitch("读取 SELinux 状态","SELINUX_STATUS_COMMAND",false);
  addSwitch("只读文件访问","FILESYSTEM_READ_COMMAND",false);
  addSwitch("读取系统服务列表","SERVICE_LIST_COMMAND",false);
  addSwitch("管理 AppOps（高权限）","APPOPS_MANAGE",true);
  addSwitch("管理运行时权限（高权限）","RUNTIME_PERMISSION_MANAGE",true);
  addSwitch("安全设置写入（高权限）","SECURE_SETTINGS_WRITE",true);
  body.addView(button("撤销终端命令作用域",()->{
    if(target.isEmpty())return;
    new AlertDialog.Builder(this).setTitle("撤销终端命令权限").setMessage("移除当前应用的 TERMINAL_COMMAND 作用域？")
      .setNegativeButton("取消",null).setPositiveButton("撤销",(d,w)->apply("scope-set "+quote(target)+" TERMINAL_COMMAND 0","撤销终端命令权限")).show();
  }));
  String[] readScopes={"SHELL_ID_COMMAND","PACKAGE_LIST_COMMAND","PROCESS_LIST_COMMAND","PROPERTY_READ_COMMAND","SETTINGS_READ_COMMAND","SELINUX_STATUS_COMMAND","FILESYSTEM_READ_COMMAND","SERVICE_LIST_COMMAND"};
  android.widget.Spinner commandScope=new android.widget.Spinner(this);
  android.widget.ArrayAdapter<String> scopeAdapter=new android.widget.ArrayAdapter<>(this,android.R.layout.simple_spinner_item,readScopes);
  scopeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);commandScope.setAdapter(scopeAdapter);
  EditText cmd=new EditText(this);cmd.setSingleLine(true);cmd.setHint("只读命令：getprop / pm list packages / dumpsys package / settings get / ps");
  addCard("始终允许的命令","命令必须属于当前应用已授予的只读能力；不接受脚本、管道、重定向或写入命令。",commandScope,cmd,
    button("添加当前应用命令",()->{
      String c=cmd.getText().toString().trim();if(target.isEmpty()||c.isEmpty())return;
      new AlertDialog.Builder(this).setTitle("确认始终允许").setMessage(target+"\\n"+c)
        .setNegativeButton("取消",null).setPositiveButton("确认",(d,w)->apply("always-set "+quote(target)+" "+quote(c)+" 1","添加始终允许命令")).show();
    }),
    button("执行已授权只读命令",()->{
      String c=cmd.getText().toString().trim();String scope=String.valueOf(commandScope.getSelectedItem());
      if(target.isEmpty()||c.isEmpty())return;
      root("run "+quote(target)+" "+scope+" "+quote(c),result->{
        TextView output=text(result.output==null?"":result.output,12,0xff334155,false);output.setTextIsSelectable(true);
        ScrollView view=new ScrollView(this);view.addView(output);
        new AlertDialog.Builder(this).setTitle("Stellar 只读命令 · 退出码 "+result.exitCode).setView(view).setPositiveButton("关闭",null).show();
        state.setText(result.exitCode==0?"只读命令执行完成。":"只读命令未执行："+(result.output==null?"":result.output));
      });
    }));
      EditText permissionName=new EditText(this);
  permissionName.setSingleLine(true);
  permissionName.setHint("android.permission.CAMERA / RECORD_AUDIO / ACCESS_FINE_LOCATION");
  addCard("运行时权限管理",
    "先在上方打开 RUNTIME_PERMISSION_MANAGE。仅支持预设 Android 运行时权限名称；每次授予/撤销都要求再次确认。",
    permissionName,
    button("授予权限",()->confirmManaged("permission "+quote(target)+" grant "+quote(permissionName.getText().toString().trim()),"授予运行时权限")),
    button("撤销权限",()->confirmManaged("permission "+quote(target)+" revoke "+quote(permissionName.getText().toString().trim()),"撤销运行时权限")));
  EditText secureKey = new EditText(this);
  secureKey.setSingleLine(true);
  secureKey.setHint("show_ime_with_hard_keyboard / screensaver_enabled / long_press_timeout");
  EditText secureValue = new EditText(this);
  secureValue.setSingleLine(true);
  secureValue.setHint("0 / 1 / 100-1000");
  addCard("安全设置写入",
    "先开启 SECURE_SETTINGS_WRITE。只开放三个固定低风险键；其他 secure setting 一律拒绝。每次写入都要求再次确认。",
    secureKey, secureValue,
    button("写入安全设置",()->{
      String key = secureKey.getText().toString().trim();
      String value = secureValue.getText().toString().trim();
      if (target.isEmpty() || key.isEmpty() || value.isEmpty()) {
        state.setText("请先选择目标应用并填写设置项和值。");
        return;
      }
      confirmManaged("secure-setting "+quote(target)+" "+quote(key)+" "+quote(value),
              "写入 Android 安全设置");
    }));
  EditText appOpName=new EditText(this);
  appOpName.setSingleLine(true);appOpName.setHint("CAMERA / RECORD_AUDIO / FINE_LOCATION / POST_NOTIFICATION");
  EditText appOpMode=new EditText(this);
  appOpMode.setSingleLine(true);appOpMode.setHint("allow / ignore / deny / default / foreground");
  appOpMode.setText("default");
  addCard("AppOps 管理",
    "先在上方打开 APPOPS_MANAGE。操作名和模式均使用固定白名单；不会执行任意 Shell 命令。",
    appOpName,appOpMode,
    button("应用 AppOps 模式",()->confirmManaged("appops "+quote(target)+" "+quote(appOpName.getText().toString().trim())+" "+quote(appOpMode.getText().toString().trim()),"应用 AppOps 模式")));
  addCard("授权记录","可查看当前目标应用保存的始终允许命令。",button("刷新",this::refresh));
  alwaysRows = new LinearLayout(this);
  alwaysRows.setOrientation(LinearLayout.VERTICAL);
  body.addView(alwaysRows);
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
    if ("PKG".equals(key)) apply("pkg-set "+quote(target)+" "+(on?"1":"0"),label);
    else apply("scope-set "+quote(target)+" "+key+" "+(on?"1":"0"),label);
  });
  body.addView(sw);
 }
 private void chooseTarget(){
  if(apps.isEmpty()){
   if(state!=null)state.setText("应用清单仍在加载，或系统当前没有可授权的其他应用。");
   return;
  }
  String[] labels=new String[apps.size()];int selected=0;
  for(int i=0;i<apps.size();i++){labels[i]=appLabel(apps.get(i).packageName)+"\n"+apps.get(i).packageName;if(apps.get(i).packageName.equals(target))selected=i;}
  new AlertDialog.Builder(this).setTitle("选择 Stellar 目标应用").setSingleChoiceItems(labels,selected,(d,w)->{
    target=apps.get(w).packageName;d.dismiss();updateTargetLabel();bind();
  }).setNegativeButton("关闭",null).show();
 }
 private void bind(){
  syncing=true;
  for(int i=0;i<body.getChildCount();i++)if(body.getChildAt(i) instanceof Switch){
    Switch s=(Switch)body.getChildAt(i);String k=String.valueOf(s.getTag());s.setEnabled(!target.isEmpty());
    s.setChecked("PKG".equals(k)?packages.contains(target):scopes.contains(target+"|"+k));
  }
  syncing=false;
 }
 private void confirmManaged(String command,String title){
  if(target.isEmpty()){state.setText("请先选择授权目标应用。");return;}
  new AlertDialog.Builder(this).setTitle(title)
    .setMessage("目标应用："+target+"\n请求："+command.substring(command.indexOf(' ')+1)
       +"\n\n此操作会修改目标应用的系统权限/AppOps 状态。只有你信任该应用时才继续。")
    .setNegativeButton("取消",null)
    .setPositiveButton("明确执行",(dialog,which)->root(command,result->{
      state.setText(result.exitCode==0?title+"已完成。":title+"失败："+(result.output==null?"":result.output));
      refresh();
    })).show();
 }
 private void apply(String op,String name){root(op,r->{if(r.exitCode==0)state.setText(name+"已保存。");else state.setText(name+"失败："+(r.output==null?"":r.output));refresh();});}
 private void refresh(){
  root("list",r->{
    if(r.exitCode!=0){state.setText("Stellar 策略读取失败："+r.output);return;}
    packages.clear();scopes.clear();always.clear();if(alwaysRows!=null)alwaysRows.removeAllViews();
    for(String line:(r.output==null?"":r.output).split("\\r?\\n")){
      String[] p=line.split("\\|",3);if(p.length<2)continue;
      if("PKG".equals(p[0]))packages.add(p[1]);
      else if("SCOPE".equals(p[0])&&p.length==3)scopes.add(p[1]+"|"+p[2]);
      else if("ALWAYS".equals(p[0])&&p.length==3)always.add(p[1]+"|"+p[2]);
    }
    state.setText("策略已同步 · 应用 "+packages.size()+" · 能力 "+scopes.size()+" · 始终允许 "+always.size());
    bind();
    if(alwaysRows!=null) alwaysRows.removeAllViews();
    for(String item:always){String[] p=item.split("\\|",2);if(p.length==2&&p[0].equals(target)){
      alwaysRows.addView(text(p[1],11,0xff526170,false));
      alwaysRows.addView(button("移除此命令",()->apply("always-set "+quote(p[0])+" "+quote(p[1])+" 0","移除始终允许命令")));
    }}
  });
 }
 @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
