package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * Contract test for the vendor anti-fraud package catalogue.
 *
 * The table is derived from published research (gledos/ggame 国家反诈中心 documentation
 * and sukiko789/IFW-Rules component lists), so the assertions pin the exact packages
 * that must be recognised across Xiaomi/HyperOS, Huawei/Honor, OPPO/realme/OnePlus and
 * vivo/iQOO. A package that silently drops out of the table would leave a real vendor
 * collector unguarded, so each family is asserted explicitly.
 */
public final class VendorAntiFraudCatalogTest {

    @Test public void officialAntiFraudPackageIsRecognised() {
        assertTrue(VendorAntiFraudCatalog.isOfficialAntiFraudApp("com.hicorenational.antifraud"));
        assertTrue(VendorAntiFraudCatalog.isOfficialAntiFraudApp("COM.HICORENATIONAL.ANTIFRAUD"));
        assertFalse(VendorAntiFraudCatalog.isOfficialAntiFraudApp("com.example.app"));
        assertFalse(VendorAntiFraudCatalog.isOfficialAntiFraudApp(null));
    }

    @Test public void xiaomiAndHyperOsCollectorsAreRecognised() {
        for (String pkg : new String[]{"com.miui.securitycenter",
                "com.miui.securitycenter.remote", "com.miui.guardprovider",
                "com.miui.antispam"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void huaweiAndHonorCollectorsAreRecognised() {
        for (String pkg : new String[]{"com.huawei.systemmanager", "com.huawei.hwid",
                "com.hihonor.securitycenter", "com.hihonor.systemmanager"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void oppoRealmeOnePlusCollectorsAreRecognised() {
        for (String pkg : new String[]{"com.coloros.securityguard",
                "com.coloros.safecenter", "com.oplus.security", "com.oplus.safecenter",
                "com.oplus.securitykeyguard", "com.oppo.safecenter"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void vivoAndIqooCollectorsAreRecognised() {
        for (String pkg : new String[]{"com.vivo.abe", "com.vivo.appfilter",
                "com.bbk.security", "com.vivo.browser"}) {
            assertTrue(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
    }

    @Test public void ordinaryAppsAreNotCollectors() {
        for (String pkg : new String[]{"com.example.app", "com.tencent.mm",
                "org.telegram.messenger", "com.android.settings",
                "de.privacyguard.adhook", "org.lsposed.manager"}) {
            assertFalse(pkg, VendorAntiFraudCatalog.isVendorCollector(pkg));
        }
        assertFalse(VendorAntiFraudCatalog.isVendorCollector(""));
        assertFalse(VendorAntiFraudCatalog.isVendorCollector(null));
    }

    @Test public void suppressionCoversCollectorsAndTheOfficialApp() {
        assertTrue(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.miui.securitycenter"));
        assertTrue(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.hicorenational.antifraud"));
        assertFalse(VendorAntiFraudCatalog.shouldSuppressCollectorReporting(
                "com.example.app"));
    }

    @Test public void documentedConstantsAreExposedForDiagnostics() {
        assertTrue(VendorAntiFraudCatalog.MIUI_FOREGROUND_LISTENER
                .equals("miui.process.IForegroundInfoListener"));
        assertTrue(VendorAntiFraudCatalog.ANTIFRAUD_LOG_TAG.equals("AntiFraud"));
        String[] table = VendorAntiFraudCatalog.vendorCollectorPackages();
        assertTrue("catalogue must not be empty", table.length > 15);
        // Handing out a clone keeps the compiled table immutable at runtime.
        table[0] = "tampered";
        assertFalse(VendorAntiFraudCatalog.vendorCollectorPackages()[0].equals("tampered"));
    }
}
