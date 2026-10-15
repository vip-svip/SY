package com.syfusion.manager;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * SY 管理器 · 原生主界面。
 *
 * 设计（按用户要求：本地 App + 联动模块，不联动网页）：
 *   · 完全原生控件，没有任何 WebView；
 *   · 所有数据与操作直接调用模块脚本（RootShell），不经 HTTP、
 *     不依赖面板进程 —— 面板没启动也能用全部功能；
 *   · 底部 4 个入口：状态 / 防护 / 代理 / 更多；
 *   · "打开网页面板"仍保留在「更多」里作为可选高级入口，
 *     但它不再是 App 的主界面。
 *
 * 为什么这么改：
 *   · 网页套壳启动慢、断网/面板未起时会显示系统错误页，像崩溃；
 *   · 原生控件的触摸、返回键、无障碍、深色模式与系统一致；
 *   · 联动脚本才是"模块 App"该有的形态，跨手机兼容性也更好。
 */
public class SyNativeActivity extends Activity {

    private final Handler ui = new Handler(Looper.getMainLooper());
    private LinearLayout content;
    private final TextView[] navItems = new TextView[4];
    private int curNav = 0;
    private final String[] NAV_LABELS = {"状态", "防护", "代理", "更多"};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.BG);

        TextView head = Ui.title(this, "SY 管理器");
        head.setPadding(Ui.dp(this, 16), Ui.dp(this, 14), Ui.dp(this, 16), Ui.dp(this, 4));
        root.addView(head, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        ScrollView sv = new ScrollView(this);
        content = Ui.column(this);
        content.setPadding(Ui.dp(this, 14), Ui.dp(this, 6), Ui.dp(this, 14), Ui.dp(this, 80));
        sv.addView(content);
        root.addView(sv, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        root.addView(buildNav(), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);
        showTab(0);
    }

    private View buildNav() {
        LinearLayout navBar = new LinearLayout(this);
        navBar.setOrientation(LinearLayout.HORIZONTAL);
        navBar.setBackgroundColor(Ui.SURFACE);
        navBar.setPadding(Ui.dp(this, 6), Ui.dp(this, 8), Ui.dp(this, 6), Ui.dp(this, 10));
        for (int i = 0; i < NAV_LABELS.length; i++) {
            final int idx = i;
            TextView t = new TextView(this);
            t.setText(NAV_LABELS[i]);
            t.setGravity(Gravity.CENTER);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f);
            t.setTextColor(Ui.DIM);
            t.setPadding(0, Ui.dp(this, 8), 0, Ui.dp(this, 8));
            t.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { showTab(idx); }
            });
            navItems[i] = t;
            navBar.addView(t, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
        return navBar;
    }

    private void paintNav() {
        for (int i = 0; i < navItems.length; i++) {
            navItems[i].setTextColor(i == curNav ? Ui.ACCENT : Ui.DIM);
            navItems[i].setTypeface(null, i == curNav ? Typeface.BOLD : Typeface.NORMAL);
        }
    }

    private void showTab(int idx) {
        curNav = idx;
        paintNav();
        content.removeAllViews();
        if (idx == 0) buildStatusTab();
        else if (idx == 1) buildGuardTab();
        else if (idx == 2) buildProxyTab();
        else buildMoreTab();
    }

    /* ---------------- 状态 ---------------- */

    private void buildStatusTab() {
        final LinearLayout c1 = Ui.card(this, "模块");
        final LinearLayout b1 = Ui.body(c1);
        b1.addView(Ui.hint(this, "以下数据全部来自模块脚本本身，与网页面板无关。"));
        content.addView(c1);

        final LinearLayout c2 = Ui.card(this, "运行状态");
        final LinearLayout b2 = Ui.body(c2);
        content.addView(c2);

        final LinearLayout c3 = Ui.card(this, "设备与兼容性");
        final LinearLayout b3 = Ui.body(c3);
        content.addView(c3);

        content.addView(Ui.rowOf(this,
                Ui.button(this, "刷新", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { loadStatus(b1, b2, b3); }
                }),
                Ui.button(this, "模块自检", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("模块自检", RootShell.selfCheck()); }
                })));
        loadStatus(b1, b2, b3);
    }

    private void loadStatus(final LinearLayout mod, final LinearLayout st, final LinearLayout dev) {
        mod.removeAllViews(); mod.addView(Ui.hint(this, "读取中…"));
        st.removeAllViews();  st.addView(Ui.hint(this, "读取中…"));
        dev.removeAllViews(); dev.addView(Ui.hint(this, "读取中…"));
        new Thread(new Runnable() {
            @Override public void run() {
                final String rootInfo = RootShell.rootStatus();
                final String devInfo = RootShell.deviceInfo();
                final String core = RootShell.proxyRunStatus();
                final String dns = RootShell.dnsStatus();
                final String fx = RootShell.fxStatus();
                final String clip = RootShell.clipStatus();
                ui.post(new Runnable() { @Override public void run() {
                    mod.removeAllViews();
                    for (String line : lines(rootInfo)) mod.addView(Ui.kv(SyNativeActivity.this, split(line)[0], split(line)[1])[0]);
                    st.removeAllViews();
                    st.addView(Ui.kv(SyNativeActivity.this, "内核", Jake.str(core, "version") + " · " + Jake.str(core, "running"))[0]);
                    st.addView(Ui.kv(SyNativeActivity.this, "DNS 拦截", Jake.str(dns, "rule_count") + " 条")[0]);
                    st.addView(Ui.kv(SyNativeActivity.this, "FX", "开关 " + Jake.str(fx, "enabled") + " · 域名 " + Jake.str(fx, "active_domains"))[0]);
                    st.addView(Ui.kv(SyNativeActivity.this, "剪贴板", Jake.str(clip, "running"))[0]);
                    dev.removeAllViews();
                    for (String line : lines(devInfo)) dev.addView(Ui.kv(SyNativeActivity.this, split(line)[0], split(line)[1])[0]);
                }});
            }
        }, "sy-status").start();
    }

    /* ---------------- 防护 ---------------- */

    private void buildGuardTab() {
        final LinearLayout c1 = Ui.card(this, "一键全防护");
        final LinearLayout b1 = Ui.body(c1);
        b1.addView(Ui.hint(this, "开启隐私护盾 + FX 深度抵抗 + 剪贴板监视，每一项都能单独关。"));
        b1.addView(Ui.rowOf(this,
                Ui.button(this, "一键开启全部", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("一键开启", new Call() {
                        public String run() { return RootShell.oneClickOn(); } }); }
                }),
                Ui.button(this, "一键关闭还原", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("一键关闭", new Call() {
                        public String run() { return RootShell.oneClickOff(); } }); }
                })));
        content.addView(c1);

        final LinearLayout c2 = Ui.card(this, "隐私防泄露");
        final LinearLayout b2 = Ui.body(c2);
        b2.addView(Ui.hint(this, "DNS / IPv6 / 出口 IP / VPN 击杀 / 节点防泄露。"));
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "查看状态", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("隐私防泄露状态", RootShell.leakStatus()); }
                }),
                Ui.button(this, "开启", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("开启防泄露", new Call() {
                        public String run() { return RootShell.leakAll(true); } }); }
                }),
                Ui.button(this, "关闭", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("关闭防泄露", new Call() {
                        public String run() { return RootShell.leakAll(false); } }); }
                })));
        content.addView(c2);

        final LinearLayout c3 = Ui.card(this, "FX 深度抵抗");
        final LinearLayout b3 = Ui.body(c3);
        b3.addView(Ui.hint(this, "阻断设备指纹 / 风控上报 / 埋点 / 安装清单上传等端点。"));
        b3.addView(Ui.rowOf(this,
                Ui.button(this, "查看报告", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("FX 深度抵抗报告", RootShell.fxReport()); }
                }),
                Ui.button(this, "应急恢复", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("应急恢复", new Call() {
                        public String run() { return RootShell.leakPanic(); } }); }
                })));
        content.addView(c3);

        final LinearLayout c4 = Ui.card(this, "Hook 与注入");
        final LinearLayout b4 = Ui.body(c4);
        final EditText et = new EditText(this);
        et.setHint("每行一条：标签 类名#方法名；或粘贴任意规则（自动识别语法）");
        et.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        et.setTextColor(Ui.TEXT);
        et.setHintTextColor(Ui.DIM);
        et.setMinLines(3);
        et.setPadding(Ui.dp(this, 8), Ui.dp(this, 8), Ui.dp(this, 8), Ui.dp(this, 8));
        b4.addView(Ui.hint(this, "支持：域名 / ||domain^ / 正则 / ##选择器 / hosts / AdGuard 语法。"));
        b4.addView(et);
        b4.addView(Ui.rowOf(this,
                Ui.button(this, "识别（只看结果）", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("识别结果", RootShell.hookRulesAnalyze(et.getText().toString())); }
                }),
                Ui.button(this, "导入并应用", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("导入规则", new Call() {
                        public String run() { return RootShell.hookRulesImport(et.getText().toString()); } }); }
                })));
        b4.addView(Ui.rowOf(this,
                Ui.button(this, "Hook 状态", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("Hook 状态", RootShell.hookStatus()); }
                }),
                Ui.button(this, "Hook 事件", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("Hook 事件", RootShell.hookEvents(40)); }
                }),
                Ui.button(this, "清空事件", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("清空事件", new Call() {
                        public String run() { return RootShell.hookClear(); } }); }
                })));
        content.addView(c4);
    }

    /* ---------------- 代理 ---------------- */

    private void buildProxyTab() {
        final LinearLayout c1 = Ui.card(this, "内核状态");
        final LinearLayout b1 = Ui.body(c1);
        content.addView(c1);

        content.addView(Ui.rowOf(this,
                Ui.button(this, "启动内核", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("启动内核", new Call() {
                        public String run() { return RootShell.script("proxyrun.sh", "start"); } }); }
                }),
                Ui.button(this, "停止", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("停止内核", new Call() {
                        public String run() { return RootShell.script("proxyrun.sh", "stop"); } }); }
                }),
                Ui.button(this, "重启", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("重启内核", new Call() {
                        public String run() { return RootShell.script("proxyrun.sh", "restart"); } }); }
                })));

        final LinearLayout c2 = Ui.card(this, "生效验证");
        final LinearLayout b2 = Ui.body(c2);
        b2.addView(Ui.hint(this, "逐步检查：配置语法 / 内核进程 / 控制 API / 数据面 / 真实连通性。"));
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "验证是否生效", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("生效验证", RootShell.proxyVerify()); }
                }),
                Ui.button(this, "健康检查", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("健康检查", RootShell.proxyHealth()); }
                })));
        content.addView(c2);

        final LinearLayout c3 = Ui.card(this, "运行模式");
        final LinearLayout b3 = Ui.body(c3);
        b3.addView(Ui.hint(this, "直连=全部不走代理；全局=全部走代理；规则=按规则分流。"));
        b3.addView(Ui.rowOf(this,
                Ui.button(this, "直连", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("切换直连", new Call() {
                        public String run() { return RootShell.proxyMode("direct"); } }); }
                }),
                Ui.button(this, "全局", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("切换全局", new Call() {
                        public String run() { return RootShell.proxyMode("global"); } }); }
                }),
                Ui.button(this, "规则", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("切换规则", new Call() {
                        public String run() { return RootShell.proxyMode("rule"); } }); }
                })));
        content.addView(c3);

        final LinearLayout c4 = Ui.card(this, "节点");
        final LinearLayout b4 = Ui.body(c4);
        final TextView nodeOut = new TextView(this);
        nodeOut.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        nodeOut.setTextColor(Ui.TEXT);
        nodeOut.setTypeface(Typeface.MONOSPACE);
        b4.addView(Ui.hint(this, "节点详细数据（协议/服务器/端口/加密/SNI/传输）。"));
        b4.addView(nodeOut);
        b4.addView(Ui.rowOf(this,
                Ui.button(this, "读取节点", true, new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        nodeOut.setText("读取中…");
                        new Thread(new Runnable() {
                            @Override public void run() {
                                final String s = RootShell.nodesList();
                                ui.post(new Runnable() { @Override public void run() {
                                    nodeOut.setText(Jake.prettyNodes(s)); } });
                            }
                        }, "sy-nodes").start();
                    }
                }),
                Ui.button(this, "重建索引", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("重建节点索引", new Call() {
                        public String run() { return RootShell.nodesBuildMeta(); } }); }
                })));
        content.addView(c4);

        final LinearLayout c5 = Ui.card(this, "支持的协议");
        final LinearLayout b5 = Ui.body(c5);
        b5.addView(Ui.hint(this, "读取中…"));
        content.addView(c5);
        new Thread(new Runnable() {
            @Override public void run() {
                final String p = RootShell.protocols();
                ui.post(new Runnable() { @Override public void run() {
                    b5.removeAllViews();
                    b5.addView(Ui.hint(SyNativeActivity.this,
                            "内核支持：" + (p == null ? "?" : p.replace('\n', ' ')))); } });
            }
        }, "sy-proto").start();

        loadProxyStatus(b1);
    }

    private void loadProxyStatus(final LinearLayout box) {
        box.removeAllViews();
        box.addView(Ui.hint(this, "读取中…"));
        new Thread(new Runnable() {
            @Override public void run() {
                final String core = RootShell.proxyRunStatus();
                final String mgr = RootShell.proxyMgrStatus();
                ui.post(new Runnable() { @Override public void run() {
                    box.removeAllViews();
                    box.addView(Ui.kv(SyNativeActivity.this, "内核", Jake.str(core, "version") + " · " + Jake.str(core, "arch"))[0]);
                    box.addView(Ui.kv(SyNativeActivity.this, "运行",
                            "true".equals(Jake.str(core, "running")) || "yes".equals(Jake.str(core, "running"))
                                    ? "运行中 (PID " + Jake.str(core, "pid") + ")" : "未运行")[0]);
                    box.addView(Ui.kv(SyNativeActivity.this, "生命周期", Jake.str(mgr, "lifecycle"))[0]);
                    box.addView(Ui.kv(SyNativeActivity.this, "整体就绪", Jake.bool(mgr, "readiness") ? "是" : "否")[0]);
                    box.addView(Ui.kv(SyNativeActivity.this, "配置", "yes".equals(Jake.str(core, "config")) ? "已生成" : "未生成")[0]);
                    box.addView(Ui.kv(SyNativeActivity.this, "节点数", Jake.str(core, "nodes"))[0]);
                }});
            }
        }, "sy-proxy").start();
    }

    /* ---------------- 更多 ---------------- */

    private void buildMoreTab() {
        final LinearLayout c1 = Ui.card(this, "内置规则（8 份）");
        final LinearLayout b1 = Ui.body(c1);
        b1.addView(Ui.hint(this, "去水印 / 反广告拦截 / 阻止诱导下载 / 广告域名 / 反拦截 / 反诈 / 推送 / 追踪器。"));
        b1.addView(Ui.rowOf(this,
                Ui.button(this, "读取清单", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("内置规则", RootShell.builtinRules()); }
                }),
                Ui.button(this, "汇总应用", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("应用规则", new Call() {
                        public String run() { return RootShell.script("builtin_rules.sh", "apply"); } }); }
                })));
        content.addView(c1);

        final LinearLayout c2 = Ui.card(this, "模块与 App");
        final LinearLayout b2 = Ui.body(c2);
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "App 自检修复", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("App 自检修复", new Call() {
                        public String run() { return RootShell.appEnsure(); } }); }
                }),
                Ui.button(this, "模块自检", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("模块自检", RootShell.selfCheck()); }
                })));
        content.addView(c2);

        final LinearLayout c3 = Ui.card(this, "高级：网页面板");
        final LinearLayout b3 = Ui.body(c3);
        b3.addView(Ui.hint(this, "面板网页功能更全（30 个页面）。App 本身已能用核心功能，这里只是可选的补充入口。"));
        b3.addView(Ui.rowOf(this,
                Ui.button(this, "启动面板", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("启动面板", new Call() {
                        public String run() { return RootShell.startPanel(); } }); }
                }),
                Ui.button(this, "用浏览器打开", true, new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        int port = getSharedPreferences("sy", MODE_PRIVATE).getInt("port", PanelApi.DEFAULT_PORT);
                        try {
                            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(PanelApi.base(port) + "/")));
                        } catch (Exception e) { toast("没有可用的浏览器"); }
                    }
                })));
        content.addView(c3);

        final LinearLayout c4 = Ui.card(this, "关于");
        final LinearLayout b4 = Ui.body(c4);
        b4.addView(Ui.kv(this, "App 版本", "1.0.6")[0]);
        b4.addView(Ui.kv(this, "模块目录", RootShell.MODDIR)[0]);
        b4.addView(Ui.kv(this, "Root", RootShell.hasRoot() ? "可用" : "不可用")[0]);
        b4.addView(Ui.hint(this, "本 App 是纯原生界面，直接调用模块脚本，不加载网页。"));
        content.addView(c4);
    }

    /* ---------------- 通用 ---------------- */

    private interface Call { String run(); }

    private void runAndShow(final String title, final Call c) {
        toast(title + "…");
        new Thread(new Runnable() {
            @Override public void run() {
                final String out = c.run();
                ui.post(new Runnable() { @Override public void run() {
                    showText(title, out);
                    if (curNav == 2) showTab(2);
                }});
            }
        }, "sy-cmd").start();
    }

    private void showText(final String title, final String body) {
        String s = (body == null || body.trim().length() == 0) ? "(无输出)" : body.trim();
        if (s.length() > 4000) s = s.substring(0, 4000) + "\n…（已截断）";
        new android.app.AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(s)
                .setPositiveButton("知道了", null)
                .show();
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    private static String[] lines(String s) {
        return s == null ? new String[0] : s.split("\n");
    }

    private static String[] split(String line) {
        int i = line.indexOf(':');
        if (i < 0) return new String[]{line, ""};
        return new String[]{line.substring(0, i).trim(), line.substring(i + 1).trim()};
    }
}
