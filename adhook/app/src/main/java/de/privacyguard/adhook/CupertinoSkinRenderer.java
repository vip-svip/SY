package de.privacyguard.adhook;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.TextView;

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

    /** Apply Cupertino presentation to explicitly tagged shared FX components. */
    static void applyTaggedComponent(Activity activity, View view) {
        if (activity == null || view == null || !(view.getTag() instanceof String)) return;
        String role = (String) view.getTag();
        float density = activity.getResources().getDisplayMetrics().density;
        if (role.startsWith("fx-title:") && view instanceof TextView) {
            int requested = parseRequestedSize(role, 18);
            TextView title = (TextView) view;
            title.setTextColor(CupertinoColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    requested >= 22 ? CupertinoTypographyTokens.PAGE_TITLE_SP
                            : Math.max(requested, CupertinoTypographyTokens.SECTION_TITLE_SP));
            title.setLetterSpacing(0f);
            title.setPadding(dp(CupertinoSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.TITLE_VERTICAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.TITLE_VERTICAL_PADDING_DP, density));
            if (requested >= 22) {
                title.setBackground(rounded(CupertinoColorTokens.TOP_BAR_BACKGROUND,
                        CupertinoColorTokens.DIVIDER, CupertinoShapeTokens.NAV_BAR_RADIUS_DP, density));
            }
            return;
        }
        if (role.startsWith("fx-section:") && view instanceof TextView) {
            TextView section = (TextView) view;
            section.setTextColor(CupertinoColorTokens.PRIMARY_TEXT);
            section.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            section.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.SECTION_TITLE_SP);
            section.setLetterSpacing(-0.005f);
            section.setPadding(dp(CupertinoSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SECTION_VERTICAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SECTION_VERTICAL_PADDING_DP, density));
            section.setBackground(rounded(CupertinoColorTokens.SURFACE_VARIANT,
                    CupertinoColorTokens.DIVIDER, CupertinoShapeTokens.SECTION_RADIUS_DP, density));
            section.setMinimumHeight(dp(CupertinoSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-card-title".equals(role) && view instanceof TextView) {
            TextView heading = (TextView) view;
            heading.setTextColor(CupertinoColorTokens.PRIMARY_TEXT);
            heading.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            heading.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.CARD_TITLE_SP);
            return;
        }
        if ("fx-card-body".equals(role) && view instanceof TextView) {
            TextView detail = (TextView) view;
            detail.setTextColor(CupertinoColorTokens.SECONDARY_TEXT);
            detail.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 13f);
            detail.setLineSpacing(dp(2, density), 1.05f);
            return;
        }
        if ("fx-card-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(CupertinoColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.CARD_TITLE_SP);
            title.setLetterSpacing(-0.005f);
            return;
        }
        if (("fx-card-detail".equals(role) || "fx-card-body".equals(role)) && view instanceof TextView) {
            TextView detail = (TextView) view;
            detail.setTextColor(CupertinoColorTokens.SECONDARY_TEXT);
            detail.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            detail.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.CARD_DESCRIPTION_SP);
            detail.setLineSpacing(dp(1, density), 1.0f);
            detail.setPadding(0, dp(4, density), 0, dp(6, density));
            return;
        }
        if (("fx-card".equals(role) || "fx-setting-card".equals(role)) && view instanceof ViewGroup) {
            ViewGroup card = (ViewGroup) view;
            card.setBackground(rounded(CupertinoColorTokens.CARD_SURFACE,
                    CupertinoColorTokens.CARD_STROKE, CupertinoShapeTokens.CARD_RADIUS_DP, density));
            card.setPadding(dp(CupertinoSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-switch-row".equals(role) && view instanceof android.widget.Switch) {
            android.widget.Switch row = (android.widget.Switch) view;
            row.setTextColor(CupertinoColorTokens.PRIMARY_TEXT);
            row.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.SWITCH_LABEL_SP);
            row.setMinimumHeight(dp(CupertinoSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            row.setPadding(dp(CupertinoSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density));
            row.setBackground(rounded(CupertinoColorTokens.CARD_SURFACE,
                    CupertinoColorTokens.CARD_STROKE, CupertinoShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-action-row".equals(role) && view instanceof Button) {
            Button action = (Button) view;
            if (FxNativeSkin.shouldPreserveSemanticAction(action)) return;
            action.setAllCaps(false);
            action.setTextColor(CupertinoColorTokens.ACCENT);
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    CupertinoTypographyTokens.ACTION_LABEL_SP);
            action.setMinHeight(dp(CupertinoSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setMinWidth(dp(CupertinoSpacingTokens.ACTION_MIN_WIDTH_DP, density));
            action.setPadding(dp(CupertinoSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(CupertinoSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(CupertinoColorTokens.ACTION_BACKGROUND,
                    CupertinoColorTokens.ACTION_BORDER, CupertinoShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, CupertinoShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(CupertinoColorTokens.ROW_RIPPLE), surface, mask));
        }
    }

    private static int parseRequestedSize(String role, int fallback) {
        try {
            return Integer.parseInt(role.substring("fx-title:".length()));
        } catch (RuntimeException ignored) {
            return fallback;
        }
    }

    private static int dp(int value, float density) {
        return Math.round(value * density);
    }

    private static GradientDrawable rounded(int color, int strokeColor, int radiusDp, float density) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp, density));
        if ((strokeColor >>> 24) != 0) {
            drawable.setStroke(Math.max(1, dp(1, density)), strokeColor);
        }
        return drawable;
    }
}
