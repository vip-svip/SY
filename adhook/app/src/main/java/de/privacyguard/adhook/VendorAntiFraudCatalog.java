package de.privacyguard.adhook;

import java.util.Locale;

/**
 * Recognises the vendor-built-in anti-fraud and inspection components.
 *
 * Research basis:
 *  - gledos/ggame `docs/censorship/国家反诈中心.md` documents that MIUI's
 *    `com.miui.securitycenter` runs an `AntiFraud` component which, on every foreground
 *    change, calls `PackageManager.getApplicationInfo` for the newly visible app to
 *    report it upstream. The same doc records real cases of installed apps being
 *    reported (ChatGPT, Bumble, remote-desktop tools) across MIUI, Huawei, Honor and
 *    ColorOS/realme devices.
 *  - sukiko789/IFW-Rules ships the real official package `com.hicorenational.antifraud`
 *    with its manifest components, including `service.ScreenRecordService` and
 *    `service.ScreenRecord2Service` (screen capture under an anti-fraud label).
 *  - OriginOS / vivo browser, realme UI 4.0 and Honor's security centre each ship a
 *    "反诈中心拦截服务" fed by central data.
 *
 * The classifier is pure and table-driven so it can be unit-tested and audited.
 */
public final class VendorAntiFraudCatalog {
    private VendorAntiFraudCatalog() { }

    /** The documented official package for the state anti-fraud app. */
    public static final String OFFICIAL_ANTIFRAUD_PACKAGE = "com.hicorenational.antifraud";

    /**
     * Vendor components that host an anti-fraud collector. These are system packages,
     * so they are blocked by matching the *component* surface rather than by replacing
     * the package itself (which would break the phone's own security UI).
     */
    private static final String[] VENDOR_COLLECTOR_PACKAGES = {
            // Xiaomi / Redmi / POCO (MIUI / HyperOS): AntiFraud inside securitycentre.
            "com.miui.securitycenter",
            "com.miui.securitycenter.remote",
            "com.miui.guardprovider",
            "com.miui.antispam",
            // Huawei / Honor
            "com.huawei.systemmanager",
            "com.huawei.hwid",
            "com.hihonor.securitycenter",
            "com.hihonor.systemmanager",
            // OPPO / realme / OnePlus (ColorOS / realme UI / OxygenOS)
            "com.coloros.securityguard",
            "com.coloros.safecenter",
            "com.oplus.security",
            "com.oplus.safecenter",
            "com.oplus.securitykeyguard",
            "com.oppo.safecenter",
            // vivo / iQOO (OriginOS / Funtouch)
            "com.vivo.abe",
            "com.vivo.appfilter",
            "com.bbk.security",
            "com.vivo.browser",
            // Samsung
            "com.samsung.android.kgclient",
            "com.samsung.android.forest"
    };

    /** Class / log tags the anti-fraud collectors use inside those host packages. */
    public static final String ANTIFRAUD_LOG_TAG = "AntiFraud";

    /**
     * The foreground-observer interface MIUI's AntiFraud binds to. Reporting a
     * foreground change is what turns "app installed" into "app reported upstream".
     */
    public static final String MIUI_FOREGROUND_LISTENER =
            "miui.process.IForegroundInfoListener";

    /** True when the package is the documented official anti-fraud app. */
    public static boolean isOfficialAntiFraudApp(String packageName) {
        return packageName != null && OFFICIAL_ANTIFRAUD_PACKAGE.equals(
                packageName.toLowerCase(Locale.ROOT));
    }

    /** True when the package hosts a vendor anti-fraud collector. */
    public static boolean isVendorCollector(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(Locale.ROOT);
        for (String candidate : VENDOR_COLLECTOR_PACKAGES) {
            if (candidate.equals(normalized)) return true;
        }
        return false;
    }

    /**
     * Whether this package's *own* foreground observer should stop reporting the
     * installed-app inventory. Distinguished from blocking a target app: here we are
     * restricting what a vendor collector may read about the rest of the device.
     */
    public static boolean shouldSuppressCollectorReporting(String packageName) {
        return isVendorCollector(packageName) || isOfficialAntiFraudApp(packageName);
    }

    /** Vendor collector packages, for diagnostics and regression assertions. */
    public static String[] vendorCollectorPackages() {
        return VENDOR_COLLECTOR_PACKAGES.clone();
    }
}
