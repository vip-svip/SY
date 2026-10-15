package com.syfusion.manager;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * 原生界面小部件工厂 —— **严格对照参考图**。
 *
 * 参考图的关键特征（逐条照做，不自行发挥）：
 *   ① 大状态卡：左盾牌图标（描边、深色）+ 标题 + 副标题 + 右侧蓝色胶囊按钮；
 *      下方一行四个元素：延迟 / 值 / 今日流量 / 值。
 *   ② 4 宫格：图标**直接放着，没有背景块**，图标下是文字。
 *   ③ 双列功能卡：标题 + 右上角两点（⋯）；行 = 图标 + 文字 + 值 + 箭头。
 *   ④ 开关：**空心描边胶囊**（关）/ 蓝色实心胶囊 + 白点（开）。
 *   ⑤ 底部 4 入口：图标 + 文字。
 *
 * 配色跟随系统深浅色。
 */
final class Ui {
    private Ui() {}

    static boolean dark(Context c) {
        int m = c.getResources().getConfiguration().uiMode
                & Configuration.UI_MODE_NIGHT_MASK;
        return m == Configuration.UI_MODE_NIGHT_YES;
    }

    static int page(Context c)   { return dark(c) ? 0xFF0E1116 : 0xFFF2F4F7; }
    static int card(Context c)   { return dark(c) ? 0xFF171A1F : 0xFFFFFFFF; }
    static int line(Context c)   { return dark(c) ? 0xFF2A2F37 : 0xFFE8EAED; }
    static int text(Context c)   { return dark(c) ? 0xFFEDEFF2 : 0xFF14171C; }
    static int dim(Context c)    { return dark(c) ? 0xFF9AA1AB : 0xFF9AA0A6; }
    static int accent(Context c) { return 0xFF1A73E8; }
    static int okc(Context c)    { return dark(c) ? 0xFF4ADE80 : 0xFF16A34A; }
    static int errc(Context c)   { return dark(c) ? 0xFFF87171 : 0xFFDC2626; }
    static int iconColor(Context c) { return dark(c) ? 0xFFEDEFF2 : 0xFF1F2430; }
    static int trackOff(Context c)  { return dark(c) ? 0xFF3A4048 : 0xFFDADCE0; }

    /**
     * 界面字体：Android 自带 "sans-serif-medium"。
     * 为什么用它：参考图的字明显比 Regular 更饱满（中等字重），
     * 在小米 ROM 上这个字族映射到 MiSans Medium，观感与参考图一致。
     * 标题再加粗一档用 bold。
     */
    static Typeface tf(Context c) {
        return Typeface.create("sans-serif-medium", Typeface.NORMAL);
    }

    static Typeface tfBold(Context c) {
        return Typeface.create("sans-serif-medium", Typeface.BOLD);
    }

    static int dp(Context c, float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                c.getResources().getDisplayMetrics());
    }

    static GradientDrawable round(Context c, int fill, int stroke, float radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(dp(c, radiusDp));
        if (stroke != 0) g.setStroke(dp(c, 1), stroke);
        return g;
    }

    static LinearLayout col(Context c) {
        LinearLayout v = new LinearLayout(c);
        v.setOrientation(LinearLayout.VERTICAL);
        return v;
    }

    static LinearLayout hrow(Context c) {
        LinearLayout v = new LinearLayout(c);
        v.setOrientation(LinearLayout.HORIZONTAL);
        v.setGravity(Gravity.CENTER_VERTICAL);
        return v;
    }

    /* ================= 卡片 ================= */

    static LinearLayout card(Context c, String title) {
        return card(c, title, null);
    }

    /** 卡片 + 标题行（more 非空时右上角显示 ⋯，点击进入三级菜单） */
    static LinearLayout card(Context c, String title, View.OnClickListener more) {
        LinearLayout wrap = new LinearLayout(c);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(0, 0, 0, dp(c, 12));
        LinearLayout b = new LinearLayout(c);
        b.setOrientation(LinearLayout.VERTICAL);
        b.setBackground(round(c, card(c), 0, 16));
        // 【真机缺陷修复】水平内边距从 18dp 收到 14dp：半宽卡片只有 124dp 内容宽，
        // 18dp 时放不下「图标+标签+值+箭头」，值会被挤成 0 宽而只露出尾巴
        // （真机实测：4800 行 显示成 0 行、3088 条 显示成 )88 条）。
        b.setPadding(dp(c, 14), dp(c, 16), dp(c, 14), dp(c, 16));
        if (title != null && title.length() > 0) {
            LinearLayout head = hrow(c);
            TextView t = new TextView(c);
            t.setText(title);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f);
            t.setTextColor(text(c));
            t.setTypeface(tfBold(c));
            head.addView(t, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            if (more != null) {
                ImageView dots = icon(c, "ic_dots", 20, dim(c));
                dots.setOnClickListener(more);
                head.addView(dots);
            }
            b.addView(head, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        wrap.addView(b, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return wrap;
    }

    static LinearLayout body(LinearLayout wrap) { return (LinearLayout) wrap.getChildAt(0); }

    /** 行间细分隔线（三级菜单里用） */
    static View divider(Context c) {
        View v = new View(c);
        v.setBackgroundColor(line(c));
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Math.max(1, dp(c, 0.6f))));
        return v;
    }

    /* ================= 图标 ================= */

    /**
     * 描边矢量图标（res/drawable）。参考图的图标是**深色描边、无背景块**，
     * 所以这里只返回 ImageView，不套圆角背景。
     */
    static ImageView icon(Context c, String name, float dpSize, int color) {
        ImageView iv = new ImageView(c);
        int id = c.getResources().getIdentifier(name, "drawable", c.getPackageName());
        if (id == 0) id = c.getResources().getIdentifier("ic_list", "drawable", c.getPackageName());
        iv.setImageResource(id);
        iv.setColorFilter(color);
        iv.setLayoutParams(new LinearLayout.LayoutParams(dp(c, dpSize), dp(c, dpSize)));
        return iv;
    }

    /** 标签 → 图标名映射 */
    static String iconOf(String label) {
        if (label == null) return "ic_list";
        if (label.contains("代理管理")) return "ic_shield_check";
        if (label.contains("广告拦截")) return "ic_shield_check";
        if (label.contains("Hook")) return "ic_shield_plus";
        if (label.contains("DNS 设置")) return "ic_drop";
        if (label.contains("代理")) return "ic_shield_plus";
        if (label.contains("规则列表")) return "ic_list";
        if (label.contains("已启用")) return "ic_list_check";
        if (label.contains("黑白") || label.contains("名单")) return "ic_shield_sm";
        if (label.contains("CA 证书") || label.contains("证书")) return "ic_cert";
        if (label.contains("解密") || label.contains("MITM")) return "ic_lock";
        if (label.contains("指纹")) return "ic_fingerprint";
        if (label.contains("日志")) return "ic_trash";
        if (label.contains("自动跳过") || label.contains("无障碍")) return "ic_skip";
        if (label.contains("表单")) return "ic_form";
        if (label.contains("首页")) return "ic_home";
        if (label.contains("规则")) return "ic_rules";
        if (label.contains("工具")) return "ic_tools";
        if (label.contains("我的")) return "ic_me";
        if (label.contains("节点")) return "ic_bolt";
        return "ic_list";
    }

    /* ================= 行 ================= */

    /**
     * 行：图标 + 文字 + 右侧值 + 箭头。
     *
     * 对齐契约（真机实测修正）：
     *   · **箭头位置恒定** —— 无论这一行有没有箭头，都在最右侧留出等宽位置。
     *     旧版只在 withArrow 时才 addView 箭头，导致同一张卡里"有箭头的行"
     *     与"没箭头的行"右边缘差 36~75px（真机量测：943 / 904 / 979），
     *     看起来就是"字体/内容没对齐"。
     *   · 值用固定宽度 + 右对齐，这样多行的值也竖着对齐。
     */
    static View[] row(Context c, String label, String value, boolean withArrow,
                      View.OnClickListener l) {
        LinearLayout r = hrow(c);
        r.setPadding(0, dp(c, 13), 0, dp(c, 13));
        ImageView ic = icon(c, iconOf(label), 22, iconColor(c));
        r.addView(ic);
        TextView t = new TextView(c);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f);
        t.setTextColor(text(c));
        t.setTypeface(tf(c));
        t.setSingleLine(true);
        t.setPadding(dp(c, 10), 0, dp(c, 8), 0);
        // 标签 wrap_content：多长的字都完整显示，绝不裁剪（上一版裁过）
        r.addView(t, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        // 【回退修复】上一版给值固定 52dp 宽度 —— 结果值区把标签区挤爆，
        // 标签被裁成"规则列/已启F/黑白名"（真机截图确认）。
        // 正确做法（也是参考图的做法）：
        //   标签 wrap_content（自然宽度、绝不裁剪），
        //   值 wrap_content 右对齐，箭头位**恒定 20dp**（有箭头就画，没箭头就占位）。
        //   这样三者总能放下，且右边缘必然对齐。
        TextView v = new TextView(c);
        v.setText(value == null ? "" : value);
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        v.setTextColor(dim(c));
        v.setTypeface(tf(c));
        v.setSingleLine(true);
        v.setGravity(Gravity.END);
        r.addView(v, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        // 箭头位：**恒定 20dp**，有箭头才画图标，没箭头留同宽空位 → 右边缘对齐。
        ImageView a = icon(c, "ic_arrow", 18, withArrow ? dim(c) : 0x00000000);
        r.addView(a, new LinearLayout.LayoutParams(dp(c, 20), dp(c, 20)));

        if (l != null) r.setOnClickListener(l);
        return new View[]{r, v};
    }

    /**
     * 半宽卡专用**紧凑单行**行布局（照参考图，仍是一行）。
     *
     * 宽度账（实测）：半宽卡内容宽 = 132dp。
     *   常规尺寸：图标22 + 标签54 + 值43 + 箭头20 = 139dp → 超 7dp，值被裁
     *            （真机表现："4800 行"→"0 行"、"3088 条"→"88 条"）。
     *   紧凑尺寸：图标20 + 标签50 + 值40 + 箭头16 = 126dp → 放得下 ✓
     * 所以这里把图标/字号/箭头各收一档，保持一行且数值完整。
     */
    static View[] rowStack(Context c, String label, String value, boolean withArrow,
                           View.OnClickListener l) {
        LinearLayout r = hrow(c);
        r.setPadding(0, dp(c, 12), 0, dp(c, 12));
        r.addView(icon(c, iconOf(label), 20, iconColor(c)));

        TextView t = new TextView(c);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        t.setTextColor(text(c));
        t.setTypeface(tf(c));
        t.setSingleLine(true);
        t.setPadding(dp(c, 7), 0, dp(c, 5), 0);
        r.addView(t, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        // 弹性空隙：宽度富余时把值推到右边；不富余时自动收为 0
        View sp = new View(c);
        r.addView(sp, new LinearLayout.LayoutParams(0, 1, 1f));

        TextView v = new TextView(c);
        v.setText(value == null ? "" : value);
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        v.setTextColor(dim(c));
        v.setTypeface(tf(c));
        v.setSingleLine(true);
        v.setGravity(Gravity.END);
        r.addView(v, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        if (withArrow) {
            ImageView a = icon(c, "ic_arrow", 15, dim(c));
            a.setPadding(dp(c, 4), 0, 0, 0);
            r.addView(a);
        }
        if (l != null) r.setOnClickListener(l);
        return new View[]{r, v};
    }

    /** 行：图标 + 文字 + 蓝色圆点（参考图 MITM 卡的做法） */
    static View rowDot(Context c, String label, boolean on, View.OnClickListener l) {
        LinearLayout r = hrow(c);
        r.setPadding(0, dp(c, 13), 0, dp(c, 13));
        r.addView(icon(c, iconOf(label), 22, iconColor(c)));
        TextView t = new TextView(c);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f);
        t.setTextColor(text(c));
        t.setTypeface(tf(c));
        t.setSingleLine(true);
        t.setPadding(dp(c, 10), 0, 0, 0);
        r.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        View dot = new View(c);
        dot.setBackground(round(c, on ? accent(c) : 0x00000000, on ? 0 : trackOff(c), 9));
        r.addView(dot, new LinearLayout.LayoutParams(dp(c, 18), dp(c, 18)));
        if (l != null) r.setOnClickListener(l);
        return r;
    }

    /** 从 rowDot 返回的行里取出圆点 View（供调用方后续改状态） */
    static View dotOf(View row) {
        if (row instanceof LinearLayout) {
            LinearLayout r = (LinearLayout) row;
            return r.getChildAt(r.getChildCount() - 1);
        }
        return null;
    }

    /* ================= 开关 ================= */

    /**
     * 空心描边胶囊开关（参考图的样式）。
     * 关：白色/深色底 + 灰描边 + 左圆点；开：蓝色实心 + 右白点。
     */
    static TextView pillSwitch(Context c, boolean on) {
        TextView sw = new TextView(c);
        sw.setWidth(dp(c, 46));
        sw.setHeight(dp(c, 26));
        sw.setPadding(dp(c, 2), 0, dp(c, 2), 0);
        sw.setGravity(on ? (Gravity.END | Gravity.CENTER_VERTICAL)
                        : (Gravity.START | Gravity.CENTER_VERTICAL));
        sw.setText("\u25cf");
        sw.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        sw.setTypeface(tf(c));
        if (on) {
            sw.setBackground(round(c, accent(c), 0, 13));
            sw.setTextColor(Color.WHITE);
        } else {
            sw.setBackground(round(c, card(c), trackOff(c), 13));
            sw.setTextColor(trackOff(c));
        }
        return sw;
    }

    static View[] rowSwitch(Context c, String label, boolean on, View.OnClickListener l) {
        LinearLayout r = hrow(c);
        r.setPadding(0, dp(c, 13), 0, dp(c, 13));
        r.addView(icon(c, iconOf(label), 22, iconColor(c)));
        TextView t = new TextView(c);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f);
        t.setTextColor(text(c));
        t.setTypeface(tf(c));
        t.setSingleLine(true);   /* 参考图里标签都在一行，不折行 */
        t.setSingleLine(true);
        t.setPadding(dp(c, 10), 0, 0, 0);
        r.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView sw = pillSwitch(c, on);
        r.addView(sw);
        r.setOnClickListener(l);
        return new View[]{r, sw};
    }

    /* ================= 按钮 ================= */

    static TextView pill(Context c, String s, boolean filled, View.OnClickListener l) {
        TextView b = new TextView(c);
        b.setText(s);
        b.setGravity(Gravity.CENTER);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f);
        b.setTypeface(tfBold(c));
        b.setPadding(dp(c, 20), dp(c, 10), dp(c, 20), dp(c, 10));
        b.setBackground(round(c, filled ? accent(c) : card(c), filled ? 0 : line(c), 20));
        b.setTextColor(filled ? Color.WHITE : text(c));
        if (l != null) b.setOnClickListener(l);
        return b;
    }

    static TextView button(Context c, String s, boolean primary, View.OnClickListener l) {
        TextView b = new TextView(c);
        b.setText(s);
        b.setGravity(Gravity.CENTER);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f);
        b.setTypeface(tf(c));
        b.setPadding(dp(c, 12), dp(c, 13), dp(c, 12), dp(c, 13));
        b.setBackground(round(c, primary ? accent(c) : card(c), primary ? 0 : line(c), 12));
        b.setTextColor(primary ? Color.WHITE : text(c));
        if (l != null) b.setOnClickListener(l);
        return b;
    }

    static LinearLayout rowOf(Context c, View... items) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setPadding(0, dp(c, 8), 0, dp(c, 2));
        for (int i = 0; i < items.length; i++) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            if (i > 0) lp.leftMargin = dp(c, 8);
            r.addView(items[i], lp);
        }
        return r;
    }

    static LinearLayout twoCol(Context c, View left, View right) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp2.leftMargin = dp(c, 12);
        r.addView(left, lp1);
        r.addView(right, lp2);
        return r;
    }

    static TextView title(Context c, String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f);
        t.setTextColor(text(c));
        t.setTypeface(tfBold(c));
        t.setPadding(0, dp(c, 6), 0, dp(c, 10));
        return t;
    }

    static TextView hint(Context c, String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        t.setTextColor(dim(c));
        t.setTypeface(tf(c));
        t.setLineSpacing(0, 1.4f);
        t.setPadding(0, dp(c, 4), 0, dp(c, 6));
        return t;
    }

    static TextView text2(Context c, String s, float sp, int color) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        t.setTypeface(tf(c));
        return t;
    }

    static View gap(Context c, int h) {
        View v = new View(c);
        v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(c, h)));
        return v;
    }
}
