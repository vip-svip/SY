package roro.stellar.manager.authorization;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;
import java.util.ArrayDeque;
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
import java.util.concurrent.atomic.AtomicLong;
import java.util.UUID;

/** Stellar authorization manager retained inside Yulong Shield in the single FX APK. */
public final class FxStellarManagerActivity extends Activity {
 // Root operations are serialized, but a bounded queue prevents rapid UI actions
 // from accumulating an unbounded number of long-running su processes.
 private final ThreadPoolExecutor worker=new ThreadPoolExecutor(
   1,1,0L,TimeUnit.MILLISECONDS,new ArrayBlockingQueue<>(16),r->{
     Thread thread=new Thread(r,"fx-stellar-app-inventory");thread.setDaemon(true);return thread;
   },new ThreadPoolExecutor.AbortPolicy());
 private final List<ApplicationInfo> apps=new ArrayList<>();
 private final Map<String,String> appLabels=new HashMap<>();
 private final Set<String> packages=new HashSet<>(), scopes=new HashSet<>(), always=new HashSet<>();
 private String target="";
 private LinearLayout body;
 private TextView state, selectedLabel, auditOutput, bootScriptStatus;
 private LinearLayout alwaysRows;
 private Switch bootScriptSwitch;
 private android.content.SharedPreferences stellarSettings;
 private boolean syncing;
 private boolean bootScriptUpdating;
 private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
 private TextView text(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
 private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
 private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
 private static final String COMMAND_SHORTCUT_ACTION =
   "roro.stellar.manager.action.EXECUTE_COMMAND_SHORTCUT";
 private static final String COMMAND_SHORTCUT_PREFS = "fx_stellar_command_shortcuts";
 private static final int MAX_COMMAND_SHORTCUTS = 24;

 private boolean isReadOnlyScope(String scope){
  return "SHELL_ID_COMMAND".equals(scope)
      || "PACKAGE_LIST_COMMAND".equals(scope)
      || "PROCESS_LIST_COMMAND".equals(scope)
      || "PROPERTY_READ_COMMAND".equals(scope)
      || "SETTINGS_READ_COMMAND".equals(scope)
      || "SELINUX_STATUS_COMMAND".equals(scope)
      || "FILESYSTEM_READ_COMMAND".equals(scope)
      || "SERVICE_LIST_COMMAND".equals(scope);
 }
 private boolean isReadOnlyCommand(String command){
  if(command==null||command.isEmpty()||command.length()>512)return false;
  for(int i=0;i<command.length();i++){
   char ch=command.charAt(i);
   if(ch<0x20||ch==0x7f)return false;
  }
  if("getprop".equals(command)||"id".equals(command)||"id -u".equals(command)
      ||"whoami".equals(command)||"ps".equals(command)||"ps -A".equals(command)
      ||"ps -ef".equals(command)||"getenforce".equals(command)
      ||"service list".equals(command))return true;
  return command.matches("getprop [A-Za-z0-9_.-]{1,128}")
      ||command.matches("pm list packages( -3|-s|-f|-U)?")
      ||command.matches("cmd package list packages( -3|-s|-f|-U)?")
      ||command.matches("dumpsys package [A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
      ||command.matches("settings get (secure|global|system) [A-Za-z0-9_.-]{1,128}")
      ||command.matches("cat /proc/(version|uptime)")
      ||command.matches("cat /sys/fs/selinux/enforce")
      ||command.matches("ls (/system|/product|/vendor|/apex|/proc|/sys)(/[A-Za-z0-9_.-]+)*");
 }
 private void pinReadOnlyCommandShortcut(String packageName,String scope,String command){
  if(Build.VERSION.SDK_INT<26){
   state.setText("Android 8.0 之前不支持桌面快捷方式。");return;
  }
  if(packageName==null||!packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
      ||!packages.contains(packageName)){
   state.setText("请先选择已授权的目标应用。");return;
  }
  if(!isReadOnlyScope(scope)||!scopes.contains(packageName+"|"+scope)){
   state.setText("目标应用尚未获得对应只读能力作用域，不能创建快捷方式。");return;
  }
  if(!isReadOnlyCommand(command)||!always.contains(packageName+"|"+command)){
   state.setText("快捷方式只能绑定已加入“始终允许命令”的只读命令；请先添加并刷新授权状态。");return;
  }
  ShortcutManager shortcutManager=getSystemService(ShortcutManager.class);
  if(shortcutManager==null||!shortcutManager.isRequestPinShortcutSupported()){
   state.setText("当前桌面不支持固定应用快捷方式。");return;
  }
  android.content.SharedPreferences prefs=getSharedPreferences(COMMAND_SHORTCUT_PREFS,MODE_PRIVATE);
  int existing=0;
  for(String key:prefs.getAll().keySet())if(key.endsWith(".package"))existing++;
  if(existing>=MAX_COMMAND_SHORTCUTS){
   state.setText("已达到 "+MAX_COMMAND_SHORTCUTS+" 个命令快捷方式的本地保存上限。");
   return;
  }
  String id=UUID.randomUUID().toString().replace("-","");
  prefs.edit().putString(id+".package",packageName)
      .putString(id+".scope",scope)
      .putString(id+".command",command)
      .putLong(id+".created",System.currentTimeMillis())
      .apply();
  String shortLabel=command.length()>24?command.substring(0,23)+"…":command;
  Intent launch=new Intent(this,FxStellarCommandShortcutActivity.class);
  launch.setAction(COMMAND_SHORTCUT_ACTION);
  launch.putExtra("command_id",id);
  launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
  ShortcutInfo shortcut=new ShortcutInfo.Builder(this,"fx-stellar-"+id)
      .setShortLabel(shortLabel)
      .setLongLabel("FX Stellar · "+shortLabel)
      .setIcon(Icon.createWithResource(this,android.R.drawable.ic_menu_info_details))
      .setIntent(launch)
      .build();
  try{
   if(shortcutManager.requestPinShortcut(shortcut,null)){
    state.setText("已向 Android 桌面提交固定快捷方式请求。桌面确认后即可使用；每次启动仍需确认执行。");
   }else{
    prefs.edit().remove(id+".package").remove(id+".scope")
        .remove(id+".command").remove(id+".created").apply();
    state.setText("桌面拒绝快捷方式请求；未保存可执行入口。");
   }
  }catch(RuntimeException failure){
   prefs.edit().remove(id+".package").remove(id+".scope")
       .remove(id+".command").remove(id+".created").apply();
   state.setText("快捷方式创建失败："+failure.getClass().getSimpleName());
  }
 }
 private boolean activityAlive(){return !isFinishing()&&!isDestroyed();}
 private void deliver(java.util.function.Consumer<RootAccess.Result> cb,RootAccess.Result result){
  runOnUiThread(()->{if(activityAlive())cb.accept(result);});
 }
 private static final int MAX_PENDING_ROOT_REQUESTS = 16;
 private final AtomicLong rootRequestIds = new AtomicLong(1L);
 private final ArrayDeque<PendingRootRequest> rootQueue = new ArrayDeque<>();
 private final Map<Long,java.util.function.Consumer<RootAccess.Result>> rootCallbacks = new HashMap<>();
 private Messenger stellarService;
 private boolean stellarServiceReady;
 private boolean stellarServiceBound;
 private static final class PendingRootRequest {
  final long id; final String args;
  final java.util.function.Consumer<RootAccess.Result> callback;
  PendingRootRequest(long requestId,String shellArgs,java.util.function.Consumer<RootAccess.Result> cb){
   id=requestId;args=shellArgs;callback=cb;
  }
 }
 private final Handler binderReplyHandler = new Handler(Looper.getMainLooper(), message -> {
  if(message.what==StellarAuthorizationService.MSG_READY){
   Bundle data=message.getData();
   int version=data==null?0:data.getInt(StellarAuthorizationService.KEY_PROTOCOL_VERSION,0);
   if(version!=StellarAuthorizationService.PROTOCOL_VERSION){
    failRootRequests("Stellar Binder 协议版本不匹配；本次请求没有执行。");
    return true;
   }
   stellarServiceReady=true;
   flushRootRequests();
   return true;
  }
  if(message.what==StellarAuthorizationService.MSG_RESULT){
   Bundle data=message.getData();
   if(data==null)return true;
   long id=data.getLong(StellarAuthorizationService.KEY_REQUEST_ID,-1L);
   java.util.function.Consumer<RootAccess.Result> callback=rootCallbacks.remove(id);
   if(callback!=null){
    int code=data.getInt(StellarAuthorizationService.KEY_EXIT_CODE,1);
    String output=data.getString(StellarAuthorizationService.KEY_OUTPUT,"");
    boolean denied=data.getBoolean(StellarAuthorizationService.KEY_DENIED,false);
    callback.accept(new RootAccess.Result(code,output,denied));
   }
   flushRootRequests();
   return true;
  }
  return true;
 });
 private final Messenger binderReplyMessenger = new Messenger(binderReplyHandler);
 private final ServiceConnection stellarConnection = new ServiceConnection(){
  @Override public void onServiceConnected(ComponentName name,IBinder binder){
   stellarService=new Messenger(binder);
   stellarServiceReady=false;
   try{
    Message hello=Message.obtain(null,StellarAuthorizationService.MSG_HELLO);
    hello.replyTo=binderReplyMessenger;
    stellarService.send(hello);
   }catch(RemoteException failure){
    stellarService=null;
    failRootRequests("Stellar Binder 握手失败："+failure.getClass().getSimpleName());
   }
  }
  @Override public void onServiceDisconnected(ComponentName name){
   stellarService=null;stellarServiceReady=false;
   failRootRequests("Stellar Binder 服务断开；正在执行的请求结果未知，请刷新状态后再操作。");
  }
  @Override public void onBindingDied(ComponentName name){
   stellarService=null;stellarServiceReady=false;
   failRootRequests("Stellar Binder 绑定已失效；请重新打开授权管理页。");
  }
  @Override public void onNullBinding(ComponentName name){
   stellarService=null;stellarServiceReady=false;
   failRootRequests("Stellar Binder 服务未返回可用接口。");
  }
 };
 private void failRootRequests(String reason){
  for(java.util.function.Consumer<RootAccess.Result> callback:new ArrayList<>(rootCallbacks.values())){
   callback.accept(RootAccess.failure(75,reason));
  }
  rootCallbacks.clear();
  while(!rootQueue.isEmpty()){
   PendingRootRequest request=rootQueue.removeFirst();
   request.callback.accept(RootAccess.failure(75,reason));
  }
 }
 private void flushRootRequests(){
  if(!stellarServiceReady||stellarService==null||!activityAlive())return;
  while(!rootQueue.isEmpty()&&rootCallbacks.size()<MAX_PENDING_ROOT_REQUESTS){
   PendingRootRequest request=rootQueue.removeFirst();
   Message message=Message.obtain(null,StellarAuthorizationService.MSG_EXECUTE);
   Bundle data=new Bundle();
   data.putLong(StellarAuthorizationService.KEY_REQUEST_ID,request.id);
   data.putString(StellarAuthorizationService.KEY_SHELL_ARGS,request.args);
   message.setData(data);
   message.replyTo=binderReplyMessenger;
   rootCallbacks.put(request.id,request.callback);
   try{
    stellarService.send(message);
   }catch(RemoteException failure){
    rootCallbacks.remove(request.id);
    request.callback.accept(RootAccess.failure(75,
      "Stellar Binder 请求发送失败："+failure.getClass().getSimpleName()));
    stellarServiceReady=false;
    stellarService=null;
    failRootRequests("Stellar Binder 连接中断；尚未发送的请求已停止。");
    return;
   }
  }
 }
 private void root(String args,java.util.function.Consumer<RootAccess.Result> cb){
  if(Looper.myLooper()!=Looper.getMainLooper()){
   runOnUiThread(()->root(args,cb));
   return;
  }
  if(!activityAlive())return;
  if(args==null||args.isEmpty()||args.length()>StellarAuthorizationService.MAX_SHELL_ARGS){
   cb.accept(RootAccess.failure(2,"Stellar 请求为空或超过大小限制；未执行。"));
   return;
  }
  if(rootQueue.size()+rootCallbacks.size()>=MAX_PENDING_ROOT_REQUESTS){
   cb.accept(RootAccess.failure(75,"Stellar 请求队列已满；本次请求未执行。"));
   return;
  }
  long id=rootRequestIds.getAndIncrement();
  rootQueue.addLast(new PendingRootRequest(id,args,cb));
  flushRootRequests();
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
  stellarServiceBound=bindService(
    new Intent(this,StellarAuthorizationService.class),
    stellarConnection,Context.BIND_AUTO_CREATE);
  if(!stellarServiceBound){
   state.setText("Stellar Binder 服务绑定失败；授权数据未读取。");
   failRootRequests("Stellar Binder 服务绑定失败；请求未执行。");
  }
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
  body.addView(button("无线调试 / Secure Settings 授权",()->startActivity(new Intent(this,FxStellarSecureSettingsActivity.class))));
  addBootScriptControls();
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
    }),
    button("创建桌面命令快捷方式",()->{
      String c=cmd.getText().toString().trim();
      String scope=String.valueOf(commandScope.getSelectedItem());
      pinReadOnlyCommandShortcut(target,scope,c);
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
  addCard("Stellar 操作记录",
    "只显示 FX 本地授权管理器成功执行的运行时权限、AppOps 和安全设置变更；最多保留 500 条，不代表原 Stellar Binder 守护服务的完整运行日志。",
    button("刷新操作记录",this::loadAuditLogs),
    button("清除操作记录",this::confirmClearAuditLogs));
  auditOutput=text("尚未读取操作记录。",11,0xff526170,false);
  auditOutput.setTextIsSelectable(true);
  body.addView(auditOutput);
  body.addView(button("撤销当前应用全部 Stellar 授权",()->{
    if(target.isEmpty())return;
    new AlertDialog.Builder(this).setTitle("撤销授权").setMessage("同时移除应用白名单、能力作用域和始终允许命令？")
      .setNegativeButton("取消",null).setPositiveButton("撤销",(d,w)->apply("pkg-set "+quote(target)+" 0","撤销 Stellar 授权")).show();
  }));
 }
 private android.content.SharedPreferences stellarSettings(){
  if(stellarSettings==null){
   android.content.Context deviceProtected=createDeviceProtectedStorageContext();
   stellarSettings=deviceProtected.getSharedPreferences("settings",MODE_PRIVATE);
  }
  return stellarSettings;
 }

 private void addBootScriptControls(){
  String savedMode=stellarSettings().getString("boot_mode","NONE");
  boolean scriptSelected="SCRIPT".equals(savedMode);
  boolean supportedMode="NONE".equals(savedMode)||scriptSelected;
  bootScriptSwitch=new Switch(this);
  bootScriptSwitch.setText("KernelSU/Magisk service.d 开机启动（SCRIPT）");
  bootScriptSwitch.setChecked(scriptSelected);
  bootScriptSwitch.setEnabled(supportedMode);
  bootScriptSwitch.setOnCheckedChangeListener((button,enabled)->{
   if(bootScriptUpdating)return;
   bootScriptUpdating=true;
   button.setEnabled(false);
   new AlertDialog.Builder(this)
     .setTitle(enabled?"安装 Stellar 开机脚本":"移除 Stellar 开机脚本")
     .setMessage(enabled
       ?"将把经过校验的 FX libstellar.so 启动脚本原子写入 /data/adb/service.d/stellar.sh。设备完成启动后，脚本会定位本 FX 包的本机库并执行 Stellar。此操作需要 Root；不会打开 ADB、修改 tcpip 端口或自动授予 WRITE_SECURE_SETTINGS。"
       :"将删除 FX 管理的 /data/adb/service.d/stellar.sh，之后重启不再由此脚本启动 Stellar。不会删除 FX APK 或其他启动脚本。")
     .setNegativeButton("取消",(dialog,which)->{
      bootScriptUpdating=false;
      button.setChecked(!enabled);
      button.setEnabled(true);
     })
     .setPositiveButton(enabled?"安装并启用":"移除并关闭",(dialog,which)->applyBootScriptMode(enabled))
     .setOnCancelListener(dialog->{
      if(bootScriptUpdating){
       bootScriptUpdating=false;
       button.setChecked(!enabled);
       button.setEnabled(true);
      }
     }).show();
  });

  bootScriptStatus=text("正在读取开机脚本状态…",12,0xff617080,false);
  LinearLayout panel=new LinearLayout(this);
  panel.setOrientation(1);
  panel.addView(bootScriptSwitch);
  panel.addView(bootScriptStatus);
  panel.addView(button("查询开机脚本状态",this::refreshBootScriptStatus));
  if(!supportedMode){
   bootScriptStatus.setText("检测到保存的原版 BootMode="+savedMode+"。此 FX 构建尚未迁入该模式的完整启动链；为防止伪迁移，开关已锁定。先使用下面的“关闭旧启动模式”明确停用。");
   panel.addView(button("关闭未迁移的旧启动模式",()->{
    new AlertDialog.Builder(this).setTitle("将原版启动模式设为 NONE")
      .setMessage("该模式的完整 Receiver/WorkManager 链尚未迁入 FX。明确关闭后，FX 不会再按旧模式调度开机启动。")
      .setNegativeButton("取消",null)
      .setPositiveButton("设为 NONE",(dialog,which)->{
       root("boot-script remove",result->{
        if(result.exitCode!=0||result.output==null
             ||!result.output.contains("success=1 boot_script=removed")){
         bootScriptStatus.setText("清理旧启动脚本失败；原模式偏好未修改："+(result.output==null?"":result.output));
         return;
        }
        if(!stellarSettings().edit().putString("boot_mode","NONE").commit()){
         bootScriptStatus.setText("启动脚本已移除，但 NONE 偏好未能保存；请再次刷新并重试。");
         return;
        }
        bootScriptUpdating=false;
        bootScriptSwitch.setChecked(false);
        bootScriptSwitch.setEnabled(true);
        bootScriptStatus.setText("已关闭旧启动模式；当前 BootMode=NONE。");
       });
      }).show();
   }));
  }
  addCard("开机启动模式", "默认 NONE。当前已迁入的模式只有 SCRIPT；BROADCAST 和 TCPIP_PREWARM 的原版 Receiver/WorkManager 行为仍在迁移中，不会在此处伪装成可用。", panel);
  refreshBootScriptStatus();
 }

 private void applyBootScriptMode(boolean install){
  final String command="boot-script "+(install?"install":"remove");
  root(command,result->{
   String marker=install?"success=1 boot_script=installed":"success=1 boot_script=removed";
   if(result.exitCode!=0||result.output==null||!result.output.contains(marker)){
    bootScriptUpdating=false;
    bootScriptSwitch.setChecked(!install);
    bootScriptSwitch.setEnabled(true);
    bootScriptStatus.setText((install?"安装":"移除")+"失败；boot_mode 未修改。Root 退出码 "
       +result.exitCode+"："+(result.output==null?"":result.output));
    return;
   }
   boolean saved=stellarSettings().edit().putString("boot_mode",install?"SCRIPT":"NONE").commit();
   if(!saved){
    if(install){
     root("boot-script remove",rollback->{
      bootScriptUpdating=false;
      bootScriptSwitch.setChecked(false);
      bootScriptSwitch.setEnabled(true);
      bootScriptStatus.setText("启动脚本已安装，但 boot_mode 偏好写入失败；已尝试回滚脚本。"
        +(rollback.exitCode==0?"回滚成功。":"回滚失败，请手动检查 service.d。"));
     });
    }else{
     bootScriptUpdating=false;
     bootScriptSwitch.setChecked(true);
     bootScriptSwitch.setEnabled(true);
     bootScriptStatus.setText("启动脚本已删除，但 boot_mode=NONE 写入失败；请刷新后确认状态。");
    }
    return;
   }
   bootScriptUpdating=false;
   bootScriptSwitch.setChecked(install);
   bootScriptSwitch.setEnabled(true);
   bootScriptStatus.setText(install
      ?"已安装并启用 SCRIPT 开机脚本；只有检测到服务脚本和 FX libstellar.so 后才会执行。"
      :"已移除 FX 开机脚本；boot_mode=NONE。");
   state.setText(install?"Stellar BootMode 已设置为 SCRIPT。":"Stellar BootMode 已设置为 NONE。");
  });
 }

 private void refreshBootScriptStatus(){
  if(bootScriptStatus==null)return;
  bootScriptStatus.setText("正在通过受保护的 Root broker 查询 service.d…");
  root("boot-script status",result->{
   if(bootScriptStatus==null)return;
   if(result.exitCode!=0||result.output==null){
    bootScriptStatus.setText("开机脚本状态查询失败（Root "+result.exitCode+"）："
      +(result.output==null?"":result.output));
    return;
   }
   String mode=stellarSettings().getString("boot_mode","NONE");
   if(result.output.contains("boot_script=installed")){
    bootScriptStatus.setText("磁盘脚本：FX 已安装并可执行 · BootMode="+mode);
   }else if(result.output.contains("boot_script=legacy")){
    bootScriptStatus.setText("磁盘脚本：检测到原版 Stellar 脚本；打开开关可迁移到 FX 包名和启动器。");
   }else if(result.output.contains("boot_script=absent")){
    bootScriptStatus.setText("磁盘脚本：未安装 · BootMode="+mode);
   }else{
    bootScriptStatus.setText("磁盘脚本存在但不属于 FX 管理，已拒绝自动替换或删除。");
   }
  });
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
  private void loadAuditLogs(){
  root("logs",r->{
   if(auditOutput==null)return;
   if(r.exitCode!=0){auditOutput.setText("操作记录读取失败："+(r.output==null?"":r.output));return;}
   String value=r.output==null?"":r.output.trim();
   if("FXSTELLARLOG_EMPTY".equals(value))auditOutput.setText("当前没有本地授权操作记录。");
   else if(value.startsWith("FXSTELLARLOG1\n"))auditOutput.setText(value.substring("FXSTELLARLOG1\n".length()));
   else auditOutput.setText(value);
  });
 }
 private void confirmClearAuditLogs(){
  new AlertDialog.Builder(this).setTitle("清除 Stellar 操作记录")
   .setMessage("只删除 FX 本地授权管理器的操作记录，不会撤销应用授权，也不会清除系统或守护服务的其他日志。")
   .setNegativeButton("取消",null)
   .setPositiveButton("清除",(dialog,which)->root("clear-logs",r->{
    if(r.exitCode==0){if(auditOutput!=null)auditOutput.setText("操作记录已清除。");state.setText("Stellar 本地操作记录已清除。");}
    else state.setText("清除操作记录失败："+(r.output==null?"":r.output));
   })).show();
 }
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
 @Override protected void onDestroy(){
  stellarServiceReady=false;stellarService=null;
  if(stellarServiceBound){
   try{unbindService(stellarConnection);}catch(IllegalArgumentException ignored){}
   stellarServiceBound=false;
  }
  rootQueue.clear();rootCallbacks.clear();
  worker.shutdownNow();
  super.onDestroy();
 }
}
