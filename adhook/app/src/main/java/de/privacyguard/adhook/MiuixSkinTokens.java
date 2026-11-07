package de.privacyguard.adhook;

/**
 * Miuix (HyperOS) design tokens for the FX Skin.
 *
 * Miuix keeps its own HyperOS-flavoured palette, geometry and typography. The
 * Compose shell already consumes the vendored Miuix theme; this Android-View token
 * set keeps the native pages on the same HyperOS measurements.
 */
final class MiuixSkinTokens {
    private MiuixSkinTokens() { }

    static final class MiuixColorTokens {
        static final int TOP_BAR_BACKGROUND = 0xfff8f9fd;
        static final int CARD_SURFACE = 0xffeaf0fb;
        static final int CARD_STROKE = 0x223478f6;
        static final int ROW_RIPPLE = 0x223478f6;
        static final int LIST_ROW_SURFACE = 0xffeff3fb;
        static final int LIST_ROW_BORDER = 0x223478f6;
        static final int LIST_ROW_RIPPLE = 0x223478f6;
        static final int BACKGROUND = 0xfff3f5fa;
        static final int WALLPAPER_TINT = 0xfff3f5fa;
        static final int NAV_SURFACE = 0xfff8f9fd;
        static final int SURFACE = 0xffeaf0fb;
        static final int SURFACE_VARIANT = 0xffe5ecf8;
        static final int SELECTED_TAB_SURFACE = 0x333478f6;
        static final int DIVIDER = 0x223478f6;
        static final int PRIMARY_TEXT = 0xff202b3c;
        static final int SECONDARY_TEXT = 0xff718091;
        static final int ACCENT = 0xff3478f6;
        static final int ACTION_BACKGROUND = 0xffe5ecf8;
        static final int ACTION_BORDER = 0xffd8e1ef;
        static final int SWITCH_OFF_TRACK = 0xffc3ccda;
        static final int INPUT_BORDER = 0xffccd7e8;
        static final int EMPTY_STATE_SURFACE = 0xffedf2fb;
        static final int EMPTY_STATE_STROKE = 0xffd7e2f3;
        static final int EMPTY_STATE_TEXT = 0xff718091;
        static final int LOADING_STATE_SURFACE = 0xffe6eefc;
        static final int LOADING_STATE_STROKE = 0xffc3d6f5;
        static final int LOADING_STATE_TEXT = 0xff3478f6;
        static final int ERROR_STATE_SURFACE = 0xfffdeeed;
        static final int ERROR_STATE_STROKE = 0xffefb7b3;
        static final int ERROR_STATE_TEXT = 0xffa12d2d;
        static final int SUCCESS_STATE_SURFACE = 0xffebf7f0;
        static final int SUCCESS_STATE_STROKE = 0xffb8ddc7;
        static final int SUCCESS_STATE_TEXT = 0xff24734a;
        private MiuixColorTokens() { }
    }

    static final class MiuixShapeTokens {
        static final int NAV_BAR_RADIUS_DP = 20;
        static final int TAB_RADIUS_DP = 18;
        static final int CARD_RADIUS_DP = 22;
        static final int SECTION_RADIUS_DP = 16;
        static final int ACTION_RADIUS_DP = 22;
        static final int RISK_CERTAIN_SURFACE = 0xfffdecec;
        static final int RISK_CERTAIN_STROKE = 0xffefb7b3;
        static final int RISK_CERTAIN_TEXT = 0xffa12d2d;
        static final int RISK_SUSPECT_SURFACE = 0xfffff6e8;
        static final int RISK_SUSPECT_STROKE = 0xffedd39e;
        static final int RISK_SUSPECT_TEXT = 0xff79552b;
        static final int LIST_ROW_RADIUS_DP = 18;
        private MiuixShapeTokens() { }
    }

    static final class MiuixTypographyTokens {
        static final float TAB_LABEL_SP = 14f;
        static final float PAGE_TITLE_SP = 22f;
        static final float SECTION_TITLE_SP = 15f;
        static final float CARD_TITLE_SP = 16.5f;
        static final float CARD_DESCRIPTION_SP = 13.5f;
        static final float ACTION_LABEL_SP = 14.5f;
        static final float SWITCH_LABEL_SP = 15.5f;
        static final float CHOICE_LABEL_SP = 15f;
        static final float INPUT_LABEL_SP = 15f;
        static final float SPINNER_LABEL_SP = 15f;
        static final float LIST_ROW_TITLE_SP = 15.5f;
        static final float LIST_ROW_SUBTITLE_SP = 12.5f;
        private MiuixTypographyTokens() { }
    }

    static final class MiuixSpacingTokens {
        static final int NAV_HEIGHT_DP = 68;
        static final int NAV_OUTER_HORIZONTAL_DP = 10;
        static final int NAV_OUTER_VERTICAL_DP = 4;
        static final int NAV_INNER_HORIZONTAL_DP = 4;
        static final int NAV_INNER_VERTICAL_DP = 3;
        static final int TAB_HEIGHT_DP = 62;
        static final int ACTION_MIN_HEIGHT_DP = 48;
        static final int ACTION_MIN_WIDTH_DP = 72;
        static final int ACTION_HORIZONTAL_PADDING_DP = 18;
        static final int ACTION_VERTICAL_PADDING_DP = 10;
        static final int SWITCH_HORIZONTAL_PADDING_DP = 18;
        static final int SWITCH_VERTICAL_PADDING_DP = 11;
        static final int INPUT_MIN_HEIGHT_DP = 48;
        static final int SPINNER_HORIZONTAL_PADDING_DP = 16;
        static final int SPINNER_VERTICAL_PADDING_DP = 10;
        static final int TITLE_HORIZONTAL_PADDING_DP = 20;
        static final int TITLE_VERTICAL_PADDING_DP = 12;
        static final int SECTION_HORIZONTAL_PADDING_DP = 18;
        static final int SECTION_VERTICAL_PADDING_DP = 11;
        static final int CARD_HORIZONTAL_PADDING_DP = 16;
        static final int CARD_VERTICAL_PADDING_DP = 13;
        static final int ROW_MIN_HEIGHT_DP = 50;
        static final int LIST_ROW_MIN_HEIGHT_DP = 54;
        static final int LIST_ROW_HORIZONTAL_PADDING_DP = 16;
        static final int LIST_ROW_VERTICAL_PADDING_DP = 11;

        private MiuixSpacingTokens() { }
    }
}
