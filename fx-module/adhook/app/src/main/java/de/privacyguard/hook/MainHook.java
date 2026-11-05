package de.privacyguard.hook;

import android.annotation.SuppressLint;
import android.content.ClipData;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.database.MatrixCursor;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.location.Location;
import android.location.LocationListener;
import android.media.AudioRecord;
import android.net.TrafficStats;
import android.os.BatteryManager;
import android.os.Build;
import android.os.SystemClock;
import android.util.DisplayMetrics;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * PrivacyGuard LSPosed Hook 入口。
 * 配置源: /data/local/tmp/privacyguard/xposed.conf（由模块 scripts/gen_xposed_conf.sh 生成）
 * 格式: key=value 顶层开关 + [conf:节名]/[list:节名] 值列表，键名与 WebUI data-key 一致。
 * conf 段内 key=value 行用 confOf(段,键) 读取；纯路径/域名列表用 lines(段) 读取。
 */
public class MainHook implements IXposedHookLoadPackage {

    private static final String TAG = "PrivacyGuard";
    private static final String CONF_PATH = "/data/local/tmp/privacyguard/xposed.conf";
    private static final String API101_MANAGED_PATH = "/data/local/tmp/privacyguard/fx-api101-managed.conf";
    private static final Random RNG = new Random();
    /** 本模块自身包名（绝不对自己 Hook，否则 WebUI/状态接口会被自己的过滤逻辑搞坏） */
    private static final String SELF_PKG = "de.privacyguard.adhook";

    private final Map<String, String> sw = new HashMap<>();
    private final Map<String, List<String>> sec = new HashMap<>();
    private String pkg = "?";
    /** 生效的档位: compat|standard|aggressive；custom = 未配置档位，走逐键模式（v1.10.4 旧行为） */
    private String profile = "custom";
    /** [conf:lsposed_scope] 白名单（空=不额外限制，仍由 LSPosed 作用域决定；默认空） */
    private final List<String> scopeAllow = new ArrayList<>();
    private final Set<String> api101Managed = new HashSet<>();
    private boolean api101OwnershipAvailable;

    /* ================= 破坏性 Hook 分级（PART B） =================
     * 背景：「破坏性」= 不改宿主 App 自身数据，而是让宿主看到的系统 API 结果变成
     * 空/false/0/异常。这类 Hook 在模块自身作用域(android)里无害（system_server
     * 已被跳过），但一旦用户把普通 App 勾进作用域，就会直接打断该 App 的正常逻辑：
     *   block_pm_query   → queryIntentActivities 返回空 → 分享/深链/内置浏览器
     *                      取 result[0] 直接 NPE/IndexOutOfBounds
     *   block_process_list→ getRunningAppProcesses 返回空 → 任务管理/自检类 App 崩溃
     *   block_mounts/hide_mounts → /proc/mounts 抛 FileNotFoundException →
     *                       依赖挂载表判断存储/SD 卡的代码未捕获即崩
     *   block_netstats   → TrafficStats 全 0 → 流量面板除零/显示错乱
     *   block_net_ifaces → 网卡枚举为空 → 取本机 IP 的代码 NPE
     *   block_cell_info/usagestats_off → 空列表 → 取 [0] 崩溃
     *   hide_su/hide_magisk/hide_ksu/block_rootcheck_libs/fs_* → File.exists false、
     *                       Runtime.exec 抛 IOException → 检测库未捕获即崩
     * 因此：档位只决定这些「破坏性键」，其余（设备伪装/传感器/相机麦克风等）
     * 仍按各自开关决定 —— 那些是「功能屏蔽」，不是「改坏宿主环境」。
     */
    private static final Set<String> RISKY = new HashSet<>(Arrays.asList(
            // 进程 / 包管理 / 存储 / 网络统计
            "block_process_list", "block_pm_query", "block_mounts", "hide_mounts",
            "block_netstats", "block_net_ifaces", "block_cell_info", "block_mediastore",
            "usagestats_off", "k_task", "app_list",
            // root / 文件痕迹
            "hide_su", "hide_magisk", "hide_ksu", "block_rootcheck_libs",
            "hide_sysfs_nodes", "hide_kernel_debug", "block_logcat",
            "fs_attrs", "fs_hide", "fs_rootlist", "fs_isolate", "fs_vfs",
            // 系统能力枚举
            "block_notif_listen", "hide_notif_perm", "block_ime_logging", "a11y_hide",
            "syssvc_hide", "clipboard", "clipboard_isolate", "ad_id_unify",
            "block_wifi_scan", "vpn_hide", "block_kernel_version"));

    /** compat：零破坏 —— 所有破坏性 Hook 关闭。勾了普通 App 也绝不改变它的行为。 */
    private static final Set<String> TIER_COMPAT = new HashSet<>();

    /** standard：只保留「几乎不会被普通 App 依赖」的 root 痕迹隐藏；
     *  进程/包查询/挂载表/流量/网卡/通知/输入法/无障碍/剪贴板全部关闭。 */
    private static final Set<String> TIER_STANDARD = new HashSet<>(Arrays.asList(
            "hide_su", "hide_magisk", "hide_ksu",
            "hide_sysfs_nodes", "hide_kernel_debug",
            "block_rootcheck_libs", "ad_id_unify"));

    /** aggressive：全部破坏性 Hook 开启（= v1.10.4 逐键模式把相关键都设为 1 的效果）。
     *  仅建议对「确定能承受」的 App 使用；可能导致该 App 部分功能失效或闪退。 */
    private static final Set<String> TIER_AGGRESSIVE = null; // null = 全部 RISKY 视为开启

    /** 明确的系统进程/框架黑名单：system_server(android)、本模块自身、
     *  LSPosed 管理器进程永不 Hook（Hook 框架自身会让"模块启用/作用域"状态错乱）。 */
    private static final Set<String> NEVER_HOOK = new HashSet<>(Arrays.asList(
            "android", SELF_PKG, "system", "org.lsposed.manager"));

    /* ================= 崩溃兜底（PART B） =================
     * Xposed 的 handleHookedMethod 不会替你吞异常：before/after 里抛出的 Throwable 会
     * 直接穿到被 Hook 的方法调用点，宿主 App 未捕获就是一次 FATAL EXCEPTION / 闪退。
     * SafeHook 把 before/after 收成 final，所有 Hook 体改在 onBefore/onAfter 里实现，
     * 异常一律 XposedBridge.log 后丢弃 —— 模块最坏情况变成"这条 Hook 没生效"，
     * 而绝不再是"宿主 App 崩了"。
     */
    private abstract static class SafeHook extends XC_MethodHook {
        @Override
        public final void beforeHookedMethod(MethodHookParam param) throws Throwable {
            try {
                onBefore(param);
            } catch (Throwable t) {
                onHookError("before", param, t);
            }
        }

        @Override
        public final void afterHookedMethod(MethodHookParam param) throws Throwable {
            try {
                onAfter(param);
            } catch (Throwable t) {
                onHookError("after", param, t);
            }
        }

        /** 子类实现：替换原来的 beforeHookedMethod */
        protected void onBefore(MethodHookParam param) throws Throwable {}

        /** 子类实现：替换原来的 afterHookedMethod */
        protected void onAfter(MethodHookParam param) throws Throwable {}

        private void onHookError(String phase, MethodHookParam param, Throwable t) {
            String mn = param != null && param.method != null ? param.method.getName() : "?";
            String cls = param != null && param.method != null
                    ? param.method.getDeclaringClass().getSimpleName() : "?";
            log("hook " + phase + " failed " + cls + "." + mn + ": " + t);
        }
    }

    /** 常量替换的兜底版本：语义等同 constHook(v)
     *  （before 里 setResult 即跳过原方法体并直接返回该值），
     *  但走 SafeHook 通道，异常不会穿到宿主。 */
    private static SafeHook constHook(final Object v) {
        return new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) {
                param.setResult(v);
            }
        };
    }

    /* ================= 入口 ================= */

    @SuppressLint("DefaultLocale")
    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpp) throws Throwable {
        pkg = lpp.packageName;
        // 自身包名绝不 Hook（否则 WebUI 的 bridge/状态查询会被自己的过滤逻辑裁掉）
        if (SELF_PKG.equals(pkg)) return;
        if (!loadConf()) {
            log("no config, hooks inactive in " + pkg);
            return;
        }
        // Fail closed: a missing, malformed, or disabled master switch must never
        // install privacy hooks. The previous check only rejected the literal "0",
        // so a truncated config with no lsposed_enabled key could enable hooks.
        String master = sw.get("lsposed_enabled");
        if (!"1".equals(master)) {
            log("privacy hooks inactive: lsposed_enabled is not explicitly 1 in " + pkg);
            return;
        }
        // 系统进程/system_server 不做任何 Hook：一是避免系统不稳定，二是 android
        // 进程里的 queryIntentActivities/File.exists 一旦被改空会让全系统连锁异常。
        // Build 等伪装由各应用进程内独立生效，不需要在 system_server 里做。
        if (NEVER_HOOK.contains(pkg)) return;
        // 可选白名单（默认空）：空 = 完全沿用 LSPosed 管理器里勾选的作用域
        if (!inScopeAllowlist()) {
            log("skip " + pkg + " (not in [conf:lsposed_scope])");
            return;
        }

        // --- 设备/系统伪装 ---
        try { buildSpoof(); } catch (Throwable t) { log("build " + t); }
        try { kernelVersionHide(); } catch (Throwable t) { log("kver " + t); }
        try { secureSettingsSpoof(); } catch (Throwable t) { log("secure " + t); }
        try { serialSpoof(); } catch (Throwable t) { log("serial " + t); }
        try { telephonySpoof(); } catch (Throwable t) { log("tel " + t); }
        try { btWifiMacSpoof(); } catch (Throwable t) { log("mac " + t); }
        try { batterySpoof(); } catch (Throwable t) { log("bat " + t); }
        try { screenSpoof(); } catch (Throwable t) { log("screen " + t); }
        try { storageSpoof(); } catch (Throwable t) { log("storage " + t); }
        try { sysPropsHide(); } catch (Throwable t) { log("sysprop " + t); }

        // --- 系统服务与 API ---
        try { sysSvcHide(); } catch (Throwable t) { log("syssvc " + t); }
        try { clipboardGuard(); } catch (Throwable t) { log("clip " + t); }
        try { appListHide(lpp); } catch (Throwable t) { log("applist " + t); }
        try { pmQueryHide(lpp); } catch (Throwable t) { log("pmquery " + t); }
        try { procListHide(); } catch (Throwable t) { log("proc " + t); }
        try { mediastoreHide(); } catch (Throwable t) { log("media " + t); }
        try { netIfacesHide(); } catch (Throwable t) { log("ifaces " + t); }
        try { netStatsHide(); } catch (Throwable t) { log("netstats " + t); }
        try { vpnHide(lpp); } catch (Throwable t) { log("vpnhide " + t); }
        try { adIdUnify(lpp); } catch (Throwable t) { log("adid " + t); }
        try { imeHide(); } catch (Throwable t) { log("ime " + t); }

        // --- 定位与传感器 ---
        try { locationMock(); } catch (Throwable t) { log("loc " + t); }
        try { gnssSpoof(); } catch (Throwable t) { log("gnss " + t); }
        try { passiveLocHide(); } catch (Throwable t) { log("passive " + t); }
        try { wifiScanHide(); } catch (Throwable t) { log("wifiscan " + t); }
        try { sensorHide(); } catch (Throwable t) { log("sensor " + t); }

        // --- 硬件与媒体 ---
        try { cameraNull(); } catch (Throwable t) { log("cam " + t); }
        try { micBlock(); } catch (Throwable t) { log("mic " + t); }
        try { audioFpBlock(); } catch (Throwable t) { log("audiofp " + t); }
        try { bioHide(lpp); } catch (Throwable t) { log("bio " + t); }

        // --- 通知/使用情况/无障碍/EXIF ---
        try { notifHide(); } catch (Throwable t) { log("notif " + t); }
        try { notifPermHide(); } catch (Throwable t) { log("notifperm " + t); }
        try { usageHide(); } catch (Throwable t) { log("usage " + t); }
        try { a11yHide(); } catch (Throwable t) { log("a11y " + t); }
        try { exifStrip(lpp); } catch (Throwable t) { log("exif " + t); }

        // --- Root/文件痕迹 ---
        try { rootHide(); } catch (Throwable t) { log("root " + t); }
        try { fsHooks(); } catch (Throwable t) { log("fs " + t); }
        // k_netfilter 免编译说明：iptables/netfilter 链由 shell 层 apply.sh 的
        // PGUARD/PGNAT 实现（内核 netfilter 钩子用户态可编程，无需编译内核）

        log("hooks installed in " + pkg + " (flags: " + countOn() + " on)");
    }

    /* ================= 配置读取 ================= */

    private boolean loadConf() {
        loadApi101Managed();
        File f = new File(CONF_PATH);
        if (!f.canRead()) return false;
        try {
            BufferedReader r = new BufferedReader(new FileReader(f));
            String ln, cur = null;
            while ((ln = r.readLine()) != null) {
                ln = ln.trim();
                if (ln.isEmpty() || ln.startsWith("#")) continue;
                if (ln.startsWith("[") && ln.endsWith("]")) {
                    String name = ln.substring(1, ln.length() - 1);
                    if (name.startsWith("conf:")) {
                        cur = name.substring(5);
                        sec.putIfAbsent(cur, new ArrayList<>());
                    } else if (name.startsWith("list:")) {
                        cur = "list:" + name.substring(5);
                        sec.putIfAbsent(cur, new ArrayList<>());
                    } else {
                        cur = null;
                    }
                    continue;
                }
                if (cur == null) {
                    int i = ln.indexOf('=');
                    if (i > 0) sw.put(ln.substring(0, i).trim(), ln.substring(i + 1).trim());
                } else {
                    sec.get(cur).add(ln);
                }
            }
            r.close();
            // 档位解析：profile 取值 compat/standard/aggressive；非法值一律退回 custom（逐键模式）
            String p = sw.get("lsposed_profile");
            if (p != null) {
                p = p.trim().toLowerCase(Locale.US);
                if ("compat".equals(p) || "standard".equals(p) || "aggressive".equals(p)) {
                    profile = p;
                } else {
                    profile = "custom";
                }
            }
            // [conf:lsposed_scope] 白名单：支持每行一个包名、逗号分隔、前缀通配 com.x.*
            for (String s : lines("lsposed_scope")) {
                String t = s.trim();
                if (t.isEmpty() || t.startsWith("#")) continue;
                for (String one : t.split(",")) {
                    String q = one.trim();
                    if (!q.isEmpty() && !q.startsWith("#")) scopeAllow.add(q);
                }
            }
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    private static final Set<String> API101_OWNED_LEGACY_KEYS = new HashSet<>(Arrays.asList(
            "exif_strip", "clipboard", "clipboard_isolate",
            "sensor_accel", "sensor_gyro", "sensor_light", "sensor_magnet",
            "sensor_pressure", "sensor_prox", "sensor_rate_limit",
            "block_wifi_scan", "block_notif_listen", "hide_notif_perm",
            "mic_block", "audio_fp_block", "cam_null", "disable_passive_loc",
            "block_mediastore"));

    private void loadApi101Managed() {
        api101Managed.clear();
        api101OwnershipAvailable = false;
        File managed = new File(API101_MANAGED_PATH);
        if (!managed.isFile() || !managed.canRead()) {
            log("API-101 ownership map unreadable; overlapping legacy hooks disabled for safety");
            return;
        }
        try {
            BufferedReader reader = new BufferedReader(new FileReader(managed));
            try {
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] parts = line.trim().split(",", -1);
                    if (parts.length < 2 || !parts[0].matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+")) continue;
                    for (int i = 1; i < parts.length; i++) {
                        String key = parts[i].trim();
                        if (key.matches("[a-z0-9_]{1,64}")) api101Managed.add(parts[0] + "|" + key);
                    }
                }
            } finally {
                reader.close();
            }
            api101OwnershipAvailable = true;
        } catch (IOException e) {
            api101Managed.clear();
            api101OwnershipAvailable = false;
            log("API-101 ownership map read failed; overlapping legacy hooks disabled for safety");
        }
    }

    private static final Set<String> DISABLED_EVASION_KEYS = new HashSet<>(Arrays.asList(
            "hide_su", "hide_magisk", "hide_ksu", "block_rootcheck_libs",
            "hide_sysfs_nodes", "hide_kernel_debug", "fs_attrs", "fs_hide", "fs_rootlist",
            "fs_isolate", "fs_vfs", "block_process_list", "block_pm_query", "block_mounts",
            "hide_mounts", "block_netstats", "block_net_ifaces", "block_cell_info",
            "usagestats_off", "k_task", "app_list", "vpn_hide", "syssvc_hide",
            "block_kernel_version", "patch_spoof", "gnss_spoof", "mock_location",
            "perapp_mock", "gps", "gps_accuracy", "spoof_android_id", "spoof_imei", "spoof_sim", "telephony", "spoof_serial",
            "spoof_hardware", "spoof_baseband", "spoof_brand", "spoof_manufacturer",
            "spoof_model", "spoof_fingerprint", "spoof_bt_mac", "spoof_wifi_mac",
            "spoof_version", "spoof_storage", "spoof_screen", "spoof_battery",
            "cam_hw_hide", "hide_face_hw", "hide_fingerprint_hw", "mic_hw_hide"));

    private boolean on(String k) {
        if (api101Managed.contains(pkg + "|" + k)) return false;
        if (!api101OwnershipAvailable && API101_OWNED_LEGACY_KEYS.contains(k)) return false;
        if (DISABLED_EVASION_KEYS.contains(k)) return false;
        // 档位优先于逐键值：profile != custom 时，破坏性键由档位裁决，其余键仍看逐键开关。
        // 这样用户「选兼容模式」即得到零破坏保证，不用逐键理解 30 多个破坏性开关。
        if (RISKY.contains(k) && !"custom".equals(profile)) {
            if ("compat".equals(profile)) return false;
            if ("standard".equals(profile)) return TIER_STANDARD.contains(k);
            if ("aggressive".equals(profile)) return true;
        }
        return "1".equals(sw.get(k));
    }

    /** 该包是否在 [conf:lsposed_scope] 白名单内（白名单为空 = 不额外限制，沿用 LSPosed 作用域） */
    private boolean inScopeAllowlist() {
        if (scopeAllow.isEmpty()) return true;
        for (String p : scopeAllow) {
            String t = p.trim();
            if (t.isEmpty() || t.startsWith("#")) continue;
            if (t.equals(pkg)) return true;
            // 支持逗号分隔一行多个与通配后缀: com.example.*
            if (t.endsWith("*") && pkg.startsWith(t.substring(0, t.length() - 1))) return true;
        }
        return false;
    }

    private int countOn() {
        int n = 0;
        for (String v : sw.values()) if ("1".equals(v)) n++;
        return n;
    }

    /** 段内纯行列表（fs_rootlist/syssvc_hide/perapp_mock 等） */
    private List<String> lines(String name) {
        List<String> l = sec.get(name);
        return l != null ? l : Collections.<String>emptyList();
    }

    /** conf 段内 key=value 解析：confOf("spoof_model","ro.product.model","Pixel 6") */
    private String confOf(String section, String key, String def) {
        String pfx = key + "=";
        for (String s : lines(section)) {
            String t = s.trim();
            if (t.startsWith(pfx)) {
                String v = t.substring(pfx.length()).trim();
                if (!v.isEmpty()) return v;
            }
        }
        return def;
    }

    private double confDbl(String section, String key, double def) {
        try {
            return Double.parseDouble(confOf(section, key, String.valueOf(def)));
        } catch (Exception e) {
            return def;
        }
    }

    private long confLong(String section, String key, long def) {
        try {
            return Long.parseLong(confOf(section, key, String.valueOf(def)));
        } catch (Exception e) {
            return def;
        }
    }

    private int confInt(String section, String key, int def) {
        try {
            return Integer.parseInt(confOf(section, key, String.valueOf(def)));
        } catch (Exception e) {
            return def;
        }
    }

    /** 稳定的按包名哈希伪 ID */
    private String hashHex(String seed, int len) {
        StringBuilder sb = new StringBuilder();
        int h = seed.hashCode();
        while (sb.length() < len) {
            h = h * 31 + 0x9E3779B9;
            sb.append(String.format("%08x", h));
        }
        return sb.substring(0, len);
    }

    /* ================= Build 字段伪装 ================= */

    private void setField(Class<?> c, String field, Object v) {
        try {
            java.lang.reflect.Field f = c.getDeclaredField(field);
            f.setAccessible(true);
            f.set(null, v);
        } catch (Throwable ignored) {}
    }

    private void buildSpoof() {
        if (on("spoof_model")) {
            setField(Build.class, "MODEL", confOf("spoof_model", "ro.product.model", "Pixel 6"));
            String dev = confOf("spoof_model", "ro.product.device", "oriole");
            setField(Build.class, "DEVICE", dev);
            setField(Build.class, "PRODUCT", dev);
        }
        if (on("spoof_manufacturer")) {
            setField(Build.class, "MANUFACTURER", confOf("spoof_manufacturer", "ro.product.manufacturer", "Google"));
        }
        if (on("spoof_brand")) {
            setField(Build.class, "BRAND", confOf("spoof_brand", "ro.product.brand", "google"));
        }
        if (on("spoof_hardware")) {
            setField(Build.class, "HARDWARE", confOf("spoof_hardware", "ro.hardware", "oriole"));
            setField(Build.class, "BOARD", confOf("spoof_hardware", "ro.board.platform", "gs101"));
        }
        if (on("spoof_fingerprint")) {
            setField(Build.class, "FINGERPRINT",
                    confOf("spoof_fingerprint", "ro.build.fingerprint", Build.FINGERPRINT));
        }
        if (on("spoof_version")) {
            setField(Build.VERSION.class, "RELEASE",
                    confOf("spoof_version", "ro.build.version.release", Build.VERSION.RELEASE));
            int sdk = confInt("spoof_version", "ro.build.version.sdk", Build.VERSION.SDK_INT);
            if (sdk > 0) setField(Build.VERSION.class, "SDK_INT", sdk);
        }
        if (on("patch_spoof")) {
            String sp = confOf("patch_spoof", "security_patch", null);
            if (sp == null) sp = confOf("patch_spoof", "ro.build.version.security_patch",
                    Build.VERSION.SECURITY_PATCH != null ? Build.VERSION.SECURITY_PATCH : "2023-06-05");
            setField(Build.VERSION.class, "SECURITY_PATCH", sp);
        }
        if (on("spoof_baseband")) {
            try {
                Method m = Build.class.getMethod("getRadioVersion");
                XposedBridge.hookMethod(m, constHook(
                        confOf("spoof_baseband", "ro.build.expect.baseband", "g5300-XXXXXX")));
            } catch (Throwable ignored) {}
        }
    }

    /* ================= 内核版本隐藏 (block_kernel_version) ================= */

    private static final String FAKE_KERNEL = "4.14.180-perf";

    private void kernelVersionHide() {
        if (!on("block_kernel_version")) return;
        setField(Build.class, "KERNEL", FAKE_KERNEL);
        try {
            Class<?> sys = System.class;
            hookAll(sys, "getProperty", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args != null && param.args.length >= 1 && param.args[0] instanceof String) {
                        String n = (String) param.args[0];
                        if ("os.version".equals(n)) param.setResult(FAKE_KERNEL);
                        else if ("os.name".equals(n)) param.setResult("Linux");
                    }
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= Settings.Secure 合并伪装 ================= */
    /* android_id (spoof_android_id) / default_input_method (block_ime_logging) /
       enabled_notification_listeners (block_notif_listen) */

    private void secureSettingsSpoof() {
        final boolean aid = on("spoof_android_id");
        final boolean ime = on("block_ime_logging");
        final boolean nl = on("block_notif_listen");
        if (!aid && !ime && !nl) return;
        final String fakeAid = confOf("spoof_android_id", "android_id", "");
        try {
            XposedHelpers.findAndHookMethod(
                "android.provider.Settings$Secure", null,
                "getString", "android.content.ContentResolver", String.class,
                new SafeHook() {
                    @Override
                    protected void onAfter(MethodHookParam param) {
                        Object a1 = param.args != null && param.args.length > 1 ? param.args[1] : null;
                        if (!(a1 instanceof String)) return;
                        String name = (String) a1;
                        if (aid && "android_id".equals(name)) {
                            param.setResult(fakeAid.isEmpty() ? hashHex(pkg + "|aid", 16) : fakeAid);
                        } else if (ime && "default_input_method".equals(name)) {
                            param.setResult("");
                        } else if (nl && "enabled_notification_listeners".equals(name)) {
                            param.setResult("");
                        }
                    }
                });
        } catch (Throwable ignored) {}
    }

    /* ================= 序列号 (spoof_serial) ================= */

    private void serialSpoof() {
        if (!on("spoof_serial")) return;
        String fake = confOf("spoof_serial", "serial", "");
        if (fake.isEmpty()) fake = "PG" + hashHex(pkg + "|serial", 10);
        setField(Build.class, "SERIAL", fake);
        Class<?> b = Build.class;
        hookAll(b, "getSerial", constHook(fake));
    }

    /* ================= 电话标识 (spoof_imei / spoof_sim / telephony / block_cell_info) ================= */

    private void telephonySpoof() {
        boolean imeiOn = on("spoof_imei");
        boolean simOn = on("spoof_sim");
        boolean telOn = on("telephony");
        if (!imeiOn && !simOn && !telOn && !on("block_cell_info")) return;

        Class<?> tm = XposedHelpers.findClass("android.telephony.TelephonyManager", null);

        if (imeiOn) {
            String fakeImei = confOf("spoof_imei", "imei", confOf("telephony", "imei", "860000000000001"));
            for (String m : new String[]{"getDeviceId", "getImei", "getMeid"}) {
                hookAll(tm, m, constHook(fakeImei));
            }
        }
        if (simOn || telOn) {
            String simSerial = confOf("spoof_sim", "sim_serial", confOf("telephony", "sim_serial", "8986000000000000001"));
            String imsi = confOf("telephony", "imsi", "460000000000001");
            hookAll(tm, "getSimSerialNumber", constHook(simSerial));
            hookAll(tm, "getSubscriberId", constHook(imsi));
            hookAll(tm, "getGroupIdLine1", constHook(imsi));
        }
        if (telOn) {
            String carrier = confOf("spoof_sim", "carrier", confOf("telephony", "operator", "CMCC"));
            String country = confOf("spoof_sim", "country", "cn");
            String line1 = confOf("telephony", "line1", "13800000000");
            hookAll(tm, "getSimOperatorName", constHook(carrier));
            hookAll(tm, "getNetworkOperatorName", constHook(carrier));
            hookAll(tm, "getSimOperator", constHook("46000"));
            hookAll(tm, "getNetworkOperator", constHook("46000"));
            hookAll(tm, "getSimCountryIso", constHook(country));
            hookAll(tm, "getNetworkCountryIso", constHook(country));
            hookAll(tm, "getLine1Number", constHook(line1));
        }
        if (on("block_cell_info")) {
            hookAll(tm, "getAllCellInfo", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    param.setResult(new ArrayList<>());
                }
            });
            hookAll(tm, "getCellLocation", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    param.setResult(null);
                }
            });
        }
    }

    /* ================= 蓝牙/WiFi MAC (spoof_bt_mac / spoof_wifi_mac) ================= */

    private void btWifiMacSpoof() {
        if (on("spoof_bt_mac")) {
            String mac = confOf("spoof_bt_mac", "bt_mac", "02:00:00:00:00:00");
            try {
                Class<?> ba = XposedHelpers.findClass("android.bluetooth.BluetoothAdapter", null);
                hookAll(ba, "getAddress", constHook(mac));
            } catch (Throwable ignored) {}
        }
        if (on("spoof_wifi_mac")) {
            String mac = confOf("spoof_wifi_mac", "wifi_mac", "02:00:00:00:00:00");
            try {
                Class<?> wi = XposedHelpers.findClass("android.net.wifi.WifiInfo", null);
                hookAll(wi, "getMacAddress", constHook(mac));
                hookAll(wi, "getBSSID", constHook(mac));
                hookAll(wi, "getSSID", constHook("<unknown ssid>"));
            } catch (Throwable ignored) {}
        }
    }

    /* ================= 电池伪装 (spoof_battery) ================= */

    private void batterySpoof() {
        if (!on("spoof_battery")) return;
        final long capacity = confLong("spoof_battery", "capacity", 5000);     // mAh
        final int health = (int) confLong("spoof_battery", "health", 100);     // %
        try {
            Class<?> bm = XposedHelpers.findClass("android.os.BatteryManager", null);
            hookAll(bm, "getIntProperty", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    long id = param.args != null && param.args.length > 0 && param.args[0] instanceof Integer
                            ? (Integer) param.args[0] : -1L;
                    if (id == BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER) {
                        param.setResult((int) (capacity * 1000));
                    } else if (id == BatteryManager.BATTERY_PROPERTY_CAPACITY) {
                        param.setResult(health);
                    } else if (id == BatteryManager.BATTERY_PROPERTY_STATUS) {
                        param.setResult(BatteryManager.BATTERY_STATUS_FULL);
                    } else {
                        param.setResult(-1);
                    }
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= 屏幕伪装 (spoof_screen) ================= */

    private void screenSpoof() {
        if (!on("spoof_screen")) return;
        String spec = confOf("spoof_screen", "size", "1080x2400x420");
        final int w, h, dpi;
        try {
            String[] p = spec.toLowerCase(Locale.US).split("x");
            w = Integer.parseInt(p[0].trim());
            h = Integer.parseInt(p[1].trim());
            dpi = p.length > 2 ? Integer.parseInt(p[2].trim()) : 420;
        } catch (Exception e) {
            return;
        }
        try {
            Class<?> disp = XposedHelpers.findClass("android.view.Display", null);
            XC_MethodHook hook = new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0 && param.args[0] instanceof DisplayMetrics) {
                        DisplayMetrics dm = (DisplayMetrics) param.args[0];
                        dm.widthPixels = w;
                        dm.heightPixels = h;
                        dm.densityDpi = dpi;
                        dm.density = dpi / 160f;
                        dm.xdpi = dpi;
                        dm.ydpi = dpi;
                    }
                }
            };
            hookAll(disp, "getMetrics", hook);
            hookAll(disp, "getRealMetrics", hook);
        } catch (Throwable ignored) {}
    }

    /* ================= 存储伪装 (spoof_storage) ================= */

    private void storageSpoof() {
        if (!on("spoof_storage")) return;
        final long total = confLong("spoof_storage", "total", 256) * 1024L * 1024L * 1024L;
        final long free = total * 37L / 100L;
        XC_MethodHook fh = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                String n = param.method.getName();
                Object r = param.getResult();
                if (r instanceof Long) {
                    if ("getTotalSpace".equals(n)) param.setResult(total);
                    else if ("getUsableSpace".equals(n) || "getFreeSpace".equals(n)) param.setResult(free);
                }
            }
        };
        hookAll(File.class, "getTotalSpace", fh);
        hookAll(File.class, "getUsableSpace", fh);
        hookAll(File.class, "getFreeSpace", fh);
        try {
            Class<?> st = XposedHelpers.findClass("android.os.StatFs", null);
            XC_MethodHook sh = new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    String n = param.method.getName();
                    Object r = param.getResult();
                    if (r instanceof Long) {
                        if (n.contains("Total")) param.setResult(total);
                        else if (n.contains("Free") || n.contains("Available")) param.setResult(free);
                        else if (n.contains("BlockSize")) param.setResult(4096L);
                    } else if (r instanceof Integer) {
                        int i = (Integer) r;
                        if (n.contains("BlockSize")) param.setResult(4096);
                        else if (n.contains("Count")) param.setResult((int) (total / 4096));
                        else if (n.contains("Free") || n.contains("Available")) param.setResult((int) (free / 4096));
                        else if (i == 0) param.setResult(0);
                    }
                }
            };
            for (String m : new String[]{"getTotalBytes", "getFreeBytes", "getAvailableBytes",
                    "getBlockSize", "getBlockSizeLong", "getBlockCount", "getBlockCountLong",
                    "getFreeBlocks", "getFreeBlocksLong", "getAvailableBlocks", "getAvailableBlocksLong"}) {
                hookAll(st, m, sh);
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 系统属性屏蔽 (fs_attrs) ================= */

    private void sysPropsHide() {
        if (!on("fs_attrs")) return;
        final Map<String, String> safe = new HashMap<>();
        safe.put("ro.debuggable", "0");
        safe.put("ro.secure", "1");
        safe.put("ro.build.type", "user");
        safe.put("ro.build.tags", "release-keys");
        safe.put("ro.build.selinux", "1");
        safe.put("ro.kernel.qemu", "0");
        for (String k : lines("fs_attrs")) {
            String t = k.trim();
            if (!t.isEmpty() && !safe.containsKey(t)) safe.put(t, t.startsWith("ro.") ? "" : "0");
        }
        try {
            Class<?> sp = XposedHelpers.findClass("android.os.SystemProperties", null);
            XC_MethodHook hook = new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0 && param.args[0] instanceof String) {
                        String k = (String) param.args[0];
                        String v = safe.get(k);
                        if (v != null) param.setResult(v);
                    }
                }
            };
            hookAll(sp, "get", hook);
        } catch (Throwable ignored) {}
    }

    /* ================= 系统服务隐藏 (syssvc_hide) ================= */

    private void sysSvcHide() {
        if (!on("syssvc_hide")) return;
        final Set<String> names = new HashSet<>();
        for (String s : lines("syssvc_hide")) {
            String t = s.trim();
            if (!t.isEmpty()) names.add(t);
        }
        if (names.isEmpty()) return;
        try {
            Class<?> ci = XposedHelpers.findClass("android.app.ContextImpl", null);
            XC_MethodHook hook = new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0 && param.args[0] instanceof String) {
                        if (names.contains((String) param.args[0])) param.setResult(null);
                    }
                }
            };
            hookAll(ci, "getSystemService", hook);
        } catch (Throwable ignored) {}
    }

    /* ================= 剪贴板 (clipboard / clipboard_isolate) ================= */

    private static ClipData SELF_CLIP;

    private void clipboardGuard() {
        boolean clipOn = on("clipboard");
        boolean isoOn = on("clipboard_isolate");
        if (!clipOn && !isoOn) return;
        final String mode = confOf("clipboard", "read", "block");
        final String fakeText = confOf("clipboard", "fake_text", "PrivacyGuard");
        final boolean fake = clipOn && "fake".equals(mode);
        final boolean block = clipOn && "block".equals(mode);
        Class<?> cm = XposedHelpers.findClass("android.content.ClipboardManager", null);
        if (clipOn) {
            hookAll(cm, "getPrimaryClip", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (block) param.setResult(null);
                    else if (fake) param.setResult(ClipData.newPlainText(null, fakeText));
                }
            });
            hookAll(cm, "hasPrimaryClip", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (block) param.setResult(false);
                    else if (fake) param.setResult(true);
                }
            });
        }
        if (isoOn) {
            // 每个应用进程只能读到自己写过的内容 —— 进程隔离即应用隔离
            hookAll(cm, "setPrimaryClip", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args != null && param.args.length > 1 && param.args[1] instanceof ClipData) {
                        SELF_CLIP = (ClipData) param.args[1];
                    }
                }
            });
            hookAll(cm, "getPrimaryClip", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(SELF_CLIP);
                }
            });
            hookAll(cm, "hasPrimaryClip", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(SELF_CLIP != null);
                }
            });
        }
    }

    /* ================= 应用列表 (app_list) ================= */

    private void appListHide(XC_LoadPackage.LoadPackageParam lpp) {
        if (!on("app_list")) return;
        final String mode = confOf("app_list", "mode", "custom");
        final Set<String> hide = csv(confOf("app_list", "hide", ""));
        final Set<String> keep = csv(confOf("app_list", "keep", ""));
        XC_MethodHook filter = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                Object res = param.getResult();
                if (!(res instanceof List)) return;
                List<?> in = (List<?>) res;
                List<Object> out = new ArrayList<>();
                for (Object o : in) {
                    String pn = null;
                    if (o instanceof PackageInfo) pn = ((PackageInfo) o).packageName;
                    else if (o instanceof ApplicationInfo) pn = ((ApplicationInfo) o).packageName;
                    if (pn == null) {
                        out.add(o);
                        continue;
                    }
                    boolean pass;
                    if ("empty".equals(mode)) {
                        pass = pn.equals(pkg) || pn.equals("android");
                    } else if ("allowlist".equals(mode)) {
                        pass = pn.equals(pkg) || keep.contains(pn);
                    } else { // custom
                        pass = !hide.contains(pn);
                    }
                    if (pass) out.add(o);
                }
                param.setResult(out);
            }
        };
        try {
            Class<?> pm = XposedHelpers.findClass("android.app.ApplicationPackageManager", lpp.classLoader);
            for (String m : new String[]{"getInstalledPackages", "getInstalledApplications"}) {
                hookAll(pm, m, filter);
            }
            if ("custom".equals(mode) && !hide.isEmpty()) {
                for (String m : new String[]{"getPackageInfo", "getApplicationInfo"}) {
                    hookAll(pm, m, new SafeHook() {
                        @Override
                        protected void onBefore(MethodHookParam param) throws Throwable {
                            if (param.args != null && param.args.length > 0 && param.args[0] instanceof String) {
                                if (hide.contains((String) param.args[0])) {
                                    param.setThrowable(new PackageManager.NameNotFoundException(
                                            (String) param.args[0]));
                                }
                            }
                        }
                    });
                }
            }
        } catch (Throwable ignored) {}
    }

    private Set<String> csv(String s) {
        Set<String> out = new HashSet<>();
        if (s != null) {
            for (String p : s.split(",")) {
                String t = p.trim();
                if (!t.isEmpty()) out.add(t);
            }
        }
        return out;
    }

    /* ================= Intent 查询 (block_pm_query) ================= */

    private void pmQueryHide(XC_LoadPackage.LoadPackageParam lpp) {
        if (!on("block_pm_query")) return;
        XC_MethodHook empty = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(new ArrayList<>());
            }
        };
        try {
            Class<?> pm = XposedHelpers.findClass("android.app.ApplicationPackageManager", lpp.classLoader);
            for (String m : new String[]{"queryIntentActivities", "queryIntentActivityOptions",
                    "queryIntentServices", "queryIntentReceivers", "queryContentProviders",
                    "getPreferredPackages"}) {
                hookAll(pm, m, empty);
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 进程列表 (block_process_list) ================= */

    private void procListHide() {
        // k_task（内核任务列表的免编译路线：应用可见的进程枚举全部走
        // ActivityManager binder 接口，Java 层拦截即等价于“隐藏其他任务”）
        boolean taskHide = on("k_task");
        if (!on("block_process_list") && !taskHide) return;
        XC_MethodHook empty = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(new ArrayList<>());
            }
        };
        try {
            Class<?> am = XposedHelpers.findClass("android.app.ActivityManager", null);
            for (String m : new String[]{"getRunningAppProcesses", "getRunningServices", "getRunningTasks",
                    "getRecentTasks"}) {
                hookAll(am, m, empty);
            }
        } catch (Throwable ignored) {}
        if (!taskHide) return;
        // /proc/<pid> 遍历遮蔽：应用读 /proc 枚举进程的兜底路径（读取他人 /proc/pid
        // 仍受 SELinux 约束，这里把常见目录列表拦截掉）
        try {
            File procDir = new File("/proc");
            for (Method m : File.class.getDeclaredMethods()) {
                if (!m.getName().equals("listFiles")) continue;
                XposedBridge.hookMethod(m, new SafeHook() {
                    @Override
                    protected void onAfter(MethodHookParam param) {
                        Object r = param.getResult();
                        if (!(r instanceof File[])) return;
                        File self = new File("/proc/" + android.os.Process.myPid());
                        ArrayList<File> keep = new ArrayList<>();
                        for (File f : (File[]) r) {
                            String n = f.getName();
                            if (n.matches("\\d+") && !f.equals(self)) continue; // 数字 pid 隐藏他人
                            keep.add(f);
                        }
                        param.setResult(keep.toArray(new File[0]));
                    }
                });
                break; // 只 hook 第一个同名重载（参数为空的那个语义相同）
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 媒体库 (block_mediastore) ================= */

    private void mediastoreHide() {
        if (!on("block_mediastore")) return;
        try {
            Class<?> cr = XposedHelpers.findClass("android.content.ContentResolver", null);
            hookAll(cr, "query", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args == null || param.args.length == 0) return;
                    Object u = param.args[0];
                    if (u == null || !u.toString().startsWith("content://media")) return;
                    String[] proj = param.args.length > 1 && param.args[1] instanceof String[]
                            ? (String[]) param.args[1] : new String[]{"_id"};
                    param.setResult(new MatrixCursor(proj));
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= 网卡枚举 (block_net_ifaces) ================= */

    private void netIfacesHide() {
        if (!on("block_net_ifaces")) return;
        try {
            Class<?> ni = XposedHelpers.findClass("java.net.NetworkInterface", null);
            XC_MethodHook empty = new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(Collections.emptyEnumeration());
                }
            };
            hookAll(ni, "getNetworkInterfaces", empty);
            hookAll(ni, "getNetworkInterfacesList", empty);
            hookAll(ni, "getInterfaceNames", empty);
        } catch (Throwable ignored) {}
    }

    /* ================= 流量统计 (block_netstats) ================= */

    private void netStatsHide() {
        if (!on("block_netstats")) return;
        XC_MethodHook zero = new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) {
                param.setResult(0L);
            }
        };
        for (String m : new String[]{"getUidTxBytes", "getUidRxBytes", "getTotalTxBytes", "getTotalRxBytes",
                "getMobileTxBytes", "getMobileRxBytes", "getUidTcpTxBytes", "getUidTcpRxBytes",
                "getUidUdpTxBytes", "getUidUdpRxBytes"}) {
            hookAll(TrafficStats.class, m, zero);
        }
    }

    /* ================= 隐藏 VPN/节点 (vpn_hide) =================
     * 目标：应用/检测方完全看不到代理痕迹，其观测到的"本机网络"就是节点出口所在网络。
     * 覆盖以下主流 VPN/代理检测手段：
     *   1) 网卡枚举出现 tun/ppp/ipsec（NetworkInterface）
     *   2) ConnectivityManager TRANSPORT_VPN + NetworkCapabilities NET_CAPABILITY_NOT_VPN
     *   3) VpnService 包名枚举 / 已建立 VPN 的应用列表
     *   4) /proc/net/tcp、/proc/net/udp 中出现代理客户端本地监听端口（7890/1080/...）
     *   5) /proc/net/route 默认路由指向 tun0
     *   6) PackageManager 已安装代理客户端包名枚举
     *   7) SystemProperties http.proxyHost 等代理属性
     *   8) TrafficStats per-uid 流量计数暴露代理 UID
     * shell 侧(apply.sh vpn_hide)负责 DNS 全劫持 + QUIC/STUN/痕迹端口封锁 + TCP 指纹规范化，
     * 两侧协同后对端看到的 IP 即节点出口 IP，与"我就在节点所在地"一致。
     */
    private void vpnHide(XC_LoadPackage.LoadPackageParam lpp) {
        if (!on("vpn_hide")) return;
        // 本模块自身与 root 管理器不 hook（保持 WebUI 状态显示可用）
        if ("de.privacyguard.hook".equals(pkg)) return;

        /* (1) 网卡枚举：过滤 tun/ppp/ipsec/vpn 虚拟网卡，只保留物理网卡
         *     netIfacesHide 是"全空枚举"(block_net_ifaces 全关场景)，
         *     这里做"只去虚拟网卡"的精滤，两个开关可独立生效。 */
        try {
            Class<?> ni = XposedHelpers.findClass("java.net.NetworkInterface", null);
            XC_MethodHook stripVpnIf = new SafeHook() {
                @Override
                @SuppressWarnings("unchecked")
                protected void onAfter(MethodHookParam param) {
                    Object res = param.getResult();
                    if (!(res instanceof java.util.Enumeration)) return;
                    java.util.List<Object> keep = new ArrayList<>();
                    java.util.Enumeration<Object> en = (java.util.Enumeration<Object>) res;
                    while (en.hasMoreElements()) {
                        Object o = en.nextElement();
                        String nm = null;
                        try {
                            java.lang.reflect.Method gn = o.getClass().getMethod("getName");
                            nm = String.valueOf(gn.invoke(o));
                        } catch (Throwable ignored) {}
                        if (nm != null && isVpnIface(nm)) continue;
                        keep.add(o);
                    }
                    param.setResult(Collections.enumeration(keep));
                }
            };
            hookAll(ni, "getNetworkInterfaces", stripVpnIf);
            hookAll(ni, "getNetworkInterfacesList", stripVpnIf);
        } catch (Throwable ignored) {}

        /* (2) ConnectivityManager / NetworkCapabilities：隐藏 TRANSPORT_VPN */
        try {
            Class<?> nc = XposedHelpers.findClass("android.net.NetworkCapabilities", null);
            hookAll(nc, "hasTransport", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    // NetworkCapabilities.TRANSPORT_VPN == 4
                    if (param.args.length > 0 && (param.args[0] instanceof Integer)
                            && ((Integer) param.args[0]) == 4) {
                        param.setResult(false);
                    }
                }
            });
            hookAll(nc, "hasCapability", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    // NET_CAPABILITY_NOT_VPN == 15：VPN 网络此能力为 false
                    if (param.args.length > 0 && (param.args[0] instanceof Integer)
                            && ((Integer) param.args[0]) == 15) {
                        param.setResult(true);
                    }
                }
            });
            // toString 里含 "VPN" 字样（日志/异常堆栈会泄露代理痕迹）
            hookAll(nc, "toString", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    String s = String.valueOf(param.getResult());
                    if (s.contains("VPN")) {
                        param.setResult(s.replace("VPN", "WIFI").replace("vpn", "wifi"));
                    }
                }
            });
        } catch (Throwable ignored) {}
        try {
            Class<?> cm = XposedHelpers.findClass("android.net.ConnectivityManager", lpp.classLoader);
            // getActiveNetwork/getActiveNetworkInfo 的 VPN 网络改写为 WIFI 传输类型
            hookAll(cm, "getNetworkCapabilities", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    Object caps = param.getResult();
                    if (caps == null) return;
                    try {
                        XposedHelpers.callMethod(caps, "setTransportType", 1); // TRANSPORT_WIFI
                    } catch (Throwable ignored) {}
                }
            });
        } catch (Throwable ignored) {}

        /* (3) VpnService 痕迹：枚举已配置 VPN 的应用（PackageManager 查询 prepare 结果） */
        try {
            Class<?> vs = XposedHelpers.findClass("android.net.VpnService", lpp.classLoader);
            hookAll(vs, "prepare", constHook(null));
        } catch (Throwable ignored) {}

        /* (4) /proc/net/tcp|udp 读取过滤：代理客户端本地监听端口不出现 */
        try {
            Class<?> fis = XposedHelpers.findClass("java.io.FileInputStream", null);
            XposedHelpers.findAndHookConstructor(fis, String.class, new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    String path = String.valueOf(param.args[0]);
                    if (!path.equals("/proc/net/tcp") && !path.equals("/proc/net/udp")
                            && !path.equals("/proc/net/tcp6") && !path.equals("/proc/net/udp6")) return;
                    if (hideProcFilter == null) hideProcFilter = buildHideProcFilter();
                    try {
                        java.io.InputStream in = (java.io.InputStream) param.thisObject;
                        String txt = readAll(in);
                        if (!txt.isEmpty()) {
                            param.setResult(new java.io.ByteArrayInputStream(
                                    hideProcFilter.matcher(txt).replaceAll("").getBytes("UTF-8")));
                        }
                    } catch (Throwable ignored) {}
                }
            });
        } catch (Throwable ignored) {}

        /* (5) 默认路由/接口名痕迹：/proc/net/route 里默认路由指向 tun0 即暴露代理 */
        try {
            Class<?> fis2 = XposedHelpers.findClass("java.io.FileInputStream", null);
            XposedHelpers.findAndHookConstructor(fis2, String.class, new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    String path = String.valueOf(param.args[0]);
                    if (!path.equals("/proc/net/route") && !path.equals("/proc/net/ipv6_route")) return;
                    try {
                        java.io.InputStream in = (java.io.InputStream) param.thisObject;
                        String txt = readAll(in);
                        if (!txt.isEmpty()) {
                            // 路由行含 tun/ppp/ipsec/wg 等虚拟网卡名则整行删除。
                            // 注意: /proc/net/route 网卡在第1列, /proc/net/ipv6_route 在末列,
                            // 因此扫描整行所有字段, 不能只看 f[0]（否则 IPv6 路由表漏隐藏）。
                            StringBuilder out = new StringBuilder();
                            for (String line : txt.split("\n")) {
                                String trim = line.trim();
                                if (trim.isEmpty()) { out.append(line).append('\n'); continue; }
                                boolean drop = false;
                                for (String f : trim.split("\\s+")) {
                                    if (isVpnIface(f)) { drop = true; break; }
                                }
                                if (drop) continue;
                                out.append(line).append('\n');
                            }
                            param.setResult(new java.io.ByteArrayInputStream(out.toString().getBytes("UTF-8")));
                        }
                    } catch (Throwable ignored) {}
                }
            });
        } catch (Throwable ignored) {}

        /* (6) 已安装 VPN 代理 App 枚举：PackageManager 查询时过滤已知代理客户端包名 */
        try {
            Class<?> pm = XposedHelpers.findClass("android.content.pm.PackageManager", lpp.classLoader);
            hookAll(pm, "getInstalledPackages", new SafeHook() {
                @Override
                @SuppressWarnings("unchecked")
                protected void onAfter(MethodHookParam param) {
                    Object res = param.getResult();
                    if (!(res instanceof List)) return;
                    List<Object> keep = new ArrayList<>();
                    for (Object pi : (List<Object>) res) {
                        String pn = null;
                        try {
                            java.lang.reflect.Field f = pi.getClass().getField("packageName");
                            pn = String.valueOf(f.get(pi));
                        } catch (Throwable ignored) {}
                        if (pn != null && isProxyApp(pn)) continue;
                        keep.add(pi);
                    }
                    param.setResult(keep);
                }
            });
            hookAll(pm, "getInstalledApplications", new SafeHook() {
                @Override
                @SuppressWarnings("unchecked")
                protected void onAfter(MethodHookParam param) {
                    Object res = param.getResult();
                    if (!(res instanceof List)) return;
                    List<Object> keep = new ArrayList<>();
                    for (Object ai : (List<Object>) res) {
                        String pn = null;
                        try {
                            java.lang.reflect.Field f = ai.getClass().getField("packageName");
                            pn = String.valueOf(f.get(ai));
                        } catch (Throwable ignored) {}
                        if (pn != null && isProxyApp(pn)) continue;
                        keep.add(ai);
                    }
                    param.setResult(keep);
                }
            });
        } catch (Throwable ignored) {}

        /* (7) 系统属性代理痕迹：http.proxyHost/system 属性里的代理配置 */
        try {
            Class<?> sp = XposedHelpers.findClass("android.os.SystemProperties", null);
            hookAll(sp, "get", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    String key = String.valueOf(param.args[0]);
                    if (key.equals("http.proxyHost") || key.equals("https.proxyHost")) {
                        param.setResult("");
                    }
                }
            });
        } catch (Throwable ignored) {}

        /* (8) TrafficStats per-uid 流量统计：代理客户端 UID 的流量计数归零 */
        try {
            Class<?> ts = XposedHelpers.findClass("android.net.TrafficStats", null);
            hookAll(ts, "getUidRxBytes", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args.length > 0 && (param.args[0] instanceof Integer)
                            && ((Integer) param.args[0]) >= 10000) {
                        param.setResult(0L);
                    }
                }
            });
            hookAll(ts, "getUidTxBytes", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args.length > 0 && (param.args[0] instanceof Integer)
                            && ((Integer) param.args[0]) >= 10000) {
                        param.setResult(0L);
                    }
                }
            });
        } catch (Throwable ignored) {}
    }

    /** 已知代理客户端包名判定（用于 PackageManager 枚举过滤） */    private static boolean isProxyApp(String pn) {
        String p = pn.toLowerCase(Locale.US);
        return p.contains("clash") || p.contains("mihomo") || p.contains("v2ray")
                || p.contains("xray") || p.contains("singbox") || p.contains("sing-box")
                || p.contains("shadowsocks") || p.contains("surfboard") || p.contains("surge")
                || p.contains("trojan") || p.contains("hysteria") || p.contains("naiveproxy")
                || p.contains("nekoray") || p.contains("v2rayng") || p.contains("ssr");
    }

    /** tun/ppp/ipsec/虚拟 VPN 网卡名判定 */
    private static boolean isVpnIface(String nm) {
        String n = nm.toLowerCase(Locale.US);
        return n.startsWith("tun") || n.startsWith("ppp") || n.startsWith("ipsec")
                || n.startsWith("vpn") || n.startsWith("wg") || n.startsWith("tap");
    }

    /** /proc/net/tcp|udp 行过滤正则：命中代理客户端本地监听端口的行整行删除（懒加载） */
    private java.util.regex.Pattern hideProcFilter = null;

    /** 从 [conf:vpn] local_port 与常见代理端口集合生成 /proc/net 过滤正则（端口十六进制大写, 补足4位） */
    private java.util.regex.Pattern buildHideProcFilter() {
        Set<String> ports = new HashSet<>(Arrays.asList(
                "7890", "7891", "7892", "7893", "7894", "7897", "7898",   // clash/mihomo
                "1080", "1081", "1085", "1086", "1090",                    // socks5
                "8080", "8081", "8082", "8087", "8888",                    // http proxy
                "9090", "9091", "9150", "9151",                           // v2ray/xray
                "3128", "20171", "2080", "2081"));                          // squid/surge
        // [conf:vpn] local_port 必须透传给 hook 才能命中用户自定义端口
        for (String s : lines("vpn")) {
            String t = s.trim();
            if (t.startsWith("local_port=")) {
                String v = t.substring(11).trim();
                int i = v.lastIndexOf(':');
                if (i >= 0 && i + 1 < v.length()) v = v.substring(i + 1);
                if (!v.isEmpty()) ports.add(v);
            }
        }
        StringBuilder sb = new StringBuilder("(?m)^.*:(");
        boolean first = true;
        for (String p : ports) {
            int port;
            try { port = Integer.parseInt(p); } catch (Exception e) { continue; }
            if (port <= 0 || port > 65535) continue;
            if (first) first = false; else sb.append('|');
            sb.append(String.format("%04X", port));
        }
        sb.append(") .*$");
        try {
            return java.util.regex.Pattern.compile(sb.toString());
        } catch (Throwable t) {
            return java.util.regex.Pattern.compile("(?m)^.*:(1ED0|0438|2382) .*$");
        }
    }

    /* ================= 广告 ID 统一 (ad_id_unify) ================= */

    private void adIdUnify(XC_LoadPackage.LoadPackageParam lpp) {
        if (!on("ad_id_unify")) return;
        final String fake = hashHex(pkg + "|adid", 8) + "-" + hashHex(pkg + "|adid2", 4).substring(0, 4)
                + "-" + hashHex(pkg + "|adid3", 4).substring(0, 4)
                + "-" + hashHex(pkg + "|adid4", 4).substring(0, 4)
                + "-" + hashHex(pkg + "|adid5", 12);
        try {
            Class<?> info = XposedHelpers.findClass(
                    "com.google.android.gms.ads.identifier.AdvertisingIdClient$Info", lpp.classLoader);
            hookAll(info, "getId", constHook(fake));
        } catch (Throwable ignored) {}
        try {
            // 华为 OAID
            Class<?> oid = XposedHelpers.findClass("com.huawei.hms.ads.identifier.AdvertisingIdClient", lpp.classLoader);
            for (String m : new String[]{"getAdvertisingId", "getOaid"}) {
                hookAll(oid, m, constHook(fake));
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 输入法隐藏 (block_ime_logging) ================= */

    private void imeHide() {
        if (!on("block_ime_logging")) return;
        XC_MethodHook empty = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(new ArrayList<>());
            }
        };
        try {
            Class<?> imm = XposedHelpers.findClass("android.view.inputmethod.InputMethodManager", null);
            hookAll(imm, "getEnabledInputMethodList", empty);
            hookAll(imm, "getInputMethodList", empty);
            hookAll(imm, "getEnabledInputMethodSubtypeList", empty);
        } catch (Throwable ignored) {}
    }

    /* ================= 定位伪装 (mock_location / perapp_mock / gps_accuracy) ================= */

    private Location fakeLocation() {
        double lat = 39.9042, lon = 116.4074;
        float acc = 35f;
        // 单应用坐标优先于全局坐标；perapp_mock 可独立开启（无全局开关时仍生效）
        boolean anyMock = on("mock_location") || on("perapp_mock");
        if (!anyMock) return null;
        for (String l : lines("perapp_mock")) {
            int i = l.indexOf('=');
            if (i <= 0) continue;
            if (!pkg.equals(l.substring(0, i).trim())) continue;
            String[] p = l.substring(i + 1).split(",");
            try {
                lat = Double.parseDouble(p[0].trim());
                lon = Double.parseDouble(p[1].trim());
            } catch (Exception ignored) {}
            break;
        }
        if (on("mock_location")) {
            // 全局坐标作兜底（未被 perapp 覆盖时）
            lat = confDbl("mock_location", "lat", lat);
            lon = confDbl("mock_location", "lng", lon);
            acc = (float) confDbl("mock_location", "acc", acc);
        }
        if (on("gps_accuracy")) acc = (float) confDbl("gps_accuracy", "accuracy", 50);
        Location loc = new Location("gps");
        loc.setLatitude(lat);
        loc.setLongitude(lon);
        loc.setAccuracy(acc);
        loc.setTime(System.currentTimeMillis());
        loc.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
        return loc;
    }

    @SuppressWarnings("unchecked")
    private void locationMock() {
        if (!on("mock_location") && !on("perapp_mock")) return;
        final Location fake = fakeLocation();
        if (fake == null) return;
        Class<?> lm = XposedHelpers.findClass("android.location.LocationManager", null);
        hookAll(lm, "getLastKnownLocation", new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(fake);
            }
        });
        // getCurrentLocation: 直接向 Consumer 回调假位置
        hookAll(lm, "getCurrentLocation", new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) {
                if (param.args == null) return;
                for (Object a : param.args) {
                    if (a instanceof java.util.function.Consumer) {
                        try {
                            ((java.util.function.Consumer<Object>) a).accept(fake);
                        } catch (Throwable ignored) {}
                        break;
                    }
                }
                param.setResult(null);
            }
        });
        // requestLocationUpdates: 注册后立即投递一次假位置
        hookAll(lm, "requestLocationUpdates", new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                if (param.args == null) return;
                for (Object a : param.args) {
                    if (a instanceof LocationListener) {
                        try {
                            ((LocationListener) a).onLocationChanged(fake);
                        } catch (Throwable ignored) {}
                        break;
                    }
                }
            }
        });
        try {
            Class<?> lc = XposedHelpers.findClass("android.location.Location", null);
            // isFromMockProvider: API<35; isMock: API 35+ 取代者 —— 两个都 hook,
            // hookAll 按名匹配, 旧版无 isMock 方法时静默跳过, 天然向下兼容
            hookAll(lc, "isFromMockProvider", constHook(false));
            hookAll(lc, "isMock", constHook(false));
        } catch (Throwable ignored) {}
    }

    /* ================= GNSS 伪装 (gnss_spoof) ================= */

    private void gnssSpoof() {
        if (!on("gnss_spoof")) return;
        try {
            Class<?> lm = XposedHelpers.findClass("android.location.LocationManager", null);
            for (String m : new String[]{"registerGnssMeasurementsCallback",
                    "registerGnssNavigationMessageCallback", "registerGnssStatusCallback"}) {
                hookAll(lm, m, new SafeHook() {
                    @Override
                    protected void onBefore(MethodHookParam param) {
                        param.setResult(false);
                    }
                });
            }
            for (String m : new String[]{"getGnssHardwareModelName", "getGnssYearOfHardware", "getGnssBatchSize"}) {
                hookAll(lm, m, new SafeHook() {
                    @Override
                    protected void onBefore(MethodHookParam param) {
                        String n = param.method.getName();
                        if (n.endsWith("ModelName")) param.setResult("");
                        else if (n.endsWith("YearOfHardware")) param.setResult(2016);
                        else param.setResult(1);
                    }
                });
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 被动定位 (disable_passive_loc) ================= */

    private void passiveLocHide() {
        if (!on("disable_passive_loc")) return;
        try {
            Class<?> lm = XposedHelpers.findClass("android.location.LocationManager", null);
            XC_MethodHook strip = new SafeHook() {
                @Override
                @SuppressWarnings("unchecked")
                protected void onAfter(MethodHookParam param) {
                    Object r = param.getResult();
                    if (r instanceof List) {
                        List<Object> out = new ArrayList<>();
                        for (Object o : (List<Object>) r) {
                            if (!"passive".equals(String.valueOf(o))) out.add(o);
                        }
                        param.setResult(out);
                    }
                }
            };
            hookAll(lm, "getAllProviders", strip);
            hookAll(lm, "getProviders", strip);
            hookAll(lm, "getProvider", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0
                            && "passive".equals(param.args[0])) {
                        param.setResult(null);
                    }
                }
            });
            hookAll(lm, "getBestProvider", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if ("passive".equals(param.getResult())) param.setResult("gps");
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= WiFi 扫描 (block_wifi_scan) ================= */

    private void wifiScanHide() {
        if (!on("block_wifi_scan")) return;
        try {
            Class<?> wm = XposedHelpers.findClass("android.net.wifi.WifiManager", null);
            hookAll(wm, "getScanResults", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(new ArrayList<>());
                }
            });
            hookAll(wm, "startScan", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    param.setResult(false);
                }
            });
            hookAll(wm, "isScanAlwaysAvailable", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    param.setResult(false);
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= 传感器 (sensor_* / sensor_rate_limit) ================= */

    private void sensorHide() {
        boolean any = on("sensor_accel") || on("sensor_gyro") || on("sensor_light")
                || on("sensor_magnet") || on("sensor_pressure") || on("sensor_prox");
        if (any) {
            // 开关 → Sensor 类型常量
            List<Integer> types = new ArrayList<>();
            if (on("sensor_accel")) types.add(Sensor.TYPE_ACCELEROMETER);
            if (on("sensor_magnet")) types.add(Sensor.TYPE_MAGNETIC_FIELD);
            if (on("sensor_gyro")) types.add(Sensor.TYPE_GYROSCOPE);
            if (on("sensor_light")) types.add(Sensor.TYPE_LIGHT);
            if (on("sensor_pressure")) types.add(Sensor.TYPE_PRESSURE);
            if (on("sensor_prox")) types.add(Sensor.TYPE_PROXIMITY);
            XC_MethodHook listHook = new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0 && param.args[0] instanceof Integer) {
                        if (types.contains((Integer) param.args[0])) param.setResult(new ArrayList<>());
                    }
                }
            };
            hookAll(SensorManager.class, "getSensorList", listHook);
            hookAll(SensorManager.class, "getDefaultSensor", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    if (param.args != null && param.args.length > 0 && param.args[0] instanceof Integer) {
                        if (types.contains((Integer) param.args[0])) param.setResult(null);
                    }
                }
            });
        }
        if (on("sensor_rate_limit")) {
            // 采样率钳制到 10Hz 以下
            hookAll(SensorManager.class, "registerListener", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args != null && param.args.length >= 3
                            && param.args[1] instanceof Sensor && param.args[2] instanceof Integer) {
                        int rate = (Integer) param.args[2];
                        if (rate < 100000) param.args[2] = 100000;
                    }
                }
            });
        }
    }

    /* ================= 相机 (cam_null / cam_hw_hide) ================= */

    private void cameraNull() {
        boolean deny = on("cam_null");
        boolean hw = on("cam_hw_hide");
        if (!deny && !hw) return;
        try {
            Class<?> cm = XposedHelpers.findClass("android.hardware.camera2.CameraManager", null);
            if (hw) {
                hookAll(cm, "getCameraIdList", new SafeHook() {
                    @Override
                    protected void onAfter(MethodHookParam param) {
                        param.setResult(new String[0]);
                    }
                });
            }
            if (!deny) return;
            // mode=black/noise 当前与 error 等效（拦截打开），见 README
            Object disabled = null;
            try {
                Class<?> exc = XposedHelpers.findClass("android.hardware.camera2.CameraAccessException", null);
                disabled = XposedHelpers.newInstance(exc, 0x0000000D /* CAMERA_DISABLED */, "disabled by PrivacyGuard");
            } catch (Throwable ignored) {}
            if (disabled == null) disabled = new SecurityException("Camera disabled by PrivacyGuard");
            final Throwable t = (Throwable) disabled;
            Class<?> cb = XposedHelpers.findClass(
                    "android.hardware.camera2.CameraDevice$StateCallback", null);
            for (Method m : cm.getDeclaredMethods()) {
                if (!m.getName().equals("openCamera")) continue;
                Class<?>[] pt = m.getParameterTypes();
                boolean hasCb = false;
                for (Class<?> p : pt) {
                    if (p != null && cb.isAssignableFrom(p)) { hasCb = true; break; }
                }
                if (!hasCb) continue;
                XposedBridge.hookMethod(m, new SafeHook() {
                    @Override
                    protected void onBefore(MethodHookParam param) {
                        param.setThrowable(t);
                    }
                });
            }
        } catch (Throwable ignored) {}
    }

    /* ================= 麦克风 (mic_block / mic_hw_hide) ================= */

    private void micBlock() {
        boolean block = on("mic_block");
        boolean hw = on("mic_hw_hide");
        if (!block && !hw) return;
        if (hw) {
            try {
                Class<?> am = XposedHelpers.findClass("android.media.AudioManager", null);
                hookAll(am, "getMicrophones", new SafeHook() {
                    @Override
                    protected void onAfter(MethodHookParam param) {
                        param.setResult(new ArrayList<>());
                    }
                });
            } catch (Throwable ignored) {}
        }
        if (!block) return;
        final String mode = confOf("mic_block", "mode", "silence");
        if ("error".equals(mode)) {
            hookAll(AudioRecord.class, "startRecording", new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    param.setResult(AudioRecord.ERROR_BAD_VALUE);
                }
            });
            return;
        }
        // silence / noise: 允许录音，但清除/扰动采样数据
        final boolean noise = "noise".equals(mode);
        hookAll(AudioRecord.class, "read", new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                Object r = param.getResult();
                if (!(r instanceof Integer) || (Integer) r <= 0) return;
                if (param.args == null || param.args.length == 0) return;
                Object buf = param.args[0];
                if (buf instanceof byte[]) {
                    byte[] b = (byte[]) buf;
                    int n = Math.min(b.length, (Integer) r);
                    for (int i = 0; i < n; i++) b[i] = noise ? (byte) RNG.nextInt(7) : 0;
                } else if (buf instanceof short[]) {
                    short[] s = (short[]) buf;
                    int n = Math.min(s.length, (Integer) r);
                    for (int i = 0; i < n; i++) s[i] = noise ? (short) RNG.nextInt(90) : 0;
                } else if (buf instanceof float[]) {
                    float[] f = (float[]) buf;
                    int n = Math.min(f.length, (Integer) r);
                    for (int i = 0; i < n; i++) f[i] = noise ? (RNG.nextFloat() - 0.5f) * 0.01f : 0f;
                }
            }
        });
    }

    /* ================= 音频指纹 (audio_fp_block) ================= */

    private void audioFpBlock() {
        if (!on("audio_fp_block")) return;
        // 若麦克风已处于静音模式，数据已清零，无需再扰动
        if (on("mic_block") && "silence".equals(confOf("mic_block", "mode", "silence"))) return;
        hookAll(AudioRecord.class, "read", new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                Object r = param.getResult();
                if (!(r instanceof Integer) || (Integer) r <= 0) return;
                if (param.args == null || param.args.length == 0) return;
                Object buf = param.args[0];
                if (buf instanceof byte[]) {
                    byte[] b = (byte[]) buf;
                    int n = Math.min(b.length, (Integer) r);
                    for (int i = 0; i < n; i++) b[i] = (byte) (b[i] + RNG.nextInt(3) - 1);
                } else if (buf instanceof short[]) {
                    short[] s = (short[]) buf;
                    int n = Math.min(s.length, (Integer) r);
                    for (int i = 0; i < n; i++) s[i] = (short) (s[i] + RNG.nextInt(60) - 30);
                } else if (buf instanceof float[]) {
                    float[] f = (float[]) buf;
                    int n = Math.min(f.length, (Integer) r);
                    for (int i = 0; i < n; i++) f[i] = f[i] + (RNG.nextFloat() - 0.5f) * 0.004f;
                }
            }
        });
    }

    /* ================= 生物识别硬件 (hide_fingerprint_hw / hide_face_hw) ================= */

    private void bioHide(XC_LoadPackage.LoadPackageParam lpp) {
        if (on("hide_fingerprint_hw")) {
            try {
                Class<?> fm = XposedHelpers.findClass("android.hardware.fingerprint.FingerprintManager", null);
                hookAll(fm, "isHardwareDetected", constHook(false));
                hookAll(fm, "hasEnrolledFingerprints", constHook(false));
            } catch (Throwable ignored) {}
            try {
                Class<?> compat = XposedHelpers.findClass(
                        "androidx.core.hardware.fingerprint.FingerprintManagerCompat", lpp.classLoader);
                hookAll(compat, "isHardwareDetected", constHook(false));
                hookAll(compat, "hasEnrolledFingerprints", constHook(false));
            } catch (Throwable ignored) {}
        }
        if (on("hide_face_hw")) {
            try {
                Class<?> fcm = XposedHelpers.findClass("android.hardware.face.FaceManager", null);
                hookAll(fcm, "isHardwareDetected", constHook(false));
                hookAll(fcm, "hasEnrolledFaces", constHook(false));
            } catch (Throwable ignored) {}
        }
        if (on("hide_fingerprint_hw") || on("hide_face_hw")) {
            try {
                Class<?> bmm = XposedHelpers.findClass("android.hardware.biometrics.BiometricManager", null);
                hookAll(bmm, "canAuthenticate", constHook(
                        12 /* BIOMETRIC_ERROR_NO_HARDWARE */));
            } catch (Throwable ignored) {}
        }
    }

    /* ================= 通知 (block_notif_listen / hide_notif_perm) ================= */

    private void notifHide() {
        if (!on("block_notif_listen")) return;
        XC_MethodHook empty = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(new ArrayList<>());
            }
        };
        try {
            Class<?> nm = XposedHelpers.findClass("android.app.NotificationManager", null);
            hookAll(nm, "getActiveNotifications", empty);
        } catch (Throwable ignored) {}
        try {
            Class<?> nls = XposedHelpers.findClass("android.service.notification.NotificationListenerService", null);
            hookAll(nls, "getActiveNotifications", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(new android.service.notification.StatusBarNotification[0]);
                }
            });
        } catch (Throwable ignored) {}
    }

    private void notifPermHide() {
        if (!on("hide_notif_perm")) return;
        try {
            Class<?> nm = XposedHelpers.findClass("android.app.NotificationManager", null);
            hookAll(nm, "areNotificationsEnabled", constHook(false));
        } catch (Throwable ignored) {}
    }

    /* ================= 使用统计 (usagestats_off) ================= */

    private void usageHide() {
        if (!on("usagestats_off")) return;
        try {
            Class<?> usm = XposedHelpers.findClass("android.app.usage.UsageStatsManager", null);
            hookAll(usm, "queryUsageStats", new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    param.setResult(new ArrayList<>());
                }
            });
        } catch (Throwable ignored) {}
    }

    /* ================= 无障碍 (a11y_hide) ================= */

    private void a11yHide() {
        if (!on("a11y_hide")) return;
        XC_MethodHook empty = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                param.setResult(new ArrayList<>());
            }
        };
        try {
            Class<?> am = XposedHelpers.findClass("android.view.accessibility.AccessibilityManager", null);
            hookAll(am, "getEnabledAccessibilityServiceList", empty);
            hookAll(am, "getInstalledAccessibilityServiceList", empty);
        } catch (Throwable ignored) {}
    }

    /* ================= EXIF 脱敏 (exif_strip) ================= */

    private void exifStrip(XC_LoadPackage.LoadPackageParam lpp) {
        if (!on("exif_strip")) return;
        Set<String> strip = csv(confOf("exif_strip", "strip", "gps,device"));
        final boolean gps = strip.contains("gps");
        final boolean device = strip.contains("device");
        final boolean time = strip.contains("time");
        if (!gps && !device && !time) return;
        XC_MethodHook attrHook = new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) {
                if (param.args == null || param.args.length == 0) return;
                String tag = String.valueOf(param.args[0]);
                if (gps && tag.startsWith("GPS")) param.setResult(null);
                else if (device && ("Make".equals(tag) || "Model".equals(tag))) param.setResult(null);
                else if (time && tag.startsWith("DateTime")) param.setResult(null);
            }
        };
        XC_MethodHook dblHook = new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) {
                if (param.args == null || param.args.length < 2) return;
                String tag = String.valueOf(param.args[0]);
                if (gps && tag.startsWith("GPS")) param.setResult(param.args[1]);
            }
        };
        for (String cn : new String[]{"android.media.ExifInterface",
                "androidx.exifinterface.media.ExifInterface"}) {
            try {
                Class<?> ex = XposedHelpers.findClass(cn, lpp.classLoader);
                hookAll(ex, "getAttribute", attrHook);
                hookAll(ex, "getAttributeDouble", dblHook);
                if (gps) {
                    hookAll(ex, "getLatLong", new SafeHook() {
                        @Override
                        protected void onBefore(MethodHookParam param) {
                            param.setResult(null);
                        }
                    });
                }
            } catch (Throwable ignored) {}
        }
    }

    /* ================= Root / 文件痕迹隐藏 ================= */
    /* hide_magisk / hide_ksu / hide_su / block_rootcheck_libs / fs_hide / fs_rootlist */

    private static final Set<String> ROOT_PATHS = new HashSet<>(Arrays.asList(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
            "/system/app/Superuser.apk", "/system/app/Superuser",
            "/system/xbin/magisk", "/data/adb/magisk", "/data/adb/magisk32", "/data/adb/magiskinit",
            "/data/adb/modules", "/data/adb/ksu", "/data/adb/ksud", "/data/adb/ap", "/data/adb/apd",
            "/debug_ramdisk", "/data/local/tmp/privacyguard", "/data/adb/privacyguard",
            "/system/lib/libsu.so", "/system/lib64/libsu.so",
            "/system/lib/libbusybox.so", "/system/lib64/libbusybox.so",
            "/system/bin/busybox", "/system/xbin/busybox", "/data/local/tmp/busybox"));

    private void rootHide() {
        boolean any = on("hide_magisk") || on("hide_ksu") || on("hide_su")
                || on("block_rootcheck_libs") || on("fs_hide") || on("fs_rootlist");
        if (!any) return;
        final Set<String> hidden = new HashSet<>(ROOT_PATHS);
        for (String p : lines("fs_rootlist")) {
            String t = p.trim();
            if (!t.isEmpty()) hidden.add(t);
        }
        for (String p : lines("fs_hide")) {
            String t = p.trim();
            if (!t.isEmpty()) hidden.add(t);
        }
        XC_MethodHook ex = new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                Object thiz = param.thisObject;
                if (thiz instanceof File) {
                    String p = ((File) thiz).getAbsolutePath();
                    if (hidden.contains(p)) param.setResult(Boolean.FALSE);
                }
            }
        };
        hookAll(File.class, "exists", ex);
        hookAll(File.class, "canRead", ex);
        hookAll(File.class, "isDirectory", ex);
        hookAll(File.class, "isFile", ex);
        hookAll(File.class, "length", new SafeHook() {
            @Override
            protected void onAfter(MethodHookParam param) {
                Object thiz = param.thisObject;
                if (thiz instanceof File) {
                    if (hidden.contains(((File) thiz).getAbsolutePath())) param.setResult(0L);
                }
            }
        });
        // 拦截以 root 检测常用二进制为入口的 exec
        final Set<String> denyBase = new HashSet<>(Arrays.asList(
                "su", "magisk", "magisk32", "magiskinit", "ksu", "ksud", "apd", "apatch",
                "busybox", "daemonsu", "superuser"));
        if (on("block_mounts") || on("hide_mounts")) denyBase.add("mount");
        if (on("block_logcat")) denyBase.add("logcat");
        if (on("fs_attrs") || on("hide_kernel_debug")) denyBase.add("getprop");
        XC_MethodHook deny = new SafeHook() {
            @Override
            protected void onBefore(MethodHookParam param) throws Throwable {
                String cmd = firstToken(param);
                if (cmd == null) return;
                int slash = cmd.lastIndexOf('/');
                String base = slash >= 0 ? cmd.substring(slash + 1) : cmd;
                if (denyBase.contains(base)) {
                    param.setThrowable(new IOException("Permission denied"));
                }
            }
        };
        hookAll(Runtime.class, "exec", deny);
        try {
            Class<?> pb = XposedHelpers.findClass("java.lang.ProcessBuilder", null);
            hookAll(pb, "start", deny);
        } catch (Throwable ignored) {}
    }

    private String firstToken(XC_MethodHook.MethodHookParam param) {
        if (param.args == null || param.args.length == 0) return null;
        Object a0 = param.args[0];
        String cmd = null;
        if (a0 instanceof String) cmd = (String) a0;
        else if (a0 instanceof String[]) {
            String[] arr = (String[]) a0;
            if (arr.length > 0) cmd = arr[0];
        }
        if (cmd == null) return null;
        cmd = cmd.trim();
        int sp = cmd.indexOf(' ');
        return sp > 0 ? cmd.substring(0, sp) : cmd;
    }

    /* ================= 文件系统隔离/隐藏/VFS/sysfs ================= */
    /* fs_isolate / fs_hide / fs_vfs / block_mounts / hide_mounts / hide_sysfs_nodes */

    private List<String> isolateRoots, hidePaths, vfsPaths, sysfsPrefix;

    private void collectFsPaths() {
        isolateRoots = new ArrayList<>();
        hidePaths = new ArrayList<>();
        vfsPaths = new ArrayList<>();
        sysfsPrefix = new ArrayList<>();
        if (on("fs_isolate")) {
            for (String p : lines("fs_isolate")) {
                String t = p.trim();
                if (!t.isEmpty()) isolateRoots.add(t);
            }
        }
        if (on("fs_hide")) {
            for (String p : lines("fs_hide")) {
                String t = p.trim();
                if (!t.isEmpty()) hidePaths.add(t);
            }
        }
        if (on("fs_vfs") || on("block_mounts") || on("hide_mounts")) {
            for (String p : lines("fs_vfs")) {
                String t = p.trim();
                if (!t.isEmpty()) vfsPaths.add(t);
            }
            if (vfsPaths.isEmpty()) {
                vfsPaths.add("/proc/mounts");
                vfsPaths.add("/proc/self/mountinfo");
            }
        }
        if (on("hide_sysfs_nodes")) {
            sysfsPrefix.add("/sys/fs/selinux");
            sysfsPrefix.add("/sys/kernel/debug");
        }
    }

    private boolean fsBlocked(String path) {
        if (path == null) return false;
        for (String p : hidePaths) {
            if (path.equals(p) || path.startsWith(p + "/")) return true;
        }
        for (String p : sysfsPrefix) {
            if (path.startsWith(p)) return true;
        }
        return false;
    }

    private void fsHooks() {
        collectFsPaths();
        boolean needList = !isolateRoots.isEmpty() || !hidePaths.isEmpty() || !sysfsPrefix.isEmpty();
        boolean needVfs = !vfsPaths.isEmpty();
        if (!needList && !needVfs) return;

        if (needList) {
            XC_MethodHook ex = new SafeHook() {
                @Override
                protected void onAfter(MethodHookParam param) {
                    Object thiz = param.thisObject;
                    if (thiz instanceof File) {
                        if (fsBlocked(((File) thiz).getAbsolutePath())) param.setResult(Boolean.FALSE);
                    }
                }
            };
            hookAll(File.class, "exists", ex);
            hookAll(File.class, "canRead", ex);
            hookAll(File.class, "canWrite", ex);
            hookAll(File.class, "isDirectory", ex);
            hookAll(File.class, "isFile", ex);
            hookAll(File.class, "listFiles", new SafeHook() {
                @Override
                @SuppressWarnings("unchecked")
                protected void onAfter(MethodHookParam param) {
                    Object thiz = param.thisObject;
                    if (!(thiz instanceof File)) return;
                    String dir = ((File) thiz).getAbsolutePath();
                    if (fsBlocked(dir)) {
                        param.setResult(null);
                        return;
                    }
                    for (String r : isolateRoots) {
                        if (dir.equals(r) || dir.startsWith(r.endsWith("/") ? r : r + "/")) {
                            param.setResult(new File[0]);
                            return;
                        }
                    }
                    Object res = param.getResult();
                    if (res instanceof File[]) {
                        File[] in = (File[]) res;
                        List<File> out = new ArrayList<>();
                        boolean changed = false;
                        for (File f : in) {
                            if (fsBlocked(f.getAbsolutePath())) changed = true;
                            else out.add(f);
                        }
                        if (changed) param.setResult(out.toArray(new File[0]));
                    }
                }
            });
        }
        if (needVfs) {
            FileNotFoundException fnf = new FileNotFoundException("Permission denied");
            final Throwable t = fnf;
            XC_MethodHook deny = new SafeHook() {
                @Override
                protected void onBefore(MethodHookParam param) {
                    if (param.args == null || param.args.length == 0) return;
                    Object a0 = param.args[0];
                    String p = null;
                    if (a0 instanceof String) p = (String) a0;
                    else if (a0 instanceof File) p = ((File) a0).getAbsolutePath();
                    if (p == null) return;
                    for (String v : vfsPaths) {
                        if (p.equals(v)) {
                            param.setThrowable(t);
                            return;
                        }
                    }
                }
            };
            try { XposedBridge.hookAllConstructors(FileInputStream.class, deny); } catch (Throwable ignored) {}
            try { XposedBridge.hookAllConstructors(FileReader.class, deny); } catch (Throwable ignored) {}
        }
    }

    /* ================= 工具 ================= */

    private void hookAll(Class<?> c, String name, XC_MethodHook hook) {
        try {
            for (Method m : c.getDeclaredMethods()) {
                if (m.getName().equals(name) && !Modifier.isAbstract(m.getModifiers())) {
                    XposedBridge.hookMethod(m, hook);
                }
            }
        } catch (Throwable ignored) {}
    }

    private static void log(String s) {
        XposedBridge.log("[" + TAG + "] " + s);
    }

    /**
     * 完整读取一个流直到 EOF。
     * 注意: 不能用 in.available() 决定缓冲区大小 —— procfs(/proc/net/*) 的
     * st_size 恒为 0，available() 返回 0 会让读取逻辑退化成空字节数组，
     * 使 hideProcFilter / 路由过滤静默失效。
     */
    private static String readAll(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
        byte[] b = new byte[8192];
        int n;
        while ((n = in.read(b)) > 0) bos.write(b, 0, n);
        return new String(bos.toByteArray(), "UTF-8");
    }
}
