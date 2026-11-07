package de.privacyguard.adhook;

/**
 * Liquid-glass design tokens for the FX Skin.
 *
 * The Liquid mode owns translucent surfaces, larger geometry and its own
 * typography; it must not inherit Default or any skin's measurements.
 */
final class LiquidSkinTokens {
    private LiquidSkinTokens() { }

    static final class LiquidColorTokens {
        static final int TOP_BAR_BACKGROUND = 0xddefffff;
        static final int CARD_SURFACE = 0xaaffffff;
        static final int CARD_STROKE = 0x66ffffff;
        static final int ROW_RIPPLE = 0x330088ff;
        static final int LIST_ROW_SURFACE = 0xccffffff;
        static final int LIST_ROW_BORDER = 0x55ffffff;
        static final int LIST_ROW_RIPPLE = 0x330088ff;
        static final int BACKGROUND = 0xffe8eef4;
        static final int WALLPAPER_TINT = 0xffe8eef4;
        static final int NAV_SURFACE = 0xccffffff;
        static final int SURFACE = 0xccffffff;
        static final int SURFACE_VARIANT = 0xb3f2f8ff;
        static final int SELECTED_TAB_SURFACE = 0x330088ff;
        static final int DIVIDER = 0x55ffffff;
        static final int PRIMARY_TEXT = 0xff24394c;
        static final int SECONDARY_TEXT = 0xff718091;
        static final int ACCENT = 0xff0088ff;
        static final int ACTION_BACKGROUND = 0xccffffff;
        static final int ACTION_BORDER = 0x66ffffff;
        static final int SWITCH_OFF_TRACK = 0x88c5d0dc;
        static final int INPUT_BORDER = 0x55ffffff;
        static final int EMPTY_STATE_SURFACE = 0x99eff5fb;
        static final int EMPTY_STATE_STROKE = 0x44ffffff;
        static final int EMPTY_STATE_TEXT = 0xff718091;
        static final int LOADING_STATE_SURFACE = 0x990088ff;
        static final int LOADING_STATE_STROKE = 0x550088ff;
        static final int LOADING_STATE_TEXT = 0xff0064c8;
        static final int ERROR_STATE_SURFACE = 0x99ffeaea;
        static final int ERROR_STATE_STROKE = 0x55ff8f8a;
        static final int ERROR_STATE_TEXT = 0xff9b2c2c;
        static final int SUCCESS_STATE_SURFACE = 0x99e9f9ef;
        static final int SUCCESS_STATE_STROKE = 0x5548c98a;
        static final int SUCCESS_STATE_TEXT = 0xff237347;
        private LiquidColorTokens() { }
    }

    static final class LiquidShapeTokens {
        static final int NAV_BAR_RADIUS_DP = 26;
        static final int TAB_RADIUS_DP = 20;
        static final int CARD_RADIUS_DP = 24;
        static final int SECTION_RADIUS_DP = 20;
        static final int ACTION_RADIUS_DP = 24;
        static final int RISK_CERTAIN_SURFACE = 0x99ffeaea;
        static final int RISK_CERTAIN_STROKE = 0x55ff8f8a;
        static final int RISK_CERTAIN_TEXT = 0xff9b2c2c;
        static final int RISK_SUSPECT_SURFACE = 0x99fff4e0;
        static final int RISK_SUSPECT_STROKE = 0x55ffb84d;
        static final int RISK_SUSPECT_TEXT = 0xff7a4b13;
        static final int LIST_ROW_RADIUS_DP = 20;
        private LiquidShapeTokens() { }
    }

    static final class LiquidTypographyTokens {
        static final float TAB_LABEL_SP = 12f;
        static final float PAGE_TITLE_SP = 24f;
        static final float SECTION_TITLE_SP = 16f;
        static final float CARD_TITLE_SP = 17f;
        static final float CARD_DESCRIPTION_SP = 14f;
        static final float ACTION_LABEL_SP = 15f;
        static final float SWITCH_LABEL_SP = 16f;
        static final float CHOICE_LABEL_SP = 15f;
        static final float INPUT_LABEL_SP = 15f;
        static final float SPINNER_LABEL_SP = 15f;
        static final float LIST_ROW_TITLE_SP = 16f;
        static final float LIST_ROW_SUBTITLE_SP = 13f;
        private LiquidTypographyTokens() { }
    }

    static final class LiquidSpacingTokens {
        static final int NAV_HEIGHT_DP = 72;
        static final int NAV_OUTER_HORIZONTAL_DP = 12;
        static final int NAV_OUTER_VERTICAL_DP = 4;
        static final int NAV_INNER_HORIZONTAL_DP = 4;
        static final int NAV_INNER_VERTICAL_DP = 3;
        static final int TAB_HEIGHT_DP = 64;
        static final int ACTION_MIN_HEIGHT_DP = 50;
        static final int ACTION_MIN_WIDTH_DP = 76;
        static final int ACTION_HORIZONTAL_PADDING_DP = 20;
        static final int ACTION_VERTICAL_PADDING_DP = 12;
        static final int SWITCH_HORIZONTAL_PADDING_DP = 20;
        static final int SWITCH_VERTICAL_PADDING_DP = 12;
        static final int INPUT_MIN_HEIGHT_DP = 50;
        static final int SPINNER_HORIZONTAL_PADDING_DP = 18;
        static final int SPINNER_VERTICAL_PADDING_DP = 12;
        static final int TITLE_HORIZONTAL_PADDING_DP = 22;
        static final int TITLE_VERTICAL_PADDING_DP = 14;
        static final int SECTION_HORIZONTAL_PADDING_DP = 20;
        static final int SECTION_VERTICAL_PADDING_DP = 12;
        static final int CARD_HORIZONTAL_PADDING_DP = 18;
        static final int CARD_VERTICAL_PADDING_DP = 14;
        static final int ROW_MIN_HEIGHT_DP = 54;
        static final int LIST_ROW_MIN_HEIGHT_DP = 58;
        static final int LIST_ROW_HORIZONTAL_PADDING_DP = 18;
        static final int LIST_ROW_VERTICAL_PADDING_DP = 12;

        private LiquidSpacingTokens() { }
    }
}
