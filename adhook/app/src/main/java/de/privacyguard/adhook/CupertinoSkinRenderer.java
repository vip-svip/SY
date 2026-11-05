package de.privacyguard.adhook;

import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoColorTokens;
import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoShapeTokens;
import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoSpacingTokens;
import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoTypographyTokens;

/** Android View renderer for the dedicated Cupertino-inspired token set. */
final class CupertinoSkinRenderer {
    private CupertinoSkinRenderer() { }

    static FxNativeSkin.Palette palette() {
        return new FxNativeSkin.Palette(
                CupertinoColorTokens.BACKGROUND,
                CupertinoColorTokens.SURFACE,
                CupertinoColorTokens.SURFACE_VARIANT,
                CupertinoColorTokens.DIVIDER,
                CupertinoColorTokens.PRIMARY_TEXT,
                CupertinoColorTokens.SECONDARY_TEXT,
                CupertinoColorTokens.ACTION_BACKGROUND,
                CupertinoColorTokens.ACTION_BORDER,
                CupertinoColorTokens.ACCENT,
                CupertinoColorTokens.SWITCH_OFF_TRACK,
                CupertinoShapeTokens.ACTION_RADIUS_DP,
                CupertinoColorTokens.INPUT_BORDER,
                CupertinoShapeTokens.CARD_RADIUS_DP,
                CupertinoTypographyTokens.ACTION_LABEL_SP,
                CupertinoSpacingTokens.ACTION_MIN_HEIGHT_DP,
                CupertinoSpacingTokens.ACTION_MIN_WIDTH_DP,
                CupertinoSpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                CupertinoSpacingTokens.ACTION_VERTICAL_PADDING_DP,
                0f,
                CupertinoTypographyTokens.SWITCH_LABEL_SP,
                CupertinoSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP,
                CupertinoSpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                CupertinoTypographyTokens.CHOICE_LABEL_SP,
                CupertinoTypographyTokens.INPUT_LABEL_SP,
                CupertinoSpacingTokens.INPUT_MIN_HEIGHT_DP
        );
    }
}