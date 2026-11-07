package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * Contract test for the vendor anti-fraud catalogue.
 *
 * The table is derived from MuntashirAkon/android-debloat-list `oem.json` (3758 records,
 * the only public corpus covering every OEM namespace) cross-checked with the
 * gledos/ggame 国家反诈中心 documentation. Each family is asserted explicitly: a vendor
 * that silently drops out would leave real collectors unguarded, which was the original
 * complaint ("不能只处理这三个系统").
 */
public final class VendorAntiFraudCatalogTest {

    @Test public void officialAntiFraudPackageIsRecognised() {
        assertTrue(VendorAntiFraudCatalog.isOfficialAntiFraudApp("com.hicorenational.antifraud"));
        assertTrue(VendorAntiFraudCatalog.isOfficialAntiFraudApp("COM.HICORENATIONAL.ANTIFRAUD"));
        assertFalse(VendorAntiFraudCatalog.isOfficialAntiFraudApp("com.example.app"));
        assertFalse(VendorAntiFraudCatalog.isOfficialAntiFraudApp(null));
    }

    @Test public void xiaomiAndHyperOsCollectorsAreRecognised() {
        for (String pkg : new String[]{
                "com.miui.securitycenter", "com.miui.securitycenter.remote",
                "com.miui.securitycore", "com.miui.securityadd",
                "com.miui.guardprovider", "com.miui.greenguard", "com.miui.antispam",
                "com.lbe.security.miui", "com.xiaomi.security.onetrack",
                "com.xiaomi.powerchecker", "com.xiaomi.trustservice"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void huaweiAndHonorCollectorsAreRecognised() {
        for (String pkg : new String[]{
                "com.huawei.systemmanager", "com.huawei.securityserver",
                "com.huawei.securitymgr", "com.huawei.security.privacycenter",
                "com.huawei.securitypluginbase", "com.huawei.behaviorauth",
                "com.huawei.trustspace", "com.hihonor.securitycenter",
                "com.hihonor.systemmanager"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void oppoRealmeOnePlusCollectorsAreRecognised() {
        for (String pkg : new String[]{
                "com.coloros.securityguard", "com.coloros.safecenter",
                "com.coloros.oppoguardelf", "com.coloros.safesdkproxy",
                "com.coloros.phonemanager", "com.oplus.security",
                "com.oplus.safecenter", "com.oplus.securitykeyguard",
                "com.oplus.securitypermission", "com.oplus.oscenter",
                "com.oplus.stdsp", "com.oppo.safecenter", "com.oneplus.security",
                "com.realme.securitycheck"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void vivoAndIqooCollectorsAreRecognised() {
        for (String pkg : new String[]{"com.vivo.abe", "com.vivo.appfilter",
                "com.vivo.safecenter", "com.vivo.imanager", "com.vivo.sps",
                "com.bbk.security", "com.vivo.browser"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void samsungAndKnoxCollectorsAreRecognised() {
        for (String pkg : new String[]{
                "com.samsung.android.sm.devicesecurity",
                "com.samsung.android.sm.devicesecurity.tcm",
                "com.samsung.android.securitylogagent",
                "com.samsung.android.knox.mpos", "com.policydm",
                "com.sec.android.app.sysscope", "com.sec.android.providers.security"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void remainingOemsAreRecognised() {
        for (String pkg : new String[]{
                "com.zui.safecenter", "com.motorola.securityhub",
                "com.meizu.safe", "com.meizu.pps", "com.flyme.netadmin",
                "cn.nubia.security2", "cn.nubia.antivirus",
                "com.tct.privacyprotect", "com.sonymobile.devicesecurity.service",
                "com.asus.sarprotection", "com.android.safetycenter"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void namespaceFallbackCatchesUnlistedVendorCollectors() {
        // A collector added by a firmware update under an unlisted name inside a known
        // vendor namespace must still be gated.
        assertTrue(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.miui.securityfoo"));
        assertTrue(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.oplus.safebar"));
        assertTrue(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.hihonor.antifraudx"));
        // But an ordinary vendor app in the same namespace must NOT be treated as one.
        assertFalse(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.miui.camera"));
        assertFalse(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.oplus.gallery"));
        assertFalse(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.huawei.hwmaps"));
        assertFalse(VendorAntiFraudCatalog.isVendorSecurityNamespace("com.example.app"));
        assertFalse(VendorAntiFraudCatalog.isVendorSecurityNamespace(null));
    }

    @Test public void ordinaryAppsAreNotCollectors() {
        for (String pkg : new String[]{"com.example.app", "com.tencent.mm",
                "org.telegram.messenger", "com.android.settings",
                "de.privacyguard.adhook", "org.lsposed.manager",
                "com.miui.camera", "com.oplus.gallery"}) {
            assertFalse(pkg, VendorAntiFraudCatalog.shouldSuppressCollectorReporting(pkg));
        }
        assertFalse(VendorAntiFraudCatalog.isVendorCollector(""));
        assertFalse(VendorAntiFraudCatalog.isVendorCollector(null));
    }

    @Test public void suppressionCoversCollectorsAndTheOfficialApp() {
        assertTrue(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.miui.securitycenter"));
        assertTrue(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.hicorenational.antifraud"));
        assertTrue(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.coloros.securityguard"));
    }

    @Test public void catalogueIsBroadAndImmutable() {
        assertTrue(VendorAntiFraudCatalog.MIUI_FOREGROUND_LISTENER
                .equals("miui.process.IForegroundInfoListener"));
        assertTrue(VendorAntiFraudCatalog.ANTIFRAUD_LOG_TAG.equals("AntiFraud"));
        String[] packages = VendorAntiFraudCatalog.collectorPackages();
        // Derived from oem.json: 74 exact collector packages as of this corpus revision.
        assertTrue("catalogue must cover the full vendor set", packages.length >= 70);
        String[] prefixes = VendorAntiFraudCatalog.coveredVendorPrefixes();
        // 28 namespaces: Xiaomi, Huawei, OPPO, vivo, Samsung, Lenovo, Motorola, Meizu,
        // Flyme, Nubia, TCT/TCL, Transsion, Sony, LG, ASUS, official anti-fraud, ...
        assertTrue("must cover at least 25 vendor namespaces", prefixes.length >= 25);
        // Clones keep the compiled tables immutable at runtime.
        packages[0] = "tampered";
        prefixes[0] = "tampered";
        assertFalse(VendorAntiFraudCatalog.collectorPackages()[0].equals("tampered"));
        assertFalse(VendorAntiFraudCatalog.coveredVendorPrefixes()[0].equals("tampered"));
    }
}
