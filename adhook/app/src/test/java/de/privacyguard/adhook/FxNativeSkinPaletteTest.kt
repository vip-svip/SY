package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class FxNativeSkinPaletteTest {
    @Test
    fun harmonyRendererUsesItsOwnCardActionAndFormTokens() {
        val palette = HarmonySkinRenderer.palette()

        assertEquals(HarmonySkinTokens.HarmonyShapeTokens.ACTION_RADIUS_DP, palette.cornerRadiusDp)
        assertEquals(HarmonySkinTokens.HarmonyShapeTokens.CARD_RADIUS_DP, palette.cardCornerRadiusDp)
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.ACTION_LABEL_SP, palette.buttonTextSizeSp, 0f)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_MIN_HEIGHT_DP, palette.buttonMinHeightDp)
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.SWITCH_LABEL_SP, palette.switchTextSizeSp, 0f)
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.CHOICE_LABEL_SP, palette.choiceTextSizeSp, 0f)
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.INPUT_LABEL_SP, palette.inputTextSizeSp, 0f)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.INPUT_MIN_HEIGHT_DP, palette.inputMinHeightDp)
        assertEquals(HarmonySkinTokens.HarmonyColorTokens.INPUT_BORDER, palette.inputBorder)
    }

    @Test
    fun cupertinoRendererUsesItsOwnCardActionAndFormTokens() {
        val palette = CupertinoSkinRenderer.palette()

        assertEquals(CupertinoSkinTokens.CupertinoShapeTokens.ACTION_RADIUS_DP, palette.cornerRadiusDp)
        assertEquals(CupertinoSkinTokens.CupertinoShapeTokens.CARD_RADIUS_DP, palette.cardCornerRadiusDp)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.ACTION_LABEL_SP, palette.buttonTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_MIN_HEIGHT_DP, palette.buttonMinHeightDp)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.SWITCH_LABEL_SP, palette.switchTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.CHOICE_LABEL_SP, palette.choiceTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.INPUT_LABEL_SP, palette.inputTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.INPUT_MIN_HEIGHT_DP, palette.inputMinHeightDp)
        assertEquals(CupertinoSkinTokens.CupertinoColorTokens.INPUT_BORDER, palette.inputBorder)
    }

    @Test
    fun harmonyAndCupertinoGeometryAndInputsRemainDistinct() {
        val harmony = HarmonySkinRenderer.palette()
        val cupertino = CupertinoSkinRenderer.palette()

        assertNotEquals(harmony.cornerRadiusDp, cupertino.cornerRadiusDp)
        assertNotEquals(harmony.cardCornerRadiusDp, cupertino.cardCornerRadiusDp)
        assertNotEquals(harmony.inputBorder, cupertino.inputBorder)
        assertNotEquals(harmony.buttonTextSizeSp, cupertino.buttonTextSizeSp)
        assertNotEquals(harmony.inputTextSizeSp, cupertino.inputTextSizeSp)
    }
}
