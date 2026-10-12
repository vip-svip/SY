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
}
