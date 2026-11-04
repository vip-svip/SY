package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Test

class FxUiModeTest {
    @Test
    fun exposesExactlyFiveCanonicalSkins() {
        assertEquals(5, FxUiMode.values().size)
    }

    @Test
    fun mapsStableStorageIdsToExpectedRenderers() {
        assertEquals(FxUiMode.CLASSIC_WEB_COMPAT, FxUiMode.fromStorageId("classic"))
        assertEquals(FxUiMode.FX_LIQUID_NATIVE, FxUiMode.fromStorageId("glass"))
        assertEquals(FxUiMode.MIUIX_STYLE, FxUiMode.fromStorageId("miuix"))
        assertEquals(FxUiMode.HUAWEI_HARMONY_STYLE, FxUiMode.fromStorageId("huawei"))
        assertEquals(FxUiMode.IOS_CUPERTINO_STYLE, FxUiMode.fromStorageId("ios"))
    }

    @Test
    fun migratesLegacyWebAliasAndUnknownValuesSafely() {
        assertEquals("classic", FxUiMode.normalizeStorageId("web"))
        assertEquals("classic", FxUiMode.normalizeStorageId("unknown-mode"))
        assertEquals("classic", FxUiMode.normalizeStorageId(null))
    }

    @Test
    fun acceptsCanonicalDisplayNamesAsImportAliases() {
        assertEquals(FxUiMode.CLASSIC_WEB_COMPAT, FxUiMode.fromStorageId("ClassicWebCompat"))
        assertEquals(FxUiMode.FX_LIQUID_NATIVE, FxUiMode.fromStorageId("FXLiquidNative"))
        assertEquals(FxUiMode.MIUIX_STYLE, FxUiMode.fromStorageId("MiuixStyle"))
        assertEquals(FxUiMode.HUAWEI_HARMONY_STYLE, FxUiMode.fromStorageId("HUAWEI HarmonyStyle"))
        assertEquals(FxUiMode.IOS_CUPERTINO_STYLE, FxUiMode.fromStorageId("iOS CupertinoStyle"))
    }
}
