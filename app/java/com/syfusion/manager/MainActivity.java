package com.syfusion.manager;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.Toolbar;

/**
 * 内置管理器主界面。
 *
 * 结构：工具栏 + 原生状态条 + WebView。
 *   · 原生状态条让"看一眼就知道状态"，不用等网页加载
 *   · 网页部分复用模块面板，功能与 KernelSU 里的 WebUI 完全一致
 *     （面板本身有鉴权，同源注入令牌，所以这里直接加载即可）
 */
public class MainActivity extends Activity {

    private WebView web;
    private TextView tvCore, tvMode, tvUp, tvDown, tvConn;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private int port = PanelApi.DEFAULT_PORT;
    private volatile boolean polling = false;
    private long lastUp = 0, lastDown = 0;

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            pollOnce();
            ui.postDelayed(this, 2000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        port = getSharedPreferences("sy", MODE_PRIVATE).getInt("port", PanelApi.DEFAULT_PORT);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(getColor(R.color.bg));

        Toolbar tb = new Toolbar(this);
        tb.setTitle(getString(R.string.app_name));
        tb.setBackgroundColor(getColor(R.color.surface));
        tb.setTitleTextColor(getColor(R.color.text));
        setActionBar(tb);

        root.addView(tb, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(56)));

        root.addView(buildStatusStrip(), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        if (Build.VERSION.SDK_INT >= 26) {
            s.setSafeBrowsingEnabled(false);
        }
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                // 只允许留在本地面板，外链交给系统浏览器
                if (url != null && (url.startsWith("http://127.0.0.1")
                        || url.startsWith("http://localhost"))) {
                    return false;
                }
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {
                }
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient());
        web.setBackgroundColor(getColor(R.color.bg));
        root.addView(web, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
        askNotificationPermission();
        ensurePanelAndLoad();
    }

    private View buildStatusStrip() {
        LinearLayout strip = new LinearLayout(this);
        strip.setOrientation(LinearLayout.HORIZONTAL);
        strip.setBackgroundColor(getColor(R.color.surface));
        strip.setPadding(dp(4), dp(2), dp(4), dp(2));

        tvCore = addStat(strip, "内核", "…");
        tvMode = addStat(strip, "模式", "…");
        tvUp = addStat(strip, "↑", "0 B/s");
        tvDown = addStat(strip, "↓", "0 B/s");
        tvConn = addStat(strip, "连接", "0");
        return strip;
    }

    private TextView addStat(LinearLayout parent, String label, String value) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(2), dp(4), dp(2), dp(4));

        TextView lb = new TextView(this);
        lb.setText(label);
        lb.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        lb.setTextColor(getColor(R.color.text_dim));
        lb.setTypeface(Typeface.MONOSPACE);
        lb.setGravity(Gravity.CENTER);

        TextView vl = new TextView(this);
        vl.setText(value);
        vl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        vl.setTextColor(getColor(R.color.text));
        vl.setTypeface(Typeface.MONOSPACE);
        vl.setGravity(Gravity.CENTER);
        vl.setSingleLine(true);

        box.addView(lb);
        box.addView(vl);
        parent.addView(box, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        return vl;
    }

    private void ensurePanelAndLoad() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                boolean alive = PanelApi.ping(port, 1500);
                if (!alive) {
                    if (RootShell.hasRoot()) {
                        RootShell.startPanel();
                        for (int i = 0; i < 12 && !PanelApi.ping(port, 1000); i++) {
                            sleep(700);
                        }
                    }
                }
                final boolean ok = PanelApi.ping(port, 1500);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        if (ok) {
                            web.loadUrl(PanelApi.base(port) + "/");
                        } else {
                            web.loadDataWithBaseURL(null, offlineHtml(), "text/html", "utf-8", null);
                        }
                        startPolling();
                    }
                });
            }
        }, "panel-probe").start();
    }

    private void startPolling() {
        if (!polling) {
            polling = true;
            ui.post(poll);
        }
    }

    private void pollOnce() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String json = PanelApi.get(port, "/api/clash?sub=status", 2500);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        applyStatus(json);
                    }
                });
            }
        }, "status-poll").start();
    }

    private void applyStatus(String json) {
        if (json == null || !PanelApi.bool(json, "ok")) {
            tvCore.setText("未运行");
            tvCore.setTextColor(getColor(R.color.err));
            tvMode.setText("—");
            tvUp.setText("—");
            tvDown.setText("—");
            tvConn.setText("—");
            return;
        }
        String ver = PanelApi.str(json, "version");
        tvCore.setText(shortVer(ver));
        tvCore.setTextColor(getColor(R.color.ok));
        tvMode.setText(orDash(PanelApi.str(json, "mode")));
        long up = PanelApi.num(json, "up");
        long down = PanelApi.num(json, "down");
        tvUp.setText(PanelApi.speed(up));
        tvDown.setText(PanelApi.speed(down));
        tvConn.setText(String.valueOf(PanelApi.num(json, "conn_count")));
        lastUp = up;
        lastDown = down;
    }

    private static String shortVer(String v) {
        if (v == null || v.length() == 0) return "运行中";
        int i = v.lastIndexOf(' ');
        return i >= 0 ? v.substring(i + 1) : v;
    }

    private static String orDash(String s) {
        return (s == null || s.length() == 0) ? "—" : s;
    }

    private String offlineHtml() {
        return "<!doctype html><html><head><meta charset='utf-8'>"
                + "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                + "<style>body{background:#0E1116;color:#E6EDF3;font-family:monospace;"
                + "padding:28px 20px;line-height:1.7}h2{color:#F85149;font-size:16px}"
                + "p{color:#8B949E;font-size:13px}code{color:#7C7CFF}"
                + "button{margin-top:16px;background:#7C7CFF;color:#0E1116;border:0;"
                + "padding:10px 16px;border-radius:8px;font-family:monospace;font-size:13px}"
                + "</style></head><body>"
                + "<h2>面板未启动</h2>"
                + "<p>模块面板服务没有在 <code>127.0.0.1:" + port + "</code> 上响应。</p>"
                + "<p>常见原因：模块未安装完整、面板被停用、或服务进程被系统回收。</p>"
                + "<p>点下面的按钮会用 root 拉起面板，也可以从 KernelSU 的模块卡片"
                + "点操作按钮启动。</p>"
                + "<button onclick=\"location.href='http://127.0.0.1:" + port + "/'\">"
                + "重新连接</button></body></html>";
    }

    private void askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            try {
                if (checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                        != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 11);
                }
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(0, 1, 0, R.string.menu_refresh);
        menu.add(0, 2, 1, R.string.menu_browser);
        menu.add(0, 3, 2, R.string.menu_restart);
        menu.add(0, 4, 3, R.string.menu_stop);
        // 隐私防泄露子功能
        menu.add(0, 6, 4, R.string.menu_privacy_status);
        menu.add(0, 7, 5, R.string.menu_privacy_on);
        menu.add(0, 8, 6, R.string.menu_privacy_off);
        menu.add(0, 9, 7, R.string.menu_privacy_panic);
        menu.add(0, 10, 8, R.string.menu_privacy_restore);
        menu.add(0, 11, 9, R.string.menu_privacy_apps);
        // Hook 子系统 / Root / 运营商隐私
        menu.add(0, 12, 10, R.string.menu_hook_status);
        menu.add(0, 13, 11, R.string.menu_hook_events);
        menu.add(0, 14, 12, R.string.menu_hook_mode);
        menu.add(0, 15, 13, R.string.menu_hook_clear);
        menu.add(0, 16, 14, R.string.menu_carrier_on);
        menu.add(0, 17, 15, R.string.menu_root_status);
        menu.add(0, 5, 16, R.string.menu_about);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case 1:
                web.reload();
                toast("已刷新");
                return true;
            case 2:
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW,
                            Uri.parse(PanelApi.base(port) + "/")));
                } catch (Exception e) {
                    toast("没有可用的浏览器");
                }
                return true;
            case 3:
                runRootAsync(RootShell.restartCore(), "重启内核");
                return true;
            case 4:
                runRootAsync(RootShell.stopCore(), "停止内核");
                return true;
            case 6:
                showCmd(new Cmd() { public String run() { return RootShell.leakStatus(); } }, "隐私防泄露状态");
                return true;
            case 7:
                runLeakAsync(RootShell.leakAll(true), "开启全部隐私防护");
                return true;
            case 8:
                runLeakAsync(RootShell.leakAll(false), "关闭全部隐私防护");
                return true;
            case 9:
                runLeakAsync(RootShell.leakPanic(), "应急加固");
                return true;
            case 10:
                runLeakAsync(RootShell.leakRestore(), "恢复默认");
                return true;
            case 11:
                showCmd(new Cmd() { public String run() { return RootShell.leakApps("list"); } }, "隐私收敛应用清单");
                return true;
            case 12:
                showCmd(new Cmd() { public String run() { return RootShell.hookStatus(); } }, "Hook 能力与事件");
                return true;
            case 13:
                showCmd(new Cmd() { public String run() { return RootShell.hookEvents(50); } }, "最近 Hook 事件");
                return true;
            case 14:
                runCmd(new Cmd() { public String run() { return cycleHookMode(); } }, "切换 Hook 模式");
                return true;
            case 15:
                runCmd(new Cmd() { public String run() { return RootShell.hookClear(); } }, "清空 Hook 事件");
                return true;
            case 16:
                runCmd(new Cmd() { public String run() { return RootShell.carrierToggle(true); } }, "运营商隐私收敛");
                return true;
            case 17:
                showCmd(new Cmd() { public String run() { return RootShell.rootStatus(); } }, "Root 权限状态");
                return true;
            case 5:
                new android.app.AlertDialog.Builder(this)
                        .setTitle(R.string.app_name)
                        .setMessage("SY Fusion 内置管理器\n\n"
                                + "面板地址：" + PanelApi.base(port) + "\n"
                                + "模块目录：" + RootShell.MODDIR + "\n"
                                + "root：" + (RootShell.hasRoot() ? "可用" : "不可用") + "\n\n"
                                + "本 App 只做三件事：拉起面板、展示状态、"
                                + "转发需要 root 的操作。所有配置都在模块面板里完成。")
                        .setPositiveButton("知道了", null)
                        .show();
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
    }

    private void runRootAsync(final String ignored, final String what) {
        toast(what + "…");
        new Thread(new Runnable() {
            @Override
            public void run() {
                String out;
                if (what.startsWith("重启")) out = RootShell.restartCore();
                else out = RootShell.stopCore();
                final String msg = (out == null || out.trim().length() == 0)
                        ? (what + "完成") : firstLine(out);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        toast(msg);
                        ui.postDelayed(new Runnable() {
                            @Override
                            public void run() {
                                pollOnce();
                            }
                        }, 1500);
                    }
                });
            }
        }, "root-op").start();
    }

    /** 异步执行 leakguard 操作，完成后 toast 首行结果。 */
    private void runLeakAsync(final String ignored, final String what) {
        toast(what + "…");
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String out;
                if (what.startsWith("开启")) out = RootShell.leakAll(true);
                else if (what.startsWith("关闭")) out = RootShell.leakAll(false);
                else if (what.startsWith("应急")) out = RootShell.leakPanic();
                else out = RootShell.leakRestore();
                final String msg = (out == null || out.trim().length() == 0)
                        ? (what + "完成") : firstLine(out);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        toast(msg);
                    }
                });
            }
        }, "leak-op").start();
    }

    /** 命令式取值（后台执行，避免阻塞 UI 线程）。 */
    private interface Cmd {
        String run();
    }

    private void showCmd(final Cmd cmd, final String title) {
        toast(title + "…");
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String out = cmd.run();
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        new android.app.AlertDialog.Builder(MainActivity.this)
                                .setTitle(title)
                                .setMessage(out == null || out.length() == 0 ? "无输出" : out)
                                .setPositiveButton("知道了", null)
                                .show();
                    }
                });
            }
        }, "sy-cmd").start();
    }

    private void runCmd(final Cmd cmd, final String what) {
        toast(what + "…");
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String out = cmd.run();
                final String msg = (out == null || out.trim().length() == 0) ? (what + "完成") : firstLine(out);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        toast(msg);
                    }
                });
            }
        }, "sy-cmd-run").start();
    }

    /** Hook 模式循环：targets → all → off → targets。 */
    private String cycleHookMode() {
        String cur = RootShell.hookMode(null);
        if (cur == null) cur = "targets";
        cur = cur.trim();
        String next = "targets".equals(cur) ? "all" : ("all".equals(cur) ? "off" : "targets");
        String r = RootShell.hookMode(next);
        return "hook mode: " + cur + " -> " + next + "\n" + r;
    }

    /** 异步取一段文本并弹窗展示（状态/清单）。 */
    private void showTextAsync(final String command, final String title) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String out = command;
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        new android.app.AlertDialog.Builder(MainActivity.this)
                                .setTitle(title)
                                .setMessage(out == null || out.length() == 0 ? "无输出" : out)
                                .setPositiveButton("知道了", null)
                                .show();
                    }
                });
            }
        }, "leak-show").start();
    }

    private static String firstLine(String s) {
        int i = s.indexOf('\n');
        String l = i >= 0 ? s.substring(0, i) : s;
        return l.length() > 90 ? l.substring(0, 90) + "…" : l;
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    private int dp(int v) {
        return Math.round(getResources().getDisplayMetrics().density * v);
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ignored) {
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        startPolling();
    }

    @Override
    protected void onPause() {
        super.onPause();
        ui.removeCallbacks(poll);
        polling = false;
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        ui.removeCallbacks(poll);
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
