package de.privacyguard.adhook;

/**
 * Default-mode design tokens for the FX Skin.
 *
 * Default is the independent renderer required by the six-mode contract: it owns
 * its own colour, geometry, typography and spacing declarations instead of reusing
 * a skin's palette, so changing any skin can never alter Default presentation.
 */
final class DefaultSkinTokens {
    private DefaultSkinTokens() { }

    static final class DefaultColorTokens {
        static final int TOP_BAR_BACKGROUND = 0xffffffff;
        static final int CARD_SURFACE = 0xffffffff;
        static final int CARD_STROKE = 0xffe1e7ef;
        static final int ROW_RIPPLE = 0x1a315b9a;
        static final int LIST_ROW_SURFACE = 0xffffffff;
        static final int LIST_ROW_BORDER = 0xffe1e7ef;
        static final int LIST_ROW_RIPPLE = 0x1a315b9a;
        static final int BACKGROUND = 0xfff7f8fc;
        static final int WALLPAPER_TINT = 0xfff7f8fc;
        static final int NAV_SURFACE = 0xffffffff;
        static final int SURFACE = 0xffffffff;
        static final int SURFACE_VARIANT = 0xffedf1f7;
        static final int SELECTED_TAB_SURFACE = 0x1f315b9a;
        static final int DIVIDER = 0xffdce3ed;
        static final int PRIMARY_TEXT = 0xff1c2938;
        static final int SECONDARY_TEXT = 0xff647386;
        static final int ACCENT = 0xff315b9a;
        static final int ACTION_BACKGROUND = 0xffe8eef6;
        static final int ACTION_BORDER = 0xffd4deeb;
        static final int SWITCH_OFF_TRACK = 0xffc4ceda;
        static final int INPUT_BORDER = 0xffc2cddb;
        static final int EMPTY_STATE_SURFACE = 0xffeef2f8;
        static final int EMPTY_STATE_STROKE = 0xffdbe3ee;
        static final int EMPTY_STATE_TEXT = 0xff647386;
        static final int LOADING_STATE_SURFACE = 0xffeaf1fb;
        static final int LOADING_STATE_STROKE = 0xffc9d9ef;
        static final int LOADING_STATE_TEXT = 0xff315b9a;
        static final int ERROR_STATE_SURFACE = 0xfffdf0ef;
        static final int ERROR_STATE_STROKE = 0xffefb7b3;
        static final int ERROR_STATE_TEXT = 0xff9b2c2c;
        static final int SUCCESS_STATE_SURFACE = 0xffeef8f1;
        static final int SUCCESS_STATE_STROKE = 0xffb8ddc7;
        static final int SUCCESS_STATE_TEXT = 0xff237347;
        private DefaultColorTokens() { }
    }

    static final class DefaultShapeTokens {
        static final int NAV_BAR_RADIUS_DP = 18;
        static final int TAB_RADIUS_DP = 14;
        static final int CARD_RADIUS_DP = 18;
        static final int SECTION_RADIUS_DP = 14;
        static final int ACTION_RADIUS_DP = 16;
        static final int RISK_CERTAIN_SURFACE = 0xfffdeceb;
        static final int RISK_CERTAIN_STROKE = 0xffeeb4b0;
        static final int RISK_CERTAIN_TEXT = 0xff9b2c2c;
        static final int RISK_SUSPECT_SURFACE = 0xfffff6e8;
        static final int RISK_SUSPECT_STROKE = 0xffedd39e;
        static final int RISK_SUSPECT_TEXT = 0xff7a4b13;
        static final int LIST_ROW_RADIUS_DP = 14;
        private DefaultShapeTokens() { }
    }

    static final class DefaultTypographyTokens {
        static final float TAB_LABEL_SP = 13f;
        static final float PAGE_TITLE_SP = 22f;
        static final float SECTION_TITLE_SP = 15f;
        static final float CARD_TITLE_SP = 16f;
        static final float CARD_DESCRIPTION_SP = 13f;
        static final float ACTION_LABEL_SP = 14f;
        static final float SWITCH_LABEL_SP = 15f;
        static final float CHOICE_LABEL_SP = 15f;
        static final float INPUT_LABEL_SP = 15f;
        static final float SPINNER_LABEL_SP = 15f;
        static final float LIST_ROW_TITLE_SP = 15f;
        static final float LIST_ROW_SUBTITLE_SP = 12f;
        private DefaultTypographyTokens() { }
    }

    static final class DefaultSpacingTokens {
        static final int NAV_HEIGHT_DP = 66;
        static final int NAV_OUTER_HORIZONTAL_DP = 8;
        static final int NAV_OUTER_VERTICAL_DP = 4;
        static final int NAV_INNER_HORIZONTAL_DP = 4;
        static final int NAV_INNER_VERTICAL_DP = 3;
        static final int TAB_HEIGHT_DP = 58;
        static final int ACTION_MIN_HEIGHT_DP = 46;
        static final int ACTION_MIN_WIDTH_DP = 64;
        static final int ACTION_HORIZONTAL_PADDING_DP = 16;
        static final int ACTION_VERTICAL_PADDING_DP = 10;
        static final int SWITCH_HORIZONTAL_PADDING_DP = 16;
        static final int SWITCH_VERTICAL_PADDING_DP = 10;
        static final int INPUT_MIN_HEIGHT_DP = 46;
        static final int SPINNER_HORIZONTAL_PADDING_DP = 14;
        static final int SPINNER_VERTICAL_PADDING_DP = 10;
        static final int TITLE_HORIZONTAL_PADDING_DP = 18;
        static final int TITLE_VERTICAL_PADDING_DP = 12;
        static final int SECTION_HORIZONTAL_PADDING_DP = 16;
        static final int SECTION_VERTICAL_PADDING_DP = 10;
        static final int CARD_HORIZONTAL_PADDING_DP = 16;
        static final int CARD_VERTICAL_PADDING_DP = 12;
        static final int ROW_MIN_HEIGHT_DP = 48;
        static final int LIST_ROW_MIN_HEIGHT_DP = 52;
        static final int LIST_ROW_HORIZONTAL_PADDING_DP = 16;
        static final int LIST_ROW_VERTICAL_PADDING_DP = 10;

        private DefaultSpacingTokens() { }
    }
}
