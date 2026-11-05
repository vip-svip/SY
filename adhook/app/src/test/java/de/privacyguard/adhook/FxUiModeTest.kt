package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Test

class FxUiModeTest {
    @Test
    fun exposesIndependentDefaultAndExactlyFiveSkinsInStableOrder() {
        assertEquals(6, FxUiMode.values().size)
        assertEquals(
            listOf("default", "classic", "glass", "miuix", "huawei", "ios"),
            FxUiMode.values().map { it.storageId }
        )
        assertEquals(FxUiMode.DEFAULT_STANDARD, FxUiMode.values().first())
        assertEquals(FxUiMode.Renderer.NATIVE_DEFAULT, FxUiMode.DEFAULT_STANDARD.renderer)
    }

    @Test
    fun mapsStableStorageIdsToExpectedRenderers() {
        assertEquals(FxUiMode.DEFAULT_STANDARD, FxUiMode.fromStorageId("default"))
        assertEquals(FxUiMode.CLASSIC_WEB_COMPAT, FxUiMode.fromStorageId("classic"))
        assertEquals(FxUiMode.FX_LIQUID_NATIVE, FxUiMode.fromStorageId("glass"))
        assertEquals(FxUiMode.MIUIX_STYLE, FxUiMode.fromStorageId("miuix"))
        assertEquals(FxUiMode.HUAWEI_HARMONY_STYLE, FxUiMode.fromStorageId("huawei"))
        assertEquals(FxUiMode.IOS_CUPERTINO_STYLE, FxUiMode.fromStorageId("ios"))
    }

    @Test
    fun preservesEveryLegacySkinAndDefaultsUnknownValuesSafely() {
        assertEquals("classic", FxUiMode.normalizeStorageId("web"))
        assertEquals("classic", FxUiMode.normalizeStorageId("ClassicWebCompat"))
        assertEquals("glass", FxUiMode.normalizeStorageId("FXLiquidNative"))
        assertEquals("miuix", FxUiMode.normalizeStorageId("MiuixStyle"))
        assertEquals("huawei", FxUiMode.normalizeStorageId("HarmonyStyle"))
        assertEquals("ios", FxUiMode.normalizeStorageId("CupertinoStyle"))
        assertEquals("default", FxUiMode.normalizeStorageId("unknown-mode"))
        assertEquals("default", FxUiMode.normalizeStorageId(null))
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
