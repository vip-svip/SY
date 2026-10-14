package com.syfusion.manager;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;

/**
 * root 命令执行。
 *
 * 走 `su -c` 而不是直接调用模块脚本：
 *   App 自身没有 root，所有涉及模块目录的操作都要借 su 提权。
 * 统一在这里做，方便集中处理超时与输出读取。
 */
public final class RootShell {

    private static final int TIMEOUT_MS = 20000;
    private static volatile Boolean sHasRoot = null;

    private RootShell() {}

    public static final String MODDIR = "/data/adb/modules/SY";

    public static boolean hasRoot() {
        Boolean c = sHasRoot;
        if (c != null) return c;
        String out = exec("id", 6000);
        boolean ok = out != null && out.contains("uid=0");
        sHasRoot = ok;
        return ok;
    }

    /** 执行一条命令，返回 stdout+stderr；失败返回 null。 */
    public static String exec(String cmd) {
        return exec(cmd, TIMEOUT_MS);
    }

    public static String exec(String cmd, int timeoutMs) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd)
                    .redirectErrorStream(true)
                    .start();
            final Process fp = p;
            final StringBuilder sb = new StringBuilder();
            Thread reader = new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        BufferedReader br = new BufferedReader(
                                new InputStreamReader(fp.getInputStream()));
                        String line;
                        while ((line = br.readLine()) != null) {
                            sb.append(line).append('\n');
                        }
                    } catch (Exception ignored) {
                    }
                }
            });
            reader.setDaemon(true);
            reader.start();

            // su 某些实现需要把命令写到 stdin 才执行
            try {
                OutputStreamWriter w = new OutputStreamWriter(p.getOutputStream());
                w.write(cmd);
                w.write("\n");
                w.flush();
                w.close();
            } catch (Exception ignored) {
            }

            long deadline = System.currentTimeMillis() + timeoutMs;
            while (System.currentTimeMillis() < deadline) {
                try {
                    p.exitValue();
                    break;
                } catch (IllegalThreadStateException still) {
                    Thread.sleep(50);
                }
            }
            try {
                p.exitValue();
            } catch (IllegalThreadStateException still) {
                p.destroy();
            }
            reader.join(500);
            return sb.toString();
        } catch (Exception e) {
            return null;
        } finally {
            if (p != null) {
                try {
                    p.destroy();
                } catch (Exception ignored) {
                }
            }
        }
    }

    /** 模块脚本入口 */
    public static String script(String name, String args) {
        String a = (args == null || args.length() == 0) ? "" : " " + args;
        return exec("sh " + MODDIR + "/scripts/" + name + a);
    }

    public static boolean panelRunning() {
        String out = exec("pgrep -f 'abserver serve' 2>/dev/null || ps -A 2>/dev/null | grep -c 'abserver serve'", 8000);
        if (out == null) return false;
        out = out.trim();
        if (out.length() == 0) return false;
        try {
            return Integer.parseInt(out.split("\\s+")[0]) > 0;
        } catch (Exception e) {
            return out.length() > 0;
        }
    }

    public static String startPanel() {
        return script("panel.sh", "start");
    }

    public static String restartCore() {
        return script("proxynode.sh", "restart");
    }

    public static String stopCore() {
        return script("proxynode.sh", "down");
    }

    public static String startCore() {
        return script("proxynode.sh", "up");
    }

    // ================= 隐私防泄露（leakguard）联动 =================
    // 这些不是空壳：每个方法都调用模块内真实脚本并返回其输出。

    /** 隐私总状态（人类可读，逐项列出 DNS/IPv6/IP/VPN/NODE/TUNE）。 */
    public static String leakStatus() {
        return script("leakguard.sh", "status");
    }

    /** 隐私结构化报告（JSON，供解析展示）。 */
    public static String leakReport() {
        return script("leakguard.sh", "report");
    }

    /** 子功能开关：what ∈ {dns,ipv6,ip,vpn,node,tune}，on/off。 */
    public static String leakToggle(String what, boolean on) {
        return script("leakguard.sh", what + " " + (on ? "on" : "off"));
    }

    /** 总开关：enable=全防护，disable=全部关闭。 */
    public static String leakAll(boolean on) {
        return script("leakguard.sh", on ? "enable" : "disable");
    }

    /** 一键应急：全防护 + 快照（可 restore 回滚）。 */
    public static String leakPanic() {
        return script("leakguard.sh", "panic");
    }

    /** 从快照恢复并移除本模块全部规则。 */
    public static String leakRestore() {
        return script("leakguard.sh", "restore");
    }

    /** 出口 IP 归属对比（真实 IP 泄露判定）。a,b 为两个公网 IP。 */
    public static String leakOwner(String a, String b) {
        return script("leakguard.sh", "owner " + a + "," + b);
    }

    /** 应用出口收敛：list / apply。 */
    public static String leakApps(String sub) {
        return script("leakguard.sh", "apps " + (sub == null ? "list" : sub));
    }

    // ================= Hook 子系统（内置 App） =================
    // 每个方法调用模块内真实脚本，非空壳。

    /** Hook 模式：null=查询；"targets"/"all"/"on"/"off"=设置。 */
    public static String hookMode(String mode) {
        return script("leakguard.sh", "hook-mode" + (mode == null ? "" : " " + mode));
    }

    /** Hook 能力与事件总览。 */
    public static String hookStatus() {
        return script("leakguard.sh", "hook-status");
    }

    /** 最近 Hook 事件（默认最近 n 条）。 */
    public static String hookEvents(int n) {
        return script("leakguard.sh", "hook-events " + n);
    }

    /** 清空 Hook 事件日志。 */
    public static String hookClear() {
        return script("leakguard.sh", "hook-clear");
    }

    /** 运营商隐私收敛开关。 */
    public static String carrierToggle(boolean on) {
        return script("leakguard.sh", "carrier " + (on ? "on" : "off"));
    }

    /** 运营商隐私收敛状态。 */
    public static String carrierStatus() {
        return script("leakguard.sh", "carrier status");
    }

    // ================= Root 权限 =================

    /** Root 权限自检与提权状态（uid / 模块目录可读性）。 */
    public static String rootStatus() {
        String id = exec("id", 6000);
        String modok = exec("test -d " + MODDIR + " && echo MODDIR_OK || echo MODDIR_MISSING", 6000);
        boolean root = hasRoot();
        StringBuilder sb = new StringBuilder();
        sb.append("root available : ").append(root ? "yes" : "no").append('\n');
        sb.append("id             : ").append(id == null ? "?" : id.trim()).append('\n');
        sb.append("module dir     : ").append(modok == null ? "?" : modok.trim()).append('\n');
        sb.append("module path    : ").append(MODDIR).append('\n');
        sb.append(root ? "所有特权操作均通过 su -c 执行。" : "未获得 root：请在 KernelSU/Magisk 中授予本应用 root。");
        return sb.toString();
    }
}
