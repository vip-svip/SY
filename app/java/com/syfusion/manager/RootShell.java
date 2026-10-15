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

    /**
     * 【真机缺陷修复】su 串行锁。
     * 现象：同一页面同时发起 10+ 个 su -c 进程时，部分请求返回空串
     *      （真机实测：同一页里 hosts 条目能读到 4800，而用同样命令的
     *       规则列表却是 0）。
     * 原因：KernelSU 的 su 在高并发下新进程会被限流/排队，先起来的
     *      进程拿不到输出就退出。
     * 处理：把 root 命令**串行化**。UI 的读取都在后台线程，串行只影响
     *      总耗时（十几条命令约 1~2 秒），换来确定性。
     */
    private static final Object SU_LOCK = new Object();

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
        synchronized (SU_LOCK) {
            return execLocked(cmd, timeoutMs);
        }
    }

    private static String execLocked(String cmd, int timeoutMs) {
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

            /*
             * 【真机缺陷修复】旧实现有两个问题，导致 UI 上所有数值都是 0：
             *   ① 超时后立即 p.destroy() 再 reader.join(500) —— 进程被杀时
             *      管道里尚未读走的数据一起丢掉，sb 常常是空串；
             *   ② 无条件把 cmd 写进 stdin（su 已经用 -c 执行了，这些字节会
             *      被 shell 当成第二条命令读，可能干扰输出）。
             * 现在改为：等进程自然退出（最多 timeoutMs）→ 等 reader 读完
             * （最多 2s）→ 再返回。只有超时才 destroy，并且 destroy 前先给
             * reader 时间把已有数据读完。
             */
            try {
                OutputStreamWriter w = new OutputStreamWriter(p.getOutputStream());
                w.flush();   // 不写命令，只确保 shell 退出；命令已由 -c 传入
                w.close();
            } catch (Exception ignored) {
            }

            boolean exited = false;
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (System.currentTimeMillis() < deadline) {
                try {
                    p.exitValue();
                    exited = true;
                    break;
                } catch (IllegalThreadStateException still) {
                    Thread.sleep(30);
                }
            }
            // 先让 reader 把管道里剩下的数据读完（这是旧版丢数据的地方）
            reader.join(exited ? 800 : 2000);
            String out = sb.toString();
            if (!exited) p.destroy();
            return out;
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

    // ================= 模块联动扩展（原生 App 直接调用，不走 HTTP） =================
    // 说明：这些方法都调用模块内**真实脚本**。App 不依赖面板进程，
    // 所以即使面板没启动，这些功能依然可用 —— 这正是"联动模块而非联动网页"。

    /** 通用：调用任意模块脚本（name 可带 .sh） */
    public static String call(String scriptName, String args) {
        return script(scriptName, args);
    }

    /** 代理内核状态（proxyrun.sh status，JSON） */
    public static String proxyRunStatus() {
        return script("proxyrun.sh", "status");
    }

    /** 就绪三层（proxymgr.sh status，MagicNet 契约 JSON） */
    public static String proxyMgrStatus() {
        return script("proxymgr.sh", "status");
    }

    /** 代理健康检查（人类可读的逐层报告） */
    public static String proxyHealth() {
        return script("proxymgr.sh", "health");
    }

    /** 当前内核版本/路径 */
    public static String proxyCore() {
        return script("proxyrun.sh", "core");
    }

    /** 内核节点完整数据（proxynodes.sh list，JSON 含详细字段） */
    public static String nodesList() {
        return script("proxynodes.sh", "list");
    }

    /** 重建节点详细数据 */
    public static String nodesBuildMeta() {
        return script("proxynodes.sh", "build-meta");
    }

    /** 运行模式：direct / global / rule；null=查询 */
    public static String proxyMode(String mode) {
        return script("proxynodes.sh", "mode" + (mode == null ? "" : " " + mode));
    }

    /** 生效验证（5 步逐条报告：配置/进程/API/数据面/真实连通性） */
    public static String proxyVerify() {
        return script("proxynodes.sh", "verify");
    }

    /** 支持的协议清单 */
    public static String protocols() {
        return script("proxynodes.sh", "protocols");
    }

    /** 内置规则清单（8 份，JSON） */
    public static String builtinRules() {
        return script("builtin_rules.sh", "list");
    }

    /** 启用/停用某份内置规则 */
    public static String builtinRuleToggle(String key, boolean on) {
        return script("builtin_rules.sh", (on ? "on " : "off ") + key);
    }

    /** DNS 引擎状态（含拦截条数） */
    public static String dnsStatus() {
        return script("dns.sh", "status");
    }

    /** DNS 规则总表条数 */
    public static String dnsTotal() {
        return script("dns.sh", "total");
    }

    /** FX 深度抵抗状态 */
    public static String fxStatus() {
        return script("fx_deepguard.sh", "status");
    }

    /** FX 深度抵抗报告（人类可读） */
    public static String fxReport() {
        return script("fx_deepguard.sh", "report");
    }

    /** 剪贴板监视状态 */
    public static String clipStatus() {
        return script("clip_guard.sh", "status");
    }

    /** 一键全防护状态 */
    public static String oneClickStatus() {
        return script("oneclick.sh", "status");
    }

    /** 一键开启全部防护 */
    public static String oneClickOn() {
        return script("oneclick.sh", "on");
    }

    /** 一键关闭全部防护 */
    public static String oneClickOff() {
        return script("oneclick.sh", "off");
    }

    /** Hook 自定义规则统计 */
    public static String hookRuleStats() {
        return script("hook_rules.sh", "stats");
    }

    /** Hook 自定义规则内容 */
    public static String hookRulesCustom() {
        return script("hook_rules.sh", "list-custom");
    }

    /** 保存 Hook 自定义规则（内容通过临时文件传入，避免超长命令行） */
    public static String hookRulesSave(String content) {
        String stage = "/data/local/tmp/sy_hook_rules.txt";
        String b64 = android.util.Base64.encodeToString(
                content == null ? new byte[0] : content.getBytes(), android.util.Base64.NO_WRAP);
        // 用 base64 经 stdin 传给脚本，避免引号/长度问题
        return exec("printf %s '" + b64 + "' | base64 -d | sh " + MODDIR
                + "/scripts/hook_rules.sh save-custom");
    }

    /** 多语法导入（内容经 base64 传入） */
    public static String hookRulesImport(String content) {
        String b64 = android.util.Base64.encodeToString(
                content == null ? new byte[0] : content.getBytes(), android.util.Base64.NO_WRAP);
        return exec("printf %s '" + b64 + "' | base64 -d | sh " + MODDIR
                + "/scripts/hook_rules.sh import");
    }

    /** 多语法识别（只看结果，不写入） */
    public static String hookRulesAnalyze(String content) {
        String b64 = android.util.Base64.encodeToString(
                content == null ? new byte[0] : content.getBytes(), android.util.Base64.NO_WRAP);
        return exec("printf %s '" + b64 + "' | base64 -d | sh " + MODDIR
                + "/scripts/hook_rules.sh analyze");
    }

    /** 内置 App 自检与修复（未装则装；无障碍丢了就恢复） */
    public static String appEnsure() {
        return script("installapp.sh", "ensure");
    }

    /** 模块自检（selfcheck.sh，诊断模块完整性） */
    public static String selfCheck() {
        return script("selfcheck.sh", "all");
    }

    /** 设备信息（用于"适配多种手机"的诊断） */
    public static String deviceInfo() {
        StringBuilder sb = new StringBuilder();
        String[][] props = {
            {"ro.product.model", "机型"},
            {"ro.product.brand", "品牌"},
            {"ro.build.version.release", "Android 版本"},
            {"ro.build.version.sdk", "SDK"},
            {"ro.product.cpu.abi", "ABI"},
            {"ro.product.cpu.abilist", "ABI 列表"},
            {"ro.miui.ui.version.name", "MIUI"},
            {"ro.build.version.opporom", "ColorOS"},
            {"ro.vivo.os.version", "OriginOS"},
            {"ro.build.version.emui", "EMUI"},
            {"ro.semc.version.cust", "Sony"},
            {"ro.build.version.oneui", "OneUI"},
        };
        for (String[] kv : props) {
            String v = exec("getprop " + kv[0], 4000);
            if (v != null && v.trim().length() > 0) {
                sb.append(kv[1]).append(": ").append(v.trim()).append('\n');
            }
        }
        String kern = exec("uname -a", 4000);
        if (kern != null) sb.append("内核: ").append(kern.trim()).append('\n');
        String rootMgr = exec("[ -d /data/adb/ksu ] && echo KernelSU || ([ -d /data/adb/ap ] && echo APatch || ([ -d /data/adb/magisk ] && echo Magisk || echo unknown))", 5000);
        if (rootMgr != null) sb.append("Root 管理器: ").append(rootMgr.trim()).append('\n');
        return sb.toString();
    }
}
