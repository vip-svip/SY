package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.graphics.Typeface;
import android.view.Gravity;

import de.privacyguard.adhook.RootAccess;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Iterator;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Dia 23.11 data-management migration into the unified FX app. */
public final class FxDiaBackupActivity extends Activity {
    private static final int REQUEST_EXPORT = 7301;
    private static final int REQUEST_IMPORT = 7302;
    private static final int MAX_BACKUP_BYTES = 1024 * 1024;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private byte[] pendingBackup;
    private TextView status;
    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
    private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
    private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
    private static String sha(byte[] data)throws Exception{
        byte[] d=MessageDigest.getInstance("SHA-256").digest(data);StringBuilder s=new StringBuilder();
        for(byte b:d)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();
    }
    private JSONObject prefsJson(String name)throws Exception{
        SharedPreferences p=getSharedPreferences(name,MODE_PRIVATE);JSONObject out=new JSONObject();
        for(Map.Entry<String,?> e:p.getAll().entrySet()){
            Object v=e.getValue();
            if(v instanceof Set){JSONArray a=new JSONArray();for(Object x:(Set<?>)v)a.put(String.valueOf(x));out.put(e.getKey(),a);}
            else if(v instanceof String||v instanceof Boolean||v instanceof Number)out.put(e.getKey(),v);
        }
        return out;
    }
    private void restorePrefs(String name,JSONObject data)throws Exception{
        SharedPreferences.Editor edit=getSharedPreferences(name,MODE_PRIVATE).edit();edit.clear();
        Iterator<String> keys=data.keys();
        while(keys.hasNext()){
            String key=keys.next();Object value=data.get(key);
            if(value instanceof Boolean)edit.putBoolean(key,(Boolean)value);
            else if(value instanceof Integer)edit.putInt(key,(Integer)value);
            else if(value instanceof Number)edit.putLong(key,((Number)value).longValue());
            else if(value instanceof String)edit.putString(key,(String)value);
            else if(value instanceof JSONArray){
                java.util.HashSet<String> set=new java.util.HashSet<>();JSONArray a=(JSONArray)value;
                for(int i=0;i<a.length();i++)set.add(a.optString(i));edit.putStringSet(key,set);
            }
        }
        edit.apply();
    }
    private void root(String command,java.util.function.Consumer<RootAccess.Result> callback){
        worker.execute(()->{RootAccess.Result r=RootAccess.execute(command,90000L,MAX_BACKUP_BYTES);
            runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())callback.accept(r);});});
    }
    private String rootModuleCommand(){
        return "PG=/data/adb/privacyguard; test -s \\"$PG/settings.conf\\" || exit 20; "
                +"base64 \\"$PG/settings.conf\\" | tr -d '\\\\n'";
    }
    private JSONObject buildBackup(String configBase64)throws Exception{
        byte[] module=android.util.Base64.decode(configBase64,android.util.Base64.DEFAULT);
        if(module.length>MAX_BACKUP_BYTES/2)throw new IllegalStateException("模块配置超过本地备份大小上限。");
        JSONObject out=new JSONObject();out.put("schema","FX-DIA-BACKUP-1");out.put("created_at",System.currentTimeMillis());
        out.put("module_settings_b64",configBase64);out.put("module_settings_sha256",sha(module));
        JSONObject prefs=new JSONObject();
        prefs.put("MainActivity",prefsJson("MainActivity"));
        prefs.put("shield_prefs",prefsJson("shield_prefs"));
        prefs.put("stellar_command_whitelist",prefsJson("stellar_command_whitelist"));
        prefs.put("fx_hook_publish",prefsJson("fx_hook_publish"));
        out.put("preferences",prefs);
        return out;
    }
    private void exportBackup(){
        status.setText("正在读取 Root 配置和应用内规则…");
        root(rootModuleCommand(),r->{
            if(r.exitCode!=0){status.setText("导出失败："+safe(r.output));return;}
            try{
                JSONObject backup=buildBackup(r.output.trim());
                pendingBackup=backup.toString(2).getBytes(StandardCharsets.UTF_8);
                if(pendingBackup.length>MAX_BACKUP_BYTES)throw new IllegalStateException("备份文件超过 1 MiB 限制。");
                Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("application/json");
                String stamp=new SimpleDateFormat("yyyyMMdd-HHmmss",Locale.ROOT).format(new Date());
                intent.putExtra(Intent.EXTRA_TITLE,"FX-Dia-Backup-"+stamp+".json");
                startActivityForResult(intent,REQUEST_EXPORT);
            }catch(Exception e){status.setText("生成备份失败："+e.getMessage());}
        });
    }
    private void importBackup(){
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");startActivityForResult(intent,REQUEST_IMPORT);
    }
    private void restoreBackup(Uri uri){
        status.setText("正在读取并校验备份…");
        worker.execute(()->{
            try{
                ByteArrayOutputStream bytes=new ByteArrayOutputStream();
                try(InputStream in=getContentResolver().openInputStream(uri)){
                    if(in==null)throw new IllegalStateException("无法打开备份文件。");
                    byte[] buf=new byte[8192];int n;
                    while((n=in.read(buf))!=-1){bytes.write(buf,0,n);if(bytes.size()>MAX_BACKUP_BYTES)throw new IllegalStateException("备份大于 1 MiB，拒绝恢复。");}
                }
                JSONObject backup=new JSONObject(new String(bytes.toByteArray(),StandardCharsets.UTF_8));
                if(!"FX-DIA-BACKUP-1".equals(backup.optString("schema")))throw new IllegalArgumentException("备份版本不兼容。");
                String encoded=backup.getString("module_settings_b64");
                byte[] module=android.util.Base64.decode(encoded,android.util.Base64.DEFAULT);
                String expected=backup.getString("module_settings_sha256");
                if(!expected.equalsIgnoreCase(sha(module)))throw new IllegalArgumentException("模块配置 SHA-256 不匹配，文件可能已损坏。");
                java.io.File temp=new java.io.File(getCacheDir(),"fx-dia-settings.restore");
                try(OutputStream out=new java.io.FileOutputStream(temp)){out.write(module);out.flush();out.getFD().sync();}
                String path=temp.getAbsolutePath();
                String command="set -e; PG=/data/adb/privacyguard; CONF=$PG/settings.conf; "
                        +"test -d \\"$PG\\" && test -f \\"$CONF\\"; "
                        +"cp -p \\"$CONF\\" \\"$CONF.fx-dia-rollback\\"; "
                        +"cp "+quote(path)+" \\"$CONF.fx-dia-new\\"; chmod 0600 \\"$CONF.fx-dia-new\\"; "
                        +"actual=$(sha256sum \\"$CONF.fx-dia-new\\" | cut -d ' ' -f1); "
                        +"test \\"$actual\\" = "+quote(expected)+"; mv -f \\"$CONF.fx-dia-new\\" \\"$CONF\\"; "
                        +"if sh /data/adb/modules/privacyguard/scripts/apply.sh fast; then rm -f \\"$CONF.fx-dia-rollback\\"; "
                        +"else mv -f \\"$CONF.fx-dia-rollback\\" \\"$CONF\\"; sh /data/adb/modules/privacyguard/scripts/apply.sh fast >/dev/null 2>&1 || :; exit 31; fi";
                RootAccess.Result applied=RootAccess.execute(command,120000L,MAX_BACKUP_BYTES);
                if(applied.exitCode!=0)throw new IllegalStateException("模块配置恢复/应用失败："+safe(applied.output));
                JSONObject prefs=backup.getJSONObject("preferences");
                for(String name:new String[]{"MainActivity","shield_prefs","stellar_command_whitelist","fx_hook_publish"})
                    if(prefs.has(name))restorePrefs(name,prefs.getJSONObject(name));
                runOnUiThread(()->status.setText("恢复成功：FX 配置已校验、原子替换并重新应用；Hook、护盾和 Stellar 本地规则已恢复。"));
            }catch(Exception e){runOnUiThread(()->status.setText("恢复失败："+e.getMessage()));}
        });
    }
    private String safe(String s){return s==null||s.trim().isEmpty()?"Root 后端没有返回错误详情。":s.trim();}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);
        LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header=new LinearLayout(this);header.setPadding(dp(10),dp(6),dp(10),dp(6));
        header.addView(button("‹ 返回 Dia",this::finish));header.addView(text("Dia · 数据备份与恢复",18,0xff17212b,true),new LinearLayout.LayoutParams(0,-2,1));root.addView(header);
        ScrollView scroll=new ScrollView(this);LinearLayout body=new LinearLayout(this);body.setOrientation(1);body.setPadding(dp(8),dp(4),dp(8),dp(18));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
        body.addView(text("本地备份覆盖 FX settings.conf、Dia 已迁入的 Hook 目标规则、护盾白/黑名单、Stellar 授权记录和 Hook 发布状态。",13,0xff526170,false));
        body.addView(text("注意：模块配置包含 VPN 节点凭据、DNS 和过滤设置。请将备份保存在可信位置，不要公开分享。",12,0xffb45309,true));
        body.addView(button("导出本地 JSON 备份",this::exportBackup));
        body.addView(button("从 JSON 备份恢复",this::importBackup));
        status=text("尚未执行备份或恢复。",12,0xff526170,false);body.addView(status);
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(result!=RESULT_OK||data==null||data.getData()==null)return;
        if(request==REQUEST_EXPORT){
            Uri uri=data.getData();byte[] payload=pendingBackup;pendingBackup=null;
            worker.execute(()->{try(OutputStream out=getContentResolver().openOutputStream(uri,"w")){
                if(out==null)throw new IllegalStateException("无法写入所选文件。");out.write(payload);out.flush();
                runOnUiThread(()->status.setText("本地 JSON 备份已导出。"));
            }catch(Exception e){runOnUiThread(()->status.setText("导出失败："+e.getMessage()));}});
        }else if(request==REQUEST_IMPORT){
            new AlertDialog.Builder(this).setTitle("恢复 FX 备份")
                    .setMessage("恢复会替换设备当前模块 settings.conf，并覆盖 Hook、护盾和 Stellar 本地偏好设置。继续前会校验 SHA-256，并在应用失败时回滚模块配置。")
                    .setNegativeButton("取消",null).setPositiveButton("继续恢复",(d,w)->restoreBackup(data.getData())).show();
        }
    }
    @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
