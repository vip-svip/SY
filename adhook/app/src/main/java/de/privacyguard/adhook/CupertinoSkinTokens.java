package de.privacyguard.adhook;

/**
 * Cupertino-inspired design tokens for the Android FX Skin.
 * Uses original FX values and Android components; no Apple assets are bundled.
 */
final class CupertinoSkinTokens {
    private CupertinoSkinTokens() { }

    static final class CupertinoColorTokens {
        static final int BACKGROUND = 0xfff2f2f7;
        static final int WALLPAPER_TINT = 0xffffffff;
        static final int NAV_SURFACE = 0xf9ffffff;
        static final int SURFACE = 0xeaffffff;
        static final int SURFACE_VARIANT = 0xffe5e5ea;
        static final int DIVIDER = 0x1f8e8e93;
        static final int SELECTED_TAB_SURFACE = 0x1a007aff;
        static final int PRIMARY_TEXT = 0xff1c1c1e;
        static final int SECONDARY_TEXT = 0xff6c6c70;
        static final int ACCENT = 0xff007aff;
        static final int ACTION_BACKGROUND = 0xffe5e5ea;
        static final int ACTION_BORDER = 0x1f8e8e93;
        static final int SWITCH_OFF_TRACK = 0xffd1d1d6;
        static final int INPUT_BORDER = 0xffc6c6cc;
        private CupertinoColorTokens() { }
    }

    static final class CupertinoShapeTokens {
        static final int NAV_BAR_RADIUS_DP = 24;
        static final int TAB_RADIUS_DP = 18;
        static final int CARD_RADIUS_DP = 16;
        static final int ACTION_RADIUS_DP = 18;
        private CupertinoShapeTokens() { }
    }

    static final class CupertinoTypographyTokens {
        static final float TAB_LABEL_SP = 13f;
        static final float ACTION_LABEL_SP = 15f;
        static final float SWITCH_LABEL_SP = 16f;
        private CupertinoTypographyTokens() { }
    }

    static final class CupertinoSpacingTokens {
        static final int NAV_HEIGHT_DP = 76;
        static final int NAV_OUTER_HORIZONTAL_DP = 0;
        static final int NAV_OUTER_VERTICAL_DP = 0;
        static final int NAV_INNER_HORIZONTAL_DP = 12;
        static final int NAV_INNER_VERTICAL_DP = 5;
        static final int TAB_HEIGHT_DP = 68;
        private CupertinoSpacingTokens() { }
    }
}