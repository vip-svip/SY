package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.net.Uri;
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

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/**
 * Dia 23.11 Frida runtime bridge, integrated into the single FX APK.
 *
 * It operates only on locally installed Frida tools and debuggable target apps.
 * The server is bound to loopback only; injection is never attempted against
 * production/non-debuggable packages.
 */
public final class FxDiaFridaActivity extends Activity {
    private static final String PREFS = "fx_dia_frida";
    private static final String DEFAULT_SERVER = "/data/local/tmp/fx-frida/fx-frida-server";
    private static final String DEFAULT_INJECTOR = "/data/local/tmp/fx-frida/fx-frida-inject";
    private static final String SERVER_PID = "/data/adb/privacyguard/dia-frida-server.pid";
    private static final int REQUEST_EXPORT_LIBRARY = 7105;
    private static final int REQUEST_CODE_FULL_EDITOR = 0x3039;
    private static final int MAX_FRIDA_SOURCE_BYTES = 48 * 1024;
    private static final int REQUEST_IMPORT_LIBRARY = 7106;
    private static final int MAX_LIBRARY_JSON_BYTES = 1024 * 1024;
    private static final String STATE_PENDING_LIBRARY_EXPORT = "fx_frida_pending_library_export";
    private static final String PENDING_LIBRARY_EXPORT_PREFIX = "fx-dia-frida-library-";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(12),
            r -> { Thread t = new Thread(r, "fx-dia-frida"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
            });
        }
    }
    private String pendingFridaLibraryExportFileName;

    private EditText serverPath;
    private EditText injectorPath;
    private EditText fridaCliPath;
    private EditText gadgetPath;
    private EditText gadgetPort;
    private EditText gadgetProcess;
    private android.widget.RadioGroup gadgetLoadMode;
    private EditText script;
    private TextView status;
    private TextView targetLabel;
    private String targetPackage;
    private String targetName;
    private boolean targetLoading;
    private int targetLoadGeneration;
    private int monitorEventGeneration;
    private final java.util.LinkedHashSet<String> selectedProcessPids = new java.util.LinkedHashSet<>();

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
        submitWorker(() -> {
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
    private String currentFridaCliPath() {
        return fridaCliPath == null || fridaCliPath.getText() == null
                ? "" : fridaCliPath.getText().toString().trim();
    }

    private static boolean isSafePendingLibraryExportName(String name) {
        return name != null && name.matches("fx-dia-frida-library-[A-Za-z0-9]+\\.tmp");
    }

    private File stagePendingFridaLibraryExport(String json) throws Exception {
        if (json == null) throw new IllegalArgumentException("Frida 脚本库为空。");
        byte[] payload = json.getBytes(StandardCharsets.UTF_8);
        if (payload.length == 0 || payload.length > MAX_LIBRARY_JSON_BYTES)
            throw new IllegalArgumentException("Frida 脚本库 JSON 超过 1 MiB，无法导出。");
        File staged = File.createTempFile(PENDING_LIBRARY_EXPORT_PREFIX, ".tmp", getCacheDir());
        try (FileOutputStream output = new FileOutputStream(staged, false)) {
            output.write(payload);
            output.flush();
            output.getFD().sync();
            return staged;
        } catch (Exception error) {
            //noinspection ResultOfMethodCallIgnored
            staged.delete();
            throw error;
        } finally {
            java.util.Arrays.fill(payload, (byte) 0);
        }
    }

    private File resolvePendingFridaLibraryExport(String name) throws Exception {
        if (!isSafePendingLibraryExportName(name))
            throw new IllegalArgumentException("Frida 脚本库暂存文件名无效。");
        File cacheRoot = getCacheDir().getCanonicalFile();
        File candidate = new File(cacheRoot, name);
        if (java.nio.file.Files.isSymbolicLink(candidate.toPath()))
            throw new IllegalArgumentException("Frida 脚本库暂存文件不能是符号链接。");
        File canonical = candidate.getCanonicalFile();
        if (!cacheRoot.equals(canonical.getParentFile()) || !canonical.isFile() || !canonical.canRead()
                || canonical.length() <= 0 || canonical.length() > MAX_LIBRARY_JSON_BYTES)
            throw new IllegalArgumentException("Frida 脚本库暂存文件不存在或大小无效。");
        return canonical;
    }

    private void deletePendingFridaLibraryExport(String name) {
        if (!isSafePendingLibraryExportName(name)) return;
        try {
            File cacheRoot = getCacheDir().getCanonicalFile();
            File candidate = new File(cacheRoot, name);
            if (java.nio.file.Files.isSymbolicLink(candidate.toPath())) return;
            File canonical = candidate.getCanonicalFile();
            if (cacheRoot.equals(canonical.getParentFile())) {
                //noinspection ResultOfMethodCallIgnored
                canonical.delete();
            }
        } catch (Exception ignored) { }
    }

    private void cleanupStalePendingLibraryExports(String keepName) {
        File[] files = getCacheDir().listFiles((dir, name) ->
                name.startsWith(PENDING_LIBRARY_EXPORT_PREFIX) && name.endsWith(".tmp"));
        if (files == null) return;
        long staleBefore = System.currentTimeMillis() - 24L * 60L * 60L * 1000L;
        for (File file : files) {
            if (!file.getName().equals(keepName) && file.lastModified() < staleBefore) {
                //noinspection ResultOfMethodCallIgnored
                file.delete();
            }
        }
    }



    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        String restoredPendingName = state == null ? null : state.getString(STATE_PENDING_LIBRARY_EXPORT);
        if (isSafePendingLibraryExportName(restoredPendingName))
            pendingFridaLibraryExportFileName = restoredPendingName;
        cleanupStalePendingLibraryExports(pendingFridaLibraryExportFileName);
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
        fridaCliPath = new EditText(this);
        fridaCliPath.setSingleLine(true);
        fridaCliPath.setHint("/data/data/com.termux/files/usr/bin/frida");
        fridaCliPath.setText(getSharedPreferences(PREFS, MODE_PRIVATE).getString("frida_cli_path", ""));
        card(body, "Frida 工具路径", "frida-server 与 frida-inject 用于本机服务/进程注入。Gadget 远程控制需单独安装可用的 frida CLI 与 Python 依赖；FX 不会把 frida-inject 误当成远程 CLI，也不会下载第三方执行环境。",
                text("frida-server", 12, 0xff617080, true), serverPath,
                text("frida-inject（本机 PID 注入）", 12, 0xff617080, true), injectorPath,
                text("frida CLI（Gadget 远程控制，可选）", 12, 0xff617080, true), fridaCliPath,
                button("保存路径", () -> savePaths()),
                button("从文件选择并导入 Frida Server", () -> pickBinary(7101)),
                button("从文件选择并导入 Frida Inject", () -> pickBinary(7102)));

        status = text("尚未检测 Frida 环境。", 13, 0xff334155, false);
        card(body, "服务状态", "本地 Frida server", status,
                button("检测工具与服务", () -> checkRuntime()),
                button("启动本地 Frida 服务", () -> startServer()),
                button("停止 FX 启动的 Frida 服务", () -> stopServer()));

        card(body, "Frida Gadget 监听模式",
                "按 Dia 23.11 原始配置语义生成 Frida Gadget Listen 配置。WAIT：Gadget 加载后等待控制端连接并调用 resume；RESUME：Gadget 加载后立即继续应用启动。此配置只作用于加载该 Gadget 的目标进程，不会把 frida-server/frida-inject 误当作 Gadget。",
                text("Frida Gadget 动态库绝对路径", 12, 0xff617080, true));
        gadgetPath = new EditText(this);
        gadgetPath.setSingleLine(true);
        gadgetPath.setHint("/data/local/tmp/fx-frida/libgadget.so");
        gadgetPath.setText(getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString("gadget_path", "/data/local/tmp/fx-frida/libgadget.so"));
        gadgetPort = new EditText(this);
        gadgetPort.setSingleLine(true);
        gadgetPort.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        gadgetPort.setHint("27043");
        gadgetPort.setText(getSharedPreferences(PREFS, MODE_PRIVATE).getString("gadget_port", "27043"));
        gadgetProcess = new EditText(this);
        gadgetProcess.setSingleLine(true);
        gadgetProcess.setHint("默认主进程；可填 包名:remote 等一个独立进程");
        gadgetProcess.setText(getSharedPreferences(PREFS, MODE_PRIVATE).getString("gadget_process", ""));
        gadgetLoadMode = new android.widget.RadioGroup(this);
        gadgetLoadMode.setOrientation(android.widget.RadioGroup.HORIZONTAL);
        android.widget.RadioButton waitMode = new android.widget.RadioButton(this);
        waitMode.setText("WAIT · 等待远程恢复");
        waitMode.setId(android.view.View.generateViewId());
        android.widget.RadioButton resumeMode = new android.widget.RadioButton(this);
        resumeMode.setText("RESUME · 立即启动");
        resumeMode.setId(android.view.View.generateViewId());
        gadgetLoadMode.addView(waitMode);
        gadgetLoadMode.addView(resumeMode);
        boolean waitSelected = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean("gadget_on_load_wait", true);
        gadgetLoadMode.check(waitSelected ? waitMode.getId() : resumeMode.getId());
        card(body, "监听参数",
                "为了避免把调试端口暴露到局域网，此管理页固定绑定 127.0.0.1。跨设备调试请使用 ADB 端口转发；不要把未经认证的 Frida 端口绑定到 0.0.0.0。",
                text("监听 TCP 端口（1024–65535）", 12, 0xff617080, true),
                gadgetPort,
                text("Gadget 目标进程（每个端口只允许一个进程）", 12, 0xff617080, true),
                gadgetProcess, gadgetLoadMode,
                button("生成并写入 Gadget 配置", () -> saveGadgetListenConfig()),
                button("部署 Gadget 到当前目标应用", () -> confirmDeployGadgetToTarget()),
                button("移除当前目标的 FX Gadget 部署", () -> confirmRemoveGadgetFromTarget()),
                button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume()),
                button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog()),
                button("停止 Gadget 会话", () -> stopGadgetSession()),
                button("复制 ADB 连接命令", () -> copyGadgetConnectCommand()));
        TextView gadgetNote = text(
                "目标加载流程：选择 debuggable 用户应用 → 生成监听配置 → 指定一个目标进程（默认主进程；子进程填写 包名:remote）→ 部署到 nativeLibraryDir → 在 LSPosed 中启用 FX 对该目标的作用域 → 完全停止并重启目标应用。每个 Gadget 监听端口只绑定一个进程，避免应用多进程争抢同一端口。FX 只部署带 SHA-256 标记的 Gadget 动态库/配置，不修改、重打包或重签 APK；监听仅绑定 127.0.0.1。目标应用更新后可能覆盖 nativeLibraryDir，需要重新部署。",
                12, 0xff7a5b20, false);
        gadgetNote.setPadding(dp(16), dp(4), dp(16), dp(10));
        body.addView(gadgetNote);


        targetLabel = text("尚未选择目标应用。", 13, 0xff334155, false);
        card(body, "目标应用与进程", "仅显示用户安装且可调试的应用。下方多选进程仅供 Frida-inject 使用，并会重新校验 PID 对应的包名；Gadget 监听进程在上方独立选择，每个端口只绑定一个进程。",
                targetLabel,
                button("选择调试目标", () -> chooseTarget()),
                button("选择多个运行进程", () -> chooseTargetProcesses()));

        script = new EditText(this);
        script.setGravity(Gravity.TOP | Gravity.START);
        script.setMinLines(8);
        script.setText("Java.perform(function () {\\n"
                + "  console.log('[FX Dia] Frida script attached');\\n"
                + "});");
        card(body, "Frida JavaScript", "输入目标应用内的调试脚本；建议只观察应用自有代码和测试接口。",
                script,
                button("打开全屏代码编辑器", this::openFullScreenCodeEditor),
                button("保存到 Frida 脚本库", () -> saveCurrentFridaScript()),
                button("打开 Frida 脚本库", () -> showFridaScriptLibrary()),
                button("导出脚本库 JSON 文件", () -> exportFridaScriptLibrary()),
                button("从 JSON 文件批量导入脚本库", () -> importFridaScriptLibrary()),
                button("复制脚本库 JSON 到剪贴板", () -> copyFridaScriptLibraryJson()),
                button("从剪贴板粘贴 JSON 导入", () -> importFridaScriptLibraryFromClipboard()),
                button("载入 Dia 原版 Frida 示例", () -> loadOriginalExamples()),
                button("载入 FX 示例脚本", () -> loadDiaScriptTemplate()),
                button("查看监听模式说明", () -> showDiaHelp("dia/frida_listen_help.md", "Frida 监听模式")),
                button("查看方法观察/内存快照说明", () -> showDiaHelp("dia/rewrite_rule_help.md", "方法观察与内存快照")),
                button("查看当前目标注入日志", () -> showSessionLog()),
                button("查看结构化监控事件", () -> showMonitorEvents()),
                button("清空当前目标注入日志", () -> clearSessionLog()),
                button("从文件导入 JS 脚本", () -> pickScript()),
                button("导出当前 JS 脚本", () -> saveScript()),
                button("向当前调试目标注入", () -> injectScript()));

        TextView warning = text("注入要求：Root 可执行权限、frida-server 正在本机回环地址监听、frida-inject 可执行、目标应用处于前台/运行状态且为 debuggable。", 12, 0xff7a5b20, false);
        warning.setPadding(dp(16), dp(6), dp(16), dp(14));
        card(body, "Dia 开发监控模板",
                "仅对自有可调试测试应用启用。自动点击和匹配弹窗移除模板都会执行真实 UI 操作，规则默认全空且必须手动注入；弹窗移除默认只检查 DecorView/content 直接子项，扩大范围前务必确认应用和规则。不要对支付、授权、删除等敏感操作配置自动操作。",
                button("载入 HTTP 连接监控", () -> loadDiaMonitorTemplate("http")),
                button("载入 WebView 导航监控", () -> loadDiaMonitorTemplate("webview-http")),
                button("载入 SQLite 调用监控", () -> loadDiaMonitorTemplate("sql")),
                button("载入 SQLCipher/WCDB 调用监控", () -> loadDiaMonitorTemplate("sqlcipher")),
                button("载入算法方法观察模板", () -> loadDiaMonitorTemplate("algorithm")),
                button("载入 Intent 调用观察", () -> loadDiaMonitorTemplate("intent")),
                button("载入 Activity 创建入口观察", () -> loadDiaMonitorTemplate("appentry")),
                button("载入 Socket 连接观察", () -> loadDiaMonitorTemplate("socket")),
                button("载入 View 点击观察", () -> loadDiaMonitorTemplate("click")),
                button("载入正则/资源 ID 自动点击", () -> loadDiaMonitorTemplate("click-auto")),
                button("配置匹配弹窗移除规则…", this::configureDialogRemoveTemplate),
                button("载入空白弹窗移除模板", () -> loadDiaMonitorTemplate("viewgroup-remove")),
                button("载入 ViewGroup 层级观察", () -> loadDiaMonitorTemplate("viewgroup")),
                button("载入 Fragment 生命周期观察", () -> loadDiaMonitorTemplate("fragment")),
                button("载入线程/启动调用栈观察", () -> loadDiaMonitorTemplate("thread")),
                button("载入 Activity 调用栈观察", () -> loadDiaMonitorTemplate("stack")),
                button("载入 Runtime/Process 启动观察", () -> loadDiaMonitorTemplate("runtime")),
                button("载入按键事件观察", () -> loadDiaMonitorTemplate("key")),
                button("载入 Native 导出符号观察", () -> loadDiaMonitorTemplate("native")),
                button("载入 ClassLoader 观察", () -> loadDiaMonitorTemplate("classloader")),
                button("载入 HPROF 内存快照模板", () -> loadDiaMonitorTemplate("memory")));
        body.addView(warning);

        if ("SQL 监控".equals(title)) {
            android.content.SharedPreferences sqlPrefs =
                    getSharedPreferences(PREFS, MODE_PRIVATE);
            android.widget.CheckBox sqlite = new android.widget.CheckBox(this);
            sqlite.setText("Android SQLite");
            sqlite.setChecked(sqlPrefs.getBoolean("sql_monitor_sqlite", true));
            sqlite.setOnCheckedChangeListener((button, checked) ->
                    sqlPrefs.edit().putBoolean("sql_monitor_sqlite", checked).apply());

            android.widget.CheckBox sqlcipher = new android.widget.CheckBox(this);
            sqlcipher.setText("SQLCipher");
            sqlcipher.setChecked(sqlPrefs.getBoolean("sql_monitor_sqlcipher", true));
            sqlcipher.setOnCheckedChangeListener((button, checked) ->
                    sqlPrefs.edit().putBoolean("sql_monitor_sqlcipher", checked).apply());

            android.widget.CheckBox wcdb = new android.widget.CheckBox(this);
            wcdb.setText("腾讯 WCDB");
            wcdb.setChecked(sqlPrefs.getBoolean("sql_monitor_wcdb", true));
            wcdb.setOnCheckedChangeListener((button, checked) ->
                    sqlPrefs.edit().putBoolean("sql_monitor_wcdb", checked).apply());

            android.widget.CheckBox zetetic = new android.widget.CheckBox(this);
            zetetic.setText("Zetetic SQLCipher");
            zetetic.setChecked(sqlPrefs.getBoolean("sql_monitor_zetetic", true));
            zetetic.setOnCheckedChangeListener((button, checked) ->
                    sqlPrefs.edit().putBoolean("sql_monitor_zetetic", checked).apply());

            android.widget.CheckBox stack = new android.widget.CheckBox(this);
            stack.setText("记录最多 8 层调用栈");
            stack.setChecked(sqlPrefs.getBoolean("sql_monitor_stack", false));
            stack.setOnCheckedChangeListener((button, checked) ->
                    sqlPrefs.edit().putBoolean("sql_monitor_stack", checked).apply());

            card(body, "SQL 监控范围",
                    "选择要观察的数据库实现。默认不记录 SQL 文本、绑定值或查询结果；调用栈会增加日志量，默认关闭。",
                    sqlite, sqlcipher, wcdb, zetetic, stack,
                    button("载入当前 SQL 监控配置", () -> loadDiaMonitorTemplate("sqlcipher")));
        }

        // Dia fourth-level monitor pages open with their matching executable template,
        // rather than landing on an unrelated generic Frida editor.
        if ("HTTP 监控".equals(title)) {
            loadDiaMonitorTemplate("http");
        } else if ("SQL 监控".equals(title)) {
            loadDiaMonitorTemplate("sqlcipher");
        } else if ("算法监控".equals(title)) {
            loadDiaMonitorTemplate("algorithm");
        } else if ("Native 方法".equals(title)) {
            loadDiaMonitorTemplate("native");
        } else if ("按键控制".equals(title)) {
            loadDiaMonitorTemplate("key");
        } else if ("Socket 监控".equals(title)) {
            loadDiaMonitorTemplate("socket");
        } else if ("Intent 监控".equals(title)) {
            loadDiaMonitorTemplate("intent");
        } else if ("Activity 启动入口观察".equals(title)) {
            loadDiaMonitorTemplate("appentry");
        } else if ("Shell/Process 监控".equals(title)) {
            loadDiaMonitorTemplate("runtime");
        } else if ("方法堆栈".equals(title)) {
            loadDiaMonitorTemplate("stack");
        } else if ("View 点击监控".equals(title)) {
            loadDiaMonitorTemplate("click");
        } else if ("按文本/ID 自动点击".equals(title)) {
            loadDiaMonitorTemplate("click-auto");
        } else if ("按文本/ID 移除匹配弹窗".equals(title)) {
            loadDiaMonitorTemplate("viewgroup-remove");
        } else if ("ViewGroup 层级监控".equals(title)) {
            loadDiaMonitorTemplate("viewgroup");
        } else if ("Fragment 生命周期".equals(title)) {
            loadDiaMonitorTemplate("fragment");
        } else if ("Thread 启动监控".equals(title)) {
            loadDiaMonitorTemplate("thread");
        } else if ("ClassLoader 监控".equals(title)) {
            loadDiaMonitorTemplate("classloader");
        } else if ("JS 脚本列表".equals(title)) {
            body.post(this::showFridaScriptLibrary);
        } else if ("脚本编辑器".equals(title)) {
            body.post(this::openFullScreenCodeEditor);
        } else if ("运行日志".equals(title)) {
            body.post(() -> {
                if (targetPackage == null) chooseTarget();
                else showSessionLog();
            });
        }

        // Restore transient editor/target state after page templates have been applied.
        // EditText widgets are created dynamically and have no stable view IDs, so
        // Android's automatic view-state restoration cannot preserve their contents.
        restoreTransientState(state);
    }

    private void restoreTransientState(Bundle state) {
        android.content.SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        if (state != null) {
            if (serverPath != null) serverPath.setText(state.getString("fx_frida_server_path",
                    serverPath.getText().toString()));
            if (injectorPath != null) injectorPath.setText(state.getString("fx_frida_injector_path",
                    injectorPath.getText().toString()));
            if (fridaCliPath != null) fridaCliPath.setText(state.getString("fx_frida_cli_path",
                    fridaCliPath.getText().toString()));
            if (gadgetPath != null) gadgetPath.setText(state.getString("fx_frida_gadget_path",
                    gadgetPath.getText().toString()));
            if (gadgetPort != null) gadgetPort.setText(state.getString("fx_frida_gadget_port",
                    gadgetPort.getText().toString()));
            if (gadgetProcess != null) gadgetProcess.setText(state.getString("fx_frida_gadget_process",
                    gadgetProcess.getText().toString()));
            if (script != null) script.setText(state.getString("fx_frida_script", script.getText().toString()));
        }

        String savedPackage = state == null
                ? prefs.getString("target_package", null)
                : state.getString("fx_frida_target_package",
                        prefs.getString("target_package", null));
        String savedName = state == null
                ? prefs.getString("target_name", savedPackage)
                : state.getString("fx_frida_target_name",
                        prefs.getString("target_name", savedPackage));
        if (savedPackage != null && !savedPackage.trim().isEmpty()) {
            try {
                ApplicationInfo info = getPackageManager().getApplicationInfo(savedPackage, 0);
                if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0
                        && (info.flags & ApplicationInfo.FLAG_SYSTEM) == 0) {
                    targetPackage = savedPackage;
                    targetName = savedName == null || savedName.trim().isEmpty()
                            ? savedPackage : savedName;
                    prefs.edit().putString("target_package", targetPackage)
                            .putString("target_name", targetName).apply();
                    targetLabel.setText(targetName + "\\n" + targetPackage);
                    selectedProcessPids.clear();
                    ArrayList<String> restoredPids = state == null ? null
                            : state.getStringArrayList("fx_frida_selected_pids");
                    if (restoredPids != null) {
                        for (String pid : restoredPids) {
                            if (pid != null && pid.matches("[0-9]{1,10}"))
                                selectedProcessPids.add(pid);
                        }
                    }
                    if (!selectedProcessPids.isEmpty()) {
                        targetLabel.append("\\n已恢复所选进程数：" + selectedProcessPids.size()
                                + "（注入前仍会重新校验 PID）");
                    } else {
                        targetLabel.append("\\n进程：注入时自动枚举");
                    }
                } else {
                    prefs.edit().remove("target_package").remove("target_name").apply();
                    targetPackage = null;
                    targetName = null;
                    monitorEventGeneration++;
                    selectedProcessPids.clear();
                    targetLabel.setText("上次选择的目标已不再是可调试用户应用，请重新选择。");
                }
            } catch (PackageManager.NameNotFoundException ignored) {
                prefs.edit().remove("target_package").remove("target_name").apply();
                targetPackage = null;
                targetName = null;
                monitorEventGeneration++;
                selectedProcessPids.clear();
                targetLabel.setText("上次选择的目标应用已卸载，需重新选择。");
            }
        }
        if (state != null && gadgetLoadMode != null) {
            int checked = state.getInt("fx_frida_gadget_load_mode", 0);
            if (gadgetLoadMode.getChildCount() > checked && checked >= 0)
                gadgetLoadMode.check(gadgetLoadMode.getChildAt(checked).getId());
        }
        if (state != null && status != null)
            status.setText(state.getString("fx_frida_status", "已恢复上次编辑状态。"));
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (isSafePendingLibraryExportName(pendingFridaLibraryExportFileName)) {
            outState.putString(STATE_PENDING_LIBRARY_EXPORT, pendingFridaLibraryExportFileName);
        }
        if (serverPath != null) outState.putString("fx_frida_server_path", serverPath.getText().toString());
        if (injectorPath != null) outState.putString("fx_frida_injector_path", injectorPath.getText().toString());
        if (fridaCliPath != null) outState.putString("fx_frida_cli_path", fridaCliPath.getText().toString());
        if (gadgetPath != null) outState.putString("fx_frida_gadget_path", gadgetPath.getText().toString());
        if (gadgetPort != null) outState.putString("fx_frida_gadget_port", gadgetPort.getText().toString());
        if (gadgetProcess != null) outState.putString("fx_frida_gadget_process", gadgetProcess.getText().toString());
        if (script != null) {
            String source = script.getText().toString();
            // Frida editor content is intentionally capped to avoid oversized saved-state Bundles.
            if (source.getBytes(StandardCharsets.UTF_8).length <= 48 * 1024)
                outState.putString("fx_frida_script", source);
        }
        if (targetPackage != null) outState.putString("fx_frida_target_package", targetPackage);
        if (targetName != null) outState.putString("fx_frida_target_name", targetName);
        outState.putStringArrayList("fx_frida_selected_pids",
                new ArrayList<>(selectedProcessPids));
        if (gadgetLoadMode != null) {
            int checkedId = gadgetLoadMode.getCheckedRadioButtonId();
            int checkedIndex = 0;
            for (int i = 0; i < gadgetLoadMode.getChildCount(); i++) {
                if (gadgetLoadMode.getChildAt(i).getId() == checkedId) {
                    checkedIndex = i;
                    break;
                }
            }
            outState.putInt("fx_frida_gadget_load_mode", checkedIndex);
        }
        if (status != null) outState.putString("fx_frida_status", status.getText().toString());
    }

    private org.json.JSONObject readFridaScriptLibrary() throws Exception {
        return FxDiaScriptLibraryStore.read(this);
    }

    private void writeFridaScriptLibrary(org.json.JSONObject scripts) throws Exception {
        FxDiaScriptLibraryStore.replaceAll(this, scripts);
    }

    private void saveCurrentFridaScript() {
        String source = script == null || script.getText() == null
                ? "" : script.getText().toString();
        if (source.trim().isEmpty()) {
            setStatus("当前 Frida 脚本为空，未保存。");
            return;
        }
        if (source.getBytes(StandardCharsets.UTF_8).length > 128 * 1024) {
            setStatus("单个 Frida 脚本不能超过 128 KiB。");
            return;
        }
        EditText name = new EditText(this);
        name.setSingleLine(true);
        name.setHint("脚本名称，例如 HTTP 连接观察");
        new AlertDialog.Builder(this).setTitle("保存 Frida 脚本")
                .setMessage("脚本保存在 FX 本机应用偏好中，不会自动注入目标应用。")
                .setView(name)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) -> {
                    String label = name.getText() == null ? "" : name.getText().toString().trim();
                    if (label.isEmpty() || label.length() > 64 || label.indexOf('|') >= 0) {
                        setStatus("脚本名称不能为空，且不能超过 64 个字符。");
                        return;
                    }
                    try {
                        FxDiaScriptLibraryStore.save(this, label, source);
                        setStatus("Frida 脚本已保存到本地脚本库：" + label);
                    } catch (Exception error) {
                        setStatus("保存脚本失败：" + error.getMessage());
                    }
                }).show();
    }


    private void openFullScreenCodeEditor() {
        String source = script == null || script.getText() == null
                ? "" : script.getText().toString();
        if (source.getBytes(StandardCharsets.UTF_8).length > MAX_FRIDA_SOURCE_BYTES) {
            setStatus("当前 Frida 脚本超过 48 KiB，无法送入全屏编辑器。");
            return;
        }
        Intent intent = new Intent(this, FxDiaCodeEditorActivity.class);
        intent.putExtra(FxDiaCodeEditorActivity.EXTRA_CODE, source);
        intent.putExtra(FxDiaCodeEditorActivity.EXTRA_LANGUAGE, "javascript");
        try {
            startActivityForResult(intent, REQUEST_CODE_FULL_EDITOR);
            setStatus("已打开 Dia 全屏代码编辑器；代码只有在保存返回后才会更新到当前脚本。");
        } catch (Exception error) {
            setStatus("无法打开全屏代码编辑器：" + error.getClass().getSimpleName());
        }
    }

    private void showFridaScriptLibrary() {
        final org.json.JSONObject scripts;
        try {
            scripts = readFridaScriptLibrary();
        } catch (Exception error) {
            setStatus("读取 Frida 脚本库失败：" + error.getMessage());
            return;
        }
        List<String> names = new ArrayList<>();
        java.util.Iterator<String> iterator = scripts.keys();
        while (iterator.hasNext()) names.add(iterator.next());
        java.util.Collections.sort(names, String.CASE_INSENSITIVE_ORDER);
        if (names.isEmpty()) {
            new AlertDialog.Builder(this).setTitle("Frida 脚本库")
                    .setMessage("本机还没有保存 Frida 脚本。可从 Dia 示例载入后保存，或批量导入 JSON。")
                    .setPositiveButton("关闭", null).show();
            return;
        }
        final int[] selected = {0};
        new AlertDialog.Builder(this).setTitle("Frida 脚本库 · " + names.size() + " 个")
                .setSingleChoiceItems(names.toArray(new String[0]), 0,
                        (dialog, which) -> selected[0] = which)
                .setPositiveButton("载入", (dialog, which) -> {
                    String name = names.get(selected[0]);
                    script.setText(scripts.optString(name, ""));
                    setStatus("已载入 Frida 脚本：" + name + "。尚未执行。");
                })
                .setNeutralButton("删除所选", (dialog, which) -> {
                    String name = names.get(selected[0]);
                    new AlertDialog.Builder(this).setTitle("删除本地 Frida 脚本")
                            .setMessage("确认删除“" + name + "”？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除", (d, w) -> {
                                try {
                                    FxDiaScriptLibraryStore.delete(this, name);
                                    setStatus("已从本地脚本库删除：" + name);
                                } catch (Exception error) {
                                    setStatus("删除脚本失败：" + error.getMessage());
                                }
                            }).show();
                })
                .setNegativeButton("关闭", null).show();
    }

    private String buildFridaScriptLibraryJson() throws Exception {
        return FxDiaScriptLibraryStore.exportJson(this);
    }

    private void exportFridaScriptLibrary() {
        File staged = null;
        try {
            staged = stagePendingFridaLibraryExport(buildFridaScriptLibraryJson());
            pendingFridaLibraryExportFileName = staged.getName();
            Intent create = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            create.addCategory(Intent.CATEGORY_OPENABLE);
            create.setType("application/json");
            String stamp = new java.text.SimpleDateFormat("yyyyMMdd-HHmmss", Locale.ROOT)
                    .format(new java.util.Date());
            create.putExtra(Intent.EXTRA_TITLE, "FX-Dia-Frida-Scripts-" + stamp + ".json");
            startActivityForResult(create, REQUEST_EXPORT_LIBRARY);
            setStatus("脚本库已安全暂存；请在系统文件选择器中选择保存位置。");
        } catch (Throwable error) {
            String failedName = pendingFridaLibraryExportFileName;
            pendingFridaLibraryExportFileName = null;
            if (staged != null) {
                //noinspection ResultOfMethodCallIgnored
                staged.delete();
            }
            deletePendingFridaLibraryExport(failedName);
            setStatus("无法准备脚本库导出：" + error.getClass().getSimpleName()
                    + (error.getMessage() == null ? "" : "：" + error.getMessage()));
        }
    }

    private void copyFridaScriptLibraryJson() {
        try {
            String json = buildFridaScriptLibraryJson();
            android.content.ClipboardManager clipboard =
                    (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (clipboard == null) {
                setStatus("系统剪贴板不可用。");
                return;
            }
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("FX Dia Frida scripts", json));
            setStatus("Frida 脚本库 JSON 已复制到剪贴板。");
        } catch (Exception error) {
            setStatus("复制脚本库 JSON 失败：" + error.getMessage());
        }
    }

    private void importFridaScriptLibrary() {
        Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        pick.addCategory(Intent.CATEGORY_OPENABLE);
        pick.setType("application/json");
        try {
            startActivityForResult(pick, REQUEST_IMPORT_LIBRARY);
        } catch (Throwable error) {
            setStatus("无法打开脚本库 JSON 文件选择器：" + error.getClass().getSimpleName());
        }
    }

    private void importFridaScriptLibraryFromClipboard() {
        EditText input = new EditText(this);
        input.setGravity(Gravity.TOP | Gravity.START);
        input.setMinLines(8);
        input.setHint("{\"schema\":\"FX-DIA-FRIDA-SCRIPTS-1\",\"scripts\":{\"demo\":\"console.log('hello')\"}}");
        new AlertDialog.Builder(this).setTitle("从剪贴板 JSON 导入 Frida 脚本库")
                .setMessage("只导入 JSON 中的脚本源码，不会自动执行。重复名称将覆盖本机同名脚本。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("验证并导入", (dialog, which) -> {
                    try {
                        mergeFridaScriptLibraryJson(input.getText().toString());
                        showFridaScriptLibrary();
                    } catch (Exception error) {
                        setStatus("导入脚本库失败：" + error.getMessage());
                    }
                }).show();
    }

    private void importFridaScriptLibraryFile(Uri uri) {
        setStatus("正在读取 Frida 脚本库 JSON…");
        submitWorker(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri);
                 java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选 JSON 文件。");
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() > MAX_LIBRARY_JSON_BYTES - count)
                        throw new IllegalArgumentException("Frida 脚本库 JSON 超过 1 MiB。");
                    output.write(buffer, 0, count);
                }
                String json = new String(output.toByteArray(), StandardCharsets.UTF_8);
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    try {
                        int countScripts = mergeFridaScriptLibraryJson(json);
                        setStatus("已从文件导入 " + countScripts + " 个 Frida 脚本。");
                        showFridaScriptLibrary();
                    } catch (Exception error) {
                        setStatus("导入 Frida 脚本库文件失败：" + error.getMessage());
                    }
                });
            } catch (Throwable error) {
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed())
                        setStatus("读取 Frida 脚本库文件失败：" + error.getClass().getSimpleName()
                                + (error.getMessage() == null ? "" : "：" + error.getMessage()));
                });
            }
        });
    }

    private int mergeFridaScriptLibraryJson(String json) throws Exception {
        return FxDiaScriptLibraryStore.mergeImport(this, json);
    }

    private void pickScript() {
        Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        pick.addCategory(Intent.CATEGORY_OPENABLE);
        pick.setType("text/*");
        try { startActivityForResult(pick, 7103); }
        catch (Throwable error) { setStatus("无法打开 JS 文件选择器：" + error.getClass().getSimpleName()); }
    }

    private void saveScript() {
        Intent create = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        create.addCategory(Intent.CATEGORY_OPENABLE);
        create.setType("text/javascript");
        create.putExtra(Intent.EXTRA_TITLE, "dia-frida-script.js");
        try { startActivityForResult(create, 7104); }
        catch (Throwable error) { setStatus("无法创建 JS 文件：" + error.getClass().getSimpleName()); }
    }

    private void importScript(Uri uri) {
        setStatus("正在导入 JS 脚本…");
        submitWorker(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri);
                 java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取脚本文件。");
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() > 512 * 1024 - count)
                        throw new IllegalArgumentException("脚本超过 512 KiB 限制。");
                    output.write(buffer, 0, count);
                }
                String source = new String(output.toByteArray(), StandardCharsets.UTF_8);
                if (source.trim().isEmpty()) throw new IllegalArgumentException("脚本内容为空。");
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    script.setText(source);
                    setStatus("JS 脚本已导入；未自动执行。请检查目标应用和脚本内容后再手动注入。");
                });
            } catch (Throwable error) {
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed())
                        setStatus("JS 脚本导入失败：" + error.getClass().getSimpleName()
                                + (error.getMessage() == null ? "" : "：" + error.getMessage()));
                });
            }
        });
    }

    private void exportScript(Uri uri) {
        String source = script == null ? "" : script.getText().toString();
        if (source.isEmpty()) { setStatus("当前没有可导出的 JS 脚本。"); return; }
        if (source.getBytes(StandardCharsets.UTF_8).length > 512 * 1024) {
            setStatus("脚本超过 512 KiB 限制，无法导出。");
            return;
        }
        submitWorker(() -> {
            try (java.io.OutputStream output = getContentResolver().openOutputStream(uri, "w")) {
                if (output == null) throw new IllegalStateException("无法创建目标文件。");
                output.write(source.getBytes(StandardCharsets.UTF_8));
                output.flush();
                runOnUiThread(() -> setStatus("当前 JS 脚本已导出。"));
            } catch (Throwable error) {
                runOnUiThread(() -> setStatus("JS 脚本导出失败：" + error.getClass().getSimpleName()
                        + (error.getMessage() == null ? "" : "：" + error.getMessage())));
            }
        });
    }

    private void pickBinary(int requestCode) {
        Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        pick.addCategory(Intent.CATEGORY_OPENABLE);
        pick.setType("*/*");
        try {
            startActivityForResult(pick, requestCode);
        } catch (Throwable error) {
            setStatus("无法打开系统文件选择器：" + error.getClass().getSimpleName());
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_CODE_FULL_EDITOR) {
            if (resultCode == FxDiaCodeEditorActivity.RESULT_CODE_EDITOR && data != null) {
                String editedSource = data.getStringExtra(FxDiaCodeEditorActivity.EXTRA_CODE);
                if (editedSource == null) {
                    setStatus("全屏编辑器返回的代码为空，当前脚本未更改。");
                } else if (editedSource.getBytes(StandardCharsets.UTF_8).length > MAX_FRIDA_SOURCE_BYTES) {
                    setStatus("返回代码超过 48 KiB，当前脚本未更改。");
                } else if (script != null) {
                    script.setText(editedSource);
                    setStatus("全屏编辑器内容已回传；尚未执行或注入。");
                }
            } else {
                setStatus("全屏编辑器未保存，当前 Frida 脚本保持不变。");
            }
            return;
        }
        if (requestCode == REQUEST_EXPORT_LIBRARY) {
            String stagedName = pendingFridaLibraryExportFileName;
            pendingFridaLibraryExportFileName = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                deletePendingFridaLibraryExport(stagedName);
                if (!isFinishing() && !isDestroyed()) setStatus("已取消 Frida 脚本库文件导出。");
                return;
            }
            final File staged;
            try {
                staged = resolvePendingFridaLibraryExport(stagedName);
            } catch (Exception invalidPending) {
                deletePendingFridaLibraryExport(stagedName);
                setStatus("Frida 脚本库暂存文件已失效，请重新导出。");
                return;
            }
            Uri destination = data.getData();
            submitWorker(() -> {
                String resultMessage;
                try (InputStream input = new java.io.FileInputStream(staged);
                     OutputStream output = getContentResolver().openOutputStream(destination, "w")) {
                    if (output == null) throw new IllegalStateException("无法写入所选 JSON 文件。");
                    byte[] buffer = new byte[8192];
                    int count;
                    long total = 0;
                    while ((count = input.read(buffer)) != -1) {
                        total += count;
                        if (total > MAX_LIBRARY_JSON_BYTES)
                            throw new IllegalStateException("Frida 脚本库 JSON 超过 1 MiB。");
                        output.write(buffer, 0, count);
                    }
                    output.flush();
                    resultMessage = "Frida 脚本库 JSON 文件已导出。";
                } catch (Throwable error) {
                    resultMessage = "Frida 脚本库导出失败：" + error.getClass().getSimpleName()
                            + (error.getMessage() == null ? "" : "：" + error.getMessage());
                } finally {
                    //noinspection ResultOfMethodCallIgnored
                    staged.delete();
                }
                String message = resultMessage;
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed()) setStatus(message);
                });
            });
            return;
        }
        if (requestCode == REQUEST_IMPORT_LIBRARY) {
            if (resultCode == RESULT_OK && data != null && data.getData() != null)
                importFridaScriptLibraryFile(data.getData());
            else if (!isFinishing() && !isDestroyed())
                setStatus("已取消 Frida 脚本库文件导入。");
            return;
        }
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
        if (requestCode == 7101 || requestCode == 7102) {
            importBinary(data.getData(), requestCode == 7101);
        } else if (requestCode == 7103) {
            importScript(data.getData());
        } else if (requestCode == 7104) {
            exportScript(data.getData());
        }
    }

    private void importBinary(Uri uri, boolean server) {
        final String label = server ? "Frida Server" : "Frida Inject";
        final long maxBytes = server ? 150L * 1024L * 1024L : 80L * 1024L * 1024L;
        setStatus("正在读取并校验 " + label + " 文件…");
        submitWorker(() -> {
            File staging = new File(getFilesDir(), "frida-import");
            File source = null;
            try {
                if (java.nio.file.Files.isSymbolicLink(staging.toPath()))
                    throw new IllegalStateException("Frida 私有导入目录不能是符号链接。");
                if (!staging.isDirectory() && !staging.mkdirs())
                    throw new IllegalStateException("无法创建 FX 私有导入目录。");
                if (java.nio.file.Files.isSymbolicLink(staging.toPath()) || !staging.isDirectory())
                    throw new IllegalStateException("Frida 私有导入目录状态异常。");
                source = File.createTempFile(server ? "server-" : "inject-", ".upload", staging);
                if (java.nio.file.Files.isSymbolicLink(source.toPath()))
                    throw new IllegalStateException("Frida 导入暂存文件不能是符号链接。");

                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                byte[] header = new byte[20];
                int headerCount = 0;
                long total = 0;
                InputStream opened = getContentResolver().openInputStream(uri);
                if (opened == null) throw new IllegalStateException("无法读取所选文件。");
                try (InputStream input = new BufferedInputStream(opened);
                     FileOutputStream output = new FileOutputStream(source, false)) {
                    byte[] buffer = new byte[32768];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        if (total > maxBytes - count)
                            throw new IllegalStateException("文件超过 " + (maxBytes / 1024 / 1024) + " MiB 限制。");
                        int copy = Math.min(count, header.length - headerCount);
                        if (copy > 0) {
                            System.arraycopy(buffer, 0, header, headerCount, copy);
                            headerCount += copy;
                        }
                        digest.update(buffer, 0, count);
                        output.write(buffer, 0, count);
                        total += count;
                    }
                    output.getFD().sync();
                }
                if (total < 20 || headerCount < 20
                        || header[0] != 0x7f || header[1] != 'E'
                        || header[2] != 'L' || header[3] != 'F'
                        || header[4] != 2 || header[5] != 1
                        || (header[18] & 0xff) != 0xb7 || header[19] != 0) {
                    throw new IllegalArgumentException(
                            "文件不是未压缩的 ELF64 little-endian ARM64 可执行文件；请先解压 .xz/.zip 文件。");
                }
                String sha = hexDigest(digest.digest());
                String destination = server
                        ? "/data/local/tmp/fx-frida/fx-frida-server"
                        : "/data/local/tmp/fx-frida/fx-frida-inject";
                String sourcePath = source.getCanonicalPath();
                if (!source.isFile() || !source.canRead()
                        || java.nio.file.Files.isSymbolicLink(source.toPath())) {
                    throw new IllegalStateException("Frida 私有导入暂存文件不可读或路径异常。");
                }
                String command = "set -eu; d=/data/local/tmp/fx-frida; "
                        + "if [ -L /data/local/tmp/fx-frida ]; then echo unsafe-destination; exit 71; fi; "
                        + "mkdir -p \"$d\"; test -d \"$d\" && test ! -L \"$d\"; "
                        + "src=" + quote(sourcePath) + "; dst=" + quote(destination) + "; "
                        + "test -f \"$src\" && test ! -L \"$src\"; "
                        + "if [ -L \"$dst\" ] || { [ -e \"$dst\" ] && [ ! -f \"$dst\" ]; }; then echo unsafe-existing-destination; exit 73; fi; "
                        + "lock=\"$dst.fx-import.lock\"; lock_held=0; lock_wait=0; tmp=; "
                        + "cleanup_import() { "
                        + "[ -z \"$tmp\" ] || rm -f \"$tmp\" 2>/dev/null || :; "
                        + "if [ \"$lock_held\" = 1 ]; then "
                        + "owner=$(cat \"$lock\" 2>/dev/null || :); "
                        + "if [ \"$owner\" = \"$$\" ]; then "
                        + "release=\"$lock.release.$$\"; release_try=0; "
                        + "while { [ -e \"$release\" ] || [ -L \"$release\" ]; } && [ \"$release_try\" -lt 20 ]; do "
                        + "release_try=$((release_try+1)); release=\"$lock.release.$$.$release_try\"; done; "
                        + "if [ ! -e \"$release\" ] && [ ! -L \"$release\" ] && mv \"$lock\" \"$release\" 2>/dev/null; then "
                        + "release_owner=$(cat \"$release\" 2>/dev/null || :); "
                        + "if [ \"$release_owner\" = \"$$\" ]; then rm -f \"$release\" 2>/dev/null || :; fi; "
                        + "fi; fi; fi; }; "
                        + "trap cleanup_import 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                        + "while :; do "
                        + "if [ ! -L \"$lock\" ] && [ ! -e \"$lock\" ]; then "
                        + "if ( umask 077; set -C; printf '%s\\n' \"$$\" > \"$lock\" ) 2>/dev/null; then lock_held=1; break; fi; fi; "
                        + "[ ! -L \"$lock\" ] || { echo unsafe-import-lock; exit 74; }; "
                        + "owner=$(cat \"$lock\" 2>/dev/null || :); "
                        + "case \"$owner\" in ''|*[!0-9]*) : ;; *) "
                        + "if ! kill -0 \"$owner\" 2>/dev/null; then "
                        + "owner_again=$(cat \"$lock\" 2>/dev/null || :); "
                        + "if [ \"$owner_again\" = \"$owner\" ] && ! kill -0 \"$owner_again\" 2>/dev/null; then "
                        + "stale=\"$lock.stale.$$.$lock_wait\"; "
                        + "if [ ! -e \"$stale\" ] && [ ! -L \"$stale\" ] && mv \"$lock\" \"$stale\" 2>/dev/null; then "
                        + "stale_owner=$(cat \"$stale\" 2>/dev/null || :); "
                        + "if [ \"$stale_owner\" = \"$owner\" ] && ! kill -0 \"$stale_owner\" 2>/dev/null; then rm -f \"$stale\" 2>/dev/null || :; "
                        + "elif [ ! -e \"$lock\" ] && [ ! -L \"$lock\" ]; then mv \"$stale\" \"$lock\" 2>/dev/null || :; fi; "
                        + "fi; fi; fi ;; esac; "
                        + "lock_wait=$((lock_wait+1)); "
                        + "[ \"$lock_wait\" -lt 300 ] || { echo frida-import-lock-timeout; exit 75; }; sleep 0.1; done; "
                        + "umask 077; tmp=$(mktemp \"$d/.fx-frida-import.XXXXXX\"); "
                        + "[ -n \"$tmp\" ] && [ -f \"$tmp\" ] && [ ! -L \"$tmp\" ]; "
                        + "cp \"$src\" \"$tmp\"; chmod 0700 \"$tmp\"; "
                        + "actual=$(sha256sum \"$tmp\" | awk '{print $1}'); "
                        + "[ \"$actual\" = " + quote(sha) + " ] || { echo frida-import-hash-mismatch; exit 72; }; "
                        + "mv -f \"$tmp\" \"$dst\"; tmp=; "
                        + "test -f \"$dst\" && test ! -L \"$dst\"; chmod 0700 \"$dst\"; sync; "
                        + "actual=$(sha256sum \"$dst\" | awk '{print $1}'); "
                        + "[ \"$actual\" = " + quote(sha) + " ]; test -x \"$dst\"; "
                        + "printf 'installed=%s\\nsha256=%s\\nbytes=%s\\n' \"$dst\" \"$actual\" " + total;
                RootAccess.Result result = RootAccess.execute(command, 60000L, 256 * 1024);
                if (result.exitCode != 0)
                    throw new IllegalStateException("Root 安装失败（退出码 " + result.exitCode + "）："
                            + (result.output == null ? "" : result.output.trim()));
                getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                        .putString(server ? "server_path" : "injector_path", destination)
                        .putString(server ? "server_sha256" : "injector_sha256", sha)
                        .putLong(server ? "server_bytes" : "injector_bytes", total)
                        .apply();
                String successMessage = label + " 已导入并校验。\\nSHA-256：" + sha
                        + "\\n大小：" + total + " bytes\\n" + result.output;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    (server ? serverPath : injectorPath).setText(destination);
                    setStatus(successMessage);
                });
            } catch (Throwable error) {
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed())
                        setStatus(label + " 导入失败：" + error.getClass().getSimpleName()
                                + (error.getMessage() == null ? "" : "：" + error.getMessage()));
                });
            } finally {
                if (source != null) {
                    //noinspection ResultOfMethodCallIgnored
                    source.delete();
                }
            }
        });
    }

    private String hexDigest(byte[] bytes) {
        StringBuilder value = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) value.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        return value.toString();
    }

    private void savePaths() {
        String server = currentServerPath();
        String injector = currentInjectorPath();
        String cli = currentFridaCliPath();
        if (!validPath(server) || !validPath(injector)
                || (!cli.isEmpty() && !validPath(cli))) {
            setStatus("路径无效：必须是绝对路径，且不能包含空白字符或 ..。");
            return;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString("server_path", server)
                .putString("injector_path", injector)
                .putString("frida_cli_path", cli).apply();
        setStatus("Frida 工具路径已保存；远程 Gadget CLI " + (cli.isEmpty() ? "尚未配置。" : "已配置。"));
    }

    private String pathCommand(String value, String label) {
        return "test -x " + quote(value) + " && echo " + quote(label + "=ready")
                + " || { echo " + quote(label + "=missing") + "; exit 3; }";
    }

    private void checkRuntime() {
        String server = currentServerPath();
        String injector = currentInjectorPath();
        String cli = currentFridaCliPath();
        if (!validPath(server) || !validPath(injector)
                || (!cli.isEmpty() && !validPath(cli))) {
            setStatus("请先填写有效的 frida-server / frida-inject 路径；可选 frida CLI 路径也必须有效。");
            return;
        }
        String command = pathCommand(server, "frida-server") + "; "
                + pathCommand(injector, "frida-inject") + "; "
                + (cli.isEmpty()
                    ? "echo frida-cli=not-configured; "
                    : pathCommand(cli, "frida-cli") + "; " + quote(cli) + " --version; ")
                + "server=" + quote(server) + "; pidfile=" + quote(SERVER_PID) + "; "
                + serverProcessGuards()
                + "if [ -L \"$pidfile\" ]; then echo server=unsafe-pidfile; "
                + "elif [ -f \"$pidfile\" ]; then "
                + "pid=$(sed -n '1p' \"$pidfile\"); stored_server=$(sed -n '2p' \"$pidfile\"); "
                + "stored_port=$(sed -n '3p' \"$pidfile\"); stored_start=$(sed -n '4p' \"$pidfile\"); "
                + "case \"$pid\" in ''|*[!0-9]*) echo server=invalid-pid-record;; "
                + "*) if [ \"$stored_server\" != \"$server\" ] || [ \"$stored_port\" != 27042 ]; then echo server=pid-record-conflict; "
                + "elif server_pid_live \"$pid\"; then "
                + "case \"$stored_start\" in ''|*[!0-9]*) echo server=legacy-owner-unverified;; "
                + "*) current_start=$(server_pid_starttime \"$pid\" 2>/dev/null || :); "
                + "if [ \"$current_start\" != \"$stored_start\" ]; then echo server=pid-reused; "
                + "elif server_pid_matches \"$pid\"; then echo server=running; "
                + "else echo server=pid-conflict; fi;; esac; "
                + "else echo server=stale-pid; fi;; esac; "
                + "else echo server=stopped; fi";
        runRoot(command, 12000L, result ->
                setStatus("退出码 " + result.exitCode + "\n" + result.output));
    }

        private String serverProcessGuards() {
        return "server_pid_live() { "
                + "fx_server_pid=\"$1\"; case \"$fx_server_pid\" in ''|*[!0-9]*) return 1;; esac; "
                + "[ -r \"/proc/$fx_server_pid/stat\" ] || return 1; "
                + "state=$(sed 's/^.*) //' \"/proc/$fx_server_pid/stat\" 2>/dev/null | cut -d ' ' -f1); "
                + "case \"$state\" in Z|X|x) return 1;; esac; "
                + "kill -0 \"$fx_server_pid\" 2>/dev/null; }; "
                + "server_pid_starttime() { "
                + "fx_server_pid=\"$1\"; case \"$fx_server_pid\" in ''|*[!0-9]*) return 1;; esac; "
                + "fields=$(sed 's/^.*) //' \"/proc/$fx_server_pid/stat\" 2>/dev/null) || return 1; "
                + "start=$(printf '%s\\n' \"$fields\" | awk '{print $20}'); "
                + "case \"$start\" in ''|*[!0-9]*) return 1;; esac; printf '%s\\n' \"$start\"; }; "
                + "server_pid_matches() { "
                + "fx_server_pid=\"$1\"; server_pid_live \"$fx_server_pid\" || return 1; "
                + "[ -r \"/proc/$fx_server_pid/cmdline\" ] || return 1; "
                + "[ \"$(tr '\\000' '\\n' < \"/proc/$fx_server_pid/cmdline\" 2>/dev/null | sed -n '1p')\" = \"$server\" ] && "
                + "[ \"$(tr '\\000' '\\n' < \"/proc/$fx_server_pid/cmdline\" 2>/dev/null | sed -n '2p')\" = \"-l\" ] && "
                + "[ \"$(tr '\\000' '\\n' < \"/proc/$fx_server_pid/cmdline\" 2>/dev/null | sed -n '3p')\" = \"127.0.0.1:27042\" ]; }; ";
    }

        private void startServer() {
        String server = currentServerPath();
        if (!validPath(server)) {
            setStatus("frida-server 路径无效。");
            return;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("server_path", server).apply();
        String command = "set -eu; umask 077; "
                + "server=" + quote(server) + "; state=/data/adb/privacyguard; "
                + "pidfile=" + quote(SERVER_PID) + "; log=\"$state/dia-frida-server.log\"; "
                + "lock=\"$state/.dia-frida-server.lock\"; "
                + "mkdir -p \"$state\"; test -d \"$state\" && test ! -L \"$state\"; chmod 700 \"$state\"; "
                + "[ ! -L \"$pidfile\" ] && [ ! -L \"$lock\" ] && [ ! -L \"$log\" ] || { echo FX_FRIDA_UNSAFE_STATE; exit 21; }; "
                + "mkdir \"$lock\" 2>/dev/null || { echo FX_FRIDA_SERVER_START_BUSY; exit 10; }; "
                + "tmp=; spawned_pid=; spawned_start=; "
                + "cleanup_start() { [ -z \"$tmp\" ] || rm -f \"$tmp\"; "
                + "if [ -n \"$spawned_pid\" ] && [ -n \"$spawned_start\" ] "
                + "&& [ \"$(server_pid_starttime \"$spawned_pid\" 2>/dev/null || :)\" = \"$spawned_start\" ] "
                + "&& server_pid_matches \"$spawned_pid\"; then kill -TERM \"$spawned_pid\" 2>/dev/null || :; fi; "
                + "rmdir \"$lock\" 2>/dev/null || :; }; "
                + "trap cleanup_start 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "test -x \"$server\" && test ! -L \"$server\" || { echo FX_FRIDA_SERVER_PATH_INVALID; exit 20; }; "
                + serverProcessGuards()
                + "if [ -e \"$pidfile\" ]; then "
                + "[ -f \"$pidfile\" ] && [ ! -L \"$pidfile\" ] || { echo FX_FRIDA_PID_RECORD_UNSAFE; exit 22; }; "
                + "old_pid=$(sed -n '1p' \"$pidfile\"); old_server=$(sed -n '2p' \"$pidfile\"); "
                + "old_port=$(sed -n '3p' \"$pidfile\"); old_start=$(sed -n '4p' \"$pidfile\"); "
                + "case \"$old_pid\" in ''|*[!0-9]*) echo FX_FRIDA_PID_RECORD_INVALID; exit 22;; esac; "
                + "[ \"$old_server\" = \"$server\" ] && [ \"$old_port\" = 27042 ] || { echo FX_FRIDA_PID_RECORD_CONFLICT; exit 23; }; "
                + "if server_pid_live \"$old_pid\"; then "
                + "case \"$old_start\" in ''|*[!0-9]*) echo FX_FRIDA_PID_RECORD_LEGACY_UNVERIFIED; exit 24;; esac; "
                + "current_start=$(server_pid_starttime \"$old_pid\" 2>/dev/null || :); "
                + "[ \"$current_start\" = \"$old_start\" ] || { echo FX_FRIDA_PID_REUSED; exit 25; }; "
                + "server_pid_matches \"$old_pid\" || { echo FX_FRIDA_PID_OWNER_CONFLICT; exit 24; }; "
                + "echo server=already-running pid=$old_pid; exit 0; "
                + "fi; rm -f \"$pidfile\"; fi; "
                + "existing_pids=$(ps -A -o PID 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | "
                + "while IFS= read -r candidate; do if server_pid_matches \"$candidate\"; then printf '%s\\n' \"$candidate\"; fi; done); "
                + "if [ -n \"$existing_pids\" ]; then echo server=already-running-unmanaged; echo pids=\"$existing_pids\"; exit 0; fi; "
                + "tmp=$(mktemp \"$state/.dia-frida-server.pid.XXXXXX\"); [ -f \"$tmp\" ] && [ ! -L \"$tmp\" ]; "
                + "nohup \"$server\" -l 127.0.0.1:27042 >> \"$log\" 2>&1 </dev/null & pid=$!; spawned_pid=$pid; "
                + "spawned_start=$(server_pid_starttime \"$pid\" 2>/dev/null || :); "
                + "case \"$spawned_start\" in ''|*[!0-9]*) echo FX_FRIDA_SERVER_STARTTIME_UNAVAILABLE; exit 25;; esac; "
                + "printf '%s\\n%s\\n%s\\n%s\\n' \"$pid\" \"$server\" 27042 \"$spawned_start\" > \"$tmp\"; chmod 600 \"$tmp\"; "
                + "mv -f \"$tmp\" \"$pidfile\"; tmp=; sleep 1; "
                + "current_start=$(server_pid_starttime \"$pid\" 2>/dev/null || :); "
                + "[ \"$current_start\" = \"$spawned_start\" ] && server_pid_matches \"$pid\" || { "
                + "echo FX_FRIDA_SERVER_START_FAILED; exit 25; }; "
                + "spawned_pid=; spawned_start=; echo server=started pid=$pid;";
        runRoot(command, 20000L, result ->
                setStatus("启动退出码 " + result.exitCode + "\n" + result.output));
    }

        private void stopServer() {
        String command = "set -eu; umask 077; state=/data/adb/privacyguard; "
                + "pidfile=" + quote(SERVER_PID) + "; lock=\"$state/.dia-frida-server.lock\"; "
                + "mkdir -p \"$state\"; test -d \"$state\" && test ! -L \"$state\"; "
                + "[ ! -L \"$pidfile\" ] && [ ! -L \"$lock\" ] || { echo FX_FRIDA_UNSAFE_STATE; exit 21; }; "
                + "mkdir \"$lock\" 2>/dev/null || { echo FX_FRIDA_SERVER_STOP_BUSY; exit 10; }; "
                + "cleanup_stop() { rmdir \"$lock\" 2>/dev/null || :; }; "
                + "trap cleanup_stop 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "if [ ! -e \"$pidfile\" ]; then echo no-fx-owned-server; exit 0; fi; "
                + "[ -f \"$pidfile\" ] && [ ! -L \"$pidfile\" ] || { echo FX_FRIDA_PID_RECORD_UNSAFE; exit 22; }; "
                + "pid=$(sed -n '1p' \"$pidfile\"); server=$(sed -n '2p' \"$pidfile\"); "
                + "port=$(sed -n '3p' \"$pidfile\"); expected_start=$(sed -n '4p' \"$pidfile\"); "
                + "case \"$pid\" in ''|*[!0-9]*) echo FX_FRIDA_PID_RECORD_INVALID; exit 22;; esac; "
                + "case \"$server\" in /*) ;; *) echo FX_FRIDA_PID_RECORD_INVALID; exit 22;; esac; "
                + "case \"$server\" in *[!A-Za-z0-9_./-]*|*..*) echo FX_FRIDA_PID_RECORD_INVALID; exit 22;; esac; "
                + "[ \"$port\" = 27042 ] || { echo FX_FRIDA_PID_RECORD_INVALID; exit 22; }; "
                + "case \"$expected_start\" in ''|*[!0-9]*) echo FX_FRIDA_PID_RECORD_LEGACY_UNVERIFIED; exit 24;; esac; "
                + serverProcessGuards()
                + "if server_pid_live \"$pid\"; then "
                + "actual_start=$(server_pid_starttime \"$pid\" 2>/dev/null || :); "
                + "[ \"$actual_start\" = \"$expected_start\" ] || { echo FX_FRIDA_PID_REUSED; exit 25; }; "
                + "server_pid_matches \"$pid\" || { echo FX_FRIDA_PID_OWNER_CONFLICT; exit 23; }; "
                + "kill -TERM \"$pid\" 2>/dev/null || { echo FX_FRIDA_SERVER_STOP_SIGNAL_FAILED; exit 24; }; "
                + "_wait=0; while server_pid_live \"$pid\"; do "
                + "actual_start=$(server_pid_starttime \"$pid\" 2>/dev/null || :); "
                + "[ \"$actual_start\" = \"$expected_start\" ] || { echo FX_FRIDA_PID_REUSED; exit 25; }; "
                + "server_pid_matches \"$pid\" || { echo FX_FRIDA_PID_REUSED; exit 25; }; "
                + "[ \"$_wait\" -lt 50 ] || { echo FX_FRIDA_SERVER_STOP_TIMEOUT; exit 26; }; "
                + "sleep 0.1; _wait=$((_wait+1)); done; fi; "
                + "[ ! -L \"$pidfile\" ] && [ \"$(sed -n '1p' \"$pidfile\")\" = \"$pid\" ] "
                + "&& [ \"$(sed -n '4p' \"$pidfile\")\" = \"$expected_start\" ] || { echo FX_FRIDA_PID_RECORD_CHANGED; exit 27; }; "
                + "rm -f \"$pidfile\"; echo server=stopped";
        runRoot(command, 12000L, result ->
                setStatus("停止退出码 " + result.exitCode + "\n" + result.output));
    }

        private static final class Target {
        final String packageName, label;
        Target(String p, String l) { packageName = p; label = l; }
    }

    private void chooseTarget() {
        if (targetLoading) {
            setStatus("正在后台读取可调试应用列表…");
            return;
        }
        targetLoading = true;
        final int request = ++targetLoadGeneration;
        setStatus("正在后台读取可调试应用列表…");
        final PackageManager pm = getPackageManager();
        final String ownPackage = getPackageName();
        try {
            worker.execute(() -> {
                List<Target> targets = new ArrayList<>();
                String failure = null;
                try {
                    for (ApplicationInfo info : pm.getInstalledApplications(0)) {
                        if (Thread.currentThread().isInterrupted()) return;
                        if (info.packageName == null || info.packageName.equals(ownPackage)) continue;
                        if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0) continue;
                        if ((info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
                        String label;
                        try { label = String.valueOf(pm.getApplicationLabel(info)); }
                        catch (RuntimeException ignored) { label = info.packageName; }
                        targets.add(new Target(info.packageName, label));
                    }
                    targets.sort(Comparator.comparing(item -> item.label.toLowerCase(Locale.ROOT)));
                } catch (RuntimeException error) {
                    failure = error.getClass().getSimpleName();
                }
                if (Thread.currentThread().isInterrupted()) return;
                final String loadFailure = failure;
                final List<Target> result = targets;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed() || request != targetLoadGeneration) return;
                    targetLoading = false;
                    if (loadFailure != null) {
                        setStatus("读取可调试应用失败：" + loadFailure);
                        return;
                    }
                    showTargetPicker(result);
                });
            });
        } catch (RejectedExecutionException full) {
            targetLoading = false;
            setStatus("后台任务队列繁忙，应用列表未读取；请稍后重试。");
        }
    }

    private void showTargetPicker(List<Target> targets) {
        if (targets == null || targets.isEmpty()) {
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
                    monitorEventGeneration++;
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                            .putString("target_package", targetPackage)
                            .putString("target_name", targetName)
                            .apply();
                    selectedProcessPids.clear();
                    gadgetProcess.setText(targetPackage);
                    targetLabel.setText(targetName + "\\n" + targetPackage
                            + "\\nGadget 默认进程：" + targetPackage
                            + "\\nFrida-inject 进程：注入时自动枚举所有当前运行进程");
                }).setNegativeButton("取消", null).show();
    }

    private void chooseTargetProcesses() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        final int targetUid;
        try {
            ApplicationInfo targetInfo = getPackageManager().getApplicationInfo(targetPackage, 0);
            if ((targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                    || (targetInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                setStatus("目标应用已不再符合 debuggable 用户应用条件，拒绝枚举进程。");
                return;
            }
            targetUid = targetInfo.uid;
        } catch (Throwable missing) {
            setStatus("目标应用已卸载或不可用，拒绝枚举进程。");
            return;
        }
        String command = "pkg=" + quote(targetPackage) + "; uid=" + targetUid
                + "; ps -A -o PID,NAME 2>/dev/null | awk -v pkg=\"$pkg\" "
                + "'NR>1 && $1 ~ /^[0-9]+$/ && ($2==pkg || index($2,pkg \":\")==1) {print $1 \"|\" $2}'"
                + " | while IFS='|' read -r pid name; do "
                + "proc_uid=$(awk '$1==\"Uid:\" {print $2; exit}' \"/proc/$pid/status\" 2>/dev/null || :); "
                + "[ \"$proc_uid\" = \"$uid\" ] && printf '%s|%s\\n' \"$pid\" \"$name\"; done";
        runRoot(command, 15000L, result -> {
            if (result.exitCode != 0 || result.output == null) {
                setStatus("读取目标进程失败：" + result.output);
                return;
            }
            List<String> pids = new ArrayList<>();
            List<String> labels = new ArrayList<>();
            for (String line : result.output.split("\\r?\\n")) {
                String[] parts = line.trim().split("\\|", 2);
                if (parts.length != 2 || !parts[0].matches("[0-9]{1,10}")) continue;
                if (!parts[1].equals(targetPackage) && !parts[1].startsWith(targetPackage + ":")) continue;
                pids.add(parts[0]);
                labels.add(parts[1] + "  · PID " + parts[0]);
            }
            if (pids.isEmpty()) {
                selectedProcessPids.clear();
                setStatus("目标应用当前没有运行进程。启动目标应用后可重新选择；注入时也可自动枚举全部进程。");
                targetLabel.setText(targetName + "\\n" + targetPackage + "\\n当前没有运行进程");
                return;
            }
            boolean[] checked = new boolean[pids.size()];
            for (int i = 0; i < pids.size(); i++)
                checked[i] = selectedProcessPids.isEmpty() || selectedProcessPids.contains(pids.get(i));
            new AlertDialog.Builder(this).setTitle("选择目标进程（可多选）")
                    .setMultiChoiceItems(labels.toArray(new String[0]), checked,
                            (dialog, which, enabled) -> checked[which] = enabled)
                    .setNeutralButton("自动附加全部进程", (dialog, which) -> {
                        selectedProcessPids.clear();
                        targetLabel.setText(targetName + "\\n" + targetPackage
                                + "\\n进程：自动枚举全部运行进程");
                    })
                    .setNegativeButton("取消", null)
                    .setPositiveButton("保存进程选择", (dialog, which) -> {
                        selectedProcessPids.clear();
                        for (int i = 0; i < pids.size(); i++)
                            if (checked[i]) selectedProcessPids.add(pids.get(i));
                        if (selectedProcessPids.isEmpty()) {
                            targetLabel.setText(targetName + "\\n" + targetPackage
                                    + "\\n进程：未固定，注入时自动枚举全部运行进程");
                        } else {
                            targetLabel.setText(targetName + "\\n" + targetPackage
                                    + "\\n已选择进程数：" + selectedProcessPids.size());
                        }
                    }).show();
        });
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

    private void configureDialogRemoveTemplate() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        try {
            ApplicationInfo info = getPackageManager().getApplicationInfo(targetPackage, 0);
            if ((info.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                    || (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                setStatus("匹配弹窗移除只允许用户安装的 debuggable 自有测试应用。");
                return;
            }
        } catch (Throwable unavailable) {
            setStatus("目标应用已卸载或不可用，拒绝配置弹窗移除规则。");
            return;
        }

        android.content.SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(18), dp(6), dp(18), dp(4));

        TextView note = text(
                "仅检查目标应用新增到窗口根容器的 ViewGroup 子项。可使用 TextView 文本正则和资源 ID 匹配；规则为空时不生成可执行规则。每次最多 5 次移除、最多 1,500 个节点、深度 28、最多 64 个待检查根节点。",
                12, 0xff64748b, false);
        form.addView(note);

        EditText keywords = new EditText(this);
        keywords.setGravity(Gravity.TOP | Gravity.START);
        keywords.setMinLines(4);
        keywords.setMaxLines(7);
        keywords.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        keywords.setHint("每行一个 Java 正则，匹配 TextView 文本；最多 12 条\n例如：^(立即\u786e认|确定退出)$");
        keywords.setText(prefs.getString("dialog_remove_regex_rules", ""));
        form.addView(text("关键词正则", 13, 0xff334155, true));
        form.addView(keywords);

        EditText ids = new EditText(this);
        ids.setGravity(Gravity.TOP | Gravity.START);
        ids.setMinLines(3);
        ids.setMaxLines(6);
        ids.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        ids.setHint("每行一个 resourceEntryName 或十进制资源 ID；最多 12 条\n例如：dialog_confirm");
        ids.setText(prefs.getString("dialog_remove_resource_ids", ""));
        form.addView(text("资源 ID", 13, 0xff334155, true));
        form.addView(ids);

        android.widget.CheckBox broadScope = new android.widget.CheckBox(this);
        broadScope.setText("允许检查任意 ViewGroup 父容器（高风险）");
        broadScope.setChecked(false);
        broadScope.setPadding(0, dp(4), 0, dp(4));
        form.addView(broadScope);
        TextView scopeWarning = text(
                "默认只移除 DecorView / android.R.id.content 的直接子项。开启任意父容器会扩大删除范围，可能误删普通业务 UI；仅在隔离测试应用中使用。",
                12, 0xff9a3412, false);
        form.addView(scopeWarning);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Dia · 配置匹配弹窗移除")
                .setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("验证规则并载入脚本", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    List<String> regexRules = new ArrayList<>();
                    List<String> resourceRules = new ArrayList<>();
                    for (String line : keywords.getText().toString().split("\\r?\\n")) {
                        String value = line.trim();
                        if (value.isEmpty()) continue;
                        if (value.length() > 160 || regexRules.size() >= 12) {
                            setStatus("关键词规则每条最多 160 字符，最多 12 条；没有载入脚本。");
                            return;
                        }
                        try {
                            java.util.regex.Pattern.compile(value, java.util.regex.Pattern.CASE_INSENSITIVE);
                        } catch (java.util.regex.PatternSyntaxException invalid) {
                            setStatus("关键词正则无效：" + value + " · " + invalid.getDescription());
                            return;
                        }
                        if (!regexRules.contains(value)) regexRules.add(value);
                    }
                    for (String line : ids.getText().toString().split("\\r?\\n")) {
                        String value = line.trim();
                        if (value.isEmpty()) continue;
                        boolean namedId = value.matches("[A-Za-z_][A-Za-z0-9_]*");
                        boolean numericId = value.matches("[0-9]{1,10}");
                        if (value.length() > 160 || (!namedId && !numericId)
                                || resourceRules.size() >= 12) {
                            setStatus("资源 ID 只允许 resourceEntryName 或十进制资源 ID，最多 12 条；没有载入脚本。");
                            return;
                        }
                        if (!resourceRules.contains(value)) resourceRules.add(value);
                    }
                    if (regexRules.isEmpty() && resourceRules.isEmpty()) {
                        setStatus("至少填写一条关键词正则或资源 ID。规则留空时仅保留空白模板，不会执行移除。");
                        return;
                    }
                    Runnable applyRules = () -> {
                        try {
                            String template = readDiaTemplateAsset("dia/fx_dialog_remove_template.js");
                            org.json.JSONArray regexJson = new org.json.JSONArray();
                            for (String value : regexRules) regexJson.put(value);
                            org.json.JSONArray idJson = new org.json.JSONArray();
                            for (String value : resourceRules) idJson.put(value);
                            template = replaceExactlyOnce(template,
                                    "var ALERT_KEYWORD_PATTERNS = [];",
                                    "var ALERT_KEYWORD_PATTERNS = " + regexJson.toString() + ";");
                            template = replaceExactlyOnce(template,
                                    "var ALERT_VIEW_IDS = [];",
                                    "var ALERT_VIEW_IDS = " + idJson.toString() + ";");
                            template = replaceExactlyOnce(template,
                                    "var ALLOW_ANY_PARENT = false;",
                                    "var ALLOW_ANY_PARENT = " + broadScope.isChecked() + ";");
                            if (template.length() > MAX_FRIDA_SOURCE_BYTES) {
                                setStatus("生成的弹窗规则脚本超过 48 KiB，未载入。");
                                return;
                            }
                            boolean saved = prefs.edit()
                                    .putString("dialog_remove_regex_rules", String.join("\\n", regexRules))
                                    .putString("dialog_remove_resource_ids", String.join("\\n", resourceRules))
                                    .putBoolean("dialog_remove_any_parent", broadScope.isChecked())
                                    .commit();
                            if (!saved) {
                                setStatus("规则本地保存失败；脚本未载入。");
                                return;
                            }
                            script.setText(template);
                            setStatus("已验证并载入 " + regexRules.size() + " 条正则、"
                                    + resourceRules.size() + " 条资源 ID。脚本尚未注入；请检查目标和规则后手动注入。"
                                    + (broadScope.isChecked()
                                        ? " 注意：当前规则会检查任意 ViewGroup 父容器。"
                                        : " 扫描范围仍限 DecorView/content 根容器直接子项。"));
                            dialog.dismiss();
                        } catch (Exception error) {
                            setStatus("生成弹窗移除脚本失败：" + error.getClass().getSimpleName()
                                    + "：" + error.getMessage());
                        }
                    };
                    if (broadScope.isChecked()) {
                        new AlertDialog.Builder(this)
                                .setTitle("扩大弹窗移除范围？")
                                .setMessage("允许任意 ViewGroup 父容器会增加误删普通 UI 的风险。只允许在隔离的自有 debuggable 测试应用中使用。确认继续？")
                                .setNegativeButton("返回修改", null)
                                .setPositiveButton("确认扩大范围", (confirm, which) -> applyRules.run())
                                .show();
                    } else {
                        applyRules.run();
                    }
                }));
        dialog.show();
    }

    private String replaceExactlyOnce(String source, String placeholder, String replacement) {
        int first = source.indexOf(placeholder);
        if (first < 0 || source.indexOf(placeholder, first + placeholder.length()) >= 0) {
            throw new IllegalStateException("弹窗模板结构已变化，无法安全生成规则脚本。");
        }
        return source.substring(0, first) + replacement
                + source.substring(first + placeholder.length());
    }

    private void loadDiaMonitorTemplate(String kind) {
        String source;
        switch (kind) {
            case "http":
                source = "Java.perform(function () {\\n"
                        + "  function safeHost(value) { try { return String(Java.use('java.net.URL').$new(String(value)).getHost()); } catch (_) { return ''; } }\\n"
                        + "  var URL = Java.use('java.net.URL');\\n"
                        + "  var open = URL.openConnection.overload();\\n"
                        + "  open.implementation = function () {\\n"
                        + "    var host = String(this.getHost());\\n"
                        + "    send('[DIA_HTTP] URLConnection host=' + host);\\n"
                        + "    return open.call(this);\\n"
                        + "  };\\n"
                        + "  try { var H = Java.use('java.net.HttpURLConnection'); var code = H.getResponseCode.overload();\\n"
                        + "    code.implementation = function () { var started=Date.now(); var result=code.call(this); var host=''; var method='';\\n"
                        + "      try { host=String(this.getURL().getHost()); } catch (_) {} try { method=String(this.getRequestMethod()); } catch (_) {}\\n"
                        + "      send('[DIA_HTTP] HttpURLConnection method=' + method + ' host=' + host + ' status=' + result + ' elapsedMs=' + (Date.now()-started)); return result;\\n"
                        + "    };\\n"
                        + "  } catch (_) {}\\n"
                        + "  function hookOkHttp(className) { try { var C=Java.use(className);\\n"
                        + "    try { var execute=C.execute.overload(); execute.implementation=function(){ var request=this.request(); var url=request.url(); var host=String(url.host()); var method=String(request.method()); var started=Date.now();\\n"
                        + "      try { var response=execute.call(this); var status=response.code(); send('[DIA_HTTP] OkHttp method='+method+' host='+host+' status='+status+' elapsedMs='+(Date.now()-started)); return response; }\\n"
                        + "      catch(e){send('[DIA_HTTP] OkHttp method='+method+' host='+host+' exception='+e.$className);throw e;} }; } catch (_) {}\\n"
                        + "    try { C.enqueue.overloads.forEach(function(enqueue){ if(enqueue.argumentTypes.length!==1)return; enqueue.implementation=function(callback){ var request=this.request(); var url=request.url(); send('[DIA_HTTP] OkHttp enqueue method='+String(request.method())+' host='+String(url.host())); return enqueue.call(this,callback); }; }); } catch (_) {}\\n"
                        + "  } catch (_) {} }\\n"
                        + "  hookOkHttp('okhttp3.RealCall'); hookOkHttp('okhttp3.internal.connection.RealCall');\\n"
                        + "  try { var Volley=Java.use('com.android.volley.Request'); var getUrl=Volley.getUrl.overload(); getUrl.implementation=function(){ var url=String(getUrl.call(this)); send('[DIA_HTTP] Volley host='+safeHost(url)); return url; }; } catch (_) {}\\n"
                        + "});";
                break;
            case "webview-http":
                source = "Java.perform(function () {\\n"
                        + "  function hostOf(value) { try { return String(Java.use('java.net.URL').$new(String(value)).getHost()); } catch (_) { return ''; } }\\n"
                        + "  try { var WebView=Java.use('android.webkit.WebView');\\n"
                        + "    try { var load=WebView.loadUrl.overload('java.lang.String'); load.implementation=function(url){\\n"
                        + "      var host=hostOf(url); send('[DIA_WEBVIEW] loadUrl host='+host); return load.call(this,url); }; } catch (_) {}\\n"
                        + "    try { var loadHeaders=WebView.loadUrl.overload('java.lang.String','java.util.Map'); loadHeaders.implementation=function(url,headers){\\n"
                        + "      var host=hostOf(url); send('[DIA_WEBVIEW] loadUrl(headers) host='+host); return loadHeaders.call(this,url,headers); }; } catch (_) {}\\n"
                        + "    try { var post=WebView.postUrl.overload('java.lang.String','[B'); post.implementation=function(url,body){\\n"
                        + "      var host=hostOf(url); var length=-1; try { length=body===null?-1:body.length; } catch (_) {}\\n"
                        + "      send('[DIA_WEBVIEW] postUrl host='+host+' bodyBytes='+length+' content=redacted'); return post.call(this,url,body); }; } catch (_) {}\\n"
                        + "  } catch(e) { send('[DIA_WEBVIEW] WebView class unavailable: '+e.$className); }\\n"
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
                        + "  function byteLength(value) { try { return value === null ? -1 : value.length; } catch (_) { return -1; } }\\n"
                        + "  function install(className, methodNames, label) {\\n"
                        + "    try { var C=Java.use(className); methodNames.forEach(function(name){ try { C[name].overloads.forEach(function(overload){\\n"
                        + "      overload.implementation=function(){ var started=Date.now(); var inputBytes=arguments.length?byteLength(arguments[0]):-1; var algorithm='unknown';\\n"
                        + "        try { algorithm=String(this.getAlgorithm()); } catch (_) {}\\n"
                        + "        try { var result=overload.apply(this,arguments); var outputBytes=byteLength(result);\\n"
                        + "          send('[DIA_ALGORITHM] family='+label+' algorithm='+algorithm+' method='+name+' inputBytes='+inputBytes+' outputBytes='+outputBytes+' elapsedMs='+(Date.now()-started)); return result;\\n"
                        + "        } catch(e){ send('[DIA_ALGORITHM] family='+label+' algorithm='+algorithm+' method='+name+' exception='+e.$className+' elapsedMs='+(Date.now()-started)); throw e; }\\n"
                        + "      };\\n"
                        + "    }); } catch (_) {} }); } catch(e) { send('[DIA_ALGORITHM] class unavailable '+className); }\\n"
                        + "  }\\n"
                        + "  install('java.security.MessageDigest',['digest'],'MessageDigest');\\n"
                        + "  install('javax.crypto.Cipher',['doFinal'],'Cipher');\\n"
                        + "  install('javax.crypto.Mac',['doFinal'],'Mac');\\n"
                        + "  install('java.security.Signature',['sign','verify'],'Signature');\\n"
                        + "  send('[DIA_ALGORITHM] JCA metadata observers installed; payloads, keys and returned values are not logged.');\\n"
                        + "});";
                break;
            case "native":
                source = "var moduleName = 'libtarget.so';\\n"
                        + "var symbolName = 'target_export';\\n"
                        + "var address = Module.findExportByName(moduleName, symbolName);\\n"
                        + "if (address === null) {\\n"
                        + "  send('[DIA_NATIVE] export not found: ' + moduleName + '!' + symbolName);\\n"
                        + "} else {\\n"
                        + "  Interceptor.attach(address, {\\n"
                        + "    onEnter: function (args) { this.started = Date.now(); },\\n"
                        + "    onLeave: function (retval) {\\n"
                        + "      send('[DIA_NATIVE] ' + moduleName + '!' + symbolName + ' elapsedMs=' + (Date.now() - this.started));\\n"
                        + "    }\\n"
                        + "  });\\n"
                        + "  send('[DIA_NATIVE] attached ' + moduleName + '!' + symbolName);\\n"
                        + "}";
                break;
            case "classloader":
                source = "Java.perform(function () {\\n"
                        + "  var prefix = 'com.example.target.'; // change to the target package/class prefix\\n"
                        + "  var Loader = Java.use('java.lang.ClassLoader');\\n"
                        + "  var load = Loader.loadClass.overload('java.lang.String');\\n"
                        + "  load.implementation = function (name) {\\n"
                        + "    var result = load.call(this, name);\\n"
                        + "    if (String(name).indexOf(prefix) === 0) {\\n"
                        + "      var loaderName = ''; try { loaderName = String(this.getClass().getName()); } catch (_) {}\\n"
                        + "      send('[DIA_CLASSLOADER] class=' + name + ' loader=' + loaderName);\\n"
                        + "    }\\n"
                        + "    return result;\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "sqlcipher": {
                android.content.SharedPreferences sqlPrefs =
                        getSharedPreferences(PREFS, MODE_PRIVATE);
                java.util.List<String> databaseClasses = new java.util.ArrayList<>();
                java.util.List<String> statementClasses = new java.util.ArrayList<>();
                if (sqlPrefs.getBoolean("sql_monitor_sqlite", true)) {
                    databaseClasses.add("android.database.sqlite.SQLiteDatabase");
                    statementClasses.add("android.database.sqlite.SQLiteStatement");
                }
                if (sqlPrefs.getBoolean("sql_monitor_sqlcipher", true)) {
                    databaseClasses.add("net.sqlcipher.database.SQLiteDatabase");
                    statementClasses.add("net.sqlcipher.database.SQLiteStatement");
                }
                if (sqlPrefs.getBoolean("sql_monitor_wcdb", true)) {
                    databaseClasses.add("com.tencent.wcdb.database.SQLiteDatabase");
                    statementClasses.add("com.tencent.wcdb.database.SQLiteStatement");
                }
                if (sqlPrefs.getBoolean("sql_monitor_zetetic", true)) {
                    databaseClasses.add("net.zetetic.database.sqlcipher.SQLiteDatabase");
                    statementClasses.add("net.zetetic.database.sqlcipher.SQLiteStatement");
                }
                String databaseJson = new org.json.JSONArray(databaseClasses).toString();
                String statementJson = new org.json.JSONArray(statementClasses).toString();
                boolean captureStack = sqlPrefs.getBoolean("sql_monitor_stack", false);
                String stackCapture = captureStack
                        ? "var stackText=''; try { stackText=Java.backtrace({limit:8}).frames.map(function(f){return f.className+'.'+f.methodName;}).join(' <- '); } catch (_) {}"
                        : "var stackText='';";
                source = "Java.perform(function () {\\n"
                        + "  var classes = " + databaseJson + ";\\n"
                        + "  var methods = ['rawQuery', 'execSQL', 'query', 'insert', 'update', 'delete'];\\n"
                        + "  if (classes.length === 0) { send('[DIA_SQL] no database backend selected'); return; }\\n"
                        + "  classes.forEach(function (className) {\\n"
                        + "    try { var DB = Java.use(className);\\n"
                        + "      methods.forEach(function (methodName) {\\n"
                        + "        try { var overloads = DB[methodName].overloads;\\n"
                        + "          overloads.forEach(function (overload) {\\n"
                        + "            overload.implementation = function () {\\n"
                        + "              var started = Date.now(); var argCount = arguments.length; var firstLength = -1;\\n"
                        + "              try { if (typeof arguments[0] === 'string') firstLength = arguments[0].length; } catch (_) {}\\n"
                        + "              " + stackCapture + "\\n"
                        + "              try { var result = overload.apply(this, arguments);\\n"
                        + "                send('[DIA_SQL] class=' + className + ' method=' + methodName + ' args=' + argCount + ' firstStringLength=' + firstLength + ' elapsedMs=' + (Date.now() - started) + (stackText ? ' stack=' + stackText : ''));\\n"
                        + "                return result;\\n"
                        + "              } catch (e) { send('[DIA_SQL] class=' + className + ' method=' + methodName + ' exception=' + e.$className + ' elapsedMs=' + (Date.now() - started) + (stackText ? ' stack=' + stackText : '')); throw e; }\\n"
                        + "            };\\n"
                        + "          });\\n"
                        + "        } catch (_) {}\\n"
                        + "      });\\n"
                        + "    } catch (_) { send('[DIA_SQL] class unavailable ' + className); }\\n"
                        + "  });\\n"
                        + "  var statementClasses = " + statementJson + ";\\n"
                        + "  var statementMethods = ['execute', 'executeInsert', 'executeUpdateDelete', 'simpleQueryForLong', 'simpleQueryForString'];\\n"
                        + "  statementClasses.forEach(function (className) {\\n"
                        + "    try { var ST = Java.use(className);\\n"
                        + "      statementMethods.forEach(function (methodName) {\\n"
                        + "        try { ST[methodName].overloads.forEach(function (overload) {\\n"
                        + "          overload.implementation = function () { var started = Date.now(); " + stackCapture + "\\n"
                        + "            try { var result = overload.apply(this, arguments);\\n"
                        + "              send('[DIA_SQL] statement class=' + className + ' method=' + methodName + ' elapsedMs=' + (Date.now() - started) + (stackText ? ' stack=' + stackText : '')); return result;\\n"
                        + "            } catch (e) { send('[DIA_SQL] statement class=' + className + ' method=' + methodName + ' exception=' + e.$className + ' elapsedMs=' + (Date.now() - started) + (stackText ? ' stack=' + stackText : '')); throw e; }\\n"
                        + "          };\\n"
                        + "        }); } catch (_) {}\\n"
                        + "      });\\n"
                        + "    } catch (_) { send('[DIA_SQL] statement class unavailable ' + className); }\\n"
                        + "  });\\n"
                        + "  send('[DIA_SQL] metadata-only observer ready; SQL values and result rows are not logged.');\\n"
                        + "});";
                break;
            }
            case "socket":
                source = "Java.perform(function () {\\n"
                        + "  var Socket = Java.use('java.net.Socket');\\n"
                        + "  var InetSocketAddress = Java.use('java.net.InetSocketAddress');\\n"
                        + "  function describe(address) {\\n"
                        + "    try { var item = Java.cast(address, InetSocketAddress); return String(item.getHostString()) + ':' + String(item.getPort()); }\\n"
                        + "    catch (_) { try { return String(address.getClass().getName()); } catch (_) { return 'unknown'; } }\\n"
                        + "  }\\n"
                        + "  try { var connect = Socket.connect.overload('java.net.SocketAddress', 'int');\\n"
                        + "    connect.implementation = function (address, timeout) { var endpoint = describe(address); var started = Date.now();\\n"
                        + "      try { var result = connect.call(this, address, timeout); send('[DIA_SOCKET] connect endpoint=' + endpoint + ' timeoutMs=' + timeout + ' elapsedMs=' + (Date.now()-started)); return result; }\\n"
                        + "      catch (e) { send('[DIA_SOCKET] connect endpoint=' + endpoint + ' exception=' + e.$className + ' elapsedMs=' + (Date.now()-started)); throw e; }\\n"
                        + "    };\\n"
                        + "  } catch (e) { send('[DIA_SOCKET] timeout overload unavailable'); }\\n"
                        + "  try { var connectDefault = Socket.connect.overload('java.net.SocketAddress');\\n"
                        + "    connectDefault.implementation = function (address) { var endpoint = describe(address); var started = Date.now();\\n"
                        + "      try { var result = connectDefault.call(this, address); send('[DIA_SOCKET] connect endpoint=' + endpoint + ' elapsedMs=' + (Date.now()-started)); return result; }\\n"
                        + "      catch (e) { send('[DIA_SOCKET] connect endpoint=' + endpoint + ' exception=' + e.$className + ' elapsedMs=' + (Date.now()-started)); throw e; }\\n"
                        + "    };\\n"
                        + "  } catch (e) { send('[DIA_SOCKET] default overload unavailable'); }\\n"
                        + "  send('[DIA_SOCKET] metadata observer installed; socket payloads are not read or logged.');\\n"
                        + "});";
                break;
            case "appentry":
                source = "Java.perform(function () {\\n"
                        + "  var Instrumentation = Java.use('android.app.Instrumentation');\\n"
                        + "  function emitCreate(className, intent, stage) {\\n"
                        + "    var action = ''; var pkg = '';\\n"
                        + "    try { if (intent !== null) action = String(intent.getAction() || ''); } catch (_) {}\\n"
                        + "    try { if (intent !== null) pkg = String(intent.getPackage() || ''); } catch (_) {}\\n"
                        + "    send('[DIA_APPENTRY] stage=' + stage + ' activity=' + className + ' action=' + action + ' intentPackage=' + pkg);\\n"
                        + "  }\\n"
                        + "  try { var create3 = Instrumentation.newActivity.overload('java.lang.ClassLoader', 'java.lang.String', 'android.content.Intent');\\n"
                        + "    create3.implementation = function (loader, className, intent) { emitCreate(String(className), intent, 'newActivity'); return create3.call(this, loader, className, intent); };\\n"
                        + "  } catch (e) { send('[DIA_APPENTRY] three-argument newActivity overload unavailable'); }\\n"
                        + "  try { var create4 = Instrumentation.newActivity.overload('java.lang.ClassLoader', 'java.lang.String', 'android.content.Context', 'android.content.Intent');\\n"
                        + "    create4.implementation = function (loader, className, context, intent) { emitCreate(String(className), intent, 'newActivity'); return create4.call(this, loader, className, context, intent); };\\n"
                        + "  } catch (e) { send('[DIA_APPENTRY] context newActivity overload unavailable'); }\\n"
                        + "  try { var onCreate = Instrumentation.callActivityOnCreate.overload('android.app.Activity', 'android.os.Bundle');\\n"
                        + "    onCreate.implementation = function (activity, bundle) { var name = ''; try { name = String(activity.getClass().getName()); } catch (_) {} emitCreate(name, null, 'callActivityOnCreate'); return onCreate.call(this, activity, bundle); };\\n"
                        + "  } catch (e) { send('[DIA_APPENTRY] callActivityOnCreate overload unavailable'); }\\n"
                        + "  send('[DIA_APPENTRY] metadata-only observer installed; no Activity replacement, finish or Intent extras/data access.');\\n"
                        + "});";
                break;
            case "intent":
                source = "Java.perform(function () {\\n"
                        + "  var Activity = Java.use('android.app.Activity');\\n"
                        + "  var start = Activity.startActivity.overload('android.content.Intent');\\n"
                        + "  start.implementation = function (intent) {\\n"
                        + "    var action = ''; var component = '';\\n"
                        + "    try { action = String(intent.getAction() || ''); } catch (_) {}\\n"
                        + "    try { var c = intent.getComponent(); if (c !== null) component = String(c.flattenToShortString()); } catch (_) {}\\n"
                        + "    send('[DIA_INTENT] startActivity action=' + action + ' component=' + component);\\n"
                        + "    return start.call(this, intent);\\n"
                        + "  };\\n"
                        + "  var startForResult = Activity.startActivityForResult.overload('android.content.Intent', 'int');\\n"
                        + "  startForResult.implementation = function (intent, requestCode) {\\n"
                        + "    var action = ''; try { action = String(intent.getAction() || ''); } catch (_) {}\\n"
                        + "    send('[DIA_INTENT] startActivityForResult action=' + action + ' requestCode=' + requestCode);\\n"
                        + "    return startForResult.call(this, intent, requestCode);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "click":
                source = "Java.perform(function () {\\n"
                        + "  var View = Java.use('android.view.View');\\n"
                        + "  var click = View.performClick.overload();\\n"
                        + "  click.implementation = function () {\\n"
                        + "    var cls = ''; var id = -1;\\n"
                        + "    try { cls = String(this.getClass().getName()); } catch (_) {}\\n"
                        + "    try { id = this.getId(); } catch (_) {}\\n"
                        + "    send('[DIA_CLICK] view=' + cls + ' id=' + id);\\n"
                        + "    return click.call(this);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "viewgroup":
                source = "Java.perform(function () {\\n"
                        + "  var Group = Java.use('android.view.ViewGroup');\\n"
                        + "  var add = Group.addView.overload('android.view.View');\\n"
                        + "  add.implementation = function (child) {\\n"
                        + "    var parentName = ''; var childName = ''; var id = -1;\\n"
                        + "    try { parentName = String(this.getClass().getName()); } catch (_) {}\\n"
                        + "    try { childName = String(child.getClass().getName()); id = child.getId(); } catch (_) {}\\n"
                        + "    send('[DIA_VIEWGROUP] add parent=' + parentName + ' child=' + childName + ' id=' + id);\\n"
                        + "    return add.call(this, child);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "fragment":
                source = "Java.perform(function () {\\n"
                        + "  function hookFragment(name) {\\n"
                        + "    try { var F = Java.use(name); var resume = F.onResume.overload();\\n"
                        + "      resume.implementation = function () { send('[DIA_FRAGMENT] onResume ' + name); return resume.call(this); };\\n"
                        + "    } catch (e) { send('[DIA_FRAGMENT] unavailable ' + name); }\\n"
                        + "  }\\n"
                        + "  hookFragment('android.app.Fragment');\\n"
                        + "  hookFragment('androidx.fragment.app.Fragment');\\n"
                        + "  hookFragment('android.support.v4.app.Fragment');\\n"
                        + "});";
                break;
            case "thread":
                source = "Java.perform(function () {\\n"
                        + "  var Thread = Java.use('java.lang.Thread');\\n"
                        + "  var start = Thread.start.overload();\\n"
                        + "  start.implementation = function () {\\n"
                        + "    var name = ''; try { name = String(this.getName()); } catch (_) {}\\n"
                        + "    send('[DIA_THREAD] start name=' + name + ' class=' + String(this.getClass().getName()));\\n"
                        + "    return start.call(this);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "stack":
                source = "Java.perform(function () {\\n"
                        + "  var Activity = Java.use('android.app.Activity');\\n"
                        + "  var resume = Activity.onResume.overload();\\n"
                        + "  resume.implementation = function () {\\n"
                        + "    var name = ''; try { name = String(this.getClass().getName()); } catch (_) {}\\n"
                        + "    var frames = Java.use('java.lang.Thread').currentThread().getStackTrace();\\n"
                        + "    var out = [];\\n"
                        + "    for (var i = 0; i < frames.length && i < 8; i++) out.push(String(frames[i].getClassName()) + '.' + String(frames[i].getMethodName()));\\n"
                        + "    send('[DIA_STACK] Activity.onResume ' + name + ' frames=' + out.join(' <- '));\\n"
                        + "    return resume.call(this);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "key":
                source = "Java.perform(function () {\\n"
                        + "  var Activity = Java.use('android.app.Activity');\\n"
                        + "  var dispatch = Activity.dispatchKeyEvent.overload('android.view.KeyEvent');\\n"
                        + "  dispatch.implementation = function (event) {\\n"
                        + "    var code = -1; var action = -1;\\n"
                        + "    try { code = event.getKeyCode(); action = event.getAction(); } catch (_) {}\\n"
                        + "    send('[DIA_KEY] keyCode=' + code + ' action=' + action);\\n"
                        + "    return dispatch.call(this, event);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "runtime":
                source = "Java.perform(function () {\\n"
                        + "  var Runtime = Java.use('java.lang.Runtime');\\n"
                        + "  var exec = Runtime.exec.overload('java.lang.String');\\n"
                        + "  exec.implementation = function (command) {\\n"
                        + "    send('[DIA_RUNTIME] Runtime.exec invoked; command content omitted');\\n"
                        + "    return exec.call(this, command);\\n"
                        + "  };\\n"
                        + "  var Builder = Java.use('java.lang.ProcessBuilder');\\n"
                        + "  var start = Builder.start.overload();\\n"
                        + "  start.implementation = function () {\\n"
                        + "    send('[DIA_RUNTIME] ProcessBuilder.start invoked; arguments omitted');\\n"
                        + "    return start.call(this);\\n"
                        + "  };\\n"
                        + "});";
                break;
            case "click-auto":
                try {
                    source = readDiaTemplateAsset("dia/fx_auto_click_template.js");
                } catch (Exception error) {
                    setStatus("读取自动点击模板失败：" + error.getMessage());
                    return;
                }
                break;
            case "viewgroup-remove":
                try {
                    source = readDiaTemplateAsset("dia/fx_dialog_remove_template.js");
                } catch (Exception error) {
                    setStatus("读取匹配弹窗移除模板失败：" + error.getMessage());
                    return;
                }
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
        if ("click-auto".equals(kind)) {
            setStatus("自动点击模板已载入：规则默认为空；仅对自有测试应用填写正则/资源 ID 后手动注入。");
        } else if ("viewgroup-remove".equals(kind)) {
            setStatus("匹配弹窗移除模板已载入：规则默认为空，默认只检查 DecorView/content 直接新增子视图；配置规则并确认目标后手动注入。");
        } else {
            setStatus("监控模板已载入；请先检查目标类/方法，再手动执行注入。");
        }
    }

    private String readDiaTemplateAsset(String assetName) throws Exception {
        try (InputStream in = getAssets().open(assetName)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private String gadgetConfigTarget(String libraryPath) {
        if (libraryPath == null || !libraryPath.endsWith(".so")) return null;
        return libraryPath.substring(0, libraryPath.length() - 3) + ".config.so";
    }


    private void confirmDeployGadgetToTarget() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择一个用户安装且 debuggable 的目标应用。");
            return;
        }
        String library = gadgetPath == null ? "" : gadgetPath.getText().toString().trim();
        String config = gadgetConfigTarget(library);
        String requestedProcessName = gadgetProcess == null || gadgetProcess.getText() == null
                ? "" : gadgetProcess.getText().toString().trim();
        final String processName = requestedProcessName.isEmpty()
                ? targetPackage : requestedProcessName;
        String processError = FxDiaGadgetDeployment.validateProcessName(targetPackage, processName);
        if (processError != null) {
            setStatus(processError);
            return;
        }
        int port;
        try {
            port = selectedGadgetPort();
        } catch (IllegalArgumentException invalid) {
            setStatus(invalid.getMessage());
            return;
        }
        String problem = FxDiaGadgetDeployment.validateSources(
                this, targetPackage, library, config, port, processName);
        if (problem != null) {
            setStatus(problem + " 请先导入 Gadget 动态库并生成对应监听配置。");
            return;
        }
        final String destination;
        try {
            destination = FxDiaGadgetDeployment.targetNativeLibraryDir(this, targetPackage);
        } catch (Exception error) {
            setStatus("目标应用原生库目录不可用：" + error.getMessage());
            return;
        }
        String name = targetName == null ? targetPackage : targetName;
        new AlertDialog.Builder(this)
                .setTitle("部署 Frida Gadget")
                .setMessage("即将在目标应用的 nativeLibraryDir 中部署官方 Gadget、回环监听配置和哈希标记：\n\n"
                        + name + "\n" + targetPackage + "\n进程：" + processName + "\n" + destination
                        + "\n\n一个监听端口只绑定该进程，不会让同一应用其他进程争抢端口。部署后需在 LSPosed 启用该目标作用域并重启应用。")
                .setNegativeButton("取消", null)
                .setPositiveButton("部署", (dialog, which) -> deployGadgetToTarget(library, config, destination, port, processName))
                .show();
    }

    private void deployGadgetToTarget(String library, String config,
                                      String destination, int port, String processName) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString("gadget_process", processName).apply();
        String command = FxDiaGadgetDeployment.buildDeployCommand(
                library, config, destination, targetPackage, port, processName);
        runRoot(command, 45000L, result -> {
            if (result.exitCode == 0 && result.output != null
                    && result.output.contains("FX_GADGET_DEPLOYED")) {
                setStatus("Gadget 已部署到目标应用原生库目录。请在 LSPosed 中启用目标作用域，然后完全停止并重新启动目标应用。"
                        + "\n" + result.output);
            } else {
                setStatus("Gadget 部署失败（退出码 " + result.exitCode + "）：\n" + result.output);
            }
        });
    }

    private void confirmRemoveGadgetFromTarget() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择部署过 Gadget 的目标应用。");
            return;
        }
        final String destination;
        try {
            destination = FxDiaGadgetDeployment.targetNativeLibraryDir(this, targetPackage);
        } catch (Exception error) {
            setStatus("目标应用原生库目录不可用：" + error.getMessage());
            return;
        }
        String name = targetName == null ? targetPackage : targetName;
        new AlertDialog.Builder(this)
                .setTitle("移除 FX Gadget 部署")
                .setMessage("仅删除目标目录中带有 FX 标记且 SHA-256 仍与标记一致的 Gadget 文件，不触碰其他原生库：\n\n"
                        + name + "\n" + targetPackage + "\n" + destination)
                .setNegativeButton("取消", null)
                .setPositiveButton("移除", (dialog, which) -> removeGadgetFromTarget(destination))
                .show();
    }

    private void removeGadgetFromTarget(String destination) {
        String command = FxDiaGadgetDeployment.buildRemoveCommand(destination, targetPackage);
        runRoot(command, 30000L, result -> {
            if (result.exitCode == 0 && result.output != null
                    && (result.output.contains("FX_GADGET_REMOVED")
                        || result.output.contains("FX_GADGET_NOT_DEPLOYED"))) {
                setStatus("目标应用的 FX Gadget 部署清理结果：\n" + result.output
                        + "\n如目标进程已加载 Gadget，需完全停止并重新启动该应用后才会卸载已加载的库。");
            } else {
                setStatus("Gadget 移除失败（退出码 " + result.exitCode + "）：\n" + result.output);
            }
        });
    }

    private void saveGadgetListenConfig() {
        String library = gadgetPath == null ? "" : gadgetPath.getText().toString().trim();
        String portText = gadgetPort == null ? "" : gadgetPort.getText().toString().trim();
        String configPath = gadgetConfigTarget(library);
        if (!validPath(library) || configPath == null) {
            setStatus("Gadget 路径无效：必须是 .so 结尾的绝对路径。");
            return;
        }
        int port;
        try { port = Integer.parseInt(portText); }
        catch (NumberFormatException invalid) {
            setStatus("端口必须是 1024–65535 的数字。");
            return;
        }
        if (port < 1024 || port > 65535) {
            setStatus("端口必须在 1024–65535 范围内。");
            return;
        }
        if (port == 27042) {
            setStatus("端口 27042 已由 FX frida-server 保留；Gadget 请使用 27043 或其他未占用端口。");
            return;
        }
        boolean wait = gadgetLoadMode != null
                && gadgetLoadMode.getCheckedRadioButtonId()
                == gadgetLoadMode.getChildAt(0).getId();

        final String config;
        try {
            org.json.JSONObject interaction = new org.json.JSONObject();
            interaction.put("type", "listen");
            interaction.put("address", "127.0.0.1");
            interaction.put("port", port);
            interaction.put("on_port_conflict", "fail");
            interaction.put("on_load", wait ? "wait" : "resume");
            org.json.JSONObject root = new org.json.JSONObject();
            root.put("interaction", interaction);
            config = root.toString(2);
        } catch (Exception error) {
            setStatus("生成 Gadget JSON 失败：" + error.getClass().getSimpleName());
            return;
        }

        String encoded = android.util.Base64.encodeToString(
                config.getBytes(StandardCharsets.UTF_8), android.util.Base64.NO_WRAP);
        String command = "set -e; gadget=" + quote(library) + "; config=" + quote(configPath) + "; "
                + "test -f \"$gadget\" && test ! -L \"$gadget\"; "
                + "dir=$(dirname \"$config\"); umask 077; mkdir -p \"$dir\"; "
                + "test -d \"$dir\" && test ! -L \"$dir\"; "
                + "tmp=$(mktemp \"$dir/.fx-dia-frida-config.XXXXXX\"); "
                + "[ -n \"$tmp\" ] && [ -f \"$tmp\" ] && [ ! -L \"$tmp\" ]; "
                + "cleanup_tmp() { [ -z \"$tmp\" ] || rm -f \"$tmp\"; }; "
                + "trap cleanup_tmp 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "if ! printf '%s' " + quote(encoded) + " | base64 -d > \"$tmp\"; then cleanup_tmp; exit 1; fi; "
                + "test -s \"$tmp\"; "
                + "if ! chmod 0644 \"$tmp\"; then cleanup_tmp; exit 1; fi; "
                + "chown 0:0 \"$tmp\" 2>/dev/null || :; "
                + "if ! mv -f \"$tmp\" \"$config\"; then cleanup_tmp; exit 1; fi; "
                + "tmp=; test -f \"$config\" && test ! -L \"$config\"; "
                + "printf 'config=%s\\non_load=%s\\nport=%s\\n' "
                + quote(configPath) + " " + quote(wait ? "wait" : "resume") + " " + port + "; "
                + "cat \"$config\"";
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putString("gadget_path", library)
                .putString("gadget_port", Integer.toString(port))
                .putBoolean("gadget_on_load_wait", wait)
                .apply();
        runRoot(command, 20000L, result -> {
            if (result.exitCode == 0) {
                setStatus("Frida Gadget 监听配置已写入。\\n" + result.output
                        + "\\n需由目标 debuggable 应用加载对应 Gadget 动态库后才会生效。");
            } else {
                setStatus("Gadget 配置写入失败（退出码 " + result.exitCode + "）：\\n" + result.output);
            }
        });
    }

    private int selectedGadgetPort() {
        String value = gadgetPort == null ? "27042" : gadgetPort.getText().toString().trim();
        try {
            int port = Integer.parseInt(value);
            if (port < 1024 || port > 65535) throw new NumberFormatException("out of range");
            return port;
        } catch (NumberFormatException invalid) {
            throw new IllegalArgumentException("Gadget 端口必须是 1024–65535 的数字。");
        }
    }

    private String selectedGadgetProcess() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            throw new IllegalArgumentException("请先选择 Gadget 目标应用。");
        }
        String process = gadgetProcess == null || gadgetProcess.getText() == null
                ? "" : gadgetProcess.getText().toString().trim();
        if (process.isEmpty()) process = targetPackage;
        String problem = FxDiaGadgetDeployment.validateProcessName(targetPackage, process);
        if (problem != null) throw new IllegalArgumentException(problem);
        return process;
    }

    private String gadgetSessionLogPath(int port) {
        return "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".log";
    }

    /**
     * Connects the Frida CLI injector to a Gadget Listen endpoint.
     *
     * Gadget's Listen interaction is frida-server compatible. Attaching to its
     * single exposed process named "Gadget" is the operation that releases an
     * on_load=wait target. The injector's stdout/stderr is retained as the
     * session message/console log instead of claiming a TCP probe is an attach.
     */
    private void attachToGadgetAndResume() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择已经运行的 debuggable 目标应用；Gadget 必须由该应用实际加载。");
            return;
        }
        final int targetUid;
        try {
            ApplicationInfo targetInfo = getPackageManager().getApplicationInfo(targetPackage, 0);
            if ((targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                    || (targetInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                setStatus("目标应用已不再符合 debuggable 用户应用条件，拒绝连接。");
                return;
            }
            targetUid = targetInfo.uid;
        } catch (Throwable missing) {
            setStatus("目标应用已卸载或不可用，拒绝连接 Gadget。");
            return;
        }
        final String processName;
        try {
            processName = selectedGadgetProcess();
        } catch (IllegalArgumentException invalid) {
            setStatus(invalid.getMessage());
            return;
        }
        String cli = currentFridaCliPath();
        if (!validPath(cli)) {
            setStatus("尚未配置 Frida CLI。请安装 frida-tools 及其 Python 依赖，再填写可执行的 frida 命令绝对路径；frida-inject 不能替代它。");
            return;
        }
        String source = script == null || script.getText() == null
                ? "" : script.getText().toString();
        byte[] sourceBytes = source.getBytes(StandardCharsets.UTF_8);
        if (source.trim().isEmpty() || sourceBytes.length > 48 * 1024 || source.indexOf(0) >= 0) {
            java.util.Arrays.fill(sourceBytes, (byte) 0);
            setStatus("Frida 脚本为空、包含 NUL 字符或超过 48 KiB。");
            return;
        }
        final int port;
        try {
            port = selectedGadgetPort();
        } catch (IllegalArgumentException invalid) {
            java.util.Arrays.fill(sourceBytes, (byte) 0);
            setStatus(invalid.getMessage());
            return;
        }
        final String encoded = android.util.Base64.encodeToString(sourceBytes, android.util.Base64.NO_WRAP);
        java.util.Arrays.fill(sourceBytes, (byte) 0);

        final String logPath = gadgetSessionLogPath(port);
        final String scriptPath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".js";
        final String pidPath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".pid";
        final String pipePath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".stdin";
        String command = "set -eu; umask 077; "
                + "cli=" + quote(cli) + "; pkg=" + quote(targetPackage) + "; process=" + quote(processName) + "; "
                + "log=" + quote(logPath) + "; script=" + quote(scriptPath) + "; "
                + "pidfile=" + quote(pidPath) + "; pipe=" + quote(pipePath) + "; port=" + port + "; "
                + "test -x \"$cli\" && test ! -L \"$cli\"; "
                + "cli_version=$(\"$cli\" --version 2>&1) || { echo FX_GADGET_CLI_UNAVAILABLE; exit 20; }; "
                + "target_uid=" + targetUid + "; proc_root=/proc; "
                + "pids=$(ps -A -o PID 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | while IFS= read -r pid; do "
                + "proc_name=$(tr '\\000' '\\n' < \"$proc_root/$pid/cmdline\" 2>/dev/null | sed -n '1p'); "
                + "[ \"$proc_name\" = \"$process\" ] || continue; "
                + "uid=$(awk '$1==\"Uid:\" {print $2; exit}' \"$proc_root/$pid/status\" 2>/dev/null || :); "
                + "[ \"$uid\" = \"$target_uid\" ] && printf '%s\\n' \"$pid\" || :; done); "
                + "[ -n \"$pids\" ] || { echo FX_GADGET_TARGET_NOT_RUNNING; exit 4; }; "
                + "dir=/data/adb/privacyguard/dia-frida/logs; mkdir -p \"$dir\"; "
                + "test -d \"$dir\" && test ! -L \"$dir\"; chmod 700 \"$dir\"; "
                + "[ ! -L \"$log\" ] && [ ! -L \"$pidfile\" ] && [ ! -L \"$pipe\" ] && [ ! -L \"$script\" ] || { echo FX_GADGET_UNSAFE_SESSION_PATH; exit 21; }; "
                + "start_lock=\"$dir/.gadget-$port.start-lock\"; "
                + "[ ! -L \"$start_lock\" ] || { echo FX_GADGET_UNSAFE_START_LOCK; exit 29; }; "
                + "mkdir \"$start_lock\" 2>/dev/null || { echo FX_GADGET_START_IN_PROGRESS; exit 26; }; "
                + "lock_held=1; tmp=; pid_tmp=; "
                + "cleanup_start() { [ -z \"$tmp\" ] || rm -f \"$tmp\"; [ -z \"$pid_tmp\" ] || rm -f \"$pid_tmp\"; "
                + "[ \"$lock_held\" != 1 ] || rmdir \"$start_lock\" 2>/dev/null || :; }; "
                + "trap cleanup_start 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "if [ -s \"$pidfile\" ]; then old_cli=$(sed -n '1p' \"$pidfile\"); old_feed=$(sed -n '2p' \"$pidfile\"); old_cli_path=$(sed -n '3p' \"$pidfile\"); old_pkg=$(sed -n '4p' \"$pidfile\"); old_port=$(sed -n '5p' \"$pidfile\"); old_process=$(sed -n '6p' \"$pidfile\"); "
                + "case \"$old_cli:$old_feed\" in *[!0-9:]*|:*) echo FX_GADGET_INVALID_PID_RECORD; exit 22;; esac; "
                + "case \"$old_port\" in ''|*[!0-9]*) echo FX_GADGET_INVALID_PID_RECORD; exit 22;; esac; "
                + "[ \"$old_pkg\" = \"$pkg\" ] && [ \"$old_port\" = \"$port\" ] && [ \"$old_cli_path\" = \"$cli\" ] && [ \"$old_process\" = \"$process\" ] || { echo FX_GADGET_SESSION_TARGET_CONFLICT; exit 30; }; "
                + "session_pid_active() { case \"$1\" in ''|*[!0-9]*) return 1;; esac; state=$(sed 's/^.*) //' \"/proc/$1/stat\" 2>/dev/null | cut -d ' ' -f1); case \"$state\" in Z|X|x) return 1;; esac; kill -0 \"$1\" 2>/dev/null; }; " + "if session_pid_active \"$old_cli\"; then "
                + "old_cmd=$(tr '\\000' ' ' < /proc/\"$old_cli\"/cmdline 2>/dev/null || :); "
                + "case \"$old_cmd\" in *\"$old_cli_path\"*\"-H\"*\"127.0.0.1:$port\"*\"-n\"*\"Gadget\"*\"-l\"*\"$script\"*) echo FX_GADGET_SESSION_ALREADY_RUNNING; exit 0;; "
                + "*) echo FX_GADGET_SESSION_PID_CONFLICT; exit 23;; esac; fi; "
                + "if [ -n \"$old_feed\" ] && session_pid_active \"$old_feed\"; then "
                + "feed_cmd=$(tr '\\000' ' ' < /proc/\"$old_feed\"/cmdline 2>/dev/null || :); "
                + "case \"$feed_cmd\" in *\"fx-gadget-feed-$port\"*\"$pipe\"*) kill \"$old_feed\" 2>/dev/null || :;; "
                + "*) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;; esac; fi; "
                + "rm -f \"$pidfile\"; "
                + "if [ -e \"$pipe\" ]; then [ -p \"$pipe\" ] || { echo FX_GADGET_UNSAFE_STALE_PIPE; exit 27; }; rm -f \"$pipe\"; fi; "
                + "elif [ -e \"$pipe\" ]; then echo FX_GADGET_ORPHAN_PIPE_NEEDS_CLEANUP; exit 28; fi; "
                + "tmp=$(mktemp \"$dir/.gadget-$port.XXXXXX\"); "
                + "[ -f \"$tmp\" ] && [ ! -L \"$tmp\" ]; "
                + "printf '%s' " + quote(encoded) + " | base64 -d > \"$tmp\"; chmod 600 \"$tmp\"; "
                + "mv -f \"$tmp\" \"$script\"; tmp=; chmod 600 \"$script\"; "
                + ": >> \"$log\"; chmod 600 \"$log\"; mkfifo -m 600 \"$pipe\"; "
                + "nohup \"$cli\" -H \"127.0.0.1:$port\" -n Gadget -l \"$script\" < \"$pipe\" >> \"$log\" 2>&1 & cli_pid=$!; "
                + "nohup sh -c 'while kill -0 \"$1\" 2>/dev/null; do sleep 1; done' \"fx-gadget-feed-$port\" \"$cli_pid\" \"$pipe\" > \"$pipe\" 2>/dev/null < /dev/null & feed_pid=$!; "
                + "pid_tmp=$(mktemp \"$dir/.gadget-$port.pid.XXXXXX\"); "
                + "printf '%s\\n%s\\n%s\\n%s\\n%s\\n%s\\n' \"$cli_pid\" \"$feed_pid\" \"$cli\" \"$pkg\" \"$port\" \"$process\" > \"$pid_tmp\"; "
                + "chmod 600 \"$pid_tmp\"; mv -f \"$pid_tmp\" \"$pidfile\"; pid_tmp=; "
                + "sleep 1; "
                + "if ! kill -0 \"$cli_pid\" 2>/dev/null || ! kill -0 \"$feed_pid\" 2>/dev/null; then "
                + "tail -n 40 \"$log\"; kill \"$cli_pid\" \"$feed_pid\" 2>/dev/null || :; rm -f \"$pidfile\" \"$pipe\"; echo FX_GADGET_SESSION_START_FAILED; exit 25; fi; "
                + "lock_held=0; rmdir \"$start_lock\"; "
                + "printf 'FX_GADGET_SESSION_STARTED\\ncli_pid=%s\\nfeeder_pid=%s\\ncli_version=%s\\nprocess=%s\\n' \"$cli_pid\" \"$feed_pid\" \"$cli_version\" \"$process\"";
        runRoot(command, 20000L, result -> {
            if (result.exitCode == 0 && result.output != null
                    && (result.output.contains("FX_GADGET_SESSION_STARTED")
                        || result.output.contains("FX_GADGET_SESSION_ALREADY_RUNNING"))) {
                setStatus("Frida CLI Gadget 会话已连接/正在运行。Gadget WAIT 将由远程 attach 释放；持续 send()/console 输出会记录到："
                        + "\n" + logPath + "\n" + result.output);
            } else if (result.output != null && result.output.contains("FX_GADGET_TARGET_NOT_RUNNING")) {
                setStatus("目标应用当前没有运行进程；请先启动目标应用并确认 Gadget 已加载。");
            } else if (result.output != null && result.output.contains("FX_GADGET_CLI_UNAVAILABLE")) {
                setStatus("Frida CLI 不可执行或 Python 依赖不完整；请检查 frida-tools 安装及其 shebang 运行环境。\n" + result.output);
            } else {
                setStatus("Frida CLI Gadget 会话启动失败（退出码 " + result.exitCode + "）。\n请确认 CLI 与 Gadget 版本匹配、目标已加载相同端口。\n日志：" + logPath + "\n" + result.output);
            }
        });
    }

    private void stopGadgetSession() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择创建该 Gadget 会话时使用的目标应用；不会停止其他目标的 Frida 会话。");
            return;
        }
        final int port;
        try {
            port = selectedGadgetPort();
        } catch (IllegalArgumentException invalid) {
            setStatus(invalid.getMessage());
            return;
        }
        final String expectedPackage = targetPackage;
        final String expectedCli = currentFridaCliPath();
        final String expectedProcess;
        try {
            expectedProcess = selectedGadgetProcess();
        } catch (IllegalArgumentException invalid) {
            setStatus(invalid.getMessage());
            return;
        }
        if (!validPath(expectedCli)) {
            setStatus("当前 Frida CLI 路径无效，拒绝停止可能不属于当前配置的 Gadget 会话。");
            return;
        }
        final String pidPath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".pid";
        final String pipePath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".stdin";
        final String scriptPath = "/data/adb/privacyguard/dia-frida/logs/gadget-" + port + ".js";
        final String startLockPath = "/data/adb/privacyguard/dia-frida/logs/.gadget-" + port + ".start-lock";
        String command = "set -eu; pidfile=" + quote(pidPath) + "; pipe=" + quote(pipePath) + "; "
                + "script=" + quote(scriptPath) + "; start_lock=" + quote(startLockPath) + "; expected_pkg=" + quote(expectedPackage)
                + "; expected_process=" + quote(expectedProcess) + "; expected_cli=" + quote(expectedCli) + "; port=" + port + "; "
                + "[ ! -L \"$start_lock\" ] || { echo FX_GADGET_UNSAFE_START_LOCK; exit 29; }; "
                + "mkdir \"$start_lock\" 2>/dev/null || { echo FX_GADGET_START_IN_PROGRESS; exit 26; }; "
                + "lock_held=1; cleanup_stop() { [ \"$lock_held\" != 1 ] || rmdir \"$start_lock\" 2>/dev/null || :; }; "
                + "trap cleanup_stop 0; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "[ ! -L \"$pidfile\" ] && [ ! -L \"$pipe\" ] || { echo FX_GADGET_UNSAFE_SESSION_PATH; exit 21; }; "
                + "if [ ! -s \"$pidfile\" ]; then echo FX_GADGET_SESSION_NOT_RUNNING; exit 0; fi; "
                + "cli_pid=$(sed -n '1p' \"$pidfile\"); feed_pid=$(sed -n '2p' \"$pidfile\"); cli=$(sed -n '3p' \"$pidfile\"); "
                + "stored_pkg=$(sed -n '4p' \"$pidfile\"); stored_port=$(sed -n '5p' \"$pidfile\"); stored_process=$(sed -n '6p' \"$pidfile\"); "
                + "case \"$cli_pid:$feed_pid\" in *[!0-9:]*|:*) echo FX_GADGET_INVALID_PID_RECORD; exit 22;; esac; "
                + "case \"$stored_port\" in ''|*[!0-9]*) echo FX_GADGET_INVALID_PID_RECORD; exit 22;; esac; "
                + "[ \"$stored_pkg\" = \"$expected_pkg\" ] && [ \"$stored_port\" = \"$port\" ] && [ \"$stored_process\" = \"$expected_process\" ] && [ \"$cli\" = \"$expected_cli\" ] || { echo FX_GADGET_SESSION_TARGET_CONFLICT; exit 30; }; "
                + "pid_active() { case \"$1\" in ''|*[!0-9]*) return 1;; esac; state=$(sed 's/^.*) //' \"/proc/$1/stat\" 2>/dev/null | cut -d ' ' -f1); case \"$state\" in Z|X|x) return 1;; esac; kill -0 \"$1\" 2>/dev/null; }; "
                + "if pid_active \"$cli_pid\"; then "
                + "cmd=$(tr '\\000' ' ' < /proc/\"$cli_pid\"/cmdline 2>/dev/null || :); "
                + "case \"$cmd\" in *\"$cli\"*'127.0.0.1:" + port + "'*Gadget*\"$script\"*) kill \"$cli_pid\";; *) echo FX_GADGET_CLI_PID_CONFLICT; exit 23;; esac; fi; "
                + "if pid_active \"$feed_pid\"; then "
                + "feed_cmd=$(tr '\\000' ' ' < /proc/\"$feed_pid\"/cmdline 2>/dev/null || :); "
                + "case \"$feed_cmd\" in *\"fx-gadget-feed-" + port + "\"*\"$pipe\"*) kill \"$feed_pid\";; *) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;; esac; fi; "
                + "_stop_wait=0; while pid_active \"$cli_pid\" || pid_active \"$feed_pid\"; do "
                + "[ \"$_stop_wait\" -lt 5 ] || { echo FX_GADGET_STOP_TIMEOUT; exit 31; }; "
                + "sleep 1; _stop_wait=$((_stop_wait+1)); done; "
                + "rm -f \"$pidfile\"; [ ! -L \"$pipe\" ] && rm -f \"$pipe\"; lock_held=0; rmdir \"$start_lock\"; echo FX_GADGET_SESSION_STOPPED";
        runRoot(command, 12000L, result -> setStatus("Gadget 会话停止退出码 "
                + result.exitCode + "\n" + result.output));
    }

    private void showGadgetSessionLog() {
        final int port;
        try {
            port = selectedGadgetPort();
        } catch (IllegalArgumentException invalid) {
            setStatus(invalid.getMessage());
            return;
        }
        String log = gadgetSessionLogPath(port);
        String command = "set -eu; path=" + quote(log) + "; "
                + "[ ! -L \"$path\" ] || { echo FX_GADGET_LOG_SYMLINK_REJECTED; exit 5; }; "
                + "if [ -s \"$path\" ]; then tail -n 500 \"$path\"; "
                + "else echo '当前端口尚无 Gadget 会话消息/console 输出。'; fi";
        runRoot(command, 12000L, result -> {
            TextView viewer = text(result.output == null ? "" : result.output,
                    12, 0xff334155, false);
            viewer.setTextIsSelectable(true);
            viewer.setPadding(dp(16), dp(10), dp(16), dp(10));
            ScrollView scroll = new ScrollView(this);
            scroll.addView(viewer);
            new AlertDialog.Builder(this)
                    .setTitle("Frida Gadget 消息/控制台 · " + port)
                    .setView(scroll)
                    .setPositiveButton("关闭", null)
                    .show();
            setStatus("Gadget 会话日志读取退出码 " + result.exitCode);
        });
    }

    private void copyGadgetConnectCommand() {
        String portText = gadgetPort == null ? "27043" : gadgetPort.getText().toString().trim();
        int port;
        try { port = Integer.parseInt(portText); }
        catch (NumberFormatException invalid) { port = 27043; }
        if (port < 1024 || port > 65535 || port == 27042) port = 27043;
        String command = "adb forward tcp:" + port + " tcp:" + port
                + "\\nfrida-ps -H 127.0.0.1:" + port
                + "\\nfrida -H 127.0.0.1:" + port + " -n Gadget";
        android.content.ClipboardManager clipboard =
                (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard != null) {
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Frida Gadget", command));
            setStatus("ADB 端口转发及 Frida Gadget 连接命令已复制：\\n" + command);
        } else {
            setStatus(command);
        }
    }

    private void injectScript() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        final int targetUid;
        try {
            ApplicationInfo targetInfo = getPackageManager().getApplicationInfo(targetPackage, 0);
            if ((targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                    || (targetInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                setStatus("目标应用已不再符合 debuggable 用户应用条件，拒绝注入。");
                return;
            }
            targetUid = targetInfo.uid;
        } catch (Throwable missing) {
            setStatus("目标应用已卸载或不可用，拒绝注入。");
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
        String logPath = sessionLogPath();
        String selected = String.join(" ", selectedProcessPids);
        String pidSource = selected.isEmpty()
                ? "pids=$(ps -A -o PID,NAME 2>/dev/null | awk -v pkg=\"$pkg\" "
                    + "'NR>1 && $1 ~ /^[0-9]+$/ && ($2==pkg || index($2,pkg \":\")==1) {print $1}'); "
                : "pids=" + quote(selected) + "; ";
        String command = "set -eu; umask 077; test -x " + quote(injector) + "; "
                + "base=/data/adb/privacyguard; dir=\"$base/dia-frida\"; logs=\"$dir/logs\"; "
                + "script=" + quote(scriptPath) + "; log=" + quote(logPath) + "; "
                + "for path in /data /data/adb /data/adb/privacyguard /data/adb/privacyguard/dia-frida /data/adb/privacyguard/dia-frida/logs; do "
                + "[ ! -L \"$path\" ] || { echo unsafe-frida-state-symlink=$path; exit 21; }; done; "
                + "mkdir -p \"$dir\" \"$logs\"; "
                + "[ -d \"$dir\" ] && [ ! -L \"$dir\" ] && [ -d \"$logs\" ] && [ ! -L \"$logs\" ] || exit 21; "
                + "[ ! -L \"$script\" ] && [ ! -L \"$log\" ] || { echo unsafe-frida-session-file; exit 21; }; "
                + "tmp=$(mktemp \"$dir/.inject-XXXXXX\"); "
                + "trap '[ -z \"$tmp\" ] || rm -f \"$tmp\"' EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; "
                + "printf '%s' " + quote(encoded) + " | base64 -d > \"$tmp\"; chmod 600 \"$tmp\"; "
                + "mv -f \"$tmp\" \"$script\"; tmp=; "
                + "if [ -e \"$log\" ] && [ ! -f \"$log\" ]; then echo unsafe-frida-log-path; exit 21; fi; "
                + ": >> \"$log\"; chmod 600 \"$log\"; "
                + "pkg=" + quote(targetPackage) + "; target_uid=" + targetUid + "; "
                + "printf '\\n[FX Dia] multi-process injection start %s target=%s\\n' \"$(date '+%F %T')\" "
                + quote(targetPackage) + " >> " + quote(logPath) + "; "
                + pidSource
                + "[ -n \"$pids\" ] || { echo no-running-target-process; exit 4; }; "
                + "injected=0; failed=0; "
                + "for pid in $pids; do "
                + "case \"$pid\" in ''|*[!0-9]*) echo invalid-pid=$pid >> " + quote(logPath) + "; failed=1; continue;; esac; "
                + "proc=$(ps -A -o PID,NAME 2>/dev/null | awk -v wanted=\"$pid\" '$1==wanted {print $2; exit}'); "
                + "case \"$proc\" in \"$pkg\"|\"$pkg\":*) ;; *) "
                + "echo skipped-stale-or-unmatched-pid=$pid >> " + quote(logPath) + "; continue;; esac; "
                + "proc_uid=$(awk '$1==\"Uid:\" {print $2; exit}' \"/proc/$pid/status\" 2>/dev/null || :); "
                + "[ \"$proc_uid\" = \"$target_uid\" ] || { echo skipped-uid-mismatch-pid=$pid >> " + quote(logPath) + "; continue; }; "
                + "echo attach process=$proc uid=$proc_uid pid=$pid >> " + quote(logPath) + "; "
                + "if " + quote(injector) + " -p \"$pid\" -s " + quote(scriptPath)
                + " >> " + quote(logPath) + " 2>&1; then injected=$((injected+1)); "
                + "else rc=$?; failed=1; echo attach-failed pid=$pid exit=$rc >> " + quote(logPath) + "; fi; "
                + "done; echo attached_processes=$injected; "
                + "[ \"$injected\" -gt 0 ] || exit 4; [ \"$failed\" -eq 0 ] || exit 5";
        runRoot(command, 90000L, result ->
                setStatus("多进程注入退出码 " + result.exitCode + "\\n日志文件：" + logPath
                        + "\\n" + result.output));
    }


    private String sessionLogPath() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) return "";
        return "/data/adb/privacyguard/dia-frida/logs/" + targetPackage + ".log";
    }

    private void showSessionLog() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        Intent page = new Intent(this, FxDiaSessionLogActivity.class);
        page.putExtra("fx_dia_session_log_target_package", targetPackage);
        page.putExtra("fx_dia_session_log_target_name",
                targetName == null ? targetPackage : targetName);
        startActivity(page);
    }

    private void showMonitorEvents() {
        if (targetPackage == null || targetPackage.trim().isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        Intent page = new Intent(this, FxDiaMonitorEventsActivity.class);
        page.putExtra(FxDiaMonitorEventsActivity.EXTRA_TARGET_PACKAGE, targetPackage);
        page.putExtra(FxDiaMonitorEventsActivity.EXTRA_TARGET_NAME,
                targetName == null ? targetPackage : targetName);
        startActivity(page);
    }

    private void clearSessionLog() {
        String log = sessionLogPath();
        if (log.isEmpty()) {
            setStatus("请先选择 debuggable 目标应用。");
            return;
        }
        new AlertDialog.Builder(this).setTitle("清空 Frida 会话日志")
                .setMessage("只清空 FX 为当前目标创建的会话日志，不会删除脚本或 Frida 服务。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清空", (dialog, which) ->
                        runRoot("if [ -f " + quote(log) + " ] && [ ! -L " + quote(log)
                                + " ]; then : > " + quote(log) + " && chmod 600 " + quote(log)
                                + "; fi; echo log-cleared", 12000L,
                                result -> setStatus("日志清理退出码 " + result.exitCode
                                        + "\\n" + result.output))).show();
    }

    @Override protected void onDestroy() {
        targetLoadGeneration++;
        targetLoading = false;
        monitorEventGeneration++;
        worker.shutdownNow();
        super.onDestroy();
    }
}
