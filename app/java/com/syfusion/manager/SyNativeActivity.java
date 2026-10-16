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
import android.view.WindowInsets;
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
    /** 内容滚动容器（切页/进堆栈时要回到顶部，否则标题会被滚出屏幕） */
    private ScrollView contentScroll;
    /** 底部栏容器（insets 适配与堆栈返回栏都作用于它） */
    private View navBar;
    /** 最近一次读到的系统栏 inset（重渲染时复用，避免每次都要等回调） */
    private int insetTop = 0, insetBottom = 0;
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

        // 【全屏优化】让内容铺满整屏（消除上下黑边）
        applyEdgeToEdge();
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.page(this));

        ScrollView sv = new ScrollView(this);
        contentScroll = sv;
        content = Ui.col(this);
        content.setPadding(Ui.dp(this, 14), Ui.dp(this, 12), Ui.dp(this, 14), Ui.dp(this, 90));
        sv.addView(content);
        root.addView(sv, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        navBar = buildNav();
        root.addView(navBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);

        // 【全屏优化】按实际 inset 给内容顶部让开状态栏、给底栏让开手势条。
        // 写死内边距在不同机型（刘海/挖孔/手势条）上都不准，必须读真实 inset。
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                int top = 0, bottom = 0, left = 0, right = 0;
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    android.graphics.Insets b = insets.getInsets(
                            WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                    top = b.top; bottom = b.bottom; left = b.left; right = b.right;
                } else {
                    top = insets.getSystemWindowInsetTop();
                    bottom = insets.getSystemWindowInsetBottom();
                    left = insets.getSystemWindowInsetLeft();
                    right = insets.getSystemWindowInsetRight();
                }
                insetTop = top; insetBottom = bottom;
                content.setPadding(Ui.dp(SyNativeActivity.this, 14) + left,
                        Ui.dp(SyNativeActivity.this, 12) + top,
                        Ui.dp(SyNativeActivity.this, 14) + right,
                        Ui.dp(SyNativeActivity.this, 90));
                if (navBar != null) {
                    navBar.setPadding(Ui.dp(SyNativeActivity.this, 6), Ui.dp(SyNativeActivity.this, 8),
                            Ui.dp(SyNativeActivity.this, 6), Ui.dp(SyNativeActivity.this, 14) + bottom);
                }
                return insets;
            }
        });
        root.requestApplyInsets();
        showTab(0);
    }

    private View buildNav() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setBackgroundColor(Ui.card(this));
        bar.setPadding(Ui.dp(this, 6), Ui.dp(this, 8), Ui.dp(this, 6), Ui.dp(this, 14));
        buildNavInto(bar);
        return bar;
    }

    /** 把 5 项导航填进容器（堆栈返回时用它恢复导航） */
    private void buildNavInto(LinearLayout bar) {
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

    /* ===== 堆栈导航（三级/四级页面）=====
     * 用户要求：不再用弹窗，改成真正的堆栈。
     *   进入下一级 -> 压栈并渲染新页，底部栏换成返回栏；
     *   点返回栏或按系统返回键 -> 弹栈回上一级；
     *   栈空 -> 恢复底部 5 项导航。
     */
    private final java.util.ArrayList<StackPage> pageStack = new java.util.ArrayList<StackPage>();

    private static class StackPage {
        final String title;
        final Runnable render;
        StackPage(String t, Runnable r) { title = t; render = r; }
    }

    /** 压入一个三级（或更深）页面 */
    private void pushPage(String title, Runnable render) {
        pageStack.add(new StackPage(title, render));
        renderStackTop();
    }

    /** 弹栈；栈空则恢复底部导航 */
    private void popPage() {
        if (pageStack.isEmpty()) return;
        pageStack.remove(pageStack.size() - 1);
        renderStackTop();
    }

    /** 渲染栈顶 */
    private void renderStackTop() {
        if (pageStack.isEmpty()) {
            setNavMode(false, null);
            showTab(curNav);
            return;
        }
        StackPage top = pageStack.get(pageStack.size() - 1);
        content.removeAllViews();
        setNavMode(true, top.title);
        // 【真机缺陷修复】切页必须回到顶部：ScrollView 会沿用上一页的滚动位置，
        // 真机上表现为"三级页标题被滚出去、顶部只露出中间几行"。
        applyContentPadding();
        if (contentScroll != null) contentScroll.scrollTo(0, 0);
        top.render.run();
    }

    /** 切换底部栏：false=5 项导航；true=返回栏 */
    private void setNavMode(boolean back, String title) {
        if (!(navBar instanceof LinearLayout)) return;
        LinearLayout bar = (LinearLayout) navBar;
        bar.removeAllViews();
        if (back) {
            LinearLayout rw = Ui.hrow(this);
            rw.setPadding(Ui.dp(this, 14), 0, Ui.dp(this, 14), 0);
            rw.addView(Ui.icon(this, "ic_arrow_back", 22, Ui.iconColor(this)));
            TextView tt = Ui.text2(this, title == null ? "返回" : title, 16f, Ui.text(this));
            tt.setTypeface(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD));
            tt.setPadding(Ui.dp(this, 10), 0, 0, 0);
            rw.addView(tt, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            rw.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { popPage(); }
            });
            bar.addView(rw, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, Ui.dp(this, 52)));
        } else {
            buildNavInto(bar);
            paintNav();
        }
    }

    @Override
    public void onBackPressed() {
        if (!pageStack.isEmpty()) { popPage(); return; }
        super.onBackPressed();
    }

    /** 打开三级页（堆栈版，调用点不用改） */
    private void level3(final String which) {
        pushPage(which, new Runnable() {
            @Override public void run() { renderLevel3(which); }
        });
    }

    private void showTab(int idx) {
        curNav = idx;
        paintNav();
        content.removeAllViews();
        applyContentPadding();
        if (contentScroll != null) contentScroll.scrollTo(0, 0);
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

        // ⓪ 【新增】大开关：一键开启 / 关闭 VPN（用户指出"VPN 里没有开启的按钮"）
        final LinearLayout sw = Ui.card(this, null);
        LinearLayout swb = Ui.body(sw);
        LinearLayout swRow = Ui.hrow(this);
        swRow.addView(Ui.icon(this, "ic_vpn", 26, Ui.iconColor(this)));
        LinearLayout swTxt = Ui.col(this);
        swTxt.setPadding(Ui.dp(this, 12), 0, 0, 0);
        final TextView swTitle = Ui.text2(this, "代理未开启", 18f, Ui.text(this));
        swTitle.setTypeface(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD));
        final TextView swSub = Ui.text2(this, "点右侧按钮启动内核", 12.5f, Ui.dim(this));
        swSub.setPadding(0, Ui.dp(this, 3), 0, 0);
        swTxt.addView(swTitle);
        swTxt.addView(swSub);
        swRow.addView(swTxt, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        final TextView powerBtn = Ui.pill(this, "开启", true, new View.OnClickListener() {
            @Override public void onClick(View v) {
                // 【真机缺陷修复】旧版 VPN 页没有开关，用户找不到"怎么开"。
                // 现在按当前状态切换：未连 → 启动内核；已连 → 停止内核。
                String cur = swTitle.getText().toString();
                boolean running = cur.contains("已开启");
                if (running) {
                    runAndShow("关闭内核", new Call() { public String run() { return RootShell.nodesDown(); } });
                } else {
                    runAndShow("开启内核", new Call() { public String run() { return RootShell.nodesUp(); } });
                }
            }
        });
        swRow.addView(powerBtn);
        swb.addView(swRow);
        content.addView(sw);

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

        // ④ 直连 | 规则 | 全局 切换
        // 【用户要求】参考图只有"规则|全局"，但用户明确要补上"直连" —— 三种模式齐全。
        // 直连=全部不走代理；规则=按规则分流；全局=全部走代理。
        final LinearLayout seg = Ui.hrow(this);
        seg.setBackground(Ui.round(this, Ui.card(this), 0, 12));
        final TextView modeDirect = segBtn("直连", false);
        final TextView modeRule = segBtn("规则", true);
        final TextView modeGlobal = segBtn("全局", false);
        final TextView[] modeBtns = { modeDirect, modeRule, modeGlobal };
        for (TextView b : modeBtns) {
            seg.addView(b, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
        modeDirect.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { switchMode3("direct", modeBtns); }
        });
        modeRule.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { switchMode3("rule", modeBtns); }
        });
        modeGlobal.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { switchMode3("global", modeBtns); }
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

        loadVpn(upTime, connState, upTv, dnTv, upSp, dnSp, cfgName, nodeName,
                modeDirect, modeRule, modeGlobal, powerBtn, swTitle, swSub);
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

    /**
     * 三态切换：直连 / 规则 / 全局。
     * 【用户要求】参考图只有"规则|全局"，用户要补"直连"，这里三种模式齐全。
     * 模式名与脚本约定一致（proxynodes.sh mode 读到 direct/rule/global）。
     */
    private void switchMode3(final String mode, final TextView[] btns) {
        String label = "direct".equals(mode) ? "直连" : ("global".equals(mode) ? "全局" : "规则");
        runAndShow("切换到" + label + "模式", new Call() {
            public String run() { return RootShell.proxyMode(mode); } });
        // 三个按钮的选中态：选中的用 line 底色 + 主文字色，其余透明 + 次文字色
        String[] ids = { "direct", "rule", "global" };
        for (int i = 0; i < btns.length && i < ids.length; i++) {
            boolean on = ids[i].equals(mode);
            btns[i].setTextColor(on ? Ui.text(this) : Ui.dim(this));
            btns[i].setBackground(Ui.round(this, on ? Ui.line(this) : 0x00000000, 0, 12));
        }
    }

    private void loadVpn(final TextView upTime, final TextView conn, final TextView upTv, final TextView dnTv,
                         final TextView upSp, final TextView dnSp, final TextView cfg, final TextView node,
                         final TextView direct, final TextView rule, final TextView global,
                         final TextView powerBtn, final TextView swTitle, final TextView swSub) {
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
                    // 大开关状态（用户要求：VPN 页要有明确的开启按钮）
                    if (swTitle != null) swTitle.setText(run ? "代理已开启" : "代理未开启");
                    if (swSub != null) swSub.setText(run ? "内核运行中 · 点右侧按钮关闭" : "点右侧按钮启动内核");
                    if (powerBtn != null) {
                        powerBtn.setText(run ? "关闭" : "开启");
                        powerBtn.setTextColor(run ? android.graphics.Color.WHITE : Ui.text(SyNativeActivity.this));
                        powerBtn.setBackground(Ui.round(SyNativeActivity.this,
                                run ? Ui.accent(SyNativeActivity.this) : Ui.card(SyNativeActivity.this),
                                run ? 0 : Ui.line(SyNativeActivity.this), 19));
                    }
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
                    // 三态高亮（直连/规则/全局）—— mode 由 proxynodes.sh mode 返回
                    String m = mode == null ? "rule" : mode.trim();
                    String[] ids = { "direct", "rule", "global" };
                    for (int i = 0; i < 3; i++) {
                        boolean on = ids[i].equals(m);
                        TextView b = (i == 0) ? direct : (i == 1 ? rule : global);
                        if (b == null) continue;
                        b.setTextColor(on ? Ui.text(SyNativeActivity.this) : Ui.dim(SyNativeActivity.this));
                        b.setBackground(Ui.round(SyNativeActivity.this, on ? Ui.line(SyNativeActivity.this) : 0x00000000, 0, 12));
                    }
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
            @Override public void onClick(View v) { level3("DNS 与规则"); }
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

        // ---- 网页端功能入口（补齐）----
        // DNS 与规则 / DNS 服务器 / 开屏跳过 / 通知过滤 / 拦截服务 / MITM 细节
        content.addView(Ui.twoCol(this,
                entryCard("ic_dns2", "DNS 与规则细节", new Runnable() { public void run() { level3("DNS 与规则"); } }),
                entryCard("ic_globe", "DNS 服务器", new Runnable() { public void run() { level3("DNS 服务器"); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_skip", "开屏跳过", new Runnable() { public void run() { level3("开屏跳过"); } }),
                entryCard("ic_bell", "通知过滤", new Runnable() { public void run() { level3("通知过滤"); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_shield_sm", "拦截服务", new Runnable() { public void run() { level3("拦截服务"); } }),
                entryCard("ic_lock", "MITM 细节", new Runnable() { public void run() { level3("MITM 功能"); } })));
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


        // 运行时开关（隐私相关）
        content.addView(switchCard("防护开关", new String[][]{
                {"隐私护盾（FX/风控隔离）", "PRIVACY_ENABLE"}, {"网络防泄露总开关", "LEAK_ENABLE"},
                {"游戏隐私保护", "GAME_PRIVACY_ENABLE"}, {"FX 深度抵抗", "FX_DEEPGUARD_ENABLE"},
                {"剪贴板监视", "CLIPGUARD_ENABLE"}}));

        // ================= 防 IP 泄露（用户要求归入隐私页） =================
        // 网页把这些能力拆在「隐私护盾 / 网络防泄露 / FX」三页，用户要求收敛到隐私页，
        // 形成一眼看全的"泄露面清单"：IP / IPv6 / VPN / 节点 / DNS 五个出口。
        LinearLayout leakCard = Ui.card(this, "防 IP 泄露", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("防护详情"); }
        });
        LinearLayout lb = Ui.body(leakCard);
        lb.addView(Ui.hint(this, "阻断把上网记录/安装清单上报的端点，并收敛设备真实出口 IP。"));

        final View[][] leakRows = new View[5][];
        final String[] leakKeys = { "ip", "ipv6", "vpn", "node", "dns" };
        final String[] leakLabels = { "IP 泄露防护", "IPv6 泄露防护", "VPN 出口收敛", "节点防泄露", "DNS 明文泄露" };
        for (int k = 0; k < leakKeys.length; k++) {
            final String key = leakKeys[k];
            final String label = leakLabels[k];
            View[] rw = Ui.rowSwitch(this, label, false, new View.OnClickListener() {
                @Override public void onClick(View v) {
                    new Thread(new Runnable() { @Override public void run() {
                        final String cur = RootShell.exec("sh " + RootShell.MODDIR
                                + "/scripts/leakguard.sh " + key + " status 2>/dev/null", 8000);
                        final boolean on = cur != null && cur.contains("on");
                        RootShell.leakToggle(key, !on);
                        ui.post(new Runnable() { @Override public void run() {
                            toast(label + " 已" + (!on ? "开启" : "关闭"));
                            renderStackTop();
                        }});
                    }}, "sy-leak-t").start();
                }
            });
            leakRows[k] = rw;
            lb.addView(rw[0]);
        }

        lb.addView(Ui.divider(this));
        lb.addView(Ui.row(this, "全部开启", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("全部开启", new Call() {
                public String run() { return RootShell.leakAll(true); } }); }
        })[0]);
        lb.addView(Ui.row(this, "全部关闭", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("全部关闭", new Call() {
                public String run() { return RootShell.leakAll(false); } }); }
        })[0]);
        lb.addView(Ui.row(this, "运营商防泄露", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("运营商状态", RootShell.carrierStatus()); }
        })[0]);
        lb.addView(Ui.row(this, "归属对比（查真实 IP 泄露）", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("归属对比", RootShell.leakOwner("", "")); }
        })[0]);
        lb.addView(Ui.row(this, "应用出口收敛（按应用）", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("应用出口", RootShell.leakApps("list")); }
        })[0]);
        lb.addView(Ui.divider(this));
        lb.addView(Ui.row(this, "查看详细报告", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("防泄露报告", RootShell.leakReport()); }
        })[0]);
        lb.addView(Ui.row(this, "应急恢复（还原全部改动）", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("应急恢复", new Call() {
                public String run() { return RootShell.leakPanic(); } }); }
        })[0]);
        content.addView(leakCard);

        // ================= 反诈与反作弊（用户要求） =================
        // 内容来源（全部可核实，不是凭空写）：
        //   · 本模块既有 guardshield-antifraud.txt（28 条 FX 反诈域名）与
        //     fx_deepguard.sh 的上报端点清单；
        //   · 设备指纹/号码认证（cmpassport/cpassport/风控云）—— 运营商侧画像；
        //   · 反作弊 SDK（riskengine 等）与营销归因（umeng/cnzz 等）。
        // 这里把「开关 + 清单 + 报告 + 一键」都放到隐私页，形成完整闭环。
        LinearLayout fxCard = Ui.card(this, "反诈与反作弊", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("防护详情"); }
        });
        LinearLayout fb = Ui.body(fxCard);
        fb.addView(Ui.hint(this, "阻断设备指纹/风控上报/反作弊/归因端点，收敛画像拼装面。"));

        // 主开关：FX 深度抵抗（读真实状态）
        final View[] fxSw = Ui.rowSwitch(this, "FX 深度抵抗（反诈）", false,
                new View.OnClickListener() {
            @Override public void onClick(View v) {
                new Thread(new Runnable() { @Override public void run() {
                    final String st = RootShell.fxStatus();
                    final boolean on = "1".equals(Jake.str(st, "enabled"));
                    RootShell.script("fx_deepguard.sh", on ? "remove" : "apply");
                    ui.post(new Runnable() { @Override public void run() {
                        toast("FX 深度抵抗 " + (on ? "已关闭" : "已开启"));
                        renderStackTop();
                    }});
                }}, "sy-fx-t").start();
            }
        });
        fb.addView(fxSw[0]);

        // 反作弊 SDK 专项开关（写进配置，由 fx 应用时读取）
        final View[] aceSw = Ui.rowSwitch(this, "反作弊 SDK 阻断", false,
                new View.OnClickListener() {
            @Override public void onClick(View v) {
                new Thread(new Runnable() { @Override public void run() {
                    String cur = RootShell.settingsGet("FX_ANTICHEAT");
                    boolean on = cur != null && cur.contains("1");
                    RootShell.settingsSet("FX_ANTICHEAT", on ? "0" : "1");
                    ui.post(new Runnable() { @Override public void run() {
                        toast("反作弊阻断 " + (!on ? "已开启" : "已关闭"));
                        renderStackTop();
                    }});
                }}, "sy-ace-t").start();
            }
        });
        fb.addView(aceSw[0]);

        // 设备指纹/号码认证专项开关
        final View[] fpSw = Ui.rowSwitch(this, "设备指纹/号码认证阻断", false,
                new View.OnClickListener() {
            @Override public void onClick(View v) {
                new Thread(new Runnable() { @Override public void run() {
                    String cur = RootShell.settingsGet("FX_DEVICEID");
                    boolean on = cur != null && cur.contains("1");
                    RootShell.settingsSet("FX_DEVICEID", on ? "0" : "1");
                    ui.post(new Runnable() { @Override public void run() {
                        toast("指纹阻断 " + (!on ? "已开启" : "已关闭"));
                        renderStackTop();
                    }});
                }}, "sy-fp-t").start();
            }
        });
        fb.addView(fpSw[0]);

        fb.addView(Ui.divider(this));
        fb.addView(Ui.row(this, "查看域名清单", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("反诈域名清单", RootShell.script("fx_deepguard.sh", "active")); }
        })[0]);
        fb.addView(Ui.row(this, "查看完整报告", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("FX 报告", RootShell.fxReport()); }
        })[0]);
        fb.addView(Ui.row(this, "重建内置清单", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { runAndShow("重建清单", new Call() {
                public String run() { return RootShell.script("fx_deepguard.sh", "seed"); } }); }
        })[0]);
        fb.addView(Ui.row(this, "测试拦截效果", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("测试结果", RootShell.script("fx_deepguard.sh", "test")); }
        })[0]);
        fb.addView(Ui.divider(this));
        // 厂商内核完整性检测（inte.ko 类）情报 —— 只读透明，不做绕过
        // 背景：一加/OPPO ColorOS 内核的 inte.ko 会记录"启动后新加载的 .ko"
        // 与 sys_call_table 劫持，结果经 /proc/inte_ko 暴露给游戏反作弊。
        // 这里把这件事变透明：有没有该机制、记了什么、本模块会不会被记。
        fb.addView(Ui.row(this, "内核完整性检测情报（inte）", "", true, new View.OnClickListener() {
            @Override public void onClick(View v) { showText("inte 检测情报", RootShell.inteReport()); }
        })[0]);
        content.addView(fxCard);

        // 异步读反诈三开关的真实状态
        new Thread(new Runnable() {
            @Override public void run() {
                final String fx = RootShell.fxStatus();
                final String ac = RootShell.settingsGet("FX_ANTICHEAT");
                final String fp = RootShell.settingsGet("FX_DEVICEID");
                ui.post(new Runnable() { @Override public void run() {
                    setSwOn((TextView) fxSw[1], "1".equals(Jake.str(fx, "enabled")));
                    setSwOn((TextView) aceSw[1], ac != null && ac.trim().endsWith("1"));
                    setSwOn((TextView) fpSw[1], fp != null && fp.trim().endsWith("1"));
                }});
            }
        }, "sy-fx-init").start();

        // 异步读五个泄露面的真实开关状态
        new Thread(new Runnable() {
            @Override public void run() {
                final boolean[] st = new boolean[5];
                for (int k = 0; k < leakKeys.length; k++) {
                    String v = RootShell.exec("sh " + RootShell.MODDIR
                            + "/scripts/leakguard.sh " + leakKeys[k] + " status 2>/dev/null", 8000);
                    st[k] = v != null && v.contains("on");
                }
                ui.post(new Runnable() { @Override public void run() {
                    for (int k = 0; k < 5; k++) {
                        TextView swx = (TextView) leakRows[k][1];
                        swx.setBackground(Ui.round(SyNativeActivity.this,
                                st[k] ? Ui.accent(SyNativeActivity.this) : Ui.card(SyNativeActivity.this),
                                st[k] ? 0 : Ui.trackOff(SyNativeActivity.this), 13));
                        swx.setGravity(st[k] ? (Gravity.END | Gravity.CENTER_VERTICAL)
                                             : (Gravity.START | Gravity.CENTER_VERTICAL));
                        swx.setTextColor(st[k] ? android.graphics.Color.WHITE : Ui.trackOff(SyNativeActivity.this));
                    }
                }});
            }
        }, "sy-leak-init").start();

        // ---- 网页端功能入口（补齐）----
        content.addView(Ui.twoCol(this,
                entryCard("ic_shield_sm", "防护详情", new Runnable() { public void run() { level3("防护详情"); } }),
                entryCard("ic_fingerprint", "隐私护盾", new Runnable() { public void run() { showText("隐私护盾", RootShell.privacyGuardStatus()); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_lock", "隐私规则集", new Runnable() { public void run() { showText("隐私规则集", RootShell.privacyRsList()); } }),
                entryCard("ic_clipboard", "剪贴板读取者", new Runnable() { public void run() { showText("剪贴板读取者", RootShell.clipReaders()); } })));
        content.addView(Ui.twoCol(this,
                entryCard("ic_game", "游戏隐私", new Runnable() { public void run() { showText("游戏隐私", RootShell.gamePrivacyStatus()); } }),
                entryCard("ic_leak", "防泄露报告", new Runnable() { public void run() { showText("防泄露报告", RootShell.leakReport()); } })));
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

        LinearLayout hookCard = Ui.card(this, "Hook 与注入", new View.OnClickListener() {
            @Override public void onClick(View v) { level3("隐私保护"); }
        });
        LinearLayout hookBody = Ui.body(hookCard);
        final EditText et = new EditText(this);
        et.setHint("每行一条：标签 类名#方法名，或粘贴任意规则（自动识别语法）");
        et.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        et.setHintTextColor(Ui.dim(this));
        et.setTextColor(Ui.text(this));
        et.setMinLines(3);
        hookBody.addView(Ui.hint(this, "支持：域名 / ||domain^ / 正则 / ##选择器 / hosts / AdGuard 语法"));
        hookBody.addView(et);
        hookBody.addView(Ui.rowOf(this,
                Ui.button(this, "识别", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { showText("识别结果",
                            RootShell.hookRulesAnalyze(et.getText().toString())); }
                }),
                Ui.button(this, "导入并应用", true, new View.OnClickListener() {
                    @Override public void onClick(View v) { runAndShow("导入规则", new Call() {
                        public String run() { return RootShell.hookRulesImport(et.getText().toString()); } }); }
                })));
        hookBody.addView(Ui.rowOf(this,
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
        content.addView(hookCard);
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
        pushPage("内置规则", new Runnable() {
            @Override public void run() { renderBuiltinRules(); }
        });
    }

    private void renderBuiltinRules() {
        content.addView(Ui.title(this, "内置规则"));
        final LinearLayout box = Ui.col(this);
        content.addView(box);
        box.setPadding(Ui.dp(this, 0), Ui.dp(this, 0), Ui.dp(this, 0), Ui.dp(this, 40));
        final TextView sum = Ui.text2(this, "读取中…", 13f, Ui.dim(this));
        sum.setPadding(0, 0, 0, Ui.dp(this, 8));
        box.addView(sum);

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
                                            renderStackTop();
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

    /** 渲染三级页内容（堆栈版，不再用弹窗） */
    private void renderLevel3(final String which) {
        content.addView(Ui.title(this, which));
        final LinearLayout box = Ui.col(this);
        content.addView(box);
        box.setPadding(Ui.dp(this, 0), Ui.dp(this, 0), Ui.dp(this, 0), Ui.dp(this, 40));

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

        } else if ("DNS 与规则".equals(which)) {
            box.addView(Ui.hint(this, "DNS 级拦截的完整控制：规则应用、hosts 挂载、引擎重建、名单与规则源。"));
            box.addView(Ui.row(this, "应用规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用规则", new Call() {
                    public String run() { return RootShell.dnsApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "更新规则源", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("更新规则源", new Call() {
                    public String run() { return RootShell.dnsUpdate(); } }); }
            })[0]);
            box.addView(Ui.row(this, "hosts 状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("hosts 状态", RootShell.dnsHostsStatus()); }
            })[0]);
            box.addView(Ui.row(this, "重新生成 hosts", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("重建 hosts", new Call() {
                    public String run() { return RootShell.dnsHostsRegen(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "重建引擎", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("重建引擎", new Call() {
                    public String run() { return RootShell.dnsFilterBuild(); } }); }
            })[0]);
            box.addView(Ui.row(this, "引擎统计", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("引擎统计", RootShell.dnsEngineStats()); }
            })[0]);
            box.addView(Ui.row(this, "引擎语法检查", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("语法检查", RootShell.dnsEngineSyntax()); }
            })[0]);
            box.addView(Ui.row(this, "清空引擎", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空引擎", new Call() {
                    public String run() { return RootShell.dnsEngineClear(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "黑名单", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("黑名单", RootShell.dnsBlacklistList()); }
            })[0]);
            box.addView(Ui.row(this, "白名单", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("白名单", RootShell.dnsWhitelistList()); }
            })[0]);
            box.addView(Ui.row(this, "自定义规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("自定义规则", RootShell.dnsCustomList()); }
            })[0]);
            box.addView(Ui.row(this, "我的规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("我的规则", RootShell.dnsMyRulesGet()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "规则源列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("规则源", RootShell.dnsSources()); }
            })[0]);
            box.addView(Ui.row(this, "订阅规则列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("规则列表", RootShell.dnsLists()); }
            })[0]);
            box.addView(Ui.row(this, "同步规则源", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("同步规则源", new Call() {
                    public String run() { return RootShell.rulesetSync(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            final EditText dnsTest = new EditText(this);
            dnsTest.setHint("输入域名，测试会被拦截还是放行");
            dnsTest.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14f);
            dnsTest.setHintTextColor(Ui.dim(this));
            dnsTest.setTextColor(Ui.text(this));
            box.addView(dnsTest);
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "测试域名", true, new View.OnClickListener() {
                        @Override public void onClick(View v) { showText("测试结果",
                                RootShell.dnsFilterTest(dnsTest.getText().toString().trim())); }
                    }),
                    Ui.button(this, "导入规则", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("导入规则", new Call() {
                            public String run() { return RootShell.dnsImportText(dnsTest.getText().toString()); } }); }
                    })));
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "导出规则", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { showText("导出", RootShell.dnsExport()); }
                    }),
                    Ui.button(this, "统计摘要", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { showText("统计摘要", RootShell.dnsStatsSummary()); }
                    }),
                    Ui.button(this, "清空名单", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("清空名单", new Call() {
                            public String run() { return RootShell.dnsBlacklistClear(); } }); }
                    })));

        } else if ("DNS 服务器".equals(which)) {
            box.addView(Ui.hint(this, "加密 DNS（DoH/DoT）与防明文泄露。国内优先 / 全加密 / 分流解析三种模式。"));
            box.addView(Ui.row(this, "DNS 服务器状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("DNS 服务器", RootShell.dnsSrvStatus()); }
            })[0]);
            box.addView(Ui.row(this, "服务器列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("服务器列表", RootShell.dnsSrvServers()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "应用配置", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用 DNS", new Call() {
                    public String run() { return RootShell.dnsSrvApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "连通性测试", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("DNS 测试", RootShell.dnsSrvTest()); }
            })[0]);
            box.addView(Ui.row(this, "清空服务器", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空", new Call() {
                    public String run() { return RootShell.dnsSrvClearServers(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "模式：国内优先", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("模式", new Call() {
                    public String run() { return RootShell.dnsSrvSetMode("cn"); } }); }
            })[0]);
            box.addView(Ui.row(this, "模式：全加密", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("模式", new Call() {
                    public String run() { return RootShell.dnsSrvSetMode("secure"); } }); }
            })[0]);
            box.addView(Ui.row(this, "模式：分流解析", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("模式", new Call() {
                    public String run() { return RootShell.dnsSrvSetMode("split"); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "开启防 DNS 泄露", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("防泄露", new Call() {
                    public String run() { return RootShell.dnsSrvLeak("on"); } }); }
            })[0]);
            box.addView(Ui.row(this, "关闭防 DNS 泄露", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("防泄露", new Call() {
                    public String run() { return RootShell.dnsSrvLeak("off"); } }); }
            })[0]);

        } else if ("防护详情".equals(which)) {
            box.addView(Ui.hint(this, "隐私护盾 + 防泄露 + 规则集的全部细节。每一项都可单独执行。"));
            box.addView(Ui.row(this, "防泄露状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("防泄露状态", RootShell.leakStatus()); }
            })[0]);
            box.addView(Ui.row(this, "详细报告", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("防泄露报告", RootShell.leakReport()); }
            })[0]);
            box.addView(Ui.row(this, "全部开启", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("全部开启", new Call() {
                    public String run() { return RootShell.leakAll(true); } }); }
            })[0]);
            box.addView(Ui.row(this, "全部关闭", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("全部关闭", new Call() {
                    public String run() { return RootShell.leakAll(false); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "隐私护盾状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("隐私护盾", RootShell.privacyGuardStatus()); }
            })[0]);
            box.addView(Ui.row(this, "隐私护盾应用", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用", new Call() {
                    public String run() { return RootShell.privacyGuardApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "隐私护盾检查", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("检查", RootShell.privacyGuardCheck()); }
            })[0]);
            box.addView(Ui.row(this, "隐私护盾还原", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("还原", new Call() {
                    public String run() { return RootShell.privacyGuardRemove(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "隐私规则集", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("隐私规则集", RootShell.privacyRsList()); }
            })[0]);
            box.addView(Ui.row(this, "启用全部隐私规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("启用规则", new Call() {
                    public String run() { return RootShell.privacyRsEnable("all"); } }); }
            })[0]);
            box.addView(Ui.row(this, "清空隐私规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空规则", new Call() {
                    public String run() { return RootShell.privacyRsClear(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "游戏隐私状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("游戏隐私", RootShell.gamePrivacyStatus()); }
            })[0]);
            box.addView(Ui.row(this, "游戏隐私应用", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("游戏隐私", new Call() {
                    public String run() { return RootShell.gamePrivacyApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "剪贴板读取者", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("剪贴板读取者", RootShell.clipReaders()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "应急恢复（还原全部）", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应急恢复", new Call() {
                    public String run() { return RootShell.leakPanic(); } }); }
            })[0]);

        } else if ("系统与日志".equals(which)) {
            box.addView(Ui.row(this, "日志列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("日志列表", RootShell.logsList()); }
            })[0]);
            box.addView(Ui.row(this, "内核日志", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("内核日志", RootShell.logsCat("kernel", 300)); }
            })[0]);
            box.addView(Ui.row(this, "服务日志", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("服务日志", RootShell.logsCat("service", 300)); }
            })[0]);
            box.addView(Ui.row(this, "清空全部日志", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空日志", new Call() {
                    public String run() { return RootShell.logsClearAll(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "备份列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("备份列表", RootShell.backupList()); }
            })[0]);
            box.addView(Ui.row(this, "立即备份", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("备份", new Call() {
                    public String run() { return RootShell.backupExport(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "检查更新", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("检查更新", RootShell.updaterCheck()); }
            })[0]);
            box.addView(Ui.row(this, "更新状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("更新状态", RootShell.updaterStatus()); }
            })[0]);
            box.addView(Ui.row(this, "立即更新模块", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("更新模块", new Call() {
                    public String run() { return RootShell.updaterUpdate(false); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "总控状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("总控状态", RootShell.ctlStatus()); }
            })[0]);
            box.addView(Ui.row(this, "全部自检", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("自检报告", RootShell.selfcheckAll()); }
            })[0]);
            box.addView(Ui.row(this, "可编辑文件列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("可编辑文件", RootShell.fileeditList()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "脚本扩展列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("脚本扩展", RootShell.scriptsList()); }
            })[0]);
            box.addView(Ui.row(this, "更新全部脚本", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("更新脚本", new Call() {
                    public String run() { return RootShell.scriptsUpdateAll(); } }); }
            })[0]);
            box.addView(Ui.row(this, "订阅列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("订阅列表", RootShell.scriptsSubsList()); }
            })[0]);

        } else if ("代理节点".equals(which)) {
            box.addView(Ui.row(this, "节点列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("节点", RootShell.nodesList()); }
            })[0]);
            box.addView(Ui.row(this, "内核配置", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("内核配置", RootShell.nodesConfigGet()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "启动内核", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("启动", new Call() {
                    public String run() { return RootShell.nodesUp(); } }); }
            })[0]);
            box.addView(Ui.row(this, "停止内核", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("停止", new Call() {
                    public String run() { return RootShell.nodesDown(); } }); }
            })[0]);
            box.addView(Ui.row(this, "重启内核", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("重启", new Call() {
                    public String run() { return RootShell.nodesRestart(); } }); }
            })[0]);
            box.addView(Ui.row(this, "生成配置", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("生成配置", new Call() {
                    public String run() { return RootShell.nodesGenConfig(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "配置事务状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("配置事务", RootShell.proxycfgStatus()); }
            })[0]);
            box.addView(Ui.row(this, "事务：暂存", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("暂存", RootShell.proxycfgStage(true)); }
            })[0]);
            box.addView(Ui.row(this, "事务：校验", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("校验", RootShell.proxycfgCheck()); }
            })[0]);
            box.addView(Ui.row(this, "事务：提交", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("提交", new Call() {
                    public String run() { return RootShell.proxycfgCommit(); } }); }
            })[0]);
            box.addView(Ui.row(this, "事务：回滚", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("回滚", new Call() {
                    public String run() { return RootShell.proxycfgRollback(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "内核日志", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("内核日志", RootShell.nodesLogs()); }
            })[0]);
            box.addView(Ui.row(this, "内核文件清单", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("内核", RootShell.proxyCore()); }
            })[0]);
            box.addView(Ui.row(this, "内核自检", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("内核自检", new Call() {
                    public String run() { return RootShell.nodesCoreEnsure(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "分应用代理列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("分应用代理", RootShell.proxyMgrAppList()); }
            })[0]);
            box.addView(Ui.row(this, "应用分应用策略", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用策略", new Call() {
                    public String run() { return RootShell.proxyMgrAppApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "节点探测", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("节点探测", RootShell.proxyMgrProbe()); }
            })[0]);


        } else if ("开屏跳过".equals(which)) {
            box.addView(Ui.row(this, "守护状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("开屏状态", RootShell.script("splash.sh", "status")); }
            })[0]);
            box.addView(Ui.row(this, "启动守护", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("启动", new Call() {
                    public String run() { return RootShell.splashStart(); } }); }
            })[0]);
            box.addView(Ui.row(this, "停止守护", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("停止", new Call() {
                    public String run() { return RootShell.splashStop(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "跳过记录", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("跳过记录", RootShell.splashRecords()); }
            })[0]);
            box.addView(Ui.row(this, "清空记录", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空", new Call() {
                    public String run() { return RootShell.splashClearRecords(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "规则列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("开屏规则", RootShell.splashRulesList()); }
            })[0]);
            box.addView(Ui.row(this, "清空规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空规则", new Call() {
                    public String run() { return RootShell.splashRulesClear(); } }); }
            })[0]);
            final EditText spIn = new EditText(this);
            spIn.setHint("粘贴开屏规则 / 或填规则订阅 URL");
            spIn.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f);
            spIn.setHintTextColor(Ui.dim(this));
            spIn.setTextColor(Ui.text(this));
            box.addView(spIn);
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "导入规则", true, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("导入", new Call() {
                            public String run() { return RootShell.splashRulesAdd(spIn.getText().toString()); } }); }
                    }),
                    Ui.button(this, "网络导入", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("网络导入", new Call() {
                            public String run() { return RootShell.splashRulesImportNet(spIn.getText().toString().trim()); } }); }
                    })));

        } else if ("通知过滤".equals(which)) {
            box.addView(Ui.row(this, "状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("通知过滤", RootShell.notifyStatus()); }
            })[0]);
            box.addView(Ui.row(this, "关键词列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("关键词", RootShell.notifyKeywords()); }
            })[0]);
            box.addView(Ui.row(this, "过滤记录", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("记录", RootShell.notifyRecords()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "启动", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("启动", new Call() {
                    public String run() { return RootShell.notifyStart(); } }); }
            })[0]);
            box.addView(Ui.row(this, "停止", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("停止", new Call() {
                    public String run() { return RootShell.notifyStop(); } }); }
            })[0]);
            box.addView(Ui.row(this, "清空关键词", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("清空", new Call() {
                    public String run() { return RootShell.notifyKeywordsClear(); } }); }
            })[0]);
            box.addView(Ui.divider(this));
            final EditText nfIn = new EditText(this);
            nfIn.setHint("输入要过滤的关键词，或粘贴多行 / 订阅 URL");
            nfIn.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f);
            nfIn.setHintTextColor(Ui.dim(this));
            nfIn.setTextColor(Ui.text(this));
            box.addView(nfIn);
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "加关键词", true, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("添加", new Call() {
                            public String run() { return RootShell.notifyKeywordAdd(nfIn.getText().toString().trim()); } }); }
                    }),
                    Ui.button(this, "批量导入", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("导入", new Call() {
                            public String run() { return RootShell.notifyKeywordsAdd(nfIn.getText().toString()); } }); }
                    }),
                    Ui.button(this, "网络导入", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("网络导入", new Call() {
                            public String run() { return RootShell.notifyImportNet(nfIn.getText().toString().trim()); } }); }
                    })));

        } else if ("拦截服务".equals(which)) {
            box.addView(Ui.row(this, "状态", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("拦截服务", RootShell.netblockStatus()); }
            })[0]);
            box.addView(Ui.row(this, "规则列表", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("规则", RootShell.netblockList()); }
            })[0]);
            box.addView(Ui.row(this, "应用规则", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { runAndShow("应用", new Call() {
                    public String run() { return RootShell.netblockApply(); } }); }
            })[0]);
            box.addView(Ui.row(this, "预览生效项", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("预览", RootShell.netblockPreview()); }
            })[0]);
            box.addView(Ui.divider(this));
            box.addView(Ui.row(this, "应用白名单", "", true, new View.OnClickListener() {
                @Override public void onClick(View v) { showText("应用清单", RootShell.netblockAppsList()); }
            })[0]);
            final EditText nbIn = new EditText(this);
            nbIn.setHint("填域名 / IP / 网段 / 包名，或粘贴多行规则");
            nbIn.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f);
            nbIn.setHintTextColor(Ui.dim(this));
            nbIn.setTextColor(Ui.text(this));
            box.addView(nbIn);
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "加域名", true, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("添加域名", new Call() {
                            public String run() { return RootShell.netblockAdd("domain", nbIn.getText().toString().trim()); } }); }
                    }),
                    Ui.button(this, "加 IP", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("添加 IP", new Call() {
                            public String run() { return RootShell.netblockAdd("ip", nbIn.getText().toString().trim()); } }); }
                    }),
                    Ui.button(this, "加应用", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("添加应用", new Call() {
                            public String run() { return RootShell.netblockAppsAdd(nbIn.getText().toString().trim()); } }); }
                    })));
            box.addView(Ui.rowOf(this,
                    Ui.button(this, "批量导入", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("导入", new Call() {
                            public String run() { return RootShell.netblockImport("domain", nbIn.getText().toString()); } }); }
                    }),
                    Ui.button(this, "清空域名", false, new View.OnClickListener() {
                        @Override public void onClick(View v) { runAndShow("清空", new Call() {
                            public String run() { return RootShell.netblockClear("domain"); } }); }
                    })));

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
        s = wrapForDisplay(s);
        if (s.length() > 12000) s = s.substring(0, 12000) + "\n…（已截断）";

        /*
         * 【真机缺陷修复·关键】不用 AlertDialog.setMessage 显示脚本输出。
         *
         * 真机证据：dns.sh engine-stats 明明返回 312 字符（logcat:
         *   cmd=...dns.sh engine-stats exit=true len=312），但弹窗只有标题、正文空白。
         * 原因：脚本输出是**没有空格的长 JSON**，setMessage 内部单行不折行，
         *       整段被推到可视区之外。
         * 处理：自己放一个可滚动、可选中、带等宽字体的 TextView ——
         *       折行规则由我们自己控制，长内容也不会溢出。
         */
        final TextView tv = new TextView(this);
        tv.setText(s);
        tv.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f);
        tv.setTextColor(Ui.text(this));
        tv.setTypeface(android.graphics.Typeface.MONOSPACE);
        tv.setTextIsSelectable(true);
        tv.setHorizontallyScrolling(false);
        tv.setPadding(Ui.dp(this, 18), Ui.dp(this, 10), Ui.dp(this, 18), Ui.dp(this, 10));

        final ScrollView sv = new ScrollView(this);
        sv.addView(tv);
        new android.app.AlertDialog.Builder(this)
                .setTitle(title)
                .setView(sv)
                .setPositiveButton("知道了", null)
                .show();
    }

    /**
     * 把脚本输出整理成"能读、能换行"的文本。
     *   · 单行 JSON：在每个 `,` 与 `{` `[` 之后断行，键值对齐；
     *   · 其余内容：按 60 字符软折行（防止无空白长串溢出）；
     *   · 已经是多行的（脚本本来就分行输出）原样保留。
     */
    private String wrapForDisplay(String s) {
        if (s == null) return "(无输出)";
        String t = s.trim();
        if (t.length() == 0) return "(无输出)";
        // 已经是多行：不动
        if (t.indexOf('\n') >= 0 && t.split("\n").length > 2) return t;
        // 单行 JSON：结构化断行
        if (t.startsWith("{") || t.startsWith("[")) {
            StringBuilder sb = new StringBuilder();
            boolean inStr = false;
            for (int i = 0; i < t.length(); i++) {
                char ch = t.charAt(i);
                if (ch == '"') inStr = !inStr;
                sb.append(ch);
                if (!inStr && (ch == ',' || ch == '{' || ch == '[')) sb.append('\n');
            }
            return sb.toString().replace(",\n", ",\n");
        }
        // 普通长串：每 56 字符软折行
        if (t.length() <= 56) return t;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < t.length(); i += 56) {
            sb.append(t, i, Math.min(t.length(), i + 56)).append('\n');
        }
        return sb.toString();
    }

    /**
     * 让内容铺满整屏（含系统栏区域），并按深浅色设置系统栏图标。
     * 低版本用已废弃的 SYSTEM_UI_FLAG_*，高版本用 WindowInsetsController，两条路径都保留。
     */
    private void applyEdgeToEdge() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                getWindow().setDecorFitsSystemWindows(false);
                android.view.WindowInsetsController c = getWindow().getInsetsController();
                if (c != null) {
                    // 深色主题 -> 浅色图标；浅色主题 -> 深色图标
                    c.setSystemBarsAppearance(Ui.dark(this) ? 0
                            : android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                            android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS);
                }
            } else {
                getWindow().getDecorView().setSystemUiVisibility(
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
            }
            getWindow().setStatusBarColor(android.graphics.Color.TRANSPARENT);
            getWindow().setNavigationBarColor(android.graphics.Color.TRANSPARENT);
        } catch (Throwable ignored) {
        }
    }

    /** 设置开关视觉状态（隐私页的多个开关共用；与 Ui.pillSwitch 外观一致） */
    private void setSwOn(TextView sw, boolean on) {
        if (sw == null) return;
        sw.setBackground(Ui.round(this, on ? Ui.accent(this) : Ui.card(this),
                on ? 0 : Ui.trackOff(this), 13));
        sw.setGravity(on ? (Gravity.END | Gravity.CENTER_VERTICAL)
                        : (Gravity.START | Gravity.CENTER_VERTICAL));
        sw.setTextColor(on ? android.graphics.Color.WHITE : Ui.trackOff(this));
    }

    /** 应用内容区内边距（含状态栏/手势条 inset）；切页时调用，保证顶部不被状态栏压住 */
    private void applyContentPadding() {
        if (content == null) return;
        content.setPadding(Ui.dp(this, 14), Ui.dp(this, 12) + insetTop,
                Ui.dp(this, 14), Ui.dp(this, 90) + insetBottom);
    }

    private void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_SHORT).show(); }
}
