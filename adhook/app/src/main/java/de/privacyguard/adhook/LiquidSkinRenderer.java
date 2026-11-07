package de.privacyguard.adhook;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Spinner;

import de.privacyguard.adhook.LiquidSkinTokens.LiquidColorTokens;
import de.privacyguard.adhook.LiquidSkinTokens.LiquidShapeTokens;
import de.privacyguard.adhook.LiquidSkinTokens.LiquidSpacingTokens;
import de.privacyguard.adhook.LiquidSkinTokens.LiquidTypographyTokens;

/** Android View renderer for the dedicated liquid-glass renderer token set. */
final class LiquidSkinRenderer {
    private LiquidSkinRenderer() { }

    static FxNativeSkin.Palette palette() {
        return new FxNativeSkin.Palette(
                LiquidColorTokens.BACKGROUND,
                LiquidColorTokens.SURFACE,
                LiquidColorTokens.SURFACE_VARIANT,
                LiquidColorTokens.DIVIDER,
                LiquidColorTokens.PRIMARY_TEXT,
                LiquidColorTokens.SECONDARY_TEXT,
                LiquidColorTokens.ACTION_BACKGROUND,
                LiquidColorTokens.ACTION_BORDER,
                LiquidColorTokens.ACCENT,
                LiquidColorTokens.SWITCH_OFF_TRACK,
                LiquidShapeTokens.ACTION_RADIUS_DP,
                LiquidColorTokens.INPUT_BORDER,
                LiquidShapeTokens.CARD_RADIUS_DP,
                LiquidTypographyTokens.ACTION_LABEL_SP,
                LiquidSpacingTokens.ACTION_MIN_HEIGHT_DP,
                LiquidSpacingTokens.ACTION_MIN_WIDTH_DP,
                LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP,
                0f,
                LiquidTypographyTokens.SWITCH_LABEL_SP,
                LiquidSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP,
                LiquidSpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                LiquidTypographyTokens.CHOICE_LABEL_SP,
                LiquidTypographyTokens.INPUT_LABEL_SP,
                LiquidSpacingTokens.INPUT_MIN_HEIGHT_DP
        );
    }

    /** Apply liquid-glass renderer presentation to explicitly tagged shared FX components. */
    static void applyTaggedComponent(Activity activity, View view, FxUiMode mode) {
        if (activity == null || view == null || mode != FxUiMode.FX_LIQUID_NATIVE
                || !(view.getTag() instanceof String)) return;
        String role = (String) view.getTag();
        if (!FxNativeSkin.beginTaggedComponentRender(view, mode, role)) return;
        float density = activity.getResources().getDisplayMetrics().density;
        if ("fx-page-root".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackgroundColor(LiquidColorTokens.BACKGROUND);
            return;
        }
        if ("fx-toolbar".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackground(rounded(LiquidColorTokens.TOP_BAR_BACKGROUND,
                    LiquidColorTokens.DIVIDER, LiquidShapeTokens.NAV_BAR_RADIUS_DP, density));
            return;
        }
        if ("fx-toolbar-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.PAGE_TITLE_SP);
            return;
        }
        if ("fx-toolbar-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(LiquidColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(LiquidSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if (role.startsWith("fx-title:") && view instanceof TextView) {
            int requested = parseRequestedSize(role, 18);
            TextView title = (TextView) view;
            title.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    requested >= 22 ? LiquidTypographyTokens.PAGE_TITLE_SP
                            : Math.max(requested, LiquidTypographyTokens.SECTION_TITLE_SP));
            title.setLetterSpacing(0.005f);
            title.setPadding(dp(LiquidSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.TITLE_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.TITLE_VERTICAL_PADDING_DP, density));
            if (requested >= 22) {
                title.setBackground(rounded(LiquidColorTokens.TOP_BAR_BACKGROUND,
                        LiquidColorTokens.DIVIDER, LiquidShapeTokens.NAV_BAR_RADIUS_DP, density));
            }
            return;
        }
        if (role.startsWith("fx-section:") && view instanceof TextView) {
            TextView section = (TextView) view;
            section.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            section.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            section.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.SECTION_TITLE_SP);
            section.setLetterSpacing(0.01f);
            section.setPadding(dp(LiquidSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SECTION_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SECTION_VERTICAL_PADDING_DP, density));
            section.setBackground(rounded(LiquidColorTokens.SURFACE_VARIANT,
                    LiquidColorTokens.DIVIDER, LiquidShapeTokens.SECTION_RADIUS_DP, density));
            section.setMinimumHeight(dp(LiquidSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-select-input".equals(role) && view instanceof Spinner) {
            Spinner select = (Spinner) view;
            select.setMinimumHeight(dp(LiquidSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            select.setPadding(dp(LiquidSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(LiquidColorTokens.SURFACE_VARIANT,
                    LiquidColorTokens.INPUT_BORDER, LiquidShapeTokens.SECTION_RADIUS_DP, density);
            select.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(LiquidColorTokens.ROW_RIPPLE), surface, null));
            select.setPopupBackgroundDrawable(rounded(LiquidColorTokens.SURFACE,
                    LiquidColorTokens.DIVIDER, LiquidShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if (("fx-search-input".equals(role) || "fx-form-input".equals(role)) && view instanceof EditText) {
            EditText input = (EditText) view;
            input.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            input.setHintTextColor(LiquidColorTokens.SECONDARY_TEXT);
            input.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.INPUT_LABEL_SP);
            input.setMinimumHeight(dp(LiquidSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            input.setPadding(dp(LiquidSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(LiquidColorTokens.SURFACE_VARIANT,
                    LiquidColorTokens.INPUT_BORDER, LiquidShapeTokens.SECTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    LiquidShapeTokens.SECTION_RADIUS_DP, density);
            input.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(LiquidColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-action-text".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(LiquidColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(LiquidSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-primary-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            boolean enabled = action.isEnabled();
            int fill = enabled ? LiquidColorTokens.ACCENT : LiquidColorTokens.SURFACE_VARIANT;
            action.setTextColor(enabled ? 0xffffffff : LiquidColorTokens.SECONDARY_TEXT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(LiquidSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(fill,
                    enabled ? 0 : LiquidColorTokens.DIVIDER,
                    LiquidShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    LiquidShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(LiquidColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-card-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.CARD_TITLE_SP);
            title.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-empty-state".equals(role) || "fx-loading-state".equals(role)
                || "fx-error-state".equals(role) || "fx-success-state".equals(role))
                && view instanceof TextView) {
            TextView state = (TextView) view;
            int surface;
            int stroke;
            int foreground;
            if ("fx-error-state".equals(role)) {
                surface = LiquidColorTokens.ERROR_STATE_SURFACE;
                stroke = LiquidColorTokens.ERROR_STATE_STROKE;
                foreground = LiquidColorTokens.ERROR_STATE_TEXT;
            } else if ("fx-success-state".equals(role)) {
                surface = LiquidColorTokens.SUCCESS_STATE_SURFACE;
                stroke = LiquidColorTokens.SUCCESS_STATE_STROKE;
                foreground = LiquidColorTokens.SUCCESS_STATE_TEXT;
            } else if ("fx-loading-state".equals(role)) {
                surface = LiquidColorTokens.LOADING_STATE_SURFACE;
                stroke = LiquidColorTokens.LOADING_STATE_STROKE;
                foreground = LiquidColorTokens.LOADING_STATE_TEXT;
            } else {
                surface = LiquidColorTokens.EMPTY_STATE_SURFACE;
                stroke = LiquidColorTokens.EMPTY_STATE_STROKE;
                foreground = LiquidColorTokens.EMPTY_STATE_TEXT;
            }
            state.setTextColor(foreground);
            state.setTypeface(Typeface.create("sans-serif-medium",
                    "fx-error-state".equals(role) ? Typeface.BOLD : Typeface.NORMAL));
            state.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    "fx-empty-state".equals(role) ? LiquidTypographyTokens.CARD_DESCRIPTION_SP
                            : LiquidTypographyTokens.LIST_ROW_SUBTITLE_SP);
            state.setLineSpacing(dp(3, density), 1.0f);
            state.setGravity("fx-empty-state".equals(role)
                    ? android.view.Gravity.CENTER
                    : android.view.Gravity.CENTER_VERTICAL | android.view.Gravity.START);
            state.setMinimumHeight(dp("fx-empty-state".equals(role) ? 76 : 52, density));
            state.setPadding(dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            state.setBackground(rounded(surface, stroke,
                    LiquidShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-list-row".equals(role) && view instanceof ViewGroup) {
            ViewGroup row = (ViewGroup) view;
            GradientDrawable surface = rounded(LiquidColorTokens.LIST_ROW_SURFACE,
                    LiquidColorTokens.LIST_ROW_BORDER, LiquidShapeTokens.LIST_ROW_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, LiquidShapeTokens.LIST_ROW_RADIUS_DP, density);
            row.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(LiquidColorTokens.LIST_ROW_RIPPLE), surface, mask));
            row.setPadding(dp(LiquidSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density));
            row.setMinimumHeight(dp(LiquidSpacingTokens.LIST_ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-list-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.LIST_ROW_TITLE_SP);
            return;
        }
        if ("fx-list-subtitle".equals(role) && view instanceof TextView) {
            TextView subtitle = (TextView) view;
            subtitle.setTextColor(LiquidColorTokens.SECONDARY_TEXT);
            subtitle.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            subtitle.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.LIST_ROW_SUBTITLE_SP);
            subtitle.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-risk-certain".equals(role) || "fx-risk-suspect".equals(role))
                && view instanceof ViewGroup) {
            boolean certain = "fx-risk-certain".equals(role);
            ViewGroup risk = (ViewGroup) view;
            risk.setBackground(rounded(
                    certain ? LiquidShapeTokens.RISK_CERTAIN_SURFACE : LiquidShapeTokens.RISK_SUSPECT_SURFACE,
                    certain ? LiquidShapeTokens.RISK_CERTAIN_STROKE : LiquidShapeTokens.RISK_SUSPECT_STROKE,
                    LiquidShapeTokens.CARD_RADIUS_DP, density));
            risk.setPadding(dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if (("fx-risk-title-certain".equals(role) || "fx-risk-title-suspect".equals(role))
                && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor("fx-risk-title-certain".equals(role)
                    ? LiquidShapeTokens.RISK_CERTAIN_TEXT : LiquidShapeTokens.RISK_SUSPECT_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.CARD_TITLE_SP);
            title.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-card".equals(role) || "fx-card-group".equals(role) || "fx-setting-card".equals(role)) && view instanceof ViewGroup) {
            ViewGroup card = (ViewGroup) view;
            card.setBackground(rounded(LiquidColorTokens.CARD_SURFACE,
                    LiquidColorTokens.CARD_STROKE, LiquidShapeTokens.CARD_RADIUS_DP, density));
            card.setPadding(dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-switch-row".equals(role) && view instanceof android.widget.CompoundButton) {
            android.widget.CompoundButton row = (android.widget.CompoundButton) view;
            row.setTextColor(LiquidColorTokens.PRIMARY_TEXT);
            row.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.SWITCH_LABEL_SP);
            row.setMinimumHeight(dp(LiquidSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            row.setPadding(dp(LiquidSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density));
            row.setBackground(rounded(LiquidColorTokens.CARD_SURFACE,
                    LiquidColorTokens.CARD_STROKE, LiquidShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-action-row".equals(role) && view instanceof Button) {
            Button action = (Button) view;
            if (FxNativeSkin.shouldPreserveSemanticAction(action)) return;
            action.setAllCaps(false);
            action.setTextColor(LiquidColorTokens.ACCENT);
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    LiquidTypographyTokens.ACTION_LABEL_SP);
            action.setMinHeight(dp(LiquidSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setMinWidth(dp(LiquidSpacingTokens.ACTION_MIN_WIDTH_DP, density));
            action.setPadding(dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(LiquidSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(LiquidColorTokens.ACTION_BACKGROUND,
                    LiquidColorTokens.ACTION_BORDER, LiquidShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, LiquidShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(LiquidColorTokens.ROW_RIPPLE), surface, mask));
        }
    }

    /** Description-role alias: imported pages tag both body and detail variants. */
    static boolean handlesDescriptionRole(String role) {
        return "fx-card-detail".equals(role) || "fx-card-body".equals(role);
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
