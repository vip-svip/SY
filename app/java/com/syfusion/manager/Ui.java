package com.syfusion.manager;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * 原生界面小部件工厂。
 *
 * 为什么不再用 WebView 套壳：
 *   · 面板（webroot/index.html）是给浏览器与 KernelSU WebUI 用的；
 *   · 内置 App 是系统里的普通应用，应该用原生控件 —— 启动快、
 *     触摸/返回键/无障碍/深色模式与系统一致、面板没起来时也不会
 *     出现"网页无法打开"这种系统错误页；
 *   · 所有操作**直接调用模块脚本**（RootShell.script），不经 HTTP、
 *     不依赖面板进程，面板没启动也能用。
 */
final class Ui {
    private Ui() {}

    static final int SURFACE = 0xFF161B22;
    static final int STROKE = 0xFF232B36;
    static final int TEXT = 0xFFE6EDF3;
    static final int DIM = 0xFF8B949E;
    static final int ACCENT = 0xFF58A6FF;
    static final int OK = 0xFF3FB950;
    static final int WARN = 0xFFD29922;
    static final int ERR = 0xFFF85149;
    static final int BG = 0xFF0E1116;

    static int dp(Context c, float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                c.getResources().getDisplayMetrics());
    }

    static LinearLayout card(Context c, String title) {
        LinearLayout wrap = new LinearLayout(c);
        wrap.setOrientation(LinearLayout.VERTICAL);
        LinearLayout card = new LinearLayout(c);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(SURFACE);
        bg.setCornerRadius(dp(c, 12));
        bg.setStroke(dp(c, 1), STROKE);
        card.setBackground(bg);
        card.setPadding(dp(c, 14), dp(c, 12), dp(c, 14), dp(c, 12));
        if (title != null && title.length() > 0) {
            TextView t = new TextView(c);
            t.setText(title);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
            t.setTextColor(TEXT);
            t.setTypeface(null, Typeface.BOLD);
            t.setPadding(0, 0, 0, dp(c, 6));
            card.addView(t);
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(c, 12);
        wrap.addView(card, lp);
        return wrap;
    }

    static LinearLayout body(LinearLayout wrap) {
        return (LinearLayout) wrap.getChildAt(0);
    }

    static View[] kv(Context c, String label, String value) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setPadding(0, dp(c, 7), 0, dp(c, 7));
        TextView l = new TextView(c);
        l.setText(label);
        l.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        l.setTextColor(DIM);
        r.addView(l, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView v = new TextView(c);
        v.setText(value);
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        v.setTextColor(TEXT);
        v.setGravity(Gravity.END);
        v.setTypeface(Typeface.MONOSPACE);
        r.addView(v, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.2f));
        return new View[]{r, v};
    }

    static TextView button(Context c, String text, boolean primary, View.OnClickListener l) {
        TextView b = new TextView(c);
        b.setText(text);
        b.setGravity(Gravity.CENTER);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f);
        b.setPadding(dp(c, 12), dp(c, 11), dp(c, 12), dp(c, 11));
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(c, 8));
        if (primary) {
            bg.setColor(ACCENT);
            b.setTextColor(Color.WHITE);
        } else {
            bg.setColor(0xFF1F2630);
            bg.setStroke(dp(c, 1), 0xFF30384A);
            b.setTextColor(TEXT);
        }
        b.setBackground(bg);
        b.setOnClickListener(l);
        return b;
    }

    static TextView title(Context c, String text) {
        TextView t = new TextView(c);
        t.setText(text);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f);
        t.setTextColor(TEXT);
        t.setTypeface(null, Typeface.BOLD);
        t.setPadding(0, dp(c, 6), 0, dp(c, 10));
        return t;
    }

    static TextView hint(Context c, String text) {
        TextView t = new TextView(c);
        t.setText(text);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        t.setTextColor(DIM);
        t.setLineSpacing(0, 1.35f);
        t.setPadding(0, dp(c, 4), 0, dp(c, 8));
        return t;
    }

    static LinearLayout rowOf(Context c, View... items) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setPadding(0, dp(c, 6), 0, 0);
        for (int i = 0; i < items.length; i++) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            if (i > 0) lp.leftMargin = dp(c, 8);
            r.addView(items[i], lp);
        }
        return r;
    }

    static LinearLayout column(Context c) {
        LinearLayout v = new LinearLayout(c);
        v.setOrientation(LinearLayout.VERTICAL);
        return v;
    }
}