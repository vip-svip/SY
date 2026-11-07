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

import de.privacyguard.adhook.DefaultSkinTokens.DefaultColorTokens;
import de.privacyguard.adhook.DefaultSkinTokens.DefaultShapeTokens;
import de.privacyguard.adhook.DefaultSkinTokens.DefaultSpacingTokens;
import de.privacyguard.adhook.DefaultSkinTokens.DefaultTypographyTokens;

/** Android View renderer for the dedicated default renderer token set. */
final class DefaultSkinRenderer {
    private DefaultSkinRenderer() { }

    static FxNativeSkin.Palette palette() {
        return new FxNativeSkin.Palette(
                DefaultColorTokens.BACKGROUND,
                DefaultColorTokens.SURFACE,
                DefaultColorTokens.SURFACE_VARIANT,
                DefaultColorTokens.DIVIDER,
                DefaultColorTokens.PRIMARY_TEXT,
                DefaultColorTokens.SECONDARY_TEXT,
                DefaultColorTokens.ACTION_BACKGROUND,
                DefaultColorTokens.ACTION_BORDER,
                DefaultColorTokens.ACCENT,
                DefaultColorTokens.SWITCH_OFF_TRACK,
                DefaultShapeTokens.ACTION_RADIUS_DP,
                DefaultColorTokens.INPUT_BORDER,
                DefaultShapeTokens.CARD_RADIUS_DP,
                DefaultTypographyTokens.ACTION_LABEL_SP,
                DefaultSpacingTokens.ACTION_MIN_HEIGHT_DP,
                DefaultSpacingTokens.ACTION_MIN_WIDTH_DP,
                DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP,
                0f,
                DefaultTypographyTokens.SWITCH_LABEL_SP,
                DefaultSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP,
                DefaultSpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                DefaultTypographyTokens.CHOICE_LABEL_SP,
                DefaultTypographyTokens.INPUT_LABEL_SP,
                DefaultSpacingTokens.INPUT_MIN_HEIGHT_DP
        );
    }

    /** Apply default renderer presentation to explicitly tagged shared FX components. */
    static void applyTaggedComponent(Activity activity, View view, FxUiMode mode) {
        if (activity == null || view == null || mode != FxUiMode.DEFAULT_STANDARD
                || !(view.getTag() instanceof String)) return;
        String role = (String) view.getTag();
        if (!FxNativeSkin.beginTaggedComponentRender(view, mode, role)) return;
        float density = activity.getResources().getDisplayMetrics().density;
        if ("fx-page-root".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackgroundColor(DefaultColorTokens.BACKGROUND);
            return;
        }
        if ("fx-toolbar".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackground(rounded(DefaultColorTokens.TOP_BAR_BACKGROUND,
                    DefaultColorTokens.DIVIDER, DefaultShapeTokens.NAV_BAR_RADIUS_DP, density));
            return;
        }
        if ("fx-toolbar-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.PAGE_TITLE_SP);
            return;
        }
        if ("fx-toolbar-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(DefaultColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(DefaultSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if (role.startsWith("fx-title:") && view instanceof TextView) {
            int requested = parseRequestedSize(role, 18);
            TextView title = (TextView) view;
            title.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    requested >= 22 ? DefaultTypographyTokens.PAGE_TITLE_SP
                            : Math.max(requested, DefaultTypographyTokens.SECTION_TITLE_SP));
            title.setLetterSpacing(0.005f);
            title.setPadding(dp(DefaultSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.TITLE_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.TITLE_VERTICAL_PADDING_DP, density));
            if (requested >= 22) {
                title.setBackground(rounded(DefaultColorTokens.TOP_BAR_BACKGROUND,
                        DefaultColorTokens.DIVIDER, DefaultShapeTokens.NAV_BAR_RADIUS_DP, density));
            }
            return;
        }
        if (role.startsWith("fx-section:") && view instanceof TextView) {
            TextView section = (TextView) view;
            section.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            section.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            section.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.SECTION_TITLE_SP);
            section.setLetterSpacing(0.01f);
            section.setPadding(dp(DefaultSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SECTION_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SECTION_VERTICAL_PADDING_DP, density));
            section.setBackground(rounded(DefaultColorTokens.SURFACE_VARIANT,
                    DefaultColorTokens.DIVIDER, DefaultShapeTokens.SECTION_RADIUS_DP, density));
            section.setMinimumHeight(dp(DefaultSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-select-input".equals(role) && view instanceof Spinner) {
            Spinner select = (Spinner) view;
            select.setMinimumHeight(dp(DefaultSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            select.setPadding(dp(DefaultSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(DefaultColorTokens.SURFACE_VARIANT,
                    DefaultColorTokens.INPUT_BORDER, DefaultShapeTokens.SECTION_RADIUS_DP, density);
            select.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(DefaultColorTokens.ROW_RIPPLE), surface, null));
            select.setPopupBackgroundDrawable(rounded(DefaultColorTokens.SURFACE,
                    DefaultColorTokens.DIVIDER, DefaultShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if (("fx-search-input".equals(role) || "fx-form-input".equals(role)) && view instanceof EditText) {
            EditText input = (EditText) view;
            input.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            input.setHintTextColor(DefaultColorTokens.SECONDARY_TEXT);
            input.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.INPUT_LABEL_SP);
            input.setMinimumHeight(dp(DefaultSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            input.setPadding(dp(DefaultSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(DefaultColorTokens.SURFACE_VARIANT,
                    DefaultColorTokens.INPUT_BORDER, DefaultShapeTokens.SECTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    DefaultShapeTokens.SECTION_RADIUS_DP, density);
            input.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(DefaultColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-action-text".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(DefaultColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(DefaultSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-primary-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            boolean enabled = action.isEnabled();
            int fill = enabled ? DefaultColorTokens.ACCENT : DefaultColorTokens.SURFACE_VARIANT;
            action.setTextColor(enabled ? 0xffffffff : DefaultColorTokens.SECONDARY_TEXT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(DefaultSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(fill,
                    enabled ? 0 : DefaultColorTokens.DIVIDER,
                    DefaultShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    DefaultShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(DefaultColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-card-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.CARD_TITLE_SP);
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
                surface = DefaultColorTokens.ERROR_STATE_SURFACE;
                stroke = DefaultColorTokens.ERROR_STATE_STROKE;
                foreground = DefaultColorTokens.ERROR_STATE_TEXT;
            } else if ("fx-success-state".equals(role)) {
                surface = DefaultColorTokens.SUCCESS_STATE_SURFACE;
                stroke = DefaultColorTokens.SUCCESS_STATE_STROKE;
                foreground = DefaultColorTokens.SUCCESS_STATE_TEXT;
            } else if ("fx-loading-state".equals(role)) {
                surface = DefaultColorTokens.LOADING_STATE_SURFACE;
                stroke = DefaultColorTokens.LOADING_STATE_STROKE;
                foreground = DefaultColorTokens.LOADING_STATE_TEXT;
            } else {
                surface = DefaultColorTokens.EMPTY_STATE_SURFACE;
                stroke = DefaultColorTokens.EMPTY_STATE_STROKE;
                foreground = DefaultColorTokens.EMPTY_STATE_TEXT;
            }
            state.setTextColor(foreground);
            state.setTypeface(Typeface.create("sans-serif-medium",
                    "fx-error-state".equals(role) ? Typeface.BOLD : Typeface.NORMAL));
            state.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    "fx-empty-state".equals(role) ? DefaultTypographyTokens.CARD_DESCRIPTION_SP
                            : DefaultTypographyTokens.LIST_ROW_SUBTITLE_SP);
            state.setLineSpacing(dp(3, density), 1.0f);
            state.setGravity("fx-empty-state".equals(role)
                    ? android.view.Gravity.CENTER
                    : android.view.Gravity.CENTER_VERTICAL | android.view.Gravity.START);
            state.setMinimumHeight(dp("fx-empty-state".equals(role) ? 76 : 52, density));
            state.setPadding(dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            state.setBackground(rounded(surface, stroke,
                    DefaultShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-list-row".equals(role) && view instanceof ViewGroup) {
            ViewGroup row = (ViewGroup) view;
            GradientDrawable surface = rounded(DefaultColorTokens.LIST_ROW_SURFACE,
                    DefaultColorTokens.LIST_ROW_BORDER, DefaultShapeTokens.LIST_ROW_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, DefaultShapeTokens.LIST_ROW_RADIUS_DP, density);
            row.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(DefaultColorTokens.LIST_ROW_RIPPLE), surface, mask));
            row.setPadding(dp(DefaultSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density));
            row.setMinimumHeight(dp(DefaultSpacingTokens.LIST_ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-list-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.LIST_ROW_TITLE_SP);
            return;
        }
        if ("fx-list-subtitle".equals(role) && view instanceof TextView) {
            TextView subtitle = (TextView) view;
            subtitle.setTextColor(DefaultColorTokens.SECONDARY_TEXT);
            subtitle.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            subtitle.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.LIST_ROW_SUBTITLE_SP);
            subtitle.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-risk-certain".equals(role) || "fx-risk-suspect".equals(role))
                && view instanceof ViewGroup) {
            boolean certain = "fx-risk-certain".equals(role);
            ViewGroup risk = (ViewGroup) view;
            risk.setBackground(rounded(
                    certain ? DefaultShapeTokens.RISK_CERTAIN_SURFACE : DefaultShapeTokens.RISK_SUSPECT_SURFACE,
                    certain ? DefaultShapeTokens.RISK_CERTAIN_STROKE : DefaultShapeTokens.RISK_SUSPECT_STROKE,
                    DefaultShapeTokens.CARD_RADIUS_DP, density));
            risk.setPadding(dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if (("fx-risk-title-certain".equals(role) || "fx-risk-title-suspect".equals(role))
                && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor("fx-risk-title-certain".equals(role)
                    ? DefaultShapeTokens.RISK_CERTAIN_TEXT : DefaultShapeTokens.RISK_SUSPECT_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.CARD_TITLE_SP);
            title.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-card".equals(role) || "fx-card-group".equals(role) || "fx-setting-card".equals(role)) && view instanceof ViewGroup) {
            ViewGroup card = (ViewGroup) view;
            card.setBackground(rounded(DefaultColorTokens.CARD_SURFACE,
                    DefaultColorTokens.CARD_STROKE, DefaultShapeTokens.CARD_RADIUS_DP, density));
            card.setPadding(dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-switch-row".equals(role) && view instanceof android.widget.CompoundButton) {
            android.widget.CompoundButton row = (android.widget.CompoundButton) view;
            row.setTextColor(DefaultColorTokens.PRIMARY_TEXT);
            row.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.SWITCH_LABEL_SP);
            row.setMinimumHeight(dp(DefaultSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            row.setPadding(dp(DefaultSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density));
            row.setBackground(rounded(DefaultColorTokens.CARD_SURFACE,
                    DefaultColorTokens.CARD_STROKE, DefaultShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-action-row".equals(role) && view instanceof Button) {
            Button action = (Button) view;
            if (FxNativeSkin.shouldPreserveSemanticAction(action)) return;
            action.setAllCaps(false);
            action.setTextColor(DefaultColorTokens.ACCENT);
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    DefaultTypographyTokens.ACTION_LABEL_SP);
            action.setMinHeight(dp(DefaultSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setMinWidth(dp(DefaultSpacingTokens.ACTION_MIN_WIDTH_DP, density));
            action.setPadding(dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(DefaultSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(DefaultColorTokens.ACTION_BACKGROUND,
                    DefaultColorTokens.ACTION_BORDER, DefaultShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, DefaultShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(DefaultColorTokens.ROW_RIPPLE), surface, mask));
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
