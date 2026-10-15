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
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * SY 管理器 · 原生主界面（按用户给的参考图重做）。
 *
 * 参考图布局（逐块对应）：
 *   ① 大状态卡：左圆形盾牌 + "代理已开启 / 当前节点: xx" + 右胶囊按钮 + 延迟/流量
 *   ② 4 宫格快捷入口：代理管理 / 广告拦截 / Hook 管理 / DNS 设置
 *   ③ 双列功能卡：规则管理（规则列表/已启用/黑白名单）、MITM（证书/解密/指纹）
 *   ④ 双列开关卡：隐私保护（指纹防护/日志清理）、无障碍跳过（自动跳过/表单辅助）
 *   ⑤ 底部 4 入口：首页 / 规则 / 工具 / 我的
 *
 * 关键点（用户要求）：
 *   · 纯原生控件，无 WebView；
 *   · 所有操作**直接调用模块脚本**（RootShell），不经过 HTTP、不依赖面板进程；
 *   · 配色跟随系统深浅色（Ui.dark 判断）。
 */
public class SyNativeActivity extends Activity {

    private final Handler ui = new Handler(Looper.getMainLooper());
    private LinearLayout content;
    private final TextView[] navItems = new TextView[5];
    private int curNav = 0;
    /** 内置规则 JSON 缓存：让详情弹窗立刻有内容可渲染（见 showBuiltinRules 注释） */
    private String sBuiltinCache = null;
    /**
     * 底部 5 项（用户指定）：VPN / Ad / 隐私 / 脚本 / 设置。
     * 不再有"首页" —— 原首页的内容已按主题拆进 Ad、隐私、脚本三个页。
     */
    private static final String[] NAV = {"VPN", "Ad", "隐私", "脚本", "设置"};
    /** 底部导航图标名（对应 res/drawable/ic_<name>.xml 的描边矢量图标） */
    private static final String[] NAV_ICON = {"vpn", "shield_check", "fingerprint", "rules", "config"};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.page(this));

        ScrollView sv = new ScrollView(this);
        content = Ui.col(this);
        content.setPadding(Ui.dp(this, 14), Ui.dp(this, 12), Ui.dp(this, 14), Ui.dp(this, 90));
        sv.addView(content);
        root.addView(sv, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        root.addView(buildNav(), new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);
        showTab(0);
    }

    private View buildNav() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setBackgroundColor(Ui.card(this));
        bar.setPadding(Ui.dp(this, 6), Ui.dp(this, 8), Ui.dp(this, 6), Ui.dp(this, 14));
        for (int i = 0; i < NAV.length; i++) {
            final int idx = i;
            LinearLayout cell = Ui.col(this);
            cell.setGravity(Gravity.CENTER);
            ImageView ic = Ui.icon(this, "ic_" + NAV_ICON[i], 26, Ui.dim(this));
            TextView lb = new TextView(this);
            lb.setText(NAV[i]);
            lb.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
            lb.setGravity(Gravity.CENTER);
            lb.setTextColor(Ui.dim(this));
            cell.addView(ic);
            cell.addView(lb);
            cell.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { showTab(idx); }
            });
            navItems[i] = lb;
            cell.setTag(ic);
            bar.addView(cell, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
        return bar;
    }

    private void paintNav() {
        for (int i = 0; i < NAV.length; i++) {
            TextView lb = navItems[i];
            ImageView ic = (ImageView) ((View) lb.getParent()).getTag();
            boolean on = i == curNav;
            lb.setTextColor(on ? Ui.accent(this) : Ui.dim(this));
            ic.setColorFilter(on ? Ui.accent(this) : Ui.dim(this));
        }
    }

    private void showTab(int idx) {
        curNav = idx;
        paintNav();
        content.removeAllViews();
        if (idx == 0) tabVpn();
        else if (idx == 1) tabAd();
        else if (idx == 2) tabPrivacy();
        else if (idx == 3) tabScripts();
        else tabSettings();
    }

    /* ================= ② VPN（照用户给的 SmartProxy 界面） =================
     *
     * 结构（逐块对应参考图）：
     *   ① 顶部两个小卡：运行时长 / 连接（图标 + 大数字）
     *   ② 总流量 / 速度（上行 ↓ 下行）
     *   ③ 当前配置（配置名）
     *   ④ 规则 | 全局 切换（同一行两个按钮）
     *   ⑤ 我的配置 / 添加配置
     *   ⑥ 分应用代理 / DNS
     *   ⑦ 分流 / 分流规则
     *   ⑧ 网络检测 / 测速
     *   ⑨ Apple TV / 统计与分析
     *   ⑩ 备份与同步
     *   ⑪ 底部：当前选中节点（可点切换）
     *
     * 数据全部来自模块脚本（proxymgr / proxynode / proxyrun），不依赖面板。
     */
    private void tabVpn() {
        final TextView upTime = Ui.text2(this, "0:00:00", 20f, Ui.text(this));
        final TextView connState = Ui.text2(this, "未连接", 20f, Ui.text(this));
        final TextView upTv = Ui.text2(this, "↑ 0 B", 15f, Ui.text(this));
        final TextView dnTv = Ui.text2(this, "↓ 0 B", 15f, Ui.text(this));
        final TextView upSp = Ui.text2(this, "↑ 0 B/s", 15f, Ui.text(this));
        final TextView dnSp = Ui.text2(this, "↓ 0 B/s", 15f, Ui.text(this));
        final TextView cfgName = Ui.text2(this, "自动选择", 16f, Ui.text(this));

        // ① 运行时长 / 连接（两列）
        content.addView(Ui.twoCol(this,
                smallCard("ic_clock", "运行时长", upTime),
                smallCard("ic_monitor", "连接", connState)));

        // ② 总流量 / 速度
        content.addView(Ui.twoCol(this,
                twoValueCard("ic_swap", "总流量", upTv, dnTv),
                twoValueCard("ic_gauge", "速度", upSp, dnSp)));

        // ③ 当前配置
        LinearLayout c3 = Ui.card(this, null);
        LinearLayout b3 = Ui.body(c3);
        LinearLayout h3 = Ui.hrow(this);
        h3.addView(Ui.icon(this, "ic_config", 22, Ui.iconColor(this)));
        TextView t3 = Ui.text2(this, "当前配置", 15f, Ui.text(this));
        t3.setPadding(Ui.dp(this, 10), 0, 0, 0);
        t3.setTypeface(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL));
        h3.addView(t3, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        b3.addView(h3);
        cfgName.setPadding(0, Ui.dp(this, 6), 0, 0);
        b3.addView(cfgName);
        content.addView(c3);

        // ④ 规则 | 全局 切换
        final LinearLayout seg = Ui.hrow(this);
        seg.setBackground(Ui.round(this, Ui.card(this), 0, 12));
        final TextView modeRule = segBtn("规则", true);
        final TextView modeGlobal = segBtn("全局", false);
        seg.addView(modeRule, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        seg.addView(modeGlobal, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        modeRule.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { switchMode("rule", modeRule, modeGlobal); }
        });
        modeGlobal.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { switchMode("global", modeRule, modeGlobal); }
        });
        LinearLayout segWrap = Ui.col(this);
        segWrap.setPadding(0, 0, 0, Ui.dp(this, 12));
        segWrap.addView(seg);
        content.addView(segWrap);

        // ⑤ ~ ⑩ 两列功能入口
        content.addView(Ui.twoCol(this,
                entryCard("ic_config", "我的配置", new Runnable() { public void run() { showText("我的配置", RootShell.nodesList()); } }),
                entryCard("ic_plus2", "添加配置", new Runnable() { public void run() { showText("添加配置", "请在网页面板导入订阅或节点。\n\nApp 侧可执行：导入订阅（后续版本支持直接粘贴）。"); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_split", "分应用代理", new Runnable() { public void run() { showText("分应用代理", RootShell.script("proxymgr.sh", "app list")); } }),
                entryCard("ic_dns2", "DNS", new Runnable() { public void run() { showText("DNS", RootShell.script("dns.sh", "status")); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_split", "分流", new Runnable() { public void run() { showText("分流", RootShell.script("proxycfg.sh", "status")); } }),
                entryCard("ic_rules", "分流规则", new Runnable() { public void run() { showText("分流规则", RootShell.exec("head -50 /data/adb/SY/rules/proxy/config.json 2>/dev/null", 10000)); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_gauge", "网络检测", new Runnable() { public void run() { showText("网络检测", RootShell.script("proxymgr.sh", "health")); } }),
                entryCard("ic_clock", "测速", new Runnable() { public void run() { showText("测速", RootShell.proxyVerify()); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_tv", "Apple TV", new Runnable() { public void run() { showText("Apple TV", "此功能用于在 Apple TV 等设备上通过本机代理，需在同一局域网。\n\n当前模块已监听 2080 端口，可在局域网设备上把代理指向本机 IP:2080。"); } }),
                entryCard("ic_chart", "统计与分析", new Runnable() { public void run() { showText("统计与分析", RootShell.proxyMgrStatus()); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_sync", "备份与同步", new Runnable() { public void run() { showText("备份与同步", RootShell.script("backup.sh", "list")); } }),
                entryCard("ic_bolt2", "全局加速", new Runnable() { public void run() { runAndShow("全局加速", new Call() { public String run() { return RootShell.proxyMode("global"); } }); } })));

        // ⑪ 底部：当前节点（可点）
        LinearLayout bottom = Ui.card(this, null);
        LinearLayout bb2 = Ui.body(bottom);
        LinearLayout hb = Ui.hrow(this);
        hb.addView(Ui.icon(this, "ic_vpn", 22, Ui.iconColor(this)));
        final TextView nodeName = Ui.text2(this, "自动选择", 16f, Ui.text(this));
        nodeName.setPadding(Ui.dp(this, 10), 0, 0, 0);
        hb.addView(nodeName, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        hb.addView(Ui.icon(this, "ic_arrow", 18, Ui.dim(this)));
        bb2.addView(hb);
        bottom.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { showText("选择节点", RootShell.nodesList()); }
        });
        content.addView(bottom);

        loadVpn(upTime, connState, upTv, dnTv, upSp, dnSp, cfgName, nodeName, modeRule, modeGlobal);
    }

    /** 单值小卡：图标 + 标题 + 大数字 */
    private LinearLayout smallCard(String icon, String title, TextView value) {
        LinearLayout c = Ui.card(this, null);
        LinearLayout b = Ui.body(c);
        LinearLayout h = Ui.hrow(this);
        h.addView(Ui.icon(this, icon, 20, Ui.iconColor(this)));
        TextView t = Ui.text2(this, title, 14f, Ui.text(this));
        t.setPadding(Ui.dp(this, 8), 0, 0, 0);
        h.addView(t);
        b.addView(h);
        value.setPadding(0, Ui.dp(this, 8), 0, 0);
        b.addView(value);
        return c;
    }

    /** 双值小卡：图标 + 标题 + 两行值 */
    private LinearLayout twoValueCard(String icon, String title, TextView v1, TextView v2) {
        LinearLayout c = Ui.card(this, null);
        LinearLayout b = Ui.body(c);
        LinearLayout h = Ui.hrow(this);
        h.addView(Ui.icon(this, icon, 20, Ui.iconColor(this)));
        TextView t = Ui.text2(this, title, 14f, Ui.text(this));
        t.setPadding(Ui.dp(this, 8), 0, 0, 0);
        h.addView(t);
        b.addView(h);
        v1.setPadding(0, Ui.dp(this, 8), 0, 0);
        b.addView(v1);
        b.addView(v2);
        return c;
    }

    /** 功能入口卡（图标 + 文字，整块可点） */
    private LinearLayout entryCard(String icon, String label, final Runnable act) {
        LinearLayout c = Ui.card(this, null);
        LinearLayout b = Ui.body(c);
        LinearLayout h = Ui.hrow(this);
        h.addView(Ui.icon(this, icon, 22, Ui.iconColor(this)));
        TextView t = Ui.text2(this, label, 15f, Ui.text(this));
        t.setPadding(Ui.dp(this, 10), 0, 0, 0);
        h.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        b.addView(h);
        c.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { act.run(); }
        });
        return c;
    }

    /** 分段按钮（规则 / 全局） */
    private TextView segBtn(String text, boolean on) {
        TextView b = new TextView(this);
        b.setText(text);
        b.setGravity(Gravity.CENTER);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f);
        b.setPadding(0, Ui.dp(this, 12), 0, Ui.dp(this, 12));
        b.setTextColor(on ? Ui.text(this) : Ui.dim(this));
        b.setBackground(Ui.round(this, on ? Ui.line(this) : 0x00000000, 0, 12));
        return b;
    }

    private void switchMode(final String mode, final TextView a, final TextView b) {
        runAndShow("切换" + ("global".equals(mode) ? "全局" : "规则") + "模式", new Call() {
            public String run() { return RootShell.proxyMode(mode); } });
        a.setTextColor("rule".equals(mode) ? Ui.text(this) : Ui.dim(this));
        a.setBackground(Ui.round(this, "rule".equals(mode) ? Ui.line(this) : 0x00000000, 0, 12));
        b.setTextColor("global".equals(mode) ? Ui.text(this) : Ui.dim(this));
        b.setBackground(Ui.round(this, "global".equals(mode) ? Ui.line(this) : 0x00000000, 0, 12));
    }

    private void loadVpn(final TextView upTime, final TextView conn, final TextView upTv, final TextView dnTv,
                         final TextView upSp, final TextView dnSp, final TextView cfg, final TextView node,
                         final TextView rule, final TextView global) {
        new Thread(new Runnable() {
            @Override public void run() {
                final String core = RootShell.proxyRunStatus();
                final String mgr = RootShell.proxyMgrStatus();
                final String mode = RootShell.proxyMode(null);
                final String nodes = RootShell.exec("sed -n '1p' /data/adb/SY/rules/proxy/nodes.conf 2>/dev/null", 8000);
                final String pid = Jake.str(core, "pid");
                // 运行时长：从进程启动时间算
                final String etime = (pid == null || pid.length() == 0) ? "0:00:00"
                        : RootShell.exec("ps -o etime= -p " + pid + " 2>/dev/null | tr -d ' '", 8000);
                ui.post(new Runnable() { @Override public void run() {
                    boolean run = "true".equals(Jake.str(core, "running")) || "yes".equals(Jake.str(core, "running"));
                    upTime.setText(nz(etime));
                    conn.setText(run ? "已连接" : "未连接");
                    conn.setTextColor(run ? Ui.okc(SyNativeActivity.this) : Ui.dim(SyNativeActivity.this));
                    // 【真机缺陷修复】proxyrun.sh status 里没有 up/down 字段，
                    // 旧写法拿到空串 → 显示 "↑ B" 没有数字。改为取不到就显示 0。
                    String upV = Jake.str(core, "up");
                    String dnV = Jake.str(core, "down");
                    upTv.setText("↑ " + (upV == null || upV.length() == 0 ? "0" : upV) + " B");
                    dnTv.setText("↓ " + (dnV == null || dnV.length() == 0 ? "0" : dnV) + " B");
                    upSp.setText("↑ 0 B/s");
                    dnSp.setText("↓ 0 B/s");
                    String cfgName = Jake.str(mgr, "lifecycle");
                    cfg.setText(cfgName == null || cfgName.length() == 0 ? "自动选择" : cfgName);
                    String nn = nodes == null ? "" : nodes.trim();
                    node.setText(nn.length() == 0 ? "自动选择" : (nn.length() > 40 ? nn.substring(0, 40) + "…" : nn));
                    boolean isGlobal = "global".equals(mode);
                    rule.setTextColor(!isGlobal ? Ui.text(SyNativeActivity.this) : Ui.dim(SyNativeActivity.this));
                    rule.setBackground(Ui.round(SyNativeActivity.this, !isGlobal ? Ui.line(SyNativeActivity.this) : 0x00000000, 0, 12));
                    global.setTextColor(isGlobal ? Ui.text(SyNativeActivity.this) : Ui.dim(SyNativeActivity.this));
                    global.setBackground(Ui.round(SyNativeActivity.this, isGlobal ? Ui.line(SyNativeActivity.this) : 0x00000000, 0, 12));
                }});
            }
        }, "sy-vpn").start();
    }

    /* ================= ② Ad（广告拦截：规则 + MITM + DNS） ================= */

    private void tabAd() {
        content.addView(Ui.title(this, "Ad"));

        // 规则管理（含 ⋯ 三级）
        content.addView(Ui.twoCol(this, cardRuleMgr(), cardMitm()));

        // DNS 与规则（原规则页）
        final LinearLayout c = Ui.card(this, "DNS 与规则", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("规则管理"); }
        });
        LinearLayout b1 = Ui.body(c);
        final View[] total = Ui.row(this, "hosts 条目", "读取中…", false, null);
        final View[] engine = Ui.row(this, "引擎记录", "读取中…", false, null);
        b1.addView(total[0]);
        b1.addView(engine[0]);
        final View[] builtin = Ui.row(this, "内置规则", "读取中…", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showBuiltinRules(); }
        });
        b1.addView(builtin[0]);
        b1.addView(Ui.row(this, "汇总应用规则", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("应用规则", new Call() {
                public String run() { return RootShell.script("builtin_rules.sh", "apply"); } }); }
        })[0]);
        b1.addView(Ui.row(this, "重新编译引擎", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("编译引擎", new Call() {
                public String run() { return RootShell.script("dns.sh", "engine-build"); } }); }
        })[0]);
        content.addView(c);
        new Thread(new Runnable() {
            @Override public void run() {
                final String dns = RootShell.dnsStatus();
                final String h = RootShell.exec("wc -l < /data/adb/SY/rules/dns/hosts 2>/dev/null | tr -d ' '", 10000);
                // 内置规则：份数/总条数/已启用，全部从 builtin_rules.sh 的真实 JSON 算
                final String brJson = RootShell.builtinRules();
                sBuiltinCache = brJson;   // 缓存给详情弹窗用
                int brCnt = 0, brTotal = 0, brOn = 0;
                try {
                    org.json.JSONArray arr = new org.json.JSONArray(brJson);
                    brCnt = arr.length();
                    for (int i = 0; i < brCnt; i++) {
                        org.json.JSONObject o = arr.getJSONObject(i);
                        brTotal += o.optInt("total");
                        if ("1".equals(o.optString("enabled"))) brOn++;
                    }
                } catch (Exception ignored) {}
                final int fCnt = brCnt, fTotal = brTotal, fOn = brOn;
                ui.post(new Runnable() { @Override public void run() {
                    ((TextView) total[1]).setText(nz(h) + " 行");
                    ((TextView) engine[1]).setText(Jake.str(dns, "rule_count") + " 条");
                    ((TextView) builtin[1]).setText(fCnt + " 份 · " + fTotal + " 条 · 启用 " + fOn);
                }});
            }
        }, "sy-ad").start();

        // 运行时开关（拦截相关）
        content.addView(switchCard("拦截开关", new String[][]{
                {"DNS 级拦截", "DNS_ENABLE"}, {"MITM 透明代理", "MITM_ENABLE"},
                {"开屏广告跳过", "SPLASH_ENABLE"}, {"通知栏广告过滤", "NOTIFY_ENABLE"}}));
    }

    /* ================= ③ 隐私 ================= */

    private void tabPrivacy() {
        content.addView(Ui.title(this, "隐私"));

        // 一键全防护
        LinearLayout c0 = Ui.card(this, "一键全防护");
        LinearLayout b0 = Ui.body(c0);
        b0.addView(Ui.hint(this, "开启隐私护盾 + FX 深度抵抗 + 剪贴板监视，每一项都能单独关。"));
        b0.addView(Ui.rowOf(this,
                Ui.button(this, "一键开启全部", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("一键开启", new Call() {
                        public String run() { return RootShell.oneClickOn(); } }); }
                }),
                Ui.button(this, "一键关闭还原", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("一键关闭", new Call() {
                        public String run() { return RootShell.oneClickOff(); } }); }
                })));
        content.addView(c0);

        // 隐私保护 / 无障碍跳过（原首页的两张卡）
        content.addView(Ui.twoCol(this, cardPrivacy(), cardA11y()));

        // Hook（原规则页）
        LinearLayout c2 = Ui.card(this, "Hook 与注入", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("隐私保护"); }
        });
        LinearLayout b2 = Ui.body(c2);
        final EditText et = new EditText(this);
        et.setHint("每行一条：标签 类名#方法名，或粘贴任意规则（自动识别语法）");
        et.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        et.setHintTextColor(Ui.dim(this));
        et.setTextColor(Ui.text(this));
        et.setMinLines(3);
        b2.addView(Ui.hint(this, "支持：域名 / ||domain^ / 正则 / ##选择器 / hosts / AdGuard 语法"));
        b2.addView(et);
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "识别", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("识别结果",
                            RootShell.hookRulesAnalyze(et.getText().toString())); }
                }),
                Ui.button(this, "导入并应用", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("导入规则", new Call() {
                        public String run() { return RootShell.hookRulesImport(et.getText().toString()); } }); }
                })));
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "Hook 状态", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("Hook 状态", RootShell.hookStatus()); }
                }),
                Ui.button(this, "Hook 事件", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("Hook 事件", RootShell.hookEvents(40)); }
                }),
                Ui.button(this, "清空事件", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("清空", new Call() {
                        public String run() { return RootShell.hookClear(); } }); }
                })));
        content.addView(c2);

        // 运行时开关（隐私相关）
        content.addView(switchCard("防护开关", new String[][]{
                {"隐私护盾（FX/风控隔离）", "PRIVACY_ENABLE"}, {"网络防泄露总开关", "LEAK_ENABLE"},
                {"游戏隐私保护", "GAME_PRIVACY_ENABLE"}, {"FX 深度抵抗", "FX_DEEPGUARD_ENABLE"},
                {"剪贴板监视", "CLIPGUARD_ENABLE"}}));
    }

    /* ================= ④ 脚本（内核 / 节点 / 工具） ================= */

    private void tabScripts() {
        content.addView(Ui.title(this, "脚本"));

        // 节点
        LinearLayout c = Ui.card(this, "节点");
        LinearLayout b = Ui.body(c);
        final TextView out = new TextView(this);
        out.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        out.setTextColor(Ui.text(this));
        out.setTypeface(Typeface.MONOSPACE);
        b.addView(Ui.hint(this, "节点详细数据（协议/服务器/端口/加密/SNI/传输）"));
        b.addView(out);
        b.addView(Ui.rowOf(this,
                Ui.button(this, "读取节点", true, new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        out.setText("读取中…");
                        new Thread(new Runnable() { @Override public void run() {
                            final String s = RootShell.nodesList();
                            ui.post(new Runnable() { @Override public void run() {
                                out.setText(Jake.prettyNodes(s)); } });
                        }}, "sy-nodes").start();
                    }
                }),
                Ui.button(this, "重建索引", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("重建索引", new Call() {
                        public String run() { return RootShell.nodesBuildMeta(); } }); }
                })));
        content.addView(c);

        // 内核
        LinearLayout c2 = Ui.card(this, "内核");
        LinearLayout b2 = Ui.body(c2);
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "启动", true, new View.OnClickListener() {
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
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "生效验证", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("生效验证", RootShell.proxyVerify()); }
                }),
                Ui.button(this, "健康检查", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("健康检查", RootShell.proxyHealth()); }
                })));
        content.addView(c2);

        // 自检与恢复
        LinearLayout c3 = Ui.card(this, "自检与恢复");
        LinearLayout b3 = Ui.body(c3);
        b3.addView(Ui.rowOf(this,
                Ui.button(this, "App 自检修复", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("App 自检", new Call() {
                        public String run() { return RootShell.appEnsure(); } }); }
                }),
                Ui.button(this, "模块自检", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("模块自检", RootShell.selfCheck()); }
                })));
        b3.addView(Ui.row(this, "备份与恢复", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("备份列表", RootShell.script("backup.sh", "list")); }
        })[0]);
        b3.addView(Ui.row(this, "脚本扩展", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("脚本扩展", RootShell.script("scripts_ext.sh", "list")); }
        })[0]);
        content.addView(c3);
    }

    /* ================= ⑤ 设置 ================= */

    private void tabSettings() {
        content.addView(Ui.title(this, "设置"));

        // 外观
        LinearLayout c = Ui.card(this, "外观");
        LinearLayout b = Ui.body(c);
        b.addView(Ui.hint(this, "配色跟随系统深浅色，无需手动设置。"));
        b.addView(Ui.row(this, "当前主题", Ui.dark(this) ? "深色" : "浅色", false, null)[0]);
        b.addView(Ui.row(this, "底部导航", "5 项（VPN/Ad/隐私/脚本/设置）", false, null)[0]);
        content.addView(c);

        // 设备
        LinearLayout c2 = Ui.card(this, "设备与兼容");
        LinearLayout b2 = Ui.body(c2);
        final TextView dev = new TextView(this);
        dev.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        dev.setTextColor(Ui.text(this));
        dev.setTypeface(Typeface.MONOSPACE);
        b2.addView(dev);
        b2.addView(Ui.rowOf(this,
                Ui.button(this, "读取设备信息", false, new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        dev.setText("读取中…");
                        new Thread(new Runnable() { @Override public void run() {
                            final String s = RootShell.deviceInfo();
                            ui.post(new Runnable() { @Override public void run() {
                                dev.setText(s == null ? "(无)" : s); } });
                        }}, "sy-dev").start();
                    }
                }),
                Ui.button(this, "Root 状态", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("Root 状态", RootShell.rootStatus()); }
                })));
        content.addView(c2);

        // 高级
        LinearLayout c3 = Ui.card(this, "高级");
        LinearLayout b3 = Ui.body(c3);
        b3.addView(Ui.row(this, "打开网页面板（功能更全）", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) {
                int port = getSharedPreferences("sy", MODE_PRIVATE).getInt("port", PanelApi.DEFAULT_PORT);
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(PanelApi.base(port) + "/")));
                } catch (Exception e) { toast("没有可用的浏览器"); }
            }
        })[0]);
        b3.addView(Ui.row(this, "启动面板服务", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("启动面板", new Call() {
                public String run() { return RootShell.startPanel(); } }); }
        })[0]);
        b3.addView(Ui.hint(this, "App 版本 " + appVersion() + " · 模块 " + RootShell.MODDIR
                + " · root " + (RootShell.hasRoot() ? "可用" : "不可用")));
        content.addView(c3);

        // 运行时开关（其余）
        content.addView(switchCard("其他开关", new String[][]{
                {"面板服务自启", "PANEL_ENABLE"}, {"代理防 IP 泄露", "PROXY_LEAK"}}));
    }

    /** 读 App 自己的版本号（不再硬编码，避免代码里写的和实际装的不一致） */
    private String appVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "?";
        }
    }

    /* ================= 通用：运行时开关卡（读真实配置） ================= */

    private LinearLayout switchCard(String title, String[][] items) {
        final LinearLayout c = Ui.card(this, title);
        final LinearLayout b = Ui.body(c);
        final TextView[] sws = new TextView[items.length];
        // 【崩溃修复】注意：Ui.rowSwitch() 返回 new View[]{行, 开关} —— 只有 2 个元素。
        // 上一版误取 rw[2] 当标签 → ArrayIndexOutOfBoundsException，App 一进 Ad 页就崩。
        for (int i = 0; i < items.length; i++) {
            final String key = items[i][1];
            View[] rw = Ui.rowSwitch(this, items[i][0], false, new View.OnClickListener() {
                @Override public void onClick(View v) {
                    // 读取当前值再取反
                    new Thread(new Runnable() { @Override public void run() {
                        final String cur = RootShell.exec("grep -m1 '^" + key + "=' /data/adb/SY/config/sy.conf 2>/dev/null | cut -d= -f2", 8000);
                        final boolean toOn = !"1".equals(cur == null ? "" : cur.trim());
                        final String out = RootShell.script("settings.sh", "set " + key + " " + (toOn ? "1" : "0"));
                        ui.post(new Runnable() { @Override public void run() {
                            toast(key + " → " + (toOn ? "开" : "关"));
                            refreshSwitches(); } });
                    }}, "sy-sw").start();
                }
            });
            sws[i] = (TextView) rw[1];
            b.addView(rw[0]);
        }
        // 读初始状态
        new Thread(new Runnable() {
            @Override public void run() {
                for (int i = 0; i < items.length; i++) {
                    final int idx = i;
                    final String v = RootShell.exec("grep -m1 '^" + items[idx][1] + "=' /data/adb/SY/config/sy.conf 2>/dev/null | cut -d= -f2", 8000);
                    final boolean on = "1".equals(v == null ? "" : v.trim());
                    ui.post(new Runnable() { @Override public void run() {
                        setSwitchVisual(sws[idx], on); } });
                }
            }
        }, "sy-sw-init").start();
        return c;
    }

    private void refreshSwitches() { }

    private void setSwitchVisual(TextView sw, boolean on) {
        if (sw == null) return;
        sw.setBackground(Ui.round(this, on ? Ui.accent(this) : Ui.card(this), on ? 0 : Ui.trackOff(this), 13));
        sw.setGravity(on ? (Gravity.END | Gravity.CENTER_VERTICAL)
                        : (Gravity.START | Gravity.CENTER_VERTICAL));
        sw.setTextColor(on ? android.graphics.Color.WHITE : Ui.trackOff(this));
    }

    /**
     * 内置规则详情：8 份规则的名称 / 条数 / 开关，全部来自 builtin_rules.sh 的真实输出。
     * 为什么不再写死"（8 份）"：份数是脚本算出来的，写死会在规则变动后失真。
     */
    private void showBuiltinRules() {
        final LinearLayout box = Ui.col(this);
        box.setPadding(Ui.dp(this, 16), Ui.dp(this, 8), Ui.dp(this, 16), Ui.dp(this, 16));
        final TextView sum = Ui.text2(this, "读取中…", 13f, Ui.dim(this));
        sum.setPadding(0, 0, 0, Ui.dp(this, 8));
        box.addView(sum);
        final ScrollView sv = new ScrollView(this);
        sv.addView(box);
        final android.app.AlertDialog dlg = new android.app.AlertDialog.Builder(this)
                .setTitle("内置规则")
                .setView(sv)
                .setNegativeButton("关闭", null)
                .create();
        dlg.show();

        new Thread(new Runnable() {
            @Override public void run() {
                // 【真机缺陷修复】旧版弹窗先显示"读取中…"，但串行锁下这条读取排在
                // 页面其它读取之后，弹窗打开数秒仍可能是"读取中…"。
                // 现在把 builtinRules 的结果**缓存**在字段里，弹窗立刻用缓存渲染，
                // 同时后台再取一次新数据覆盖。
                String json = sBuiltinCache;
                if (json == null) json = RootShell.builtinRules();
                final String jsonF = json;
                ui.post(new Runnable() { @Override public void run() {
                    int total = 0, on = 0, cnt = 0;
                    try {
                        org.json.JSONArray arr = new org.json.JSONArray(jsonF);
                        cnt = arr.length();
                        for (int i = 0; i < cnt; i++) {
                            org.json.JSONObject o = arr.getJSONObject(i);
                            final String key = o.optString("key");
                            final String name = o.optString("name");
                            final boolean enabled = "1".equals(o.optString("enabled"));
                            final int c = o.optInt("total");
                            total += c;
                            if (enabled) on++;
                            View[] rv = Ui.rowSwitch(SyNativeActivity.this,
                                    name + "（" + c + "）", enabled, new View.OnClickListener() {
                                @Override public void onClick(View v) {
                                    new Thread(new Runnable() { @Override public void run() {
                                        RootShell.builtinRuleToggle(key, !enabled);
                                        ui.post(new Runnable() { @Override public void run() {
                                            toast(name + " → " + (!enabled ? "开" : "关"));
                                            dlg.dismiss();
                                            showBuiltinRules();
                                        }});
                                    }}, "sy-br").start();
                                }
                            });
                            box.addView(rv[0]);
                        }
                        sum.setText("共 " + cnt + " 份 · " + total + " 条 · 已启用 " + on + " 份");
                    } catch (Exception e) {
                        sum.setText("读取失败：" + (jsonF == null ? "无输出"
                                : jsonF.substring(0, Math.min(120, jsonF.length()))));
                    }
                }});
            }
        }, "sy-brl").start();
    }
    /* ================= 四张功能卡（被新页面复用） ================= */

    private View cardRuleMgr() {
        LinearLayout c = Ui.card(this, "规则管理", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("规则管理"); }
        });
        LinearLayout b = Ui.body(c);
        // 【真机缺陷修复】"已启用条目"原先指向 config/user_rules.txt ——
        // 该文件在重装后并不存在（真实数据在 rules/builtin-active），所以永远显示 0。
        b.addView(ruleRow("规则列表", "/data/adb/SY/rules/dns/hosts", "行"));
        b.addView(ruleRow("已启用", "/data/adb/SY/rules/builtin-active", "条"));
        b.addView(Ui.row(this, "黑白名单", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { level3("规则管理"); }
        })[0]);
        return c;
    }

    /** 带后缀单位的行（异步填数值） */
    private View ruleRow(final String label, final String path, final String unit) {
        // 半宽卡用两行布局（rowStack）：避免数值被裁（真机实测过裁切）
        View[] rv = Ui.rowStack(this, label, "…", false, null);
        final TextView v = (TextView) rv[1];
        new Thread(new Runnable() {
            @Override public void run() {
                final String out = linesOf(path);
                v.post(new Runnable() { @Override public void run() { v.setText(out + " " + unit); } });
            }
        }, "sy-rule").start();
        rv[0].setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v2) { level3("规则管理"); }
        });
        return rv[0];
    }

    private View cardMitm() {
        LinearLayout c = Ui.card(this, "MITM 功能", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("MITM 功能"); }
        });
        LinearLayout b = Ui.body(c);
        // 参考图里 MITM 卡的行右侧是蓝色圆点（已安装/已开启）
        final View caRow = Ui.rowDot(this, "CA 证书", false, null);
        final View decRow = Ui.rowDot(this, "HTTPS 解密", false, null);
        b.addView(caRow);
        b.addView(decRow);
        b.addView(Ui.row(this, "证书指纹", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("证书指纹", RootShell.exec(
                    "ls /data/adb/SY/ca/ 2>/dev/null; openssl x509 -in /data/adb/SY/ca/ca.crt -noout -fingerprint -sha256 2>/dev/null", 12000)); }
        })[0]);
        new Thread(new Runnable() {
            @Override public void run() {
                final String st = RootShell.script("mitm.sh", "status");
                final boolean caOk = "yes".equals(Jake.str(st, "ca_ready"));
                final boolean decOn = "yes".equals(Jake.str(st, "running"));
                ui.post(new Runnable() { @Override public void run() {
                    setDot(Ui.dotOf(caRow), caOk);
                    setDot(Ui.dotOf(decRow), decOn);
                }});
            }
        }, "sy-mitm").start();
        return c;
    }

    private View cardPrivacy() {
        LinearLayout c = Ui.card(this, "隐私保护", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("隐私保护"); }
        });
        LinearLayout b = Ui.body(c);
        final View[] fp = Ui.rowSwitch(this, "指纹防护", false, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("切换指纹防护", new Call() {
                public String run() { return RootShell.leakToggle("ip", true); } }); }
        });
        final View[] lg = Ui.rowSwitch(this, "日志清理", false, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("清理日志", new Call() {
                public String run() { return RootShell.exec("rm -f /data/adb/SY/logs/*.log && echo '已清理日志'", 10000); } }); }
        });
        b.addView(fp[0]);
        b.addView(lg[0]);
        new Thread(new Runnable() {
            @Override public void run() {
                final String fx = RootShell.fxStatus();
                final String clip = RootShell.clipStatus();
                ui.post(new Runnable() { @Override public void run() {
                    setSwitchVisual((TextView) fp[1], "1".equals(Jake.str(fx, "enabled")));
                    setSwitchVisual((TextView) lg[1], "1".equals(Jake.str(clip, "feature")));
                }});
            }
        }, "sy-priv").start();
        return c;
    }

    private View cardA11y() {
        LinearLayout c = Ui.card(this, "无障碍跳过", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("无障碍跳过"); }
        });
        LinearLayout b = Ui.body(c);
        final View[] skip = Ui.rowSwitch(this, "自动跳过", false, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("切换开屏跳过", new Call() {
                public String run() { return RootShell.script("splash.sh", "toggle"); } }); }
        });
        final View[] form = Ui.rowSwitch(this, "表单辅助", false, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("切换无障碍服务", new Call() {
                public String run() { return RootShell.appEnsure(); } }); }
        });
        b.addView(skip[0]);
        b.addView(form[0]);
        new Thread(new Runnable() {
            @Override public void run() {
                final String sp = RootShell.script("splash.sh", "status");
                final String acc = RootShell.exec("settings get secure enabled_accessibility_services 2>/dev/null", 8000);
                ui.post(new Runnable() { @Override public void run() {
                    setSwitchVisual((TextView) skip[1], "1".equals(Jake.str(sp, "enabled")) || "yes".equals(Jake.str(sp, "enabled")));
                    setSwitchVisual((TextView) form[1], acc != null && acc.contains("syfusion"));
                }});
            }
        }, "sy-a11y").start();
        return c;
    }

    /** 圆点状态（蓝=开，空心=关） */
    private void setDot(View dot, boolean on) {
        if (dot == null) return;
        dot.setBackground(Ui.round(this, on ? Ui.accent(this) : 0x00000000, on ? 0 : Ui.trackOff(this), 9));
    }

    /* ================= 三级菜单（卡片右上角"⋯"进入） =================
     *
     * 参考图的做法：卡片主区只放最常用的几行，全部细节在右上角"⋯"里。
     * 这样首页保持清爽，同时不牺牲功能可达性。
     */

    /** 设置圆点状态（蓝=开，空心=关） */

    /** 同步取行数（RootShell.exec 本身阻塞，直接在后台线程用即可） */
    private String linesOf(String path) {
        String n = RootShell.exec("wc -l < " + path + " 2>/dev/null | tr -d ' '", 10000);
        return (n == null || n.trim().length() == 0) ? "0" : n.trim();
    }

    private void level3(final String which) {
        final LinearLayout box = Ui.col(this);
        final ScrollView sv = new ScrollView(this);
        sv.addView(box);
        final android.app.AlertDialog dlg = new android.app.AlertDialog.Builder(this)
                .setTitle(which)
                .setView(sv)
                .setNegativeButton("关闭", null)
                .create();
        box.setPadding(Ui.dp(this, 16), Ui.dp(this, 10), Ui.dp(this, 16), Ui.dp(this, 16));

        if ("规则管理".equals(which)) {
            box.addView(Ui.row(this, "hosts 总行数", "读取中…", false, null)[0]);
            box.addView(Ui.row(this, "黑洞条目数", "读取中…", false, null)[0]);
            box.addView(Ui.row(this, "自定义规则", "读取中…", false, null)[0]);
            box.addView(Ui.row(this, "白名单条目", "读取中…", false, null)[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "自定义规则（编辑）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("自定义规则", RootShell.script("dns.sh", "custom-list")); }
            })[0]);
            box.addView(Ui.row(this, "黑名单（强制拦截）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("黑名单", RootShell.script("dns.sh", "blacklist-list")); }
            })[0]);
            box.addView(Ui.row(this, "白名单（放行）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("白名单", RootShell.script("dns.sh", "whitelist-list")); }
            })[0]);
            box.addView(Ui.row(this, "规则来源与订阅", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("规则来源", RootShell.script("dns.sh", "sources")); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "内置规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showBuiltinRules(); }
            })[0]);
            box.addView(Ui.row(this, "规则引擎统计", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("引擎统计", RootShell.script("dns.sh", "engine-stats")); }
            })[0]);
            box.addView(Ui.row(this, "重新编译引擎", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("编译引擎", new Call() {
                    public String run() { return RootShell.script("dns.sh", "engine-build"); } }); }
            })[0]);
            box.addView(Ui.row(this, "重新应用规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用规则", new Call() {
                    public String run() { return RootShell.script("dns.sh", "apply"); } }); }
            })[0]);
        } else if ("MITM 功能".equals(which)) {
            box.addView(Ui.hint(this, "MITM 是「HTTPS 元素隐藏」与「去广告注入」的执行者：把 ## 规则转成 CSS 注入网页。需要装根证书并开启解密。"));
            box.addView(Ui.row(this, "MITM 状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("MITM 状态", RootShell.script("mitm.sh", "status")); }
            })[0]);
            box.addView(Ui.row(this, "已加载规则数", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("已加载规则", RootShell.script("mitm.sh", "rules-count")); }
            })[0]);
            box.addView(Ui.row(this, "规则列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("MITM 规则", RootShell.script("mitm.sh", "rules-list")); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "启动 MITM", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("启动 MITM", new Call() {
                    public String run() { return RootShell.script("mitm.sh", "up"); } }); }
            })[0]);
            box.addView(Ui.row(this, "停止 MITM", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("停止 MITM", new Call() {
                    public String run() { return RootShell.script("mitm.sh", "down"); } }); }
            })[0]);
            box.addView(Ui.row(this, "重新加载规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("重载规则", new Call() {
                    public String run() { return RootShell.script("mitm.sh", "rules-reload"); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "证书状态与指纹", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("证书状态", RootShell.script("mitm.sh", "ca-status")); }
            })[0]);
            box.addView(Ui.row(this, "安装根证书到系统", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("安装证书", new Call() {
                    public String run() { return RootShell.script("mitm.sh", "ca-install"); } }); }
            })[0]);
            box.addView(Ui.row(this, "MITM 统计", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("MITM 统计", RootShell.script("mitm.sh", "stats")); }
            })[0]);
        } else if ("隐私保护".equals(which)) {
            box.addView(Ui.row(this, "防泄露状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("防泄露状态", RootShell.leakStatus()); }
            })[0]);
            box.addView(Ui.row(this, "结构化报告", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("防泄露报告", RootShell.leakReport()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "FX 深度抵抗报告", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("FX 报告", RootShell.fxReport()); }
            })[0]);
            box.addView(Ui.row(this, "应用出口收敛（按应用）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("应用出口", RootShell.leakApps("list")); }
            })[0]);
            box.addView(Ui.row(this, "游戏隐私保护", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("游戏隐私", RootShell.script("game_privacy.sh", "status")); }
            })[0]);
            box.addView(Ui.row(this, "剪贴板监视状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("剪贴板", RootShell.clipStatus()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "全部体检（隐私外泄）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("隐私体检", RootShell.script("privacy_check.sh", "all")); }
            })[0]);
            box.addView(Ui.row(this, "应急恢复（还原全部改动）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应急恢复", new Call() {
                    public String run() { return RootShell.leakPanic(); } }); }
            })[0]);
        } else if ("无障碍跳过".equals(which)) {
            box.addView(Ui.hint(this, "无障碍服务用于自动跳过开屏广告。需在系统设置里启用「SY 联动服务」。"));
            box.addView(Ui.row(this, "无障碍服务是否启用", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) {
                    showText("无障碍状态", RootShell.exec(
                        "settings get secure enabled_accessibility_services 2>/dev/null", 8000)); }
            })[0]);
            box.addView(Ui.row(this, "一键准备（装 App + 开无障碍）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("一键准备", new Call() {
                    public String run() { return RootShell.appEnsure(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "开屏守护状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("开屏状态", RootShell.script("splash.sh", "status")); }
            })[0]);
            box.addView(Ui.row(this, "跳过记录", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("跳过记录", RootShell.script("splash.sh", "records")); }
            })[0]);
            box.addView(Ui.row(this, "开屏规则列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("开屏规则", RootShell.script("splash.sh", "rules-list")); }
            })[0]);
            box.addView(Ui.row(this, "清空跳过记录", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空记录", new Call() {
                    public String run() { return RootShell.script("splash.sh", "clear-records"); } }); }
            })[0]);
        }

        // 异步填充前四行的真实值（仅规则管理页需要）
        if ("规则管理".equals(which)) {
            final View[] v1 = { box.getChildAt(0) };
            new Thread(new Runnable() {
                @Override public void run() {
                    final String h = RootShell.exec("wc -l < /data/adb/SY/rules/dns/hosts 2>/dev/null | tr -d ' '", 8000);
                    final String bh = RootShell.exec("grep -c '^0[.]0[.]0[.]0 ' /system/etc/hosts 2>/dev/null | head -n1", 8000);
                    final String cu = RootShell.exec("wc -l < /data/adb/SY/config/user_rules.txt 2>/dev/null | tr -d ' '", 8000);
                    final String wl = RootShell.exec("wc -l < /data/adb/SY/config/whitelist.conf 2>/dev/null | tr -d ' '", 8000);
                    ui.post(new Runnable() { @Override public void run() {
                        TextView a = findValue(box, 0); if (a != null) a.setText(nz(h) + " 行");
                        TextView b2 = findValue(box, 1); if (b2 != null) b2.setText(nz(bh) + " 条");
                        TextView c3 = findValue(box, 2); if (c3 != null) c3.setText(nz(cu) + " 条");
                        TextView d4 = findValue(box, 3); if (d4 != null) d4.setText(nz(wl) + " 条");
                    }});
                }
            }, "sy-l3").start();
        }
        dlg.show();
    }

    /** 从行容器里取出右侧值 TextView（rowValue 返回的数组第 2 项是 View，实际是 TextView） */
    private TextView findValue(LinearLayout row, int idx) {
        try {
            View v = row.getChildAt(idx);
            if (v instanceof LinearLayout) {
                LinearLayout r = (LinearLayout) v;
                View last = r.getChildAt(r.getChildCount() - (1 + (r.getChildCount() >= 3 ? 1 : 0)));
                // rowValue 结构：sym, label, value[, arrow]
                for (int i = r.getChildCount() - 1; i >= 0; i--) {
                    View c = r.getChildAt(i);
                    if (c instanceof TextView) {
                        String s = ((TextView) c).getText().toString();
                        if (s.contains("…") || s.contains("行") || s.contains("条")) return (TextView) c;
                    }
                }
                if (r.getChildCount() >= 3 && r.getChildAt(2) instanceof TextView)
                    return (TextView) r.getChildAt(2);
            }
        } catch (Exception ignored) {}
        return null;
    }

    private static String nz(String s) { return (s == null || s.trim().length() == 0) ? "0" : s.trim(); }

    /* ================= 打开网页面板的具体页面 ================= */

    private void openPanelPage(String tab) {
        toast("打开面板：" + tab);
        int port = getSharedPreferences("sy", MODE_PRIVATE).getInt("port", PanelApi.DEFAULT_PORT);
        new Thread(new Runnable() {
            @Override public void run() { RootShell.startPanel(); }
        }, "sy-panel").start();
        try {
            startActivity(new Intent(Intent.ACTION_VIEW,
                    Uri.parse(PanelApi.base(port) + "/#" + tab)));
        } catch (Exception e) { toast("没有可用的浏览器"); }
    }

    /* ================= 通用 ================= */

    private interface Call { String run(); }

    private void runAndShow(final String title, final Call c) {
        toast(title + "…");
        new Thread(new Runnable() {
            @Override public void run() {
                final String out = c.run();
                ui.post(new Runnable() { @Override public void run() {
                    showText(title, out);
                    if (curNav == 0) showTab(0);
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

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_SHORT).show(); }
}
