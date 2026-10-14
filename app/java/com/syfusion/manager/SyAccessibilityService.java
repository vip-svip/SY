package com.syfusion.manager;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.ArrayList;
import java.util.List;

/**
 * 无障碍服务：与模块联动，提供内核层无法覆盖的能力。
 *
 * 用途：
 *   1) 开屏广告自动跳过 —— 模块侧 splash.sh 负责内核窗口监听，本服务在
 *      App 进程内直接读取无障碍节点树，识别「跳过 / Skip / 关闭」按钮并点击，
 *      对 splash.sh 无法覆盖的 RN / WebView 开屏做兜底。
 *   2) 应用级隐私联动 —— 当检测到目标应用切到前台时，通过 RootShell 通知模块
 *      leakguard.sh 收紧该应用的 DNS/IP 出口策略（按需启用，默认关闭）。
 *
 * 配置来源：/data/adb/modules/SY/config/ 下的纯文本文件（借 su 读取），
 *   与模块脚本共用同一份事实源，保证「面板改了脚本认」。
 *
 * 安全：全部逻辑包在 try/catch 内，任何异常都不会影响被监听应用。
 */
public class SyAccessibilityService extends AccessibilityService {

    private static final String CFG_DIR = RootShell.MODDIR + "/config";
    private static final String CFG_APPS = CFG_DIR + "/splash_targets.txt";
    private static final String CFG_SKIP_WORDS = CFG_DIR + "/splash_skip_words.txt";

    private static final String[] DEFAULT_SKIP = {
            "跳过", "跳過", "关闭", "關閉", "skip", "Skip", "SKIP",
            "close", "Close", "跳过广告", "跳过 3", "跳过3"
    };

    private volatile String[] skipWords = DEFAULT_SKIP;
    private volatile List<String> targetPkgs = new ArrayList<String>();

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        try {
            AccessibilityServiceInfo info = getServiceInfo();
            if (info != null) {
                info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                        | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED;
                info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
                info.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                        | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
                info.notificationTimeout = 120;
                setServiceInfo(info);
            }
        } catch (Throwable ignored) {
        }
        reloadConfig();
    }

    /** 每次事件前按需重载，热更新配置无需重启服务。 */
    private void reloadConfig() {
        try {
            String raw = RootShell.exec("cat " + CFG_APPS + " 2>/dev/null", 4000);
            if (raw != null && raw.trim().length() > 0) {
                List<String> pkgs = new ArrayList<String>();
                for (String line : raw.split("\\r?\\n")) {
                    String p = line.trim();
                    if (p.length() > 0 && !p.startsWith("#")) pkgs.add(p);
                }
                targetPkgs = pkgs;
            }
            String words = RootShell.exec("cat " + CFG_SKIP_WORDS + " 2>/dev/null", 4000);
            if (words != null && words.trim().length() > 0) {
                List<String> w = new ArrayList<String>();
                for (String line : words.split("\\r?\\n")) {
                    String p = line.trim();
                    if (p.length() > 0 && !p.startsWith("#")) w.add(p);
                }
                if (!w.isEmpty()) skipWords = w.toArray(new String[0]);
            }
        } catch (Throwable ignored) {
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        try {
            if (event == null) return;
            if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                    && event.getEventType() != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
                return;
            }
            CharSequence pkgCs = event.getPackageName();
            final String pkg = pkgCs == null ? "" : pkgCs.toString();
            if (pkg.startsWith("com.android.systemui")) return;

            // 应用级隐私联动：目标应用切前台时通知模块收紧出口
            if (event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                    && targetPkgs.contains(pkg)) {
                notifyModuleAppForeground(pkg);
            }

            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) return;
            try {
                // 仅在疑似开屏场景尝试点击跳过（限制深度，避免过度遍历）
                clickSkip(root, 0);
            } finally {
                try { root.recycle(); } catch (Throwable ignored) {}
            }
        } catch (Throwable ignored) {
        }
    }

    private void notifyModuleAppForeground(final String pkg) {
        // 异步、静默：调用模块 leakguard.sh 的应用前台钩子（若存在）
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    RootShell.exec("sh " + RootShell.MODDIR + "/scripts/leakguard.sh app-enter " + pkg + " 2>/dev/null", 6000);
                } catch (Throwable ignored) {
                }
            }
        }).start();
    }

    private boolean clickSkip(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 12) return false;
        try {
            CharSequence text = node.getText();
            CharSequence desc = node.getContentDescription();
            if (matchesSkip(text) || matchesSkip(desc)) {
                AccessibilityNodeInfo clickable = findClickable(node);
                if (clickable != null) {
                    boolean ok = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    if (clickable != node) {
                        try { clickable.recycle(); } catch (Throwable ignored) {}
                    }
                    if (ok) return true;
                }
            }
            int n = node.getChildCount();
            for (int i = 0; i < n; i++) {
                AccessibilityNodeInfo c = node.getChild(i);
                if (c == null) continue;
                boolean hit = clickSkip(c, depth + 1);
                try { c.recycle(); } catch (Throwable ignored) {}
                if (hit) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    private boolean matchesSkip(CharSequence s) {
        if (s == null) return false;
        String t = s.toString().trim();
        if (t.length() == 0 || t.length() > 24) return false;
        String lower = t.toLowerCase();
        for (String w : skipWords) {
            if (w.length() == 0) continue;
            String wl = w.toLowerCase();
            if (lower.equals(wl)) return true;
            if (wl.length() >= 2 && lower.contains(wl)) return true;
        }
        return false;
    }

    private AccessibilityNodeInfo findClickable(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo cur = node;
        for (int i = 0; i < 6 && cur != null; i++) {
            if (cur.isClickable()) return cur;
            AccessibilityNodeInfo p = cur.getParent();
            if (p == cur) break;
            cur = p;
        }
        return node;
    }

    @Override
    public void onInterrupt() {
    }
}
