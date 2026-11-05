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
        assertEquals("Each selectable mode must own an independent renderer", 6, FxUiMode.values().map { it.renderer }.distinct().size)
        assertEquals(
            listOf(
                "默认模式 · Default",
                "旧网页模式 · Classic",
                "原生液态玻璃 · Glass",
                "Miuix · 小米澎湃风格",
                "HarmonyStyle · 华为风格",
                "CupertinoStyle · iOS 风格"
            ),
            FxUiMode.values().map { it.title }
        )
    }

    @Test
    fun mapsEverySkinToItsDedicatedRenderer() {
        assertEquals(FxUiMode.Renderer.NATIVE_DEFAULT, FxUiMode.DEFAULT_STANDARD.renderer)
        assertEquals(FxUiMode.Renderer.WEB_COMPAT, FxUiMode.CLASSIC_WEB_COMPAT.renderer)
        assertEquals(FxUiMode.Renderer.NATIVE_LIQUID, FxUiMode.FX_LIQUID_NATIVE.renderer)
        assertEquals(FxUiMode.Renderer.NATIVE_MIUIX, FxUiMode.MIUIX_STYLE.renderer)
        assertEquals(FxUiMode.Renderer.NATIVE_HARMONY, FxUiMode.HUAWEI_HARMONY_STYLE.renderer)
        assertEquals(FxUiMode.Renderer.NATIVE_CUPERTINO, FxUiMode.IOS_CUPERTINO_STYLE.renderer)
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
    fun normalizesWhitespaceAndCaseForLegacyImportedAliases() {
        assertEquals(FxUiMode.DEFAULT_STANDARD, FxUiMode.fromStorageId("  FXDEFAULT  "))
        assertEquals(FxUiMode.FX_LIQUID_NATIVE, FxUiMode.fromStorageId(" FXLIQUIDNATIVE "))
        assertEquals(FxUiMode.MIUIX_STYLE, FxUiMode.fromStorageId(" MIUIXSTYLE "))
        assertEquals(FxUiMode.HUAWEI_HARMONY_STYLE, FxUiMode.fromStorageId(" HUAWEI HARMONYSTYLE "))
        assertEquals(FxUiMode.IOS_CUPERTINO_STYLE, FxUiMode.fromStorageId(" IOS CUPERTINOSTYLE "))
        assertEquals(FxUiMode.CLASSIC_WEB_COMPAT, FxUiMode.fromStorageId(" CLASSICWEBCOMPAT "))
        assertEquals(FxUiMode.DEFAULT_STANDARD, FxUiMode.fromStorageId("   "))
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
