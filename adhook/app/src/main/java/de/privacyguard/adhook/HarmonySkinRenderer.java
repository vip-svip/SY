package de.privacyguard.adhook;

import de.privacyguard.adhook.HarmonySkinTokens.HarmonyColorTokens;
import de.privacyguard.adhook.HarmonySkinTokens.HarmonyShapeTokens;
import de.privacyguard.adhook.HarmonySkinTokens.HarmonySpacingTokens;
import de.privacyguard.adhook.HarmonySkinTokens.HarmonyTypographyTokens;

/** Android View renderer for the dedicated Harmony-inspired token set. */
final class HarmonySkinRenderer {
    private HarmonySkinRenderer() { }

    static FxNativeSkin.Palette palette() {
        return new FxNativeSkin.Palette(
                HarmonyColorTokens.BACKGROUND,
                HarmonyColorTokens.SURFACE,
                HarmonyColorTokens.SURFACE_VARIANT,
                HarmonyColorTokens.DIVIDER,
                HarmonyColorTokens.PRIMARY_TEXT,
                HarmonyColorTokens.SECONDARY_TEXT,
                HarmonyColorTokens.ACTION_BACKGROUND,
                HarmonyColorTokens.ACTION_BORDER,
                HarmonyColorTokens.ACCENT,
                HarmonyColorTokens.SWITCH_OFF_TRACK,
                HarmonyShapeTokens.ACTION_RADIUS_DP,
                HarmonyColorTokens.INPUT_BORDER,
                HarmonyShapeTokens.CARD_RADIUS_DP,
                HarmonyTypographyTokens.ACTION_LABEL_SP,
                HarmonySpacingTokens.ACTION_MIN_HEIGHT_DP,
                HarmonySpacingTokens.ACTION_MIN_WIDTH_DP,
                HarmonySpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                HarmonySpacingTokens.ACTION_VERTICAL_PADDING_DP,
                0f,
                HarmonyTypographyTokens.SWITCH_LABEL_SP,
                HarmonySpacingTokens.SWITCH_HORIZONTAL_PADDING_DP,
                HarmonySpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                HarmonyTypographyTokens.CHOICE_LABEL_SP,
                HarmonyTypographyTokens.INPUT_LABEL_SP,
                HarmonySpacingTokens.INPUT_MIN_HEIGHT_DP
        );
    }
}