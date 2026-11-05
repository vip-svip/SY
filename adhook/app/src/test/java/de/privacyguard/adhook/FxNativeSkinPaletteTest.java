package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class FxNativeSkinPaletteTest {
    @Test
    public void harmonyRendererUsesHarmonyComponentTokens() {
        FxNativeSkin.Palette palette = HarmonySkinRenderer.palette();

        assertEquals(HarmonySkinTokens.HarmonyColorTokens.BACKGROUND, palette.background);
        assertEquals(HarmonySkinTokens.HarmonyColorTokens.INPUT_BORDER, palette.inputBorder);
        assertEquals(HarmonySkinTokens.HarmonyShapeTokens.ACTION_RADIUS_DP, palette.cornerRadiusDp);
        assertEquals(HarmonySkinTokens.HarmonyShapeTokens.CARD_RADIUS_DP, palette.cardCornerRadiusDp);
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.ACTION_LABEL_SP,
                palette.buttonTextSizeSp, 0f);
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_MIN_HEIGHT_DP,
                palette.buttonMinHeightDp);
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_MIN_WIDTH_DP,
                palette.buttonMinWidthDp);
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                palette.buttonHorizontalPaddingDp);
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.SWITCH_LABEL_SP,
                palette.switchTextSizeSp, 0f);
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                palette.switchVerticalPaddingDp);
        assertEquals(HarmonySkinTokens.HarmonyTypographyTokens.INPUT_LABEL_SP,
                palette.inputTextSizeSp, 0f);
        assertEquals(HarmonySkinTokens.HarmonySpacingTokens.INPUT_MIN_HEIGHT_DP,
                palette.inputMinHeightDp);
    }

    @Test
    public void cupertinoRendererUsesCupertinoComponentTokens() {
        FxNativeSkin.Palette palette = CupertinoSkinRenderer.palette();

        assertEquals(CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND, palette.background);
        assertEquals(CupertinoSkinTokens.CupertinoColorTokens.INPUT_BORDER, palette.inputBorder);
        assertEquals(CupertinoSkinTokens.CupertinoShapeTokens.ACTION_RADIUS_DP, palette.cornerRadiusDp);
        assertEquals(CupertinoSkinTokens.CupertinoShapeTokens.CARD_RADIUS_DP, palette.cardCornerRadiusDp);
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.ACTION_LABEL_SP,
                palette.buttonTextSizeSp, 0f);
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_MIN_HEIGHT_DP,
                palette.buttonMinHeightDp);
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_MIN_WIDTH_DP,
                palette.buttonMinWidthDp);
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                palette.buttonHorizontalPaddingDp);
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.SWITCH_LABEL_SP,
                palette.switchTextSizeSp, 0f);
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                palette.switchVerticalPaddingDp);
        assertEquals(CupertinoSkinTokens.CupertinoTypographyTokens.INPUT_LABEL_SP,
                palette.inputTextSizeSp, 0f);
        assertEquals(CupertinoSkinTokens.CupertinoSpacingTokens.INPUT_MIN_HEIGHT_DP,
                palette.inputMinHeightDp);
    }
}
