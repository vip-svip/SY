package de.privacyguard.adhook

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FxComposeSkinTokensTest {
    private fun resolve(mode: String) = fxComposeShellTokens(
        mode = mode,
        miuixBackground = Color(0xFFF3F5FA),
        miuixSurface = Color(0xFFEAF0FB),
        miuixPrimary = Color(0xFF3478F6),
        miuixSelectedText = Color(0xFF202B3C),
        miuixInactiveText = Color(0xFF718091),
        miuixSelectedSurface = Color(0xFFE5ECF8)
    )

    @Test
    fun exposesFiveIndependentNavigationGeometries() {
        val classic = resolve("classic")
        val glass = resolve("glass")
        val miuix = resolve("miuix")
        val harmony = resolve("huawei")
        val cupertino = resolve("ios")

        assertEquals(60, classic.tabBarHeightDp)
        assertEquals(72, glass.tabBarHeightDp)
        assertEquals(68, miuix.tabBarHeightDp)
        assertEquals(72, harmony.tabBarHeightDp)
        assertEquals(76, cupertino.tabBarHeightDp)

        assertEquals(8, classic.barCornerRadiusDp)
        assertEquals(26, glass.barCornerRadiusDp)
        assertEquals(20, miuix.barCornerRadiusDp)
        assertEquals(18, harmony.barCornerRadiusDp)
        assertEquals(24, cupertino.barCornerRadiusDp)
    }

    @Test
    fun onlyLiquidSkinSelectsLensTabRenderer() {
        assertFalse(resolve("classic").useLiquidTabsRenderer)
        assertTrue(resolve("glass").useLiquidTabsRenderer)
        assertFalse(resolve("miuix").useLiquidTabsRenderer)
        assertFalse(resolve("huawei").useLiquidTabsRenderer)
        assertFalse(resolve("ios").useLiquidTabsRenderer)
    }

    @Test
    fun huaweiAndCupertinoHaveIndependentSurfaceAndAccentTokens() {
        val harmony = resolve("huawei")
        val cupertino = resolve("ios")

        assertEquals(Color(0xFFF1F5FA), harmony.pageBackground)
        assertEquals(Color(0xFFF2F2F7), cupertino.pageBackground)
        assertEquals(Color(0xFF2878D0), harmony.accent)
        assertEquals(Color(0xFF007AFF), cupertino.accent)
        assertNotEquals(harmony.barBorder, cupertino.barBorder)
        assertNotEquals(harmony.selectedTabBackground, cupertino.selectedTabBackground)
    }

    @Test
    fun miuixUsesRuntimeThemeColorsRatherThanAStaticCopiedPalette() {
        val miuix = resolve("miuix")
        assertEquals(Color(0xFFF3F5FA), miuix.pageBackground)
        assertEquals(Color(0xFFEAF0FB), miuix.barBackground)
        assertEquals(Color(0xFF202B3C), miuix.selectedText)
        assertEquals(Color(0xFF718091), miuix.inactiveText)
    }

    @Test
    fun unknownModeFallsBackToClassicSkinTokens() {
        assertEquals(resolve("classic"), resolve("not-a-skin"))
    }
}
