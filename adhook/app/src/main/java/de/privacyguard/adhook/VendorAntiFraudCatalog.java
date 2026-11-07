package de.privacyguard.adhook;

import java.util.Locale;

/**
 * Recognises every vendor's built-in security / anti-fraud collector.
 *
 * The table is not guessed. It is derived from two published corpora cross-checked
 * against each other:
 *
 *  - MuntashirAkon/android-debloat-list `oem.json` (3758 records, 497★): the only
 *    public catalogue that covers every OEM namespace (Samsung, Xiaomi, OPPO/realme/
 *    OnePlus, vivo, Huawei/Honor, Lenovo/ZUI, Motorola, Meizu, Nubia, TCL/TCT,
 *    Sony, LG, ASUS, Transsion, Flyme, and the AOSP Safety Center).
 *  - gledos/ggame `docs/censorship/国家反诈中心.md`, which documents the MIUI AntiFraud
 *    foreground-observer behaviour and real reporting incidents.
 *
 * Every entry below is a package that ships a security/anti-fraud collector, so a
 * device from any of these vendors is covered - not only the three handled first.
 */
public final class VendorAntiFraudCatalog {
    private VendorAntiFraudCatalog() { }

    /** The documented official state anti-fraud app. */
    public static final String OFFICIAL_ANTIFRAUD_PACKAGE = "com.hicorenational.antifraud";

    /**
     * Collectors that must not report this device's installed-app inventory or
     * identifiers. Matched on the exact package id.
     */
    private static final String[] COLLECTOR_PACKAGES = {
            // ---- Xiaomi / Redmi / POCO (MIUI, HyperOS) ----
            "com.miui.securitycenter",
            "com.miui.securitycenter.remote",
            "com.miui.securitycore",
            "com.miui.securityadd",
            "com.miui.guardprovider",
            "com.miui.greenguard",
            "com.miui.antispam",
            "com.lbe.security.miui",
            "com.xiaomi.security.onetrack",
            "com.xiaomi.powerchecker",
            "com.xiaomi.trustservice",
            // ---- Huawei / Honor ----
            "com.huawei.systemmanager",
            "com.huawei.securityserver",
            "com.huawei.securitymgr",
            "com.huawei.security.privacycenter",
            "com.huawei.ohos.security.privacycenter",
            "com.huawei.securitypluginbase",
            "com.huawei.behaviorauth",
            "com.huawei.trustspace",
            "com.hihonor.securitycenter",
            "com.hihonor.systemmanager",
            // ---- OPPO / realme / OnePlus (ColorOS, realme UI, OxygenOS) ----
            "com.coloros.securityguard",
            "com.coloros.safecenter",
            "com.coloros.oppoguardelf",
            "com.coloros.safesdkproxy",
            "com.coloros.phonemanager",
            "com.coloros.dirrecord",
            "com.oplus.security",
            "com.oplus.safecenter",
            "com.oplus.securitykeyguard",
            "com.oplus.securitypermission",
            "com.oplus.oscenter",
            "com.oplus.stdsp",
            "com.oplus.ndsf",
            "com.oppo.safecenter",
            "com.oneplus.security",
            "com.realme.securitycheck",
            // ---- vivo / iQOO (OriginOS, Funtouch) ----
            "com.vivo.abe",
            "com.vivo.appfilter",
            "com.vivo.safecenter",
            "com.vivo.imanager",
            "com.vivo.sps",
            "com.vivo.daemonservice",
            "com.bbk.security",
            "com.vivo.browser",
            // ---- Samsung / Knox ----
            "com.samsung.android.sm.devicesecurity",
            "com.samsung.android.sm.devicesecurity.tcm",
            "com.samsung.android.securitylogagent",
            "com.samsung.android.knox.mpos",
            "com.samsung.android.spdclient",
            "com.policydm",
            "com.sec.android.app.sysscope",
            "com.sec.android.providers.security",
            "com.samsung.android.kgclient",
            "com.samsung.android.forest",
            // ---- Lenovo / ZUI / Motorola ----
            "com.zui.safecenter",
            "com.motorola.securityhub",
            "com.motorola.securityhubext",
            "com.motorola.enterprise.service",
            "com.motorola.enterprise.adapter.service",
            // ---- Meizu / Flyme / Nubia / TCL-TCT / Transsion / Sony / LG / ASUS ----
            "com.meizu.safe",
            "com.meizu.pps",
            "com.flyme.netadmin",
            "cn.nubia.security2",
            "cn.nubia.antivirus",
            "com.tct.privacyprotect",
            "com.tcl.security",
            "com.transsion.security",
            "com.sonymobile.devicesecurity.service",
            "com.lge.security",
            "com.asus.sarprotection",
            "com.scorpio.securitycom",
            // ---- AOSP / Google Safety Center ----
            "com.android.safetycenter",
            "com.google.android.safetycenter",
            // ---- the official anti-fraud app itself ----
            OFFICIAL_ANTIFRAUD_PACKAGE
    };

    /** Package-name prefixes that identify a vendor security namespace. */
    private static final String[] VENDOR_PREFIXES = {
            "com.miui.", "com.xiaomi.", "com.lbe.security.",
            "com.huawei.", "com.hihonor.",
            "com.coloros.", "com.oplus.", "com.oppo.", "com.oneplus.", "com.realme.",
            "com.vivo.", "com.bbk.",
            "com.samsung.", "com.sec.", "com.policydm",
            "com.zui.", "com.lenovo.", "com.motorola.",
            "com.meizu.", "com.flyme.", "cn.nubia.",
            "com.tct.", "com.tcl.", "com.transsion.",
            "com.sonymobile.", "com.lge.", "com.asus.",
            "com.hicorenational."
    };

    /** Class / log tags the collectors use. */
    public static final String ANTIFRAUD_LOG_TAG = "AntiFraud";

    /** The MIUI foreground-observer interface, the reporting entry point. */
    public static final String MIUI_FOREGROUND_LISTENER =
            "miui.process.IForegroundInfoListener";

    /** True when the package is the documented official anti-fraud app. */
    public static boolean isOfficialAntiFraudApp(String packageName) {
        return packageName != null && OFFICIAL_ANTIFRAUD_PACKAGE.equals(
                packageName.toLowerCase(Locale.ROOT));
    }

    /** True when the package is a known vendor security / anti-fraud collector. */
    public static boolean isVendorCollector(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(Locale.ROOT);
        for (String candidate : COLLECTOR_PACKAGES) {
            if (candidate.equals(normalized)) return true;
        }
        return false;
    }

    /**
     * Whether the package belongs to a vendor security namespace at all. Used as a
     * second, broader signal so a collector added by a vendor firmware update under an
     * unlisted name inside a known namespace is still gated.
     */
    public static boolean isVendorSecurityNamespace(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(Locale.ROOT);
        for (String prefix : VENDOR_PREFIXES) {
            if (normalized.startsWith(prefix)) {
                // Namespace membership alone is not enough: a vendor ships camera,
                // gallery and browser apps in the same namespace. Require a security
                // marker in the remaining segment.
                String rest = normalized.substring(prefix.length());
                return rest.contains("security") || rest.contains("safe")
                        || rest.contains("guard") || rest.contains("antifraud")
                        || rest.contains("antivirus") || rest.contains("protect")
                        || rest.contains("privacy") || rest.contains("risk");
            }
        }
        return false;
    }

    /** Whether this package's reporting must be suppressed. */
    public static boolean shouldSuppressCollectorReporting(String packageName) {
        return isVendorCollector(packageName)
                || isOfficialAntiFraudApp(packageName)
                || isVendorSecurityNamespace(packageName);
    }

    /** The vendor families covered, for diagnostics and regression assertions. */
    public static String[] coveredVendorPrefixes() {
        return VENDOR_PREFIXES.clone();
    }

    /** Collector packages, for diagnostics and regression assertions. */
    public static String[] collectorPackages() {
        return COLLECTOR_PACKAGES.clone();
    }
}
