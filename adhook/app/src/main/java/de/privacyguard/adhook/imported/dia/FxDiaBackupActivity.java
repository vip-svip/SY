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
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.Base64;
import java.util.Arrays;
import java.security.SecureRandom;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import android.widget.EditText;
import java.util.concurrent.Executors;

/** Dia 23.11 data-management migration into the unified FX app. */
public final class FxDiaBackupActivity extends Activity {
    private static final int REQUEST_EXPORT = 7301;
    private static final int REQUEST_IMPORT = 7302;
    private static final int MAX_BACKUP_BYTES = 1024 * 1024;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private byte[] pendingBackup;
    private TextView status;
    private EditText backupPassword;
    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private TextView text(String s,int size,int color,boolean bold){TextView v=new TextView(this);v.setText(s);v.setTextSize(size);v.setTextColor(color);if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);v.setPadding(dp(4),dp(5),dp(4),dp(5));return v;}
    private Button button(String s,Runnable r){Button b=new Button(this);b.setAllCaps(false);b.setText(s);b.setOnClickListener(v->r.run());return b;}
    private String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
    private static String sha(byte[] data)throws Exception{
        byte[] d=MessageDigest.getInstance("SHA-256").digest(data);StringBuilder s=new StringBuilder();
        for(byte b:d)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();
    }

    private static final String ENCRYPTED_BACKUP_SCHEMA = "FX-DIA-BACKUP-2-ENC";
    private static final String BACKUP_AAD = "FX-DIA-BACKUP-2-ENC";
    private static final int BACKUP_KDF_ITERATIONS = 210000;

    private static byte[] deriveBackupKey(String password, byte[] salt, int iterations)
            throws Exception {
        if (password == null || password.length() < 12)
            throw new IllegalArgumentException("备份加密密码至少需要 12 个字符。");
        if (iterations < 100000 || iterations > 500000)
            throw new IllegalArgumentException("备份 KDF 参数无效。");
        char[] chars = password.toCharArray();
        PBEKeySpec spec = new PBEKeySpec(chars, salt, iterations, 256);
        Arrays.fill(chars, (char) 0);
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).getEncoded();
        } finally {
            spec.clearPassword();
        }
    }

    private byte[] encryptBackupPayload(byte[] plaintext, String password) throws Exception {
        if (plaintext == null || plaintext.length == 0 || plaintext.length > MAX_BACKUP_BYTES)
            throw new IllegalArgumentException("待加密备份为空或超过 1 MiB。");
        if (password == null || password.length() < 12)
            throw new IllegalArgumentException("请设置至少 12 个字符的备份加密密码。");
        byte[] salt = new byte[16];
        byte[] nonce = new byte[12];
        SecureRandom random = new SecureRandom();
        random.nextBytes(salt);
        random.nextBytes(nonce);
        byte[] rawKey = deriveBackupKey(password, salt, BACKUP_KDF_ITERATIONS);
        byte[] ciphertext;
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(rawKey, "AES"),
                    new GCMParameterSpec(128, nonce));
            cipher.updateAAD(BACKUP_AAD.getBytes(StandardCharsets.UTF_8));
            ciphertext = cipher.doFinal(plaintext);
        } finally {
            Arrays.fill(rawKey, (byte) 0);
        }
        JSONObject envelope = new JSONObject();
        envelope.put("schema", ENCRYPTED_BACKUP_SCHEMA);
        envelope.put("kdf", "PBKDF2WithHmacSHA256");
        envelope.put("iterations", BACKUP_KDF_ITERATIONS);
        envelope.put("salt_b64", Base64.getEncoder().encodeToString(salt));
        envelope.put("nonce_b64", Base64.getEncoder().encodeToString(nonce));
        envelope.put("ciphertext_b64", Base64.getEncoder().encodeToString(ciphertext));
        envelope.put("ciphertext_sha256", sha(ciphertext));
        byte[] result = envelope.toString(2).getBytes(StandardCharsets.UTF_8);
        if (result.length > MAX_BACKUP_BYTES)
            throw new IllegalStateException("加密备份超过 1 MiB。");
        return result;
    }

    private byte[] decryptBackupPayload(byte[] payload, String password) throws Exception {
        if (payload == null || payload.length == 0 || payload.length > MAX_BACKUP_BYTES)
            throw new IllegalArgumentException("备份数据为空或超过 1 MiB。");
        JSONObject envelope = new JSONObject(new String(payload, StandardCharsets.UTF_8));
        String schema = envelope.optString("schema", "");
        if ("FX-DIA-BACKUP-1".equals(schema)) return payload;
        if (!ENCRYPTED_BACKUP_SCHEMA.equals(schema))
            throw new IllegalArgumentException("备份版本不兼容。");
        if (!"PBKDF2WithHmacSHA256".equals(envelope.optString("kdf", "")))
            throw new IllegalArgumentException("备份密钥派生算法不受支持。");
        if (password == null || password.length() < 12)
            throw new IllegalArgumentException("请输入创建此加密备份时使用的密码（至少 12 个字符）。");
        int iterations = envelope.getInt("iterations");
        if (iterations < 100000 || iterations > 500000)
            throw new IllegalArgumentException("备份 KDF 参数超出允许范围。");
        byte[] salt = Base64.getDecoder().decode(envelope.getString("salt_b64"));
        byte[] nonce = Base64.getDecoder().decode(envelope.getString("nonce_b64"));
        byte[] ciphertext = Base64.getDecoder().decode(envelope.getString("ciphertext_b64"));
        if (salt.length != 16 || nonce.length != 12 || ciphertext.length < 16)
            throw new IllegalArgumentException("备份加密参数无效或数据不完整。");
        String expected = envelope.getString("ciphertext_sha256");
        if (!expected.equalsIgnoreCase(sha(ciphertext)))
            throw new IllegalArgumentException("加密备份 SHA-256 不匹配，文件可能已损坏。");
        byte[] rawKey = deriveBackupKey(password, salt, iterations);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(rawKey, "AES"),
                    new GCMParameterSpec(128, nonce));
            cipher.updateAAD(BACKUP_AAD.getBytes(StandardCharsets.UTF_8));
            return cipher.doFinal(ciphertext);
        } catch (javax.crypto.AEADBadTagException wrongPassword) {
            throw new IllegalArgumentException("备份密码错误或加密内容已被篡改。", wrongPassword);
        } finally {
            Arrays.fill(rawKey, (byte) 0);
        }
    }

    private String enteredBackupPassword() {
        return backupPassword == null || backupPassword.getText() == null
                ? "" : backupPassword.getText().toString();
    }

    private String requireExportPassword() {
        String value = enteredBackupPassword();
        if (value.length() < 12) {
            status.setText("请先设置至少 12 个字符的备份加密密码。密码仅用于本次加密，不会保存在 FX 设置中。");
            return null;
        }
        return value;
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
        private String rootStellarFilesCommand(){
        return "DIR=/data/local/tmp/stellar_guard; mkdir -p \\"$DIR\\"; "
                +"for f in command_whitelist.txt command_always_allow.txt scope_grants.txt; do "
                +"touch \\"$DIR/$f\\"; chmod 0600 \\"$DIR/$f\\"; "
                +"printf 'STELLARFILE|%s|' \\"$f\\"; base64 \\"$DIR/$f\\" | tr -d '\\\\n'; printf '\\n'; done";
    }
    private JSONObject buildBackup(String configBase64,String stellarDump)throws Exception{
        byte[] module=android.util.Base64.decode(configBase64,android.util.Base64.DEFAULT);
        if(module.length>MAX_BACKUP_BYTES/2)throw new IllegalStateException("模块配置超过本地备份大小上限。");
        JSONObject out=new JSONObject();out.put("schema","FX-DIA-BACKUP-1");out.put("created_at",System.currentTimeMillis());
        out.put("module_settings_b64",configBase64);out.put("module_settings_sha256",sha(module));
        JSONObject stellarFiles=new JSONObject(),stellarHashes=new JSONObject();
        for(String line:(stellarDump==null?"":stellarDump).split("\\r?\\n")){
            if(!line.startsWith("STELLARFILE|"))continue;
            String[] parts=line.split("\\\\|",3);
            if(parts.length!=3)continue;
            String name=parts[1];
            if(!name.equals("command_whitelist.txt")&&!name.equals("command_always_allow.txt")&&!name.equals("scope_grants.txt"))continue;
            byte[] data=android.util.Base64.decode(parts[2],android.util.Base64.DEFAULT);
            stellarFiles.put(name,parts[2]);stellarHashes.put(name,sha(data));
        }
        out.put("stellar_files_b64",stellarFiles);out.put("stellar_files_sha256",stellarHashes);
        JSONObject prefs=new JSONObject();
        prefs.put("MainActivity",prefsJson("MainActivity"));
        prefs.put("fx_dia_frida",prefsJson("fx_dia_frida"));
        prefs.put("shield_prefs",prefsJson("shield_prefs"));
        prefs.put("stellar_command_whitelist",prefsJson("stellar_command_whitelist"));
        prefs.put("fx_hook_publish",prefsJson("fx_hook_publish"));
        prefs.put("fx_dia_launcher_hidden",prefsJson("fx_dia_launcher_hidden"));
        out.put("preferences",prefs);
        return out;
    }
    private void exportBackup(){
        String encryptionPassword = requireExportPassword();
        if (encryptionPassword == null) return;
        status.setText("正在读取 Root 配置并创建 AES-256-GCM 加密备份…");
        worker.execute(()->{
            try{
                RootAccess.Result config=RootAccess.execute(rootModuleCommand(),30000L,MAX_BACKUP_BYTES);
                if(config.exitCode!=0)throw new IllegalStateException("读取 FX 配置失败："+safe(config.output));
                RootAccess.Result stellar=RootAccess.execute(rootStellarFilesCommand(),30000L,MAX_BACKUP_BYTES);
                if(stellar.exitCode!=0)throw new IllegalStateException("读取 Stellar 授权文件失败："+safe(stellar.output));
                JSONObject backup=buildBackup(config.output.trim(),stellar.output);
                byte[] plaintext=backup.toString(2).getBytes(StandardCharsets.UTF_8);
                byte[] payload=encryptBackupPayload(plaintext,encryptionPassword);
                runOnUiThread(()->{
                    pendingBackup=payload;
                    Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("application/json");
                    String stamp=new SimpleDateFormat("yyyyMMdd-HHmmss",Locale.ROOT).format(new Date());
                    intent.putExtra(Intent.EXTRA_TITLE,"FX-Dia-Backup-"+stamp+".json");
                    startActivityForResult(intent,REQUEST_EXPORT);
                });
            }catch(Exception e){runOnUiThread(()->status.setText("生成备份失败："+e.getMessage()));}
        });
    }
    private void importBackup(){
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");startActivityForResult(intent,REQUEST_IMPORT);
    }
    private void restoreBackup(Uri uri, String encryptionPassword){
        status.setText("正在读取并校验备份…");
        worker.execute(()->{
            try{
                ByteArrayOutputStream bytes=new ByteArrayOutputStream();
                try(InputStream in=getContentResolver().openInputStream(uri)){
                    if(in==null)throw new IllegalStateException("无法打开备份文件。");
                    byte[] buf=new byte[8192];int n;
                    while((n=in.read(buf))!=-1){bytes.write(buf,0,n);if(bytes.size()>MAX_BACKUP_BYTES)throw new IllegalStateException("备份大于 1 MiB，拒绝恢复。");}
                }
                restoreBackupBytes(bytes.toByteArray(), encryptionPassword);
                runOnUiThread(()->status.setText("恢复成功：配置、Hook、护盾和 Stellar 记录已恢复。"));
            }catch(Exception e){runOnUiThread(()->status.setText("恢复失败："+e.getMessage()));}
        });
    }

    private byte[] createBackupPayload(String encryptionPassword) throws Exception {
        RootAccess.Result r=RootAccess.execute(rootModuleCommand(),30000L,MAX_BACKUP_BYTES);
        if(r.exitCode!=0)throw new IllegalStateException("读取模块配置失败："+safe(r.output));
        RootAccess.Result stellar=RootAccess.execute(rootStellarFilesCommand(),30000L,MAX_BACKUP_BYTES);
        if(stellar.exitCode!=0)throw new IllegalStateException("读取 Stellar 授权文件失败："+safe(stellar.output));
        JSONObject backup=buildBackup(r.output.trim(),stellar.output);
        byte[] plaintext=backup.toString(2).getBytes(StandardCharsets.UTF_8);
        return encryptBackupPayload(plaintext,encryptionPassword);
    }

    private java.util.Map<String, java.io.File> stageAndValidateStellarFiles(JSONObject backup) throws Exception {
        java.util.LinkedHashMap<String, java.io.File> staged = new java.util.LinkedHashMap<>();
        if (!backup.has("stellar_files_b64")) return staged;

        JSONObject files = backup.getJSONObject("stellar_files_b64");
        JSONObject hashes = backup.optJSONObject("stellar_files_sha256");
        String[] names = {"command_whitelist.txt", "command_always_allow.txt", "scope_grants.txt"};
        java.util.HashSet<String> allowed = new java.util.HashSet<>(Arrays.asList(names));
        Iterator<String> fileKeys = files.keys();
        while (fileKeys.hasNext()) {
            String key = fileKeys.next();
            if (!allowed.contains(key)) {
                throw new IllegalArgumentException("备份包含未知 Stellar 文件：" + key);
            }
        }
        if (files.length() > 0 && hashes == null) {
            throw new IllegalArgumentException("备份缺少 Stellar 文件 SHA-256 清单。");
        }
        if (hashes != null) {
            Iterator<String> hashKeys = hashes.keys();
            while (hashKeys.hasNext()) {
                String key = hashKeys.next();
                if (!allowed.contains(key) || !files.has(key)) {
                    throw new IllegalArgumentException("Stellar SHA-256 清单与文件清单不匹配：" + key);
                }
            }
        }

        java.util.LinkedHashMap<String, byte[]> validated = new java.util.LinkedHashMap<>();
        long totalBytes = 0;
        for (String name : names) {
            if (!files.has(name)) continue;
            Object raw = files.get(name);
            if (!(raw instanceof String)) {
                throw new IllegalArgumentException("Stellar 文件编码格式无效：" + name);
            }
            String encoded = (String) raw;
            if (encoded.length() > (MAX_BACKUP_BYTES * 4L / 3L) + 8L) {
                throw new IllegalArgumentException("Stellar 文件编码超过备份上限：" + name);
            }
            byte[] data = Base64.getDecoder().decode(encoded);
            totalBytes += data.length;
            if (totalBytes > MAX_BACKUP_BYTES) {
                throw new IllegalArgumentException("Stellar 文件总大小超过备份上限。");
            }
            String expected = hashes.optString(name, "");
            if (!expected.matches("(?i)[0-9a-f]{64}") || !expected.equalsIgnoreCase(sha(data))) {
                throw new IllegalArgumentException("Stellar 授权文件 SHA-256 不匹配：" + name);
            }
            validated.put(name, data);
        }

        // Do not leave a partial set of sensitive staged files if cache I/O fails.
        try {
            for (Map.Entry<String, byte[]> entry : validated.entrySet()) {
                java.io.File cache = java.io.File.createTempFile(
                        "fx-dia-restore-", ".tmp", getCacheDir());
                staged.put(entry.getKey(), cache);
                try (OutputStream out = new java.io.FileOutputStream(cache, false)) {
                    out.write(entry.getValue());
                    out.flush();
                    out.getFD().sync();
                }
            }
            return staged;
        } catch (Exception error) {
            for (java.io.File cache : staged.values()) {
                //noinspection ResultOfMethodCallIgnored
                cache.delete();
            }
            throw error;
        }
    }

    private void validateBackupPreferences(JSONObject preferences) throws Exception {
        String[] names = {"MainActivity", "fx_dia_frida", "shield_prefs",
                "stellar_command_whitelist", "fx_hook_publish", "fx_dia_launcher_hidden"};
        for (String name : names) {
            if (!preferences.has(name)) continue;
            JSONObject values = preferences.getJSONObject(name);
            Iterator<String> keys = values.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                Object value = values.get(key);
                if (value instanceof JSONArray) {
                    JSONArray items = (JSONArray) value;
                    for (int i = 0; i < items.length(); i++) {
                        if (!(items.get(i) instanceof String)) {
                            throw new IllegalArgumentException("偏好设置字符串集合包含非字符串项：" + name + "/" + key);
                        }
                    }
                } else if (!(value instanceof String || value instanceof Boolean || value instanceof Number)) {
                    throw new IllegalArgumentException("偏好设置值类型不受支持：" + name + "/" + key);
                }
            }
        }
    }

    private String buildTransactionalRestoreCommand(java.io.File moduleFile, String moduleHash,
            java.util.Map<String, java.io.File> stellarFiles, JSONObject stellarHashes) throws Exception {
        final String[] names = {"command_whitelist.txt", "command_always_allow.txt", "scope_grants.txt"};
        StringBuilder command = new StringBuilder();
        command.append("set -e; PG=/data/adb/privacyguard; DIR=/data/local/tmp/stellar_guard; ")
                .append("CONF=\\\"$PG/settings.conf\\\"; TXN=\\\"$PG/.fx-dia-restore.$$\\\"; ")
                .append("STXN=\\\"$DIR/.fx-dia-restore.$$\\\"; ")
                .append("_fx_mutating=0; _fx_committed=0; _fx_config_swapped=0; _fx_recovery_failed=0; ")
                .append("rollback(){ _fx_rc=$?; ")
                .append("if [ \\\"$_fx_committed\\\" -ne 1 ] && [ \\\"$_fx_mutating\\\" -eq 1 ]; then ")
                .append("if [ -f \\\"$TXN/settings.old\\\" ]; then mv -f \\\"$TXN/settings.old\\\" \\\"$CONF\\\" || _fx_recovery_failed=1; ")
                .append("else _fx_recovery_failed=1; fi; ");
        for (String name : names) {
            if (!stellarFiles.containsKey(name)) continue;
            command.append("if [ -f \\\"$STXN/").append(name).append(".existed\\\" ]; then ")
                    .append("if [ -f \\\"$STXN/").append(name).append(".old\\\" ]; then ")
                    .append("mv -f \\\"$STXN/").append(name).append(".old\\\" \\\"$DIR/")
                    .append(name).append("\\\" || _fx_recovery_failed=1; ")
                    .append("else _fx_recovery_failed=1; fi; ")
                    .append("else rm -f \\\"$DIR/").append(name).append("\\\" || _fx_recovery_failed=1; fi; ");
        }
        command.append("if [ \\\"$_fx_config_swapped\\\" -eq 1 ]; then ")
                .append("sh /data/adb/modules/privacyguard/scripts/apply.sh fast >/dev/null 2>&1 || _fx_recovery_failed=1; ")
                .append("fi; fi; rm -rf \\\"$TXN\\\" \\\"$STXN\\\"; ")
                .append("if [ \\\"$_fx_recovery_failed\\\" -ne 0 ]; then ")
                .append("echo FX_DIA_RESTORE_ROLLBACK_FAILED; exit 90; fi; exit \\\"$_fx_rc\\\"; }; ")
                .append("trap rollback EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; ")
                .append("mkdir -p \\\"$DIR\\\"; [ ! -L \\\"$DIR\\\" ] || exit 40; ")
                .append("[ -d \\\"$PG\\\" ] && [ ! -L \\\"$PG\\\" ] || exit 41; ")
                .append("[ -f \\\"$CONF\\\" ] && [ ! -L \\\"$CONF\\\" ] || exit 42; ")
                .append("mkdir \\\"$TXN\\\"; mkdir \\\"$STXN\\\"; ")
                .append("cp -p \\\"$CONF\\\" \\\"$TXN/settings.old\\\"; ")
                .append("cp ").append(quote(moduleFile.getAbsolutePath()))
                .append(" \\\"$TXN/settings.new\\\"; chmod 0600 \\\"$TXN/settings.new\\\"; ")
                .append("actual=$(sha256sum \\\"$TXN/settings.new\\\" | cut -d ' ' -f1); test \\\"$actual\\\" = ")
                .append(quote(moduleHash)).append("; ");
        for (String name : names) {
            java.io.File cache = stellarFiles.get(name);
            if (cache == null) continue;
            String target = "/data/local/tmp/stellar_guard/" + name;
            String expected = stellarHashes.getString(name);
            command.append("if [ -e ").append(quote(target)).append(" ] || [ -L ").append(quote(target)).append(" ]; then ")
                    .append("[ -f ").append(quote(target)).append(" ] && [ ! -L ").append(quote(target)).append(" ] || exit 43; ")
                    .append("cp -p ").append(quote(target)).append(" \\\"$STXN/").append(name).append(".old\\\"; ")
                    .append(": > \\\"$STXN/").append(name).append(".existed\\\"; fi; ")
                    .append("cp ").append(quote(cache.getAbsolutePath())).append(" \\\"$STXN/")
                    .append(name).append(".new\\\"; chmod 0600 \\\"$STXN/").append(name).append(".new\\\"; ")
                    .append("actual=$(sha256sum \\\"$STXN/").append(name)
                    .append(".new\\\" | cut -d ' ' -f1); test \\\"$actual\\\" = ")
                    .append(quote(expected)).append("; ");
        }
        command.append("_fx_mutating=1; mv -f \\\"$TXN/settings.new\\\" \\\"$CONF\\\"; ")
                .append("_fx_config_swapped=1; ");
        for (String name : names) {
            if (stellarFiles.containsKey(name)) {
                command.append("mv -f \\\"$STXN/").append(name).append(".new\\\" \\\"$DIR/")
                        .append(name).append("\\\"; ");
            }
        }
        command.append("if sh /data/adb/modules/privacyguard/scripts/apply.sh fast; then :; else exit 31; fi; ")
                .append("_fx_committed=1; trap - EXIT HUP INT TERM; ")
                .append("rm -rf \\\"$TXN\\\" \\\"$STXN\\\" || :; echo FX_DIA_RESTORE_COMMITTED");
        return command.toString();
    }

    private void restoreBackupBytes(byte[] payload, String encryptionPassword) throws Exception {
        payload = decryptBackupPayload(payload, encryptionPassword);
        JSONObject backup = new JSONObject(new String(payload, StandardCharsets.UTF_8));
        if (!"FX-DIA-BACKUP-1".equals(backup.optString("schema"))) {
            throw new IllegalArgumentException("备份版本不兼容。");
        }

        // Validate the complete backup and snapshot app preferences before any write.
        String encoded = backup.getString("module_settings_b64");
        if (encoded.length() > (MAX_BACKUP_BYTES * 2L / 3L) + 8L) {
            throw new IllegalArgumentException("模块配置编码超过备份上限。");
        }
        byte[] module = android.util.Base64.decode(encoded, android.util.Base64.DEFAULT);
        if (module.length > MAX_BACKUP_BYTES / 2) {
            throw new IllegalArgumentException("模块配置超过本地备份大小上限。");
        }
        String expected = backup.getString("module_settings_sha256");
        if (!expected.matches("(?i)[0-9a-f]{64}") || !expected.equalsIgnoreCase(sha(module))) {
            throw new IllegalArgumentException("模块配置 SHA-256 不匹配，文件可能已损坏。");
        }
        JSONObject prefs = backup.getJSONObject("preferences");
        validateBackupPreferences(prefs);
        String[] preferenceNames = {"MainActivity", "fx_dia_frida", "shield_prefs",
                "stellar_command_whitelist", "fx_hook_publish", "fx_dia_launcher_hidden"};
        JSONObject previousPreferences = new JSONObject();
        for (String name : preferenceNames) previousPreferences.put(name, prefsJson(name));
        java.util.Map<String, java.io.File> stagedStellar = stageAndValidateStellarFiles(backup);

        java.io.File moduleTemp = new java.io.File(getCacheDir(), "fx-dia-settings.restore");
        boolean preferencesMayHaveChanged = false;
        try {
            try (OutputStream out = new java.io.FileOutputStream(moduleTemp, false)) {
                out.write(module);
                out.flush();
                out.getFD().sync();
            }

            // Apply preferences first so that a failed Root transaction can restore them.
            preferencesMayHaveChanged = true;
            for (String name : preferenceNames) {
                if (prefs.has(name)) restorePrefs(name, prefs.getJSONObject(name));
            }

            String restoreCommand = buildTransactionalRestoreCommand(
                    moduleTemp, expected, stagedStellar, backup.optJSONObject("stellar_files_sha256"));
            RootAccess.Result applied = RootAccess.execute(restoreCommand, 120000L, MAX_BACKUP_BYTES);
            if (applied.exitCode != 0) {
                throw new IllegalStateException("配置恢复事务失败：" + safe(applied.output));
            }
        } catch (Exception error) {
            if (preferencesMayHaveChanged) {
                for (String name : preferenceNames) {
                    try {
                        restorePrefs(name, previousPreferences.getJSONObject(name));
                    } catch (Exception rollbackError) {
                        error.addSuppressed(rollbackError);
                    }
                }
            }
            throw error;
        } finally {
            //noinspection ResultOfMethodCallIgnored
            moduleTemp.delete();
            for (java.io.File staged : stagedStellar.values()) {
                //noinspection ResultOfMethodCallIgnored
                staged.delete();
            }
        }
    }

    private String githubContentsUrl(String owner,String repo,String path) throws Exception {
        StringBuilder encoded=new StringBuilder();
        String[] parts=path.split("/");
        for(String part:parts){if(encoded.length()>0)encoded.append('/');encoded.append(URLEncoder.encode(part,"UTF-8").replace("+","%20"));}
        return "https://api.github.com/repos/"+owner+"/"+repo+"/contents/"+encoded;
    }

    private JSONObject githubRequest(String url,String token,String method,JSONObject body) throws Exception {
        HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();
        c.setRequestMethod(method);c.setConnectTimeout(15000);c.setReadTimeout(25000);
        c.setRequestProperty("Accept","application/vnd.github+json");
        c.setRequestProperty("X-GitHub-Api-Version","2022-11-28");
        c.setRequestProperty("Authorization","Bearer "+token);
        if(body!=null){
            c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");
            try(OutputStream out=c.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}
        }
        int code=c.getResponseCode();
        InputStream stream=code>=200&&code<300?c.getInputStream():c.getErrorStream();
        byte[] data=new byte[0];
        if(stream!=null)try(InputStream in=stream){ByteArrayOutputStream b=new ByteArrayOutputStream();byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){b.write(buf,0,n);if(b.size()>MAX_BACKUP_BYTES)throw new IllegalStateException("GitHub 响应超过 1 MiB。");}data=b.toByteArray();}
        c.disconnect();
        if(code<200||code>=300)throw new IllegalStateException("GitHub API HTTP "+code+"："+new String(data,StandardCharsets.UTF_8));
        return data.length==0?new JSONObject():new JSONObject(new String(data,StandardCharsets.UTF_8));
    }

    private void githubUpload(String owner,String repo,String path,String branch,String token,String encryptionPassword){
        status.setText("正在创建 AES-256-GCM 加密备份并上传 GitHub…");
        worker.execute(()->{
            try{
                byte[] payload=createBackupPayload(encryptionPassword);
                String url=githubContentsUrl(owner,repo,path);
                JSONObject prior=null;String sha=null;
                try{prior=githubRequest(url,token,"GET",null);sha=prior.optString("sha",null);}
                catch(Exception notFound){if(notFound.getMessage()==null||!notFound.getMessage().contains("HTTP 404"))throw notFound;}
                JSONObject body=new JSONObject();
                body.put("message","FX Dia configuration backup");
                body.put("content",Base64.getEncoder().encodeToString(payload));
                body.put("branch",branch);
                if(sha!=null&&!sha.isEmpty())body.put("sha",sha);
                githubRequest(url,token,"PUT",body);
                runOnUiThread(()->status.setText("GitHub 备份上传成功："+owner+"/"+repo+"/"+path));
            }catch(Exception e){runOnUiThread(()->status.setText("GitHub 上传失败："+e.getMessage()));}
        });
    }

    private void githubDownload(String owner,String repo,String path,String token,String encryptionPassword){
        status.setText("正在从 GitHub 下载备份…");
        worker.execute(()->{
            try{
                JSONObject response=githubRequest(githubContentsUrl(owner,repo,path),token,"GET",null);
                String content=response.optString("content","").replace("\\n","");
                byte[] payload=Base64.getMimeDecoder().decode(content);
                restoreBackupBytes(payload,encryptionPassword);
                runOnUiThread(()->status.setText("GitHub 备份恢复成功；SHA-256 已校验并完成模块重新应用。"));
            }catch(Exception e){runOnUiThread(()->status.setText("GitHub 下载/恢复失败："+e.getMessage()));}
        });
    }

    private HttpURLConnection webdavConnection(String url,String username,String password,String method) throws Exception {
        if(url==null||!url.startsWith("https://"))throw new IllegalArgumentException("WebDAV 必须使用 HTTPS。");
        HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();
        c.setRequestMethod(method);c.setConnectTimeout(15000);c.setReadTimeout(25000);
        String auth=Base64.getEncoder().encodeToString((username+":"+password).getBytes(StandardCharsets.UTF_8));
        c.setRequestProperty("Authorization","Basic "+auth);
        return c;
    }

    private void webdavUpload(String url,String username,String password,String encryptionPassword){
        status.setText("正在上传 AES-256-GCM 加密 WebDAV 备份…");
        worker.execute(()->{
            try{
                byte[] payload=createBackupPayload(encryptionPassword);
                HttpURLConnection c=webdavConnection(url,username,password,"PUT");
                c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");
                try(OutputStream out=c.getOutputStream()){out.write(payload);}
                int code=c.getResponseCode();c.disconnect();
                if(code<200||code>=300)throw new IllegalStateException("WebDAV PUT HTTP "+code);
                runOnUiThread(()->status.setText("WebDAV 备份上传成功。"));
            }catch(Exception e){runOnUiThread(()->status.setText("WebDAV 上传失败："+e.getMessage()));}
        });
    }

    private void webdavDownload(String url,String username,String password,String encryptionPassword){
        status.setText("正在从 WebDAV 下载备份…");
        worker.execute(()->{
            try{
                HttpURLConnection c=webdavConnection(url,username,password,"GET");
                int code=c.getResponseCode();
                if(code<200||code>=300){c.disconnect();throw new IllegalStateException("WebDAV GET HTTP "+code);}
                ByteArrayOutputStream b=new ByteArrayOutputStream();
                try(InputStream in=c.getInputStream()){byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){b.write(buf,0,n);if(b.size()>MAX_BACKUP_BYTES)throw new IllegalStateException("备份大于 1 MiB。");}}
                c.disconnect();restoreBackupBytes(b.toByteArray(),encryptionPassword);
                runOnUiThread(()->status.setText("WebDAV 备份恢复成功；SHA-256 已校验并完成模块重新应用。"));
            }catch(Exception e){runOnUiThread(()->status.setText("WebDAV 下载/恢复失败："+e.getMessage()));}
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
        backupPassword=new EditText(this);
        backupPassword.setSingleLine(true);
        backupPassword.setHint("备份加密密码（至少 12 个字符；请自行保管）");
        backupPassword.setInputType(129);
        body.addView(text("备份加密",14,0xff17212b,true));
        body.addView(backupPassword);
        body.addView(text("新备份使用 PBKDF2-HMAC-SHA256 + AES-256-GCM；密码不会保存。旧版 FX-DIA-BACKUP-1 明文备份仍可导入。",12,0xff8a5b20,false));
        body.addView(button("导出本地加密 JSON 备份",this::exportBackup));
        body.addView(button("从 JSON 备份恢复",this::importBackup));
        EditText ghOwner=new EditText(this);ghOwner.setSingleLine(true);ghOwner.setHint("GitHub 仓库 Owner");
        EditText ghRepo=new EditText(this);ghRepo.setSingleLine(true);ghRepo.setHint("GitHub 仓库名");
        EditText ghPath=new EditText(this);ghPath.setSingleLine(true);ghPath.setText("backups/fx-dia-backup.json");
        EditText ghBranch=new EditText(this);ghBranch.setSingleLine(true);ghBranch.setText("main");
        EditText ghToken=new EditText(this);ghToken.setSingleLine(true);ghToken.setHint("Fine-grained Token（Contents: Read/Write）");ghToken.setInputType(129);
        body.addView(text("GitHub Contents 远程备份",14,0xff17212b,true));
        body.addView(ghOwner);body.addView(ghRepo);body.addView(ghPath);body.addView(ghBranch);body.addView(ghToken);
        body.addView(button("上传到 GitHub",()->{
            String o=ghOwner.getText().toString().trim(),r=ghRepo.getText().toString().trim(),p=ghPath.getText().toString().trim(),b=ghBranch.getText().toString().trim(),t=ghToken.getText().toString().trim();
            if(o.isEmpty()||r.isEmpty()||p.isEmpty()||t.isEmpty()){status.setText("请填写完整 GitHub 仓库和 Token。");return;}
            String encryptionPassword = requireExportPassword();
            if (encryptionPassword == null) return;
            githubUpload(o,r,p,b.isEmpty()?"main":b,t,encryptionPassword);
        }));
        body.addView(button("从 GitHub 恢复",()->{
            String o=ghOwner.getText().toString().trim(),r=ghRepo.getText().toString().trim(),p=ghPath.getText().toString().trim(),t=ghToken.getText().toString().trim();
            if(o.isEmpty()||r.isEmpty()||p.isEmpty()||t.isEmpty()){status.setText("请填写完整 GitHub 仓库和 Token。");return;}
            new AlertDialog.Builder(this).setTitle("确认 GitHub 恢复").setMessage("将解密并覆盖本机 FX 模块配置与迁入的 Hook/护盾偏好设置。请在上方填写备份密码；旧版未加密备份不需要密码。")
                .setNegativeButton("取消",null).setPositiveButton("恢复",(d,w)->githubDownload(o,r,p,t,enteredBackupPassword())).show();
        }));
        EditText davUrl=new EditText(this);davUrl.setSingleLine(true);davUrl.setHint("https://dav.example.com/path/fx-dia-backup.json");
        EditText davUser=new EditText(this);davUser.setSingleLine(true);davUser.setHint("WebDAV 用户名");
        EditText davPass=new EditText(this);davPass.setSingleLine(true);davPass.setHint("WebDAV 应用密码");davPass.setInputType(129);
        body.addView(text("WebDAV 远程备份",14,0xff17212b,true));
        body.addView(davUrl);body.addView(davUser);body.addView(davPass);
        body.addView(button("上传到 WebDAV",()->{
            String u=davUrl.getText().toString().trim(),n=davUser.getText().toString(),p=davPass.getText().toString();
            if(u.isEmpty()){status.setText("请填写 WebDAV HTTPS 文件地址。");return;}
            String encryptionPassword = requireExportPassword();
            if (encryptionPassword == null) return;
            webdavUpload(u,n,p,encryptionPassword);
        }));
        body.addView(button("从 WebDAV 恢复",()->{
            String u=davUrl.getText().toString().trim(),n=davUser.getText().toString(),p=davPass.getText().toString();
            if(u.isEmpty()){status.setText("请填写 WebDAV HTTPS 文件地址。");return;}
            new AlertDialog.Builder(this).setTitle("确认 WebDAV 恢复").setMessage("将解密并覆盖本机 FX 模块配置与迁入的 Hook/护盾偏好设置。请在上方填写备份密码；旧版未加密备份不需要密码。")
                .setNegativeButton("取消",null).setPositiveButton("恢复",(d,w)->webdavDownload(u,n,p,enteredBackupPassword())).show();
        }));
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
                    .setMessage("恢复会解密并替换设备当前模块 settings.conf，以及 Hook、护盾和 Stellar 本地偏好设置。新备份需要上方密码；旧版未加密备份无需密码。SHA-256/GCM 完整性校验失败时拒绝恢复。")
                    .setNegativeButton("取消",null).setPositiveButton("继续恢复",(d,w)->restoreBackup(data.getData(),enteredBackupPassword())).show();
        }
    }
    @Override protected void onDestroy(){worker.shutdownNow();super.onDestroy();}
}
