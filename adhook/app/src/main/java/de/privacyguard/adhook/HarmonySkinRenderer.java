package de.privacyguard.adhook;

import de.privacyguard.adhook.HarmonySkinTokens.HarmonyColorTokens;
import de.privacyguard.adhook.HarmonySkinTokens.HarmonyShapeTokens;

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
                HarmonyShapeTokens.CARD_RADIUS_DP
        );
    }
}