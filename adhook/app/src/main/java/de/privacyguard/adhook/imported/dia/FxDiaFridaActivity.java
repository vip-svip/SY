package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Dia 23.11 Frida runtime bridge, integrated into the single FX APK.
 *
 * It operates only on locally installed Frida tools and debuggable target apps.
 * The server is bound to loopback only; injection is never attempted against
 * production/non-debuggable packages.
 */
public final class FxDiaFridaActivity extends Activity {
    private static final String PREFS = "fx_dia_frida";
    private static final String DEFAULT_SERVER = "/data/local/tmp/frida-server";
    private static final String DEFAULT_INJECTOR = "/data/local/tmp/frida-inject";
    private static final String SERVER_PID = "/data/adb/privacyguard/dia-frida-server.pid";
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    private EditText serverPath;
    private EditText injectorPath;
    private EditText script;
    private TextView status;
    private TextView targetLabel;
    private String targetPackage;
    private String targetName;

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }
    private Button button(String label, Runnable click) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label);
        b.setOnClickListener(v -> click.run()); return b;
    }
    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(10), dp(14), dp(10));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 16, 0xff17212b, true));
        panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5));
        parent.addView(panel, lp);
    }
    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
    private boolean validPath(String value) {
        return value != null && value.startsWith("/")
                && value.length() <= 256
                && value.matches("/[A-Za-z0-9_./-]+")
                && !value.contains("..");
    }
    private void runRoot(String command, long timeout, java.util.function.Consumer<RootAccess.Result> done) {
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(command, timeout, 256 * 1024);
            runOnUiThread(() -> {
                if (!isFinishing() && !isDestroyed()) done.accept(result);
            });
        });
    }
    private void setStatus(String value) {
        status.setText(value == null || value.trim().isEmpty() ? "命令已完成。" : value.trim());
    }
    private String currentServerPath() {
        return serverPath.getText() == null ? "" : serverPath.getText().toString().trim();
    }
    private String currentInjectorPath() {
        return injectorPath.getText() == null ? "" : injectorPath.getText().toString().trim();
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        String title = getIntent().getStringExtra("dia_page");
        if (title == null || title.trim().isEmpty()) title = "Frida 环境";

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · " + title, 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(16));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);

        card(body, "运行边界",
                "这是 FX 内部 Frida 管理器，不会启动第二个 APK。只接受本机已安装的 frida-server / frida-inject，服务只绑定 127.0.0.1:27042；注入目标限定为用户安装且带 DEBUGGABLE 标记的应用。FX QuickJS 脚本页仍是独立运行时，不会被当作 Frida。");

        serverPath = new EditText(this);
        serverPath.setSingleLine(true);
        serverPath.setHint(DEFAULT_SERVER);
        serverPath.setText(getSharedPreferences(PREFS, MODE_PRIVATE).getString("server_path", DEFAULT_SERVER));
        injectorPath = new EditText(this);
        injectorPath.setSingleLine(true);
        injectorPath.setHint(DEFAULT_INJECTOR);
        injectorPath.setText(getSharedPreferences(PREFS, MODE_PRIVATE).getString("injector_path", DEFAULT_INJECTOR));
        card(body, "Frida 工具路径", "填写设备上已安装的可执行文件绝对路径，不会自动下载或替换二进制。",
                text("frida-server", 12, 0xff617080, true), serverPath,
                text("frida-inject", 12, 0xff617080, true), injectorPath,
                button("保存路径", () -> savePaths()));

        status = text("尚未检测 Frida 环境。", 13, 0xff334155, false);
        card(body, "服务状态", "本地 Frida server", status,
                button("检测工具与服务", () -> checkRuntime()),
                button("启动本地 Frida 服务", () -> startServer()),
                button("停止 FX 启动的 Frida 服务", () -> stopServer()));

        targetLabel = text("尚未选择目标应用。", 13, 0xff334155, false);
        card(body, "目标应用", "仅显示用户安装且可调试的应用。非调试版本不会出现在目标列表中。",
                targetLabel, button("选择调试目标", () -> chooseTarget()));

        script = new EditText(this);
        script.setGravity(Gravity.TOP | Gravity.START);
        script.setMinLines(8);
        script.setText("Java.perform(function () {\\n"
                + "  console.log('[FX Dia] Frida script attached');\\n"
                + "});");
        card(body, "Frida JavaScript", "输入目标应用内的调试脚本；建议只观察应用自有代码和测试接口。",
                script,
                button("载入 Dia 原版 Frida 示例", () -> loadOriginalExamples()),
                button("载入 FX 示例脚本", () -> loadDiaScriptTemplate()),
                button("查看监听模式说明", () -> showDiaHelp("dia/frida_listen_help.md", "Frida 监听模式")),
                button("查看方法观察/内存快照说明", () -> showDiaHelp("dia/rewrite_rule_help.md", "方法观察与内存快照")),
                button("向当前调试目标注入", () -> injectScript()));

        TextView warning = text("注入要求：Root 可执行权限、frida-server 正在本机回环地址监听、frida-inject 可执行、目标应用处于前台/运行状态且为 debuggable。", 12, 0xff7a5b20, false);
        warning.setPadding(dp(16), dp(6), dp(16), dp(14));
        card(body, "Dia 开发监控模板",
                "仅对可调试测试应用启用。HTTP 模板只记录主机名，SQLite 模板只记录调用类型/长度/耗时；内存快照会包含进程私有内存，请只对自有测试应用使用。",
                button("载入 HTTP 连接监控", () -> loadDiaMonitorTemplate("http")),
                button("载入 SQLite 调用监控", () -> loadDiaMonitorTemplate("sql")),
                button("载入算法方法观察模板", () -> loadDiaMonitorTemplate("algorithm")),
                button("载入 HPROF 内存快照模板", () -> loadDiaMonitorTemplate("memory")));
        body.addView(warning);
    }

    private void savePaths() {
        String server = currentServerPath();
        String injector = currentInjectorPath();
        if (!validPath(server) || !validPath(injector)) {
            setStatus("路径无效：必须是绝对路径，且不能包含空白字符或 ..。");
            return;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString("server_path", server)
                .putString("injector_path", injector).apply();
        setStatus("Frida 工具路径已保存。");
    }

    private String pathCommand(String value, String label) {
        return "test -x " + quote(value) + " && echo " + quote(label + "=ready")
                + " || { echo " + quote(label + "=missing") + "; exit 3; }";
    }

    private void checkRuntime() {
        String server = currentServerPath();
        String injector = currentInjectorPath();
        if (!validPath(server) || !validPath(injector)) {
            setStatus("请先填写有效的 frida-server / frida-inject 路径。");
            return;
        }
        String command = pathCommand(server, "frida-server") + "; "
                + pathCommand(injector, "frida-inject") + "; "
                + "if [ -s " + quote(SERVER_PID) + " ]; then "
                + "pid=$(sed -n '1p' " + quote(SERVER_PID) + "); expected=$(sed -n '2p' " + quote(SERVER_PID) + "); "
                + "case $pid in ''|*[!0-9]*) echo server=stale-pid;; *) "
                + "if grep -Fq $expected /proc/$pid/cmdline 2>/dev/null; then echo server=running; "
                + "else echo server=stale-pid; fi;; esac; else echo server=stopped; fi";
        runRoot(command, 12000L, result ->
                setStatus("退出码 " + result.exitCode + "\n" + result.output));
    }

    private void startServer() {
        String server = currentServerPath();
        if (!validPath(server)) {
            setStatus("frida-server 路径无效。");
            return;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("server_path", server).apply();
        String command = "set -e; test -x " + quote(server) + "; "
                + "mkdir -p /data/adb/privacyguard; "
                + "if [ -s " + quote(SERVER_PID) + " ]; then "
                + "existing=$(sed -n '1p' " + quote(SERVER_PID) + "); expected=$(sed -n '2p' " + quote(SERVER_PID) + "); "
                + "case $existing in ''|*[!0-9]*) existing=;; *) "
                + "if grep -Fq $expected /proc/$existing/cmdline 2>/dev/null; then echo server=already-running; exit 0; fi;; esac; fi; "
                + "nohup " + quote(server) + " -l 127.0.0.1:27042 >> /data/adb/privacyguard/dia-frida-server.log 2>&1 </dev/null & "
                + "pid=$!; printf '%s\\n%s\\n' $pid " + quote(server) + " > " + quote(SERVER_PID) + "; "
                + "chmod 600 " + quote(SERVER_PID) + "; sleep 1; "
                + "kill -0 $pid; echo server=started pid=$pid;";
        runRoot(command, 20000L, result ->
                setStatus("启动退出码 " + result.exitCode + "\n" + result.output));
    }

    private void stopServer() {
        String command = "if [ -s " + quote(SERVER_PID) + " ]; then "
                + "pid=$(sed -n '1p' " + quote(SERVER_PID) + "); expected=$(sed -n '2p' " + quote(SERVER_PID) + "); "
                + "case $pid in ''|*[!0-9]*) echo invalid-pid; exit 2;; esac; "
                + "if grep -Fq $expected /proc/$pid/cmdline 2>/dev/null; then kill $pid; echo server=stopped; "
                + "else echo stale-pid-not-killed; fi; "
                + "rm -f " + quote(SERVER_PID) + "; "
                + "else echo no-fx-owned-server; fi";
        runRoot(command, 12000L, result ->
                setStatus("停止退出码 " + result.exitCode + "\n" + result.output));
    }

    private static final class Target {
        final String packageName, label;
        Target(String p, String l) { packageName = p; label = l; }
    }

    private void chooseTarget() {
        List<Target> targets = new ArrayList<>();
        PackageManager pm = getPackageManager();
        for (ApplicationInfo info : pm.getInstalledApplications(0)) {
            if (info.packageName == null || info.packageName.equals(getPackageName())) continue;
            if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0) continue;
            if ((info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
            String label;
            try { label = String.valueOf(pm.getApplicationLabel(info)); }
            catch (Throwable ignored) { label = info.packageName; }
            targets.add(new Target(info.packageName, label));
        }
        targets.sort(Comparator.comparing(item -> item.label.toLowerCase(Locale.ROOT)));
        if (targets.isEmpty()) {
            setStatus("没有可调试的用户应用。请使用自己构建的 debuggable 测试目标。");
            return;
        }
        String[] labels = new String[targets.size()];
        for (int i = 0; i < targets.size(); i++)
            labels[i] = targets.get(i).label + "\\n" + targets.get(i).packageName;
        new AlertDialog.Builder(this).setTitle("选择 debuggable 目标")
                .setItems(labels, (dialog, which) -> {
                    targetPackage = targets.get(which).packageName;
                    targetName = targets.get(which).label;
                    targetLabel.setText(targetName + "\\n" + targetPackage);
                }).setNegativeButton("取消", null).show();
    }

    private void loadOriginalExamples() {
        try {
            List<String> labels = new ArrayList<>();
            List<String> sources = new ArrayList<>();
            try (java.util.zip.ZipInputStream zip = new java.util.zip.ZipInputStream(
                    getAssets().open("dia/fridaJsExample.zip"))) {
                java.util.zip.ZipEntry entry;
                byte[] buffer = new byte[8192];
                while ((entry = zip.getNextEntry()) != null) {
                    if (entry.isDirectory()) continue;
                    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
                    int count;
                    while ((count = zip.read(buffer)) != -1) {
                        out.write(buffer, 0, count);
                        if (out.size() > 128 * 1024) throw new IllegalStateException("单个示例超过 128 KiB。");
                    }
                    if (sources.size() >= 32) break;
                    String name = entry.getName();
                    labels.add("Dia 原版示例 " + (sources.size() + 1) + " · " + name);
                    sources.add(new String(out.toByteArray(), StandardCharsets.UTF_8));
                }
            }
            if (sources.isEmpty()) {
                setStatus("原版 Frida 示例包为空或资源损坏。");
                return;
            }
            new AlertDialog.Builder(this).setTitle("选择 Dia 原版 Frida 示例")
                    .setItems(labels.toArray(new String[0]), (dialog, which) -> {
                        script.setText(sources.get(which));
                        setStatus("示例已载入编辑器；尚未对目标应用执行注入。");
                    }).setNegativeButton("取消", null).show();
        } catch (Exception error) {
            setStatus("读取原版 Frida 示例失败：" + error.getMessage());
        }
    }

    private void loadDiaScriptTemplate() {
        try (InputStream in = getAssets().open("dia/my-script.js")) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            script.setText(new String(out.toByteArray(), StandardCharsets.UTF_8));
            setStatus("Dia JS 示例模板已载入；该模板属于普通页面脚本，不是 Frida 注入脚本。");
        } catch (Exception error) {
            setStatus("读取 Dia 示例模板失败：" + error.getMessage());
        }
    }

    private void showDiaHelp(String asset, String title) {
        try (InputStream in = getAssets().open(asset)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            TextView content = new TextView(this);
            content.setText(new String(out.toByteArray(), StandardCharsets.UTF_8));
            content.setTextSize(13);
            content.setTextColor(0xff334155);
            content.setPadding(dp(18), dp(12), dp(18), dp(12));
            new AlertDialog.Builder(this).setTitle(title).setView(content)
                    .setPositiveButton("关闭", null).show();
        } catch (Exception error) {
            setStatus("读取帮助文档失败：" + error.getMessage());
        }
    }

    private void loadDiaMonitorTemplate(String kind) {
        String source;
        switch (kind) {
            case "http":
                source = "Java.perform(function () {\\n"
                        + "  var URL = Java.use('java.net.URL');\\n"
                        + "  var open = URL.openConnection.overload();\\n"
                        + "  open.implementation = function () {\\n"
                        + "    var host = String(this.getHost());\\n"
                        + "    send('[DIA_HTTP] connection host=' + host);\\n"
                        + "    return open.call(this);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "sql":
                source = "Java.perform(function () {\\n"
                        + "  var DB = Java.use('android.database.sqlite.SQLiteDatabase');\\n"
                        + "  var raw = DB.rawQuery.overload('java.lang.String', '[Ljava.lang.String;');\\n"
                        + "  raw.implementation = function (sql, args) {\\n"
                        + "    var start = Date.now(); var result = raw.call(this, sql, args);\\n"
                        + "    send('[DIA_SQL] rawQuery chars=' + String(sql).length + ' elapsedMs=' + (Date.now()-start));\\n"
                        + "    return result;\\n"
                        + "  };\\n"
                        + "  var exec = DB.execSQL.overload('java.lang.String');\\n"
                        + "  exec.implementation = function (sql) {\\n"
                        + "    var start = Date.now(); var result = exec.call(this, sql);\\n"
                        + "    send('[DIA_SQL] execSQL chars=' + String(sql).length + ' elapsedMs=' + (Date.now()-start));\\n"
                        + "    return result;\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "algorithm":
                source = "Java.perform(function () {\\n"
                        + "  var className = 'com.example.app.AlgorithmClass';\\n"
                        + "  var methodName = 'calculate';\\n"
                        + "  var C = Java.use(className);\\n"
                        + "  C[methodName].overloads.forEach(function (overload) {\\n"
                        + "    overload.implementation = function () {\\n"
                        + "      var started = Date.now();\\n"
                        + "      var result = overload.apply(this, arguments);\\n"
                        + "      send('[DIA_ALGORITHM] ' + className + '.' + methodName + ' args=' + arguments.length + ' elapsedMs=' + (Date.now()-started));\\n"
                        + "      return result;\\n"
                        + "    };\\n"
                        + "  });\\n"
                        + "});";
                break;
            case "memory":
                source = "Java.perform(function () {\\n"
                        + "  var ActivityThread = Java.use('android.app.ActivityThread');\\n"
                        + "  var app = ActivityThread.currentApplication();\\n"
                        + "  if (app === null) { send('[DIA_MEMORY] application context unavailable'); return; }\\n"
                        + "  var path = String(app.getFilesDir().getAbsolutePath()) + '/dia-memory-' + Date.now() + '.hprof';\\n"
                        + "  Java.use('android.os.Debug').dumpHprofData(path);\\n"
                        + "  send('[DIA_MEMORY] snapshot saved: ' + path);\\n"
                        + "});";
                break;
            default:
                return;
        }
        script.setText(source);
        setStatus("监控模板已载入；请先检查目标类/方法，再手动执行注入。");
    }

    private void injectScript() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        String source = script.getText() == null ? "" : script.getText().toString();
        if (source.trim().isEmpty() || source.length() > 48 * 1024) {
            setStatus("Frida 脚本为空或超过 48 KiB。");
            return;
        }
        String injector = currentInjectorPath();
        if (!validPath(injector)) {
            setStatus("frida-inject 路径无效。");
            return;
        }
        String encoded = android.util.Base64.encodeToString(
                source.getBytes(StandardCharsets.UTF_8), android.util.Base64.NO_WRAP);
        String scriptPath = "/data/adb/privacyguard/dia-frida/" + targetPackage + ".js";
        String command = "set -e; test -x " + quote(injector) + "; "
                + "mkdir -p /data/adb/privacyguard/dia-frida; "
                + "printf '%s' " + quote(encoded) + " | base64 -d > " + quote(scriptPath) + "; "
                + "chmod 600 " + quote(scriptPath) + "; "
                + "pid=$(pidof " + quote(targetPackage) + " | awk '{print $1}'); "
                + "case \"$pid\" in ''|*[!0-9]*) echo target-not-running; exit 4;; esac; "
                + quote(injector) + " -p \"$pid\" -s " + quote(scriptPath);
        runRoot(command, 45000L, result ->
                setStatus("注入退出码 " + result.exitCode + "\\n" + result.output));
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
