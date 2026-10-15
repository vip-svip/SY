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
    private LinearLayout navHolder;
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
        // 底部导航：替代原来的右上角三个点菜单
        root.addView(web, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        navHolder = buildBottomNav();
        root.addView(navHolder, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentView(root);
        askNotificationPermission();
        ensurePanelAndLoad();
    }

    /* ============================================================
     *  底部导航（替代原来的右上角三个点菜单）
     *  为什么改：三个点菜单是 17 个扁平项，用户要一次次展开才知道有什么；
     *  改成底部 4 个入口后，一级直达、二级用「更多」页列出全部能力。
     *  这也和模块 WebUI 的底部导航保持一致（同一个信息架构）。
     * ============================================================ */
    private LinearLayout navBar;
    private final java.util.List<TextView> navItems = new java.util.ArrayList<TextView>();
    private final String[] NAV_LABELS = {"面板", "状态", "防护", "更多"};
    private int curNav = 0;

    private LinearLayout buildBottomNav() {
        navBar = new LinearLayout(this);
        navBar.setOrientation(LinearLayout.HORIZONTAL);
        navBar.setBackgroundColor(getColor(R.color.surface));
        navBar.setPadding(dp(4), dp(4), dp(4), dp(6));
        for (int i = 0; i < NAV_LABELS.length; i++) {
            final int idx = i;
            TextView t = new TextView(this);
            t.setText(NAV_LABELS[i]);
            t.setGravity(Gravity.CENTER);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            t.setTextColor(getColor(R.color.text_dim));
            t.setPadding(dp(4), dp(10), dp(4), dp(10));
            t.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { onNavPick(idx); }
            });
            navItems.add(t);
            navBar.addView(t, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
        paintNav();
        return navBar;
    }

    private void paintNav() {
        for (int i = 0; i < navItems.size(); i++) {
            navItems.get(i).setTextColor(getColor(i == curNav ? R.color.accent : R.color.text_dim));
        }
    }

    private void onNavPick(int idx) {
        curNav = idx;
        paintNav();
        switch (idx) {
            case 0:
                // 面板：载入 WebUI 首页（把 17 个菜单项的位置交给面板本身）
                web.loadUrl(PanelApi.base(port) + "/");
                break;
            case 1:
                showTextAsync(RootShell.rootStatus(), "运行状态");
                break;
            case 2:
                showDefenseSheet();
                break;
            case 3:
                showMoreSheet();
                break;
        }
    }

    /* 「防护」页：把原本散在菜单里的隐私类操作集中起来，每个都是明确的按钮 */
    private void showDefenseSheet() {
        final LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(12), dp(8), dp(12), dp(8));
        box.setBackgroundColor(getColor(R.color.bg));
        addAction(box, "隐私防泄露状态", new Runnable() {
            @Override public void run() {
                showCmd(new Cmd() { public String run() { return RootShell.leakStatus(); } }, "隐私防泄露状态");
            }
        });
        addAction(box, "开启全部隐私防护", new Runnable() {
            @Override public void run() {
                runLeakAsync(RootShell.leakAll(true), "开启全部隐私防护");
            }
        });
        addAction(box, "关闭全部隐私防护", new Runnable() {
            @Override public void run() {
                runLeakAsync(RootShell.leakAll(false), "关闭全部隐私防护");
            }
        });
        addAction(box, "运营商隐私收敛", new Runnable() {
            @Override public void run() {
                runRootAsync(RootShell.carrierToggle(true), "运营商隐私收敛");
            }
        });
        addAction(box, "紧急恢复（还原全部改动）", new Runnable() {
            @Override public void run() {
                runLeakAsync(RootShell.leakPanic(), "紧急恢复");
            }
        });
        addAction(box, "恢复上次状态", new Runnable() {
            @Override public void run() {
                runLeakAsync(RootShell.leakRestore(), "恢复上次状态");
            }
        });
        new android.app.AlertDialog.Builder(this)
                .setTitle("防护")
                .setView(scroll(box))
                .setPositiveButton("关闭", null)
                .show();
    }

    /* 「更多」页：内核/主题/Hook/关于 —— 原本三个点菜单里的项全部在这 */
    private void showMoreSheet() {
        final LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(12), dp(8), dp(12), dp(8));
        box.setBackgroundColor(getColor(R.color.bg));
        addAction(box, "刷新面板", new Runnable() {
            @Override public void run() { web.reload(); toast("已刷新"); }
        });
        addAction(box, "用浏览器打开", new Runnable() {
            @Override public void run() {
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(PanelApi.base(port) + "/")));
                } catch (Exception e) { toast("没有可用的浏览器"); }
            }
        });
        addAction(box, "重启内核", new Runnable() {
            @Override public void run() { runRootAsync(RootShell.restartCore(), "重启内核"); }
        });
        addAction(box, "停止内核", new Runnable() {
            @Override public void run() { runRootAsync(RootShell.stopCore(), "停止内核"); }
        });
        addAction(box, "切换主题（跟随面板）", new Runnable() {
            @Override public void run() { toggleTheme(); }
        });
        addAction(box, "Hook 状态", new Runnable() {
            @Override public void run() {
                showTextAsync(RootShell.hookStatus(), "Hook 状态");
            }
        });
        addAction(box, "Hook 事件记录", new Runnable() {
            @Override public void run() {
                showTextAsync(RootShell.hookEvents(30), "Hook 事件记录");
            }
        });
        addAction(box, "切换 Hook 模式", new Runnable() {
            @Override public void run() {
                toast(cycleHookMode());
            }
        });
        addAction(box, "清空 Hook 记录", new Runnable() {
            @Override public void run() {
                runRootAsync(RootShell.hookClear(), "清空 Hook 记录");
            }
        });
        addAction(box, "Root 权限状态", new Runnable() {
            @Override public void run() {
                showCmd(new Cmd() { public String run() { return RootShell.rootStatus(); } }, "Root 权限状态");
            }
        });
        addAction(box, "关于", new Runnable() {
            @Override public void run() { showAbout(); }
        });
        new android.app.AlertDialog.Builder(this)
                .setTitle("更多")
                .setView(scroll(box))
                .setPositiveButton("关闭", null)
                .show();
    }

    private View scroll(View v) {
        android.widget.ScrollView sv = new android.widget.ScrollView(this);
        sv.addView(v);
        return sv;
    }

    private void addAction(LinearLayout parent, String label, final Runnable act) {
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        t.setTextColor(getColor(R.color.text));
        t.setPadding(dp(10), dp(14), dp(10), dp(14));
        t.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { act.run(); }
        });
        parent.addView(t, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    /* 主题：App 侧跟随系统深浅色（面板内部有自己的主题，两者各自独立） */
    private void toggleTheme() {
        int cur = getResources().getConfiguration().uiMode
                & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        boolean dark = cur == android.content.res.Configuration.UI_MODE_NIGHT_YES;
        android.content.SharedPreferences sp = getSharedPreferences("sy", MODE_PRIVATE);
        sp.edit().putBoolean("app_dark", !dark).apply();
        applyAppTheme(!dark);
        toast(!dark ? "App 主题：深色" : "App 主题：浅色");
    }

    private void applyAppTheme(boolean dark) {
        int bg = dark ? Color.parseColor("#0E1116") : Color.parseColor("#F6F7F9");
        int surface = dark ? Color.parseColor("#161B22") : Color.parseColor("#FFFFFF");
        int text = dark ? Color.parseColor("#E6EDF3") : Color.parseColor("#1F2328");
        int dim = dark ? Color.parseColor("#8B949E") : Color.parseColor("#6E7781");
        findViewById(android.R.id.content).setBackgroundColor(bg);
        if (navBar != null) navBar.setBackgroundColor(surface);
        web.setBackgroundColor(bg);
        appDark = dark;
        // 状态条与导航文字一起刷新
        for (TextView t : navItems) t.setTextColor(t == navItems.get(curNav) ? getColor(R.color.accent) : dim);
        setStatColors(text, dim);
    }

    private boolean appDark = true;
    private void setStatColors(int text, int dim) {
        TextView[] all = {tvCore, tvMode, tvUp, tvDown, tvConn};
        for (TextView t : all) if (t != null) t.setTextColor(text);
    }

    private void showAbout() {
        new android.app.AlertDialog.Builder(this)
                .setTitle(R.string.app_name)
                .setMessage("SY 内置管理器\n\n"
                        + "面板地址：" + PanelApi.base(port) + "\n"
                        + "模块目录：" + RootShell.MODDIR + "\n"
                        + "root：" + (RootShell.hasRoot() ? "可用" : "不可用") + "\n\n"
                        + "本 App 做四件事：拉起面板、展示状态、转发需要 root 的操作、"
                        + "承载 Hook 与无障碍跳广告。所有配置都在模块面板里完成。")
                .setPositiveButton("知道了", null)
                .show();
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
