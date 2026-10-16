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
            // 【诊断】真机排查用：把命令与返回长度写进 logcat（tag=SY-SHELL）。
            // 之前"数值全 0 / 弹窗空白"只能靠猜，加日志后能一眼看到是空返回还是没执行。
            try {
                android.util.Log.d("SY-SHELL", "cmd=" + cmd + " exit=" + exited
                        + " len=" + out.length() + " head=" + (out.length() > 60 ? out.substring(0, 60) : out));
            } catch (Throwable ignored) {}
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

    /* ====================================================================
     * 以下是"补齐网页功能"新增的方法。
     *
     * 每个方法都**严格对照脚本的真实 usage**（在真机上跑 sh <script>.sh
     * 拿到），不凭猜测写子命令 —— splash.sh 之前就因为 App 调了不存在的
     * toggle 而永远显示"无输出"，所以这次先取 usage 再写代码。
     * ==================================================================== */

    /* ---- dns.sh ---- */
    public static String dnsApply()          { return script("dns.sh", "apply"); }
    public static String dnsUpdate()         { return script("dns.sh", "update"); }
    public static String dnsHostsMount()     { return script("dns.sh", "hosts-mount"); }
    public static String dnsHostsUnmount()   { return script("dns.sh", "hosts-unmount"); }
    /** 【核对后修正】dns.sh 没有 hosts-clear，真实子命令是 hosts-toggle（切挂载） */
    public static String dnsHostsToggle()    { return script("dns.sh", "hosts-toggle"); }
    /** dns.sh clear：清空规则/引擎数据 */
    public static String dnsClear()          { return script("dns.sh", "clear"); }
    public static String dnsHostsRegen()     { return script("dns.sh", "hosts-regen"); }
    public static String dnsHostsStatus()    { return script("dns.sh", "hosts-status"); }
    public static String dnsFilterBuild()    { return script("dns.sh", "filter-build"); }
    public static String dnsFilterStats()    { return script("dns.sh", "filter-stats"); }
    public static String dnsEngineStats()    { return script("dns.sh", "engine-stats"); }
    public static String dnsEngineClear()    { return script("dns.sh", "engine-clear"); }
    public static String dnsEngineVerify()   { return script("dns.sh", "engine-verify"); }
    public static String dnsEngineSyntax()   { return script("dns.sh", "engine-syntax"); }
    public static String dnsCustomList()     { return script("dns.sh", "custom-list"); }
    public static String dnsCustomClear()    { return script("dns.sh", "custom-clear"); }
    public static String dnsBlacklistList()  { return script("dns.sh", "blacklist-list"); }
    public static String dnsBlacklistClear() { return script("dns.sh", "blacklist-clear"); }
    public static String dnsWhitelistList()  { return script("dns.sh", "whitelist-list"); }
    public static String dnsSources()        { return script("dns.sh", "sources-list"); }
    public static String dnsLists()          { return script("dns.sh", "lists"); }
    public static String dnsListsClear()     { return script("dns.sh", "lists-clear"); }
    public static String dnsMyRulesGet()     { return script("dns.sh", "my-rules-get"); }
    public static String dnsMyRulesClear()   { return script("dns.sh", "my-rules-clear"); }
    public static String dnsStatsSummary()   { return script("dns.sh", "stats-summary"); }
    public static String dnsRulesPreview()   { return script("dns.sh", "rules-preview"); }
    public static String dnsExport()         { return script("dns.sh", "export"); }
    public static String dnsFilterTest(String domain) { return script("dns.sh", "filter-test " + q(domain)); }
    public static String dnsBlacklistAdd(String d) { return script("dns.sh", "blacklist-add " + q(d)); }
    public static String dnsBlacklistDel(String d) { return script("dns.sh", "blacklist-del " + q(d)); }
    public static String dnsWhitelistAdd(String d) { return script("dns.sh", "whitelist-add " + q(d)); }
    public static String dnsWhitelistDel(String d) { return script("dns.sh", "whitelist-del " + q(d)); }
    public static String dnsSourcesAdd(String url, String name) { return script("dns.sh", "sources-add " + q(url) + " " + q(name)); }
    public static String dnsSourcesDel(String name) { return script("dns.sh", "sources-del " + q(name)); }
    public static String dnsRulesDelMulti(String csv) { return script("dns.sh", "rules-del-multi " + q(csv)); }
    /** 导入自定义规则文本（base64 走 stdin，避免命令行过长） */
    public static String dnsCustomSave(String text) { return stdinTo("dns.sh", "custom-save-b64", text); }
    public static String dnsMyRulesSave(String text) { return stdinTo("dns.sh", "my-rules-save-b64", text); }
    public static String dnsImportText(String text) { return stdinTo("dns.sh", "import-b64 custom", text); }
    public static String dnsBlacklistImport(String text) { return stdinTo("dns.sh", "blacklist-import-b64", text); }
    public static String dnsHostsSet(String text) { return stdinTo("dns.sh", "hosts-set-b64", text); }

    /* ---- dnssrv.sh ---- */
    public static String dnsSrvStatus()       { return script("dnssrv.sh", "status"); }
    public static String dnsSrvServers()      { return script("dnssrv.sh", "servers"); }
    public static String dnsSrvApply()        { return script("dnssrv.sh", "apply"); }
    public static String dnsSrvClear()        { return script("dnssrv.sh", "clear"); }
    public static String dnsSrvTest()         { return script("dnssrv.sh", "test"); }
    public static String dnsSrvSetMode(String m)   { return script("dnssrv.sh", "set-mode " + q(m)); }
    public static String dnsSrvSetDoh(String u)    { return script("dnssrv.sh", "set-doh " + q(u)); }
    public static String dnsSrvSetDot(String u)    { return script("dnssrv.sh", "set-dot " + q(u)); }
    public static String dnsSrvLeak(String onoff)  { return script("dnssrv.sh", "leak " + q(onoff)); }
    public static String dnsSrvAddServer(String s) { return script("dnssrv.sh", "add-server " + q(s)); }
    public static String dnsSrvDelServer(String s) { return script("dnssrv.sh", "del-server " + q(s)); }
    public static String dnsSrvClearServers()      { return script("dnssrv.sh", "clear-servers"); }

    /* ---- ruleset.sh ---- */
    public static String rulesetSync()        { return script("ruleset.sh", "sync"); }
    public static String rulesetStatus()      { return script("ruleset.sh", "status"); }
    public static String rulesetGetRepo()     { return script("ruleset.sh", "get-repo"); }
    public static String rulesetSetRepo(String r)   { return script("ruleset.sh", "set-repo " + q(r)); }
    public static String rulesetSetBranch(String b) { return script("ruleset.sh", "set-branch " + q(b)); }
    public static String rulesetSetMirror(String u) { return script("ruleset.sh", "set-mirror " + q(u)); }

    /* ---- mitm.sh ---- */
    public static String mitmRestart()        { return script("mitm.sh", "restart"); }
    public static String mitmCaStatus()       { return script("mitm.sh", "ca-status"); }
    public static String mitmCaRelease()      { return script("mitm.sh", "ca-release"); }
    // 【核对后移除】mitm.sh 没有 ca-uninstall 子命令（真实只有 ca-install/ca-release）
    public static String mitmStats()          { return script("mitm.sh", "stats"); }
    public static String mitmRulesCount()     { return script("mitm.sh", "rules-count"); }
    public static String mitmRulesReload()    { return script("mitm.sh", "rules-reload"); }
    public static String mitmRulesList()      { return script("mitm.sh", "rules-list"); }
    public static String mitmRulesListLines() { return script("mitm.sh", "rules-list-lines"); }
    public static String mitmRulesClear()     { return script("mitm.sh", "rules-clear"); }
    public static String mitmAppsGet()        { return script("mitm.sh", "apps-get"); }
    public static String mitmAppsSet(String csv) { return script("mitm.sh", "apps-set " + q(csv)); }
    public static String mitmRuleDel(String id)  { return script("mitm.sh", "rules-del " + q(id)); }
    public static String mitmRulesAdd(String text) { return stdinTo("mitm.sh", "rules-add-b64", text); }
    public static String mitmRulesImport(String text) { return stdinTo("mitm.sh", "rules-import", text); }

    /* ---- splash.sh ---- */
    public static String splashStart()        { return script("splash.sh", "start"); }
    public static String splashStop()         { return script("splash.sh", "stop"); }
    public static String splashEnable()       { return script("splash.sh", "enable"); }
    public static String splashDisable()      { return script("splash.sh", "disable"); }
    public static String splashRulesList()    { return script("splash.sh", "rules-list"); }
    public static String splashRulesClear()   { return script("splash.sh", "rules-clear"); }
    public static String splashRecords()      { return script("splash.sh", "records"); }
    public static String splashClearRecords() { return script("splash.sh", "clear-records"); }
    public static String splashRulesAdd(String text) { return stdinTo("splash.sh", "rules-import-b64", text); }
    public static String splashRulesImportNet(String u) { return script("splash.sh", "rules-import-net " + q(u)); }
    public static String splashRulesDelMulti(String csv) { return script("splash.sh", "rules-del-multi " + q(csv)); }

    /* ---- notify.sh ---- */
    public static String notifyStart()        { return script("notify.sh", "start"); }
    public static String notifyStop()         { return script("notify.sh", "stop"); }
    public static String notifyStatus()       { return script("notify.sh", "status"); }
    public static String notifyKeywords()     { return script("notify.sh", "keywords"); }
    public static String notifyRecords()      { return script("notify.sh", "records"); }
    public static String notifyKeywordAdd(String k) { return script("notify.sh", "keyword-add " + q(k)); }
    public static String notifyKeywordDel(String k) { return script("notify.sh", "keyword-del " + q(k)); }
    public static String notifyKeywordsClear() { return script("notify.sh", "keywords-clear"); }
    public static String notifyImportNet(String u) { return script("notify.sh", "keyword-import-net " + q(u)); }
    public static String notifyKeywordsAdd(String text) { return stdinTo("notify.sh", "keyword-add-b64", text); }

    /* ---- netblock.sh ---- */
    public static String netblockStatus()     { return script("netblock.sh", "status"); }
    public static String netblockList()       { return script("netblock.sh", "list"); }
    public static String netblockApply()      { return script("netblock.sh", "apply"); }
    public static String netblockPreview()    { return script("netblock.sh", "preview"); }
    public static String netblockAppsList()   { return script("netblock.sh", "apps-list"); }
    public static String netblockAdd(String type, String v) { return script("netblock.sh", "add " + q(type) + " " + q(v)); }
    public static String netblockDel(String type, String v) { return script("netblock.sh", "del " + q(type) + " " + q(v)); }
    public static String netblockDelMulti(String type, String v) { return script("netblock.sh", "del-multi " + q(type) + " " + q(v)); }
    public static String netblockClear(String type) { return script("netblock.sh", "clear " + q(type)); }
    public static String netblockAppsAdd(String p) { return script("netblock.sh", "apps-add " + q(p) + " " + q(p)); }
    public static String netblockAppsDelMulti(String v) { return script("netblock.sh", "apps-del-multi " + q(v)); }
    public static String netblockImportNet(String type, String u) { return script("netblock.sh", "import-net " + q(type) + " " + q(u)); }
    public static String netblockImport(String type, String text) { return stdinTo("netblock.sh", "import-b64 " + q(type), text); }

    /* ---- settings.sh（真实语法 get/set/all/dump/reset） ---- */
    public static String settingsAll()        { return script("settings.sh", "all"); }
    public static String settingsDump()       { return script("settings.sh", "dump"); }
    public static String settingsGet(String k) { return script("settings.sh", "get " + q(k)); }
    public static String settingsSet(String k, String v) { return script("settings.sh", "set " + q(k) + " " + q(v)); }
    public static String settingsReset()      { return script("settings.sh", "reset"); }

    /* ---- backup.sh ---- */
    public static String backupExport()       { return script("backup.sh", "export"); }
    public static String backupList()         { return script("backup.sh", "list"); }
    public static String backupImport(String file) { return script("backup.sh", "import " + q(file)); }
    public static String backupDelete(String name) { return script("backup.sh", "delete " + q(name)); }

    /* ---- logs.sh ---- */
    public static String logsList()           { return script("logs.sh", "list"); }
    public static String logsCat(String name, int n) { return script("logs.sh", "cat " + q(name) + " " + n); }
    public static String logsClear(String name) { return script("logs.sh", "clear " + q(name)); }
    public static String logsClearAll()       { return script("logs.sh", "clear-all"); }

    /* ---- updater.sh ---- */
    public static String updaterCheck()       { return script("updater.sh", "check"); }
    public static String updaterUpdate(boolean force) { return script("updater.sh", force ? "update force" : "update"); }
    public static String updaterStatus()      { return script("updater.sh", "status"); }
    public static String updaterSetRepo(String r) { return script("updater.sh", "set-repo " + q(r)); }

    /* ---- scripts_ext.sh ---- */
    public static String scriptsList()        { return script("scripts_ext.sh", "list"); }
    public static String scriptsListJson()    { return script("scripts_ext.sh", "list-json"); }
    public static String scriptsInfo(String n) { return script("scripts_ext.sh", "info " + q(n)); }
    public static String scriptsUpdateAll()   { return script("scripts_ext.sh", "update-all"); }
    public static String scriptsUpdate(String n) { return script("scripts_ext.sh", "update " + q(n)); }
    public static String scriptsRemove(String n) { return script("scripts_ext.sh", "remove " + q(n)); }
    public static String scriptsRemoveMulti(String csv) { return script("scripts_ext.sh", "remove-multi " + q(csv)); }
    public static String scriptsRollback(String n) { return script("scripts_ext.sh", "rollback " + q(n)); }
    public static String scriptsInstallUrl(String u) { return script("scripts_ext.sh", "install-url " + q(u)); }
    public static String scriptsInstallFile(String f) { return script("scripts_ext.sh", "install-file " + q(f)); }
    public static String scriptsSubscribe(String u) { return script("scripts_ext.sh", "subscribe " + q(u)); }
    public static String scriptsSubsList()    { return script("scripts_ext.sh", "subs-list"); }
    public static String scriptsSubsListJson() { return script("scripts_ext.sh", "subs-list-json"); }
    public static String scriptsSubsRemove(String id) { return script("scripts_ext.sh", "subs-remove " + q(id)); }
    public static String scriptsSubsRemoveMulti(String csv) { return script("scripts_ext.sh", "subs-remove-multi " + q(csv)); }
    public static String scriptsSubsToggle(String id) { return script("scripts_ext.sh", "subs-toggle " + q(id)); }
    public static String scriptsSubsEnableMulti(String csv) { return script("scripts_ext.sh", "subs-enable-multi " + q(csv)); }
    public static String scriptsImportMitm(String text) { return stdinTo("scripts_ext.sh", "import-mitm-b64", text); }
    public static String scriptsMitmToScript() { return script("scripts_ext.sh", "mitm-to-script"); }

    /* ---- 隐私相关 ---- */
    public static String privacyGuardApply()  { return script("privacy_guard.sh", "apply"); }
    public static String privacyGuardCheck()  { return script("privacy_guard.sh", "check"); }
    public static String privacyGuardRemove() { return script("privacy_guard.sh", "remove"); }
    public static String privacyGuardStatus() { return script("privacy_guard.sh", "status"); }
    public static String gamePrivacyApply()   { return script("game_privacy.sh", "apply"); }
    public static String gamePrivacyRemove()  { return script("game_privacy.sh", "remove"); }
    public static String gamePrivacyStatus()  { return script("game_privacy.sh", "status"); }
    public static String privacyRsList()      { return script("privacy_ruleset.sh", "list"); }
    public static String privacyRsStatus()    { return script("privacy_ruleset.sh", "status"); }
    public static String privacyRsEnable(String names) { return script("privacy_ruleset.sh", "enable " + q(names)); }
    public static String privacyRsDisable(String names) { return script("privacy_ruleset.sh", "disable " + q(names)); }
    public static String privacyRsClear()     { return script("privacy_ruleset.sh", "clear"); }
    public static String clipReaders()        { return script("clip_guard.sh", "readers"); }

    /* ---- proxycfg.sh ---- */
    public static String proxycfgStage(boolean fromGen) { return script("proxycfg.sh", fromGen ? "stage --from-gen" : "stage"); }
    public static String proxycfgCheck()      { return script("proxycfg.sh", "check"); }
    public static String proxycfgCommit()     { return script("proxycfg.sh", "commit"); }
    public static String proxycfgRollback()   { return script("proxycfg.sh", "rollback"); }
    public static String proxycfgStatus()     { return script("proxycfg.sh", "status"); }
    public static String proxycfgApply()      { return script("proxycfg.sh", "apply"); }

    /* ---- ctl.sh ---- */
    public static String ctlStatus()          { return script("ctl.sh", "status"); }
    public static String ctlToggle(String feature) { return script("ctl.sh", "toggle " + q(feature)); }
    public static String ctlRestart(String feature) { return script("ctl.sh", "restart " + q(feature)); }
    public static String ctlSection(String name) { return script("ctl.sh", q(name)); }

    /* ---- fileedit.sh ---- */
    public static String fileeditList()       { return script("fileedit.sh", "list"); }
    public static String fileeditRead(String rel) { return script("fileedit.sh", "read " + q(rel)); }
    public static String fileeditInfo(String rel) { return script("fileedit.sh", "info " + q(rel)); }
    public static String fileeditHashes()     { return script("fileedit.sh", "hashes"); }
    public static String fileeditWrite(String rel, String text) { return stdinTo("fileedit.sh", "write " + q(rel), text); }
    public static String fileeditAppend(String rel, String text) { return stdinTo("fileedit.sh", "append " + q(rel), text); }

    /* ---- 代理节点 / 控制面 ---- */
    public static String nodesUp()            { return script("proxynode.sh", "up"); }
    public static String nodesDown()          { return script("proxynode.sh", "down"); }
    public static String nodesRestart()       { return script("proxynode.sh", "restart"); }
    public static String nodesGenConfig()     { return script("proxynode.sh", "gen-config"); }
    public static String nodesConfigGet()     { return script("proxynode.sh", "config-get"); }
    public static String nodesConfigSet(String text) { return stdinTo("proxynode.sh", "config-set-b64", text); }
    public static String nodesCoreEnsure()    { return script("proxynode.sh", "core-ensure"); }
    public static String nodesCoreDownload(String u) { return script("proxynode.sh", "core-download " + q(u)); }
    public static String nodesLogs()          { return script("proxynode.sh", "logs"); }
    public static String nodesLeak(String onoff) { return script("proxynode.sh", "leak " + q(onoff)); }
    public static String nodesSelect(String idx) { return script("proxynode.sh", "select " + q(idx)); }
    public static String nodesDel(String idx) { return script("proxynode.sh", "del-node " + q(idx)); }
    public static String nodesClear()         { return script("proxynode.sh", "clear-nodes"); }
    public static String nodesAdd(String name, String proto, String link) { return script("proxynode.sh", "add-node " + q(name) + " " + q(proto) + " " + q(link)); }
    public static String nodesImportUrl(String u) { return script("proxynode.sh", "import-url " + q(u)); }
    public static String nodesImportText(String text) { return stdinTo("proxynode.sh", "import-b64", text); }
    public static String nodesSubAdd(String u)     { return script("proxynode.sh", "sub-add " + q(u)); }
    public static String nodesSubUpdate()     { return script("proxynode.sh", "sub-update"); }
    public static String nodesSubToggle(String idx) { return script("proxynode.sh", "sub-toggle " + q(idx)); }
    public static String proxyMgrProbe()      { return script("proxymgr.sh", "probe"); }
    public static String proxyMgrAppList()    { return script("proxymgr.sh", "app list"); }
    public static String proxyMgrAppAdd(String pkg, String pol) { return script("proxymgr.sh", "app add " + q(pkg) + " " + q(pol == null ? "proxy" : pol)); }
    public static String proxyMgrAppApply()   { return script("proxymgr.sh", "app apply"); }

    /* ---- selfcheck ---- */
    public static String selfcheckAll()       { return script("selfcheck.sh", "all"); }

    /* ====================================================================
     * 基础设施
     * ==================================================================== */

    /** shell 单引号转义：防止域名/URL/路径里的字符被 shell 解释 */
    private static String q(String s) {
        if (s == null) return "''";
        return "'" + s.replace("'", "'\\''") + "'";
    }

    /**
     * 把文本以 base64 写进脚本的标准输入后再执行子命令。
     *
     * 为什么需要它：网页端把内容直接拼进命令行参数（xxx-b64 <内容>），
     * 内容稍大就撞上 "Argument list too long"（模块里已经踩过这个坑）。
     * App 侧改成：内容 -> base64 -> 写进 su 的 stdin，脚本自己解码，
     * 命令行长度恒定。
     */
    public static String stdinTo(String scriptName, String args, String text) {
        synchronized (SU_LOCK) {
            Process p = null;
            try {
                String cmd = "sh " + MODDIR + "/scripts/" + scriptName
                        + " " + (args == null ? "" : args);
                p = new ProcessBuilder("su", "-c", cmd)
                        .redirectErrorStream(true)
                        .start();
                final Process fp = p;
                final StringBuilder sb = new StringBuilder();
                Thread reader = new Thread(new Runnable() {
                    @Override public void run() {
                        try {
                            BufferedReader br = new BufferedReader(
                                    new InputStreamReader(fp.getInputStream()));
                            String line;
                            while ((line = br.readLine()) != null) {
                                sb.append(line).append('\n');
                            }
                        } catch (Exception ignored) {}
                    }
                });
                reader.setDaemon(true);
                reader.start();
                OutputStreamWriter w = new OutputStreamWriter(p.getOutputStream());
                if (text != null) {
                    String b64 = android.util.Base64.encodeToString(
                            text.getBytes("UTF-8"), android.util.Base64.NO_WRAP);
                    w.write(b64);
                }
                w.write("\n");
                w.flush();
                w.close();
                long deadline = System.currentTimeMillis() + TIMEOUT_MS;
                boolean exited = false;
                while (System.currentTimeMillis() < deadline) {
                    try { p.exitValue(); exited = true; break; }
                    catch (IllegalThreadStateException still) { Thread.sleep(30); }
                }
                reader.join(exited ? 800 : 2000);
                String out = sb.toString();
                if (!exited) p.destroy();
                return out;
            } catch (Exception e) {
                return "ERR: " + e.getMessage();
            } finally {
                if (p != null) { try { p.destroy(); } catch (Exception ignored) {} }
            }
        }
    }
}
