package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.PowerManager;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Yulong AdBlock 7.0.1 general settings and transactional filter backup/restore. */
public final class FxYulongAdGeneralActivity extends Activity {
    private static final int IMPORT_REQUEST = 7811;
    private static final int EXPORT_REQUEST = 7812;
    private static final int MAX_BACKUP_BYTES = 1024 * 1024;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextView batteryStatus, operationStatus;
    private String pendingExport;

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label); b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout body, String title, String detail, View... children) {
        LinearLayout p = new LinearLayout(this); p.setOrientation(1);
        p.setPadding(dp(14), dp(9), dp(14), dp(9)); p.setBackgroundColor(0xfff0f3f7);
        p.addView(text(title, 15, 0xff17212b, true)); p.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) p.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); body.addView(p, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("游龙广告插件 7.0.1 · 通用设置", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        batteryStatus = text("正在读取系统省电策略…", 12, 0xff526170, false);
        card(body, "后台运行与电池优化",
                "只打开 Android 系统设置由用户自行决定是否豁免电池优化。FX 不会静默修改系统省电策略。",
                batteryStatus, button("打开电池优化设置", this::openBatterySettings));

        operationStatus = text("尚未执行导入或导出。", 12, 0xff526170, false);
        card(body, "过滤设置备份",
                "导出/导入范围：广告过滤总开关、订阅来源、域名白/黑名单、DNS 策略与服务器、每周过滤计划。导入前会备份 settings.conf 与 schedule 文件；失败会恢复原文件并重新应用。",
                button("导出过滤设置 JSON", this::exportSettings),
                button("从 JSON 导入设置", this::pickImport),
                operationStatus);

        card(body, "页面快捷入口", "这些功能仍保留在游龙广告插件自己的四级页面中。",
                button("过滤列表", () -> openPage("过滤列表")),
                button("DNS 设置", () -> openPage("DNS 设置")),
                button("域名白/黑名单", () -> openPage("域名名单")),
                button("计划任务", () -> openPage("计划任务")),
                button("VPN 与 Root Proxy", () -> openPage("VPN 与 Root Proxy")));

        card(body, "界面、主题与语言",
                "FX 已合并为单一原生应用，界面主题、语言和强调色属于 FX 应用级偏好；不会再创建第二套游龙 Activity 主题配置。");
        card(body, "关于",
                "原始功能来源：游龙广告插件 7.0.1。\n"
                        + "当前宿主：FX 1.0.0 / FX Hook。\n"
                        + "网络架构：FX 单一 VPN/TUN + Root DNS Proxy 回退；不安装游龙原版第二个 VpnService。\n"
                        + "配置和备份仅保存在本机，导入导出由用户通过 Android 文件选择器授权。");
        refreshBatteryStatus();
    }

    private void openPage(String page) {
        startActivity(new Intent(this, FxYulongAdActivity.class).putExtra("suite_page", page));
    }

    private void refreshBatteryStatus() {
        try {
            PowerManager pm = (PowerManager)getSystemService(POWER_SERVICE);
            boolean ignored = pm != null && pm.isIgnoringBatteryOptimizations(getPackageName());
            batteryStatus.setText(ignored
                    ? "FX 当前已被系统豁免电池优化。"
                    : "FX 当前未被系统豁免电池优化；后台调度可能受系统限制。");
        } catch (Throwable error) {
            batteryStatus.setText("无法读取系统电池优化状态：" + error.getClass().getSimpleName());
        }
    }

    private void openBatterySettings() {
        try {
            startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
        } catch (Throwable error) {
            try { startActivity(new Intent(Settings.ACTION_SETTINGS)); }
            catch (Throwable ignored) { batteryStatus.setText("无法打开系统设置。"); }
        }
    }

    private String rootCommand(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-ad-control.sh\" " + args;
    }

    private RootAccess.Result root(String args) {
        return RootAccess.execute(rootCommand(args), 60000L, 1024 * 1024);
    }

    private JSONObject exportSnapshot() throws Exception {
        RootAccess.Result list = root("list");
        if (list.exitCode != 0) throw new IllegalStateException("读取过滤列表失败：" + safe(list.output));
        RootAccess.Result dns = root("dns-config-get");
        if (dns.exitCode != 0) throw new IllegalStateException("读取 DNS 配置失败：" + safe(dns.output));
        RootAccess.Result schedule = root("schedule-get");
        if (schedule.exitCode != 0) throw new IllegalStateException("读取过滤计划失败：" + safe(schedule.output));

        JSONObject out = new JSONObject();
        out.put("schema", "FX_YULONG_AD_SETTINGS_V1");
        out.put("sourceVersion", "7.0.1");
        out.put("exportedAt", System.currentTimeMillis());
        JSONArray rules = new JSONArray(), allow = new JSONArray(), block = new JSONArray();
        JSONObject dnsFlags = new JSONObject();
        for (String line : lines(list.output)) {
            String[] p = line.split("\\|", -1);
            if (p.length == 2 && "AD_MASTER".equals(p[0])) out.put("adMaster", "1".equals(p[1]));
            else if (p.length >= 4 && "RULE".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("source", p[1]); item.put("title", p[2]);
                item.put("enabled", "1".equals(p[3])); rules.put(item);
            } else if (p.length >= 4 && "ALLOW".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("domain", p[1]); item.put("note", p[2]);
                item.put("enabled", "1".equals(p[3])); allow.put(item);
            } else if (p.length >= 4 && "BLOCK".equals(p[0])) {
                JSONObject item = new JSONObject(); item.put("domain", p[1]); item.put("note", p[2]);
                item.put("enabled", "1".equals(p[3])); block.put(item);
            } else if (p.length == 3 && "DNS".equals(p[0])) dnsFlags.put(p[1], "1".equals(p[2]));
        }
        out.put("rules", rules); out.put("allowDomains", allow); out.put("blockDomains", block);
        out.put("dnsFlags", dnsFlags);

        JSONObject dnsConfig = new JSONObject();
        JSONArray custom = new JSONArray(), global = new JSONArray();
        for (String line : lines(dns.output)) {
            String[] p = line.split("\\\\|", -1);
            if (p.length == 2 && "CUSTOM_ENABLED".equals(p[0])) dnsConfig.put("customEnabled", "1".equals(p[1]));
            else if (p.length == 2 && "GLOBAL_ENABLED".equals(p[0])) dnsConfig.put("globalEnabled", "1".equals(p[1]));
            else if (p.length == 2 && "CUSTOM".equals(p[0])) custom.put(p[1]);
            else if (p.length == 2 && "GLOBAL".equals(p[0])) global.put(p[1]);
            else if (p.length == 2 && "VPN_REMOTE".equals(p[0])) dnsConfig.put("vpnRemote", p[1]);
            else if (p.length == 2 && "VPN_CN".equals(p[0])) dnsConfig.put("vpnCn", p[1]);
        }
        dnsConfig.put("customServers", custom); dnsConfig.put("globalServers", global);
        out.put("dnsConfig", dnsConfig);

        JSONObject plan = new JSONObject();
        for (String line : lines(schedule.output)) {
            int eq = line.indexOf('='); if (eq <= 0) continue;
            String key = line.substring(0, eq), value = line.substring(eq + 1);
            if ("enabled".equals(key)) plan.put(key, "1".equals(value));
            else if ("start".equals(key) || "end".equals(key) || "days".equals(key)) plan.put(key, value);
        }
        out.put("schedule", plan);
        return out;
    }

    private List<String> lines(String text) {
        List<String> out = new ArrayList<>();
        if (text == null) return out;
        for (String line : text.split("\\r?\\n")) {
            String v = line.trim(); if (!v.isEmpty()) out.add(v);
        }
        return out;
    }

    private void exportSettings() {
        operationStatus.setText("正在读取 FX 设备端配置…");
        worker.execute(() -> {
            try {
                JSONObject json = exportSnapshot();
                String output = json.toString(2);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    pendingExport = output;
                    Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                    intent.addCategory(Intent.CATEGORY_OPENABLE);
                    intent.setType("application/json");
                    intent.putExtra(Intent.EXTRA_TITLE, "fx-yulong-ad-settings.json");
                    try { startActivityForResult(intent, EXPORT_REQUEST); }
                    catch (Throwable error) { operationStatus.setText("无法打开导出文件选择器。"); }
                });
            } catch (Throwable error) { showError("导出失败", error); }
        });
    }

    private void pickImport() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        try { startActivityForResult(intent, IMPORT_REQUEST); }
        catch (Throwable error) { operationStatus.setText("无法打开导入文件选择器。"); }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
        if (requestCode == EXPORT_REQUEST) writeExport(data.getData());
        else if (requestCode == IMPORT_REQUEST) readImport(data.getData());
    }

    private void writeExport(Uri uri) {
        final String output = pendingExport;
        pendingExport = null;
        if (output == null) return;
        operationStatus.setText("正在写入 JSON 备份…");
        worker.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(uri, "w")) {
                if (stream == null) throw new IllegalStateException("无法创建导出文件。");
                stream.write(output.getBytes(StandardCharsets.UTF_8)); stream.flush();
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) operationStatus.setText("过滤设置备份已导出。"); });
            } catch (Throwable error) { showError("导出失败", error); }
        });
    }

    private void readImport(Uri uri) {
        operationStatus.setText("正在读取 JSON 备份…");
        worker.execute(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选文件。");
                byte[] buffer = new byte[8192]; int n;
                while ((n = input.read(buffer)) != -1) {
                    if (output.size() > MAX_BACKUP_BYTES - n) throw new IllegalArgumentException("备份文件超过 1 MiB。");
                    output.write(buffer, 0, n);
                }
                JSONObject json = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
                validateBackup(json);
                runOnUiThread(() -> new android.app.AlertDialog.Builder(this)
                        .setTitle("确认导入过滤设置")
                        .setMessage("这会替换当前游龙广告过滤来源、域名白/黑名单、DNS 开关和每周过滤计划。导入失败时会恢复导入前配置。")
                        .setNegativeButton("取消", null)
                        .setPositiveButton("备份并导入", (d, w) -> applyImport(json))
                        .show());
            } catch (Throwable error) { showError("导入文件无效", error); }
        });
    }

    private void validateBackup(JSONObject json) throws Exception {
        if (!"FX_YULONG_AD_SETTINGS_V1".equals(json.optString("schema")))
            throw new IllegalArgumentException("不支持的备份格式。");
        if (json.optJSONArray("rules") == null || json.optJSONArray("allowDomains") == null
                || json.optJSONArray("blockDomains") == null || json.optJSONObject("dnsFlags") == null
                || json.optJSONObject("dnsConfig") == null || json.optJSONObject("schedule") == null)
            throw new IllegalArgumentException("备份缺少必需的数据段。");
        if (json.getJSONArray("rules").length() > 500
                || json.getJSONArray("allowDomains").length() > 3000
                || json.getJSONArray("blockDomains").length() > 3000)
            throw new IllegalArgumentException("备份条目超过上限。");
        for (int i=0;i<json.getJSONArray("rules").length();i++) {
            JSONObject row=json.getJSONArray("rules").getJSONObject(i);
            String source=row.getString("source"), title=row.getString("title");
            if (!(source.startsWith("https://") || source.startsWith("builtin://"))
                    || source.length()>2048 || title.trim().isEmpty() || title.length()>180)
                throw new IllegalArgumentException("第 "+(i+1)+" 条过滤源无效。");
        }
        for (String key : new String[]{"dns_engine_adguardhome","dns_forward","custom_dns","global_dns",
                "block_quic","block_dot","block_plain_dns","block_ipv6","block_track_domains",
                "vpn_external_dns_proxy","vpn_external_compat","dns_querylog_enabled"})
            if (json.getJSONObject("dnsFlags").has(key)
                    && !(json.getJSONObject("dnsFlags").get(key) instanceof Boolean))
                throw new IllegalArgumentException("DNS 开关格式错误："+key);
        JSONObject schedule=json.getJSONObject("schedule");
        String start=schedule.optString("start","22:00"), end=schedule.optString("end","07:00");
        String days=schedule.optString("days","1,2,3,4,5,6,7");
        if (!start.matches("([01][0-9]|2[0-3]):[0-5][0-9]")
                || !end.matches("([01][0-9]|2[0-3]):[0-5][0-9]")
                || !days.matches("[1-7](,[1-7])*"))
            throw new IllegalArgumentException("过滤计划时间/星期格式无效。");
    }

    private String quote(String value) { return "'" + value.replace("'", "'\\''") + "'"; }
    private boolean validIpv4(String value) {
        if (value == null || !value.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")) return false;
        for (String part : value.split("\\.")) if (Integer.parseInt(part)>255) return false;
        return true;
    }
    private String csv(JSONArray array) throws Exception {
        List<String> values=new ArrayList<>();
        for(int i=0;i<array.length();i++){String value=array.getString(i);if(!validIpv4(value))throw new IllegalArgumentException("DNS 地址无效："+value);values.add(value);}
        if(values.size()>3)throw new IllegalArgumentException("每类 DNS 最多 3 个 IPv4 地址。");
        return String.join(",",values);
    }

    private void applyImport(JSONObject json) {
        operationStatus.setText("正在备份并导入设备端配置…");
        worker.execute(() -> {
            try {
                RootAccess.Result current=root("list");
                if(current.exitCode!=0)throw new IllegalStateException("读取现有设置失败："+safe(current.output));
                StringBuilder command=new StringBuilder("set -eu; ");
                command.append("MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do ")
                        .append("if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; then MP=\"$d\"; break; fi; done; ")
                        .append("[ -n \"$MP\" ] || exit 20; PG=/data/adb/privacyguard; CONF=$PG/settings.conf; PLAN=$PG/yulong-ad-schedule.conf; ")
                        .append("B1=$PG/yulong-ad-import-settings.rollback.$$; B2=$PG/yulong-ad-import-schedule.rollback.$$; ")
                        .append("test -f \"$CONF\" && test ! -L \"$CONF\"; cp -p \"$CONF\" \"$B1\"; ")
                        .append("HAD_PLAN=0; if [ -f \"$PLAN\" ] && [ ! -L \"$PLAN\" ]; then cp -p \"$PLAN\" \"$B2\"; HAD_PLAN=1; fi; ")
                        .append("COMMITTED=0; rollback(){ rc=$?; if [ \"$COMMITTED\" != 1 ]; then ")
                        .append("cp -p \"$B1\" \"$CONF.restore.$$\" && chmod 600 \"$CONF.restore.$$\" && mv -f \"$CONF.restore.$$\" \"$CONF\" || :; ")
                        .append("if [ \"$HAD_PLAN\" = 1 ]; then cp -p \"$B2\" \"$PLAN.restore.$$\" && chmod 600 \"$PLAN.restore.$$\" && mv -f \"$PLAN.restore.$$\" \"$PLAN\" || :; else rm -f \"$PLAN\"; fi; ")
                        .append("sh \"$MP/scripts/apply.sh\" fast >/dev/null 2>&1 || :; fi; rm -f \"$B1\" \"$B2\"; exit $rc; }; trap rollback EXIT; ");
                for(String line:lines(current.output)){
                    String[] p=line.split("\\\\|",-1); if(p.length<2)continue;
                    if("RULE".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" rule-remove ").append(quote(p[1])).append("; ");
                    else if("ALLOW".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" allow-remove ").append(quote(p[1])).append("; ");
                    else if("BLOCK".equals(p[0]))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" block-remove ").append(quote(p[1])).append("; ");
                }
                JSONArray rules=json.getJSONArray("rules");
                for(int i=0;i<rules.length();i++){
                    JSONObject row=rules.getJSONObject(i);
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" rule-add ")
                            .append(quote(row.getString("source"))).append(" ")
                            .append(quote(row.getString("title"))).append(" ")
                            .append(row.optBoolean("enabled",true)?"1":"0").append("; ");
                }
                JSONArray allow=json.getJSONArray("allowDomains");
                for(int i=0;i<allow.length();i++){
                    JSONObject row=allow.getJSONObject(i);if(!row.optBoolean("enabled",true))continue;
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" allow-add ")
                            .append(quote(row.getString("domain"))).append(" ")
                            .append(quote(row.optString("note","FX 白名单"))).append("; ");
                }
                JSONArray block=json.getJSONArray("blockDomains");
                for(int i=0;i<block.length();i++){
                    JSONObject row=block.getJSONObject(i);if(!row.optBoolean("enabled",true))continue;
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" block-add ")
                            .append(quote(row.getString("domain"))).append(" ")
                            .append(quote(row.optString("note","FX 黑名单"))).append("; ");
                }
                JSONObject flags=json.getJSONObject("dnsFlags");
                java.util.Iterator<String> keys=flags.keys();
                while(keys.hasNext()){
                    String key=keys.next(); boolean value=flags.optBoolean(key,false);
                    command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-set ")
                            .append(quote(key)).append(" ").append(value?"1":"0").append("; ");
                }
                JSONObject dns=json.getJSONObject("dnsConfig");
                String custom=csv(dns.optJSONArray("customServers")==null?new JSONArray():dns.getJSONArray("customServers"));
                String global=csv(dns.optJSONArray("globalServers")==null?new JSONArray():dns.getJSONArray("globalServers"));
                if(!custom.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-config-set custom ").append(quote(custom)).append("; ");
                if(!global.isEmpty())command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-config-set global ").append(quote(global)).append("; ");
                String remote=dns.optString("vpnRemote",""), cn=dns.optString("vpnCn","");
                if(!remote.isEmpty()&&validIpv4(remote))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-vpn-set remote_dns ").append(quote(remote)).append("; ");
                if(!cn.isEmpty()&&validIpv4(cn))command.append("sh \"$MP/scripts/yulong-ad-control.sh\" dns-vpn-set cn_dns ").append(quote(cn)).append("; ");
                command.append("sh \"$MP/scripts/yulong-ad-control.sh\" ad-master ").append(json.optBoolean("adMaster",true)?"1":"0").append("; ");
                JSONObject schedule=json.getJSONObject("schedule");
                command.append("sh \"$MP/scripts/yulong-ad-control.sh\" schedule-set ")
                        .append(schedule.optBoolean("enabled",false)?"1":"0").append(" ")
                        .append(quote(schedule.optString("start","22:00"))).append(" ")
                        .append(quote(schedule.optString("end","07:00"))).append(" ")
                        .append(quote(schedule.optString("days","1,2,3,4,5,6,7"))).append("; ");
                command.append("COMMITTED=1; rm -f \"$B1\" \"$B2\"; trap - EXIT; echo import=success");
                if(command.length()>120000)throw new IllegalArgumentException("恢复命令超过安全长度限制。");
                RootAccess.Result result=RootAccess.execute(command.toString(),180000L,1024*1024);
                if(result.exitCode!=0)throw new IllegalStateException("设备端回滚/导入失败："+safe(result.output));
                runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())operationStatus.setText("导入完成。配置已原子备份并逐项应用："+safe(result.output));});
            } catch(Throwable error) { showError("导入失败",error); }
        });
    }

    private String safe(String value) { return value==null||value.trim().isEmpty()?"无错误详情":value.trim(); }
    private void showError(String title, Throwable error) {
        String message=error.getMessage()==null?error.getClass().getSimpleName():error.getMessage();
        runOnUiThread(()->{if(!isFinishing()&&!isDestroyed())operationStatus.setText(title+"："+message);});
    }

    @Override protected void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
