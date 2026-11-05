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

    /** Apply Harmony presentation to explicitly tagged shared FX components. */
    static void applyTaggedComponent(Activity activity, View view) {
        if (activity == null || view == null || !(view.getTag() instanceof String)) return;
        String role = (String) view.getTag();
        float density = activity.getResources().getDisplayMetrics().density;
        if (role.startsWith("fx-title:") && view instanceof TextView) {
            int requested = parseRequestedSize(role, 18);
            TextView title = (TextView) view;
            title.setTextColor(HarmonyColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    requested >= 22 ? HarmonyTypographyTokens.PAGE_TITLE_SP
                            : Math.max(requested, HarmonyTypographyTokens.SECTION_TITLE_SP));
            title.setLetterSpacing(0.005f);
            title.setPadding(dp(HarmonySpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.TITLE_VERTICAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.TITLE_VERTICAL_PADDING_DP, density));
            if (requested >= 22) {
                title.setBackground(rounded(HarmonyColorTokens.TOP_BAR_BACKGROUND,
                        HarmonyColorTokens.DIVIDER, HarmonyShapeTokens.NAV_BAR_RADIUS_DP, density));
            }
            return;
        }
        if (role.startsWith("fx-section:") && view instanceof TextView) {
            TextView section = (TextView) view;
            section.setTextColor(HarmonyColorTokens.PRIMARY_TEXT);
            section.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            section.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    HarmonyTypographyTokens.SECTION_TITLE_SP);
            section.setLetterSpacing(0.01f);
            section.setPadding(dp(HarmonySpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.SECTION_VERTICAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.SECTION_VERTICAL_PADDING_DP, density));
            section.setBackground(rounded(HarmonyColorTokens.SURFACE_VARIANT,
                    HarmonyColorTokens.DIVIDER, HarmonyShapeTokens.SECTION_RADIUS_DP, density));
            section.setMinimumHeight(dp(HarmonySpacingTokens.ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if (("fx-card".equals(role) || "fx-setting-card".equals(role)) && view instanceof ViewGroup) {
            ViewGroup card = (ViewGroup) view;
            card.setBackground(rounded(HarmonyColorTokens.CARD_SURFACE,
                    HarmonyColorTokens.CARD_STROKE, HarmonyShapeTokens.CARD_RADIUS_DP, density));
            card.setPadding(dp(HarmonySpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-action-row".equals(role) && view instanceof Button) {
            Button action = (Button) view;
            if (FxNativeSkin.shouldPreserveSemanticAction(action)) return;
            action.setAllCaps(false);
            action.setTextColor(HarmonyColorTokens.ACCENT);
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    HarmonyTypographyTokens.ACTION_LABEL_SP);
            action.setMinHeight(dp(HarmonySpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setMinWidth(dp(HarmonySpacingTokens.ACTION_MIN_WIDTH_DP, density));
            action.setPadding(dp(HarmonySpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(HarmonySpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(HarmonyColorTokens.ACTION_BACKGROUND,
                    HarmonyColorTokens.ACTION_BORDER, HarmonyShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, HarmonyShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(HarmonyColorTokens.ROW_RIPPLE), surface, mask));
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
