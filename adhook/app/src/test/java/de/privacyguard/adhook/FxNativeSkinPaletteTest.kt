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
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_MIN_WIDTH_DP, palette.buttonMinWidthDp)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_HORIZONTAL_PADDING_DP, palette.buttonHorizontalPaddingDp)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_VERTICAL_PADDING_DP, palette.buttonVerticalPaddingDp)
        assertEquals(0f, palette.buttonElevationDp, 0f)
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.SWITCH_LABEL_SP, palette.switchTextSizeSp, 0f)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, palette.switchHorizontalPaddingDp)
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.SWITCH_VERTICAL_PADDING_DP, palette.switchVerticalPaddingDp)
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
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_MIN_WIDTH_DP, palette.buttonMinWidthDp)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, palette.buttonHorizontalPaddingDp)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_VERTICAL_PADDING_DP, palette.buttonVerticalPaddingDp)
        assertEquals(0f, palette.buttonElevationDp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.SWITCH_LABEL_SP, palette.switchTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, palette.switchHorizontalPaddingDp)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.SWITCH_VERTICAL_PADDING_DP, palette.switchVerticalPaddingDp)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.CHOICE_LABEL_SP, palette.choiceTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.INPUT_LABEL_SP, palette.inputTextSizeSp, 0f)
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.INPUT_MIN_HEIGHT_DP, palette.inputMinHeightDp)
        assertEquals(CupertinoSkinTokens.CupertinoColorTokens.INPUT_BORDER, palette.inputBorder)
    }

    @Test
    fun cardDescriptionTypographyUsesDistinctReadableTokens() {
        assertEquals(13.5f, HarmonySkinTokens.HarmonyTypographyTokens.CARD_DESCRIPTION_SP, 0f)
        assertEquals(13f, CupertinoSkinTokens.CupertinoTypographyTokens.CARD_DESCRIPTION_SP, 0f)
    }

    @Test
    fun harmonyAndCupertinoAppListRowsUseIndependentGeometryAndTypography() {
        assertEquals(16, HarmonySkinTokens.HarmonyShapeTokens.LIST_ROW_RADIUS_DP)
        assertEquals(12, CupertinoSkinTokens.CupertinoShapeTokens.LIST_ROW_RADIUS_DP)
        assertEquals(56, HarmonySkinTokens.HarmonySpacingTokens.LIST_ROW_MIN_HEIGHT_DP)
        assertEquals(52, CupertinoSkinTokens.CupertinoSpacingTokens.LIST_ROW_MIN_HEIGHT_DP)
        assertEquals(15f, HarmonySkinTokens.HarmonyTypographyTokens.LIST_ROW_TITLE_SP, 0f)
        assertEquals(12f, HarmonySkinTokens.HarmonyTypographyTokens.LIST_ROW_SUBTITLE_SP, 0f)
        assertEquals(15f, CupertinoSkinTokens.CupertinoTypographyTokens.LIST_ROW_TITLE_SP, 0f)
        assertEquals(11f, CupertinoSkinTokens.CupertinoTypographyTokens.LIST_ROW_SUBTITLE_SP, 0f)
        assertNotEquals(
            HarmonySkinTokens.HarmonyColorTokens.LIST_ROW_SURFACE,
            CupertinoSkinTokens.CupertinoColorTokens.LIST_ROW_SURFACE
        )
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
