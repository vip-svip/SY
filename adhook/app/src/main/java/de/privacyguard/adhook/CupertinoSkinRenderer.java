package de.privacyguard.adhook;

import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoColorTokens;
import de.privacyguard.adhook.CupertinoSkinTokens.CupertinoShapeTokens;

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
                CupertinoShapeTokens.CARD_RADIUS_DP
        );
    }
}