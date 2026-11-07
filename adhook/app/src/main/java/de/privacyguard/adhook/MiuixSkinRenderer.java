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

import de.privacyguard.adhook.MiuixSkinTokens.MiuixColorTokens;
import de.privacyguard.adhook.MiuixSkinTokens.MiuixShapeTokens;
import de.privacyguard.adhook.MiuixSkinTokens.MiuixSpacingTokens;
import de.privacyguard.adhook.MiuixSkinTokens.MiuixTypographyTokens;

/** Android View renderer for the dedicated Miuix renderer token set. */
final class MiuixSkinRenderer {
    private MiuixSkinRenderer() { }

    static FxNativeSkin.Palette palette() {
        return new FxNativeSkin.Palette(
                MiuixColorTokens.BACKGROUND,
                MiuixColorTokens.SURFACE,
                MiuixColorTokens.SURFACE_VARIANT,
                MiuixColorTokens.DIVIDER,
                MiuixColorTokens.PRIMARY_TEXT,
                MiuixColorTokens.SECONDARY_TEXT,
                MiuixColorTokens.ACTION_BACKGROUND,
                MiuixColorTokens.ACTION_BORDER,
                MiuixColorTokens.ACCENT,
                MiuixColorTokens.SWITCH_OFF_TRACK,
                MiuixShapeTokens.ACTION_RADIUS_DP,
                MiuixColorTokens.INPUT_BORDER,
                MiuixShapeTokens.CARD_RADIUS_DP,
                MiuixTypographyTokens.ACTION_LABEL_SP,
                MiuixSpacingTokens.ACTION_MIN_HEIGHT_DP,
                MiuixSpacingTokens.ACTION_MIN_WIDTH_DP,
                MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP,
                MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP,
                0f,
                MiuixTypographyTokens.SWITCH_LABEL_SP,
                MiuixSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP,
                MiuixSpacingTokens.SWITCH_VERTICAL_PADDING_DP,
                MiuixTypographyTokens.CHOICE_LABEL_SP,
                MiuixTypographyTokens.INPUT_LABEL_SP,
                MiuixSpacingTokens.INPUT_MIN_HEIGHT_DP
        );
    }

    /** Apply Miuix renderer presentation to explicitly tagged shared FX components. */
    static void applyTaggedComponent(Activity activity, View view, FxUiMode mode) {
        if (activity == null || view == null || mode != FxUiMode.MIUIX_STYLE
                || !(view.getTag() instanceof String)) return;
        String role = (String) view.getTag();
        if (!FxNativeSkin.beginTaggedComponentRender(view, mode, role)) return;
        float density = activity.getResources().getDisplayMetrics().density;
        if ("fx-page-root".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackgroundColor(MiuixColorTokens.BACKGROUND);
            return;
        }
        if ("fx-toolbar".equals(role) && view instanceof ViewGroup) {
            ((ViewGroup) view).setBackground(rounded(MiuixColorTokens.TOP_BAR_BACKGROUND,
                    MiuixColorTokens.DIVIDER, MiuixShapeTokens.NAV_BAR_RADIUS_DP, density));
            return;
        }
        if ("fx-toolbar-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.PAGE_TITLE_SP);
            return;
        }
        if ("fx-toolbar-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(MiuixColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(MiuixSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if (role.startsWith("fx-title:") && view instanceof TextView) {
            int requested = parseRequestedSize(role, 18);
            TextView title = (TextView) view;
            title.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    requested >= 22 ? MiuixTypographyTokens.PAGE_TITLE_SP
                            : Math.max(requested, MiuixTypographyTokens.SECTION_TITLE_SP));
            title.setLetterSpacing(0.005f);
            title.setPadding(dp(MiuixSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.TITLE_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.TITLE_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.TITLE_VERTICAL_PADDING_DP, density));
            if (requested >= 22) {
                title.setBackground(rounded(MiuixColorTokens.TOP_BAR_BACKGROUND,
                        MiuixColorTokens.DIVIDER, MiuixShapeTokens.NAV_BAR_RADIUS_DP, density));
            }
            return;
        }
        if (role.startsWith("fx-section:") && view instanceof TextView) {
            TextView section = (TextView) view;
            section.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            section.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            section.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.SECTION_TITLE_SP);
            section.setLetterSpacing(0.01f);
            section.setPadding(dp(MiuixSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SECTION_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SECTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SECTION_VERTICAL_PADDING_DP, density));
            section.setBackground(rounded(MiuixColorTokens.SURFACE_VARIANT,
                    MiuixColorTokens.DIVIDER, MiuixShapeTokens.SECTION_RADIUS_DP, density));
            section.setMinimumHeight(dp(MiuixSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-select-input".equals(role) && view instanceof Spinner) {
            Spinner select = (Spinner) view;
            select.setMinimumHeight(dp(MiuixSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            select.setPadding(dp(MiuixSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(MiuixColorTokens.SURFACE_VARIANT,
                    MiuixColorTokens.INPUT_BORDER, MiuixShapeTokens.SECTION_RADIUS_DP, density);
            select.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(MiuixColorTokens.ROW_RIPPLE), surface, null));
            select.setPopupBackgroundDrawable(rounded(MiuixColorTokens.SURFACE,
                    MiuixColorTokens.DIVIDER, MiuixShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if (("fx-search-input".equals(role) || "fx-form-input".equals(role)) && view instanceof EditText) {
            EditText input = (EditText) view;
            input.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            input.setHintTextColor(MiuixColorTokens.SECONDARY_TEXT);
            input.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.INPUT_LABEL_SP);
            input.setMinimumHeight(dp(MiuixSpacingTokens.INPUT_MIN_HEIGHT_DP, density));
            input.setPadding(dp(MiuixSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SPINNER_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(MiuixColorTokens.SURFACE_VARIANT,
                    MiuixColorTokens.INPUT_BORDER, MiuixShapeTokens.SECTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    MiuixShapeTokens.SECTION_RADIUS_DP, density);
            input.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(MiuixColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-action-text".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            action.setTextColor(MiuixColorTokens.ACCENT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(MiuixSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-primary-action".equals(role) && view instanceof TextView) {
            TextView action = (TextView) view;
            boolean enabled = action.isEnabled();
            int fill = enabled ? MiuixColorTokens.ACCENT : MiuixColorTokens.SURFACE_VARIANT;
            action.setTextColor(enabled ? 0xffffffff : MiuixColorTokens.SECONDARY_TEXT);
            action.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.ACTION_LABEL_SP);
            action.setMinimumHeight(dp(MiuixSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setPadding(dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(fill,
                    enabled ? 0 : MiuixColorTokens.DIVIDER,
                    MiuixShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0,
                    MiuixShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(MiuixColorTokens.ROW_RIPPLE), surface, mask));
            return;
        }
        if ("fx-card-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.CARD_TITLE_SP);
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
                surface = MiuixColorTokens.ERROR_STATE_SURFACE;
                stroke = MiuixColorTokens.ERROR_STATE_STROKE;
                foreground = MiuixColorTokens.ERROR_STATE_TEXT;
            } else if ("fx-success-state".equals(role)) {
                surface = MiuixColorTokens.SUCCESS_STATE_SURFACE;
                stroke = MiuixColorTokens.SUCCESS_STATE_STROKE;
                foreground = MiuixColorTokens.SUCCESS_STATE_TEXT;
            } else if ("fx-loading-state".equals(role)) {
                surface = MiuixColorTokens.LOADING_STATE_SURFACE;
                stroke = MiuixColorTokens.LOADING_STATE_STROKE;
                foreground = MiuixColorTokens.LOADING_STATE_TEXT;
            } else {
                surface = MiuixColorTokens.EMPTY_STATE_SURFACE;
                stroke = MiuixColorTokens.EMPTY_STATE_STROKE;
                foreground = MiuixColorTokens.EMPTY_STATE_TEXT;
            }
            state.setTextColor(foreground);
            state.setTypeface(Typeface.create("sans-serif-medium",
                    "fx-error-state".equals(role) ? Typeface.BOLD : Typeface.NORMAL));
            state.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    "fx-empty-state".equals(role) ? MiuixTypographyTokens.CARD_DESCRIPTION_SP
                            : MiuixTypographyTokens.LIST_ROW_SUBTITLE_SP);
            state.setLineSpacing(dp(3, density), 1.0f);
            state.setGravity("fx-empty-state".equals(role)
                    ? android.view.Gravity.CENTER
                    : android.view.Gravity.CENTER_VERTICAL | android.view.Gravity.START);
            state.setMinimumHeight(dp("fx-empty-state".equals(role) ? 76 : 52, density));
            state.setPadding(dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            state.setBackground(rounded(surface, stroke,
                    MiuixShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-list-row".equals(role) && view instanceof ViewGroup) {
            ViewGroup row = (ViewGroup) view;
            GradientDrawable surface = rounded(MiuixColorTokens.LIST_ROW_SURFACE,
                    MiuixColorTokens.LIST_ROW_BORDER, MiuixShapeTokens.LIST_ROW_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, MiuixShapeTokens.LIST_ROW_RADIUS_DP, density);
            row.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(MiuixColorTokens.LIST_ROW_RIPPLE), surface, mask));
            row.setPadding(dp(MiuixSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.LIST_ROW_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.LIST_ROW_VERTICAL_PADDING_DP, density));
            row.setMinimumHeight(dp(MiuixSpacingTokens.LIST_ROW_MIN_HEIGHT_DP, density));
            return;
        }
        if ("fx-list-title".equals(role) && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.LIST_ROW_TITLE_SP);
            return;
        }
        if ("fx-list-subtitle".equals(role) && view instanceof TextView) {
            TextView subtitle = (TextView) view;
            subtitle.setTextColor(MiuixColorTokens.SECONDARY_TEXT);
            subtitle.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            subtitle.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.LIST_ROW_SUBTITLE_SP);
            subtitle.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-risk-certain".equals(role) || "fx-risk-suspect".equals(role))
                && view instanceof ViewGroup) {
            boolean certain = "fx-risk-certain".equals(role);
            ViewGroup risk = (ViewGroup) view;
            risk.setBackground(rounded(
                    certain ? MiuixShapeTokens.RISK_CERTAIN_SURFACE : MiuixShapeTokens.RISK_SUSPECT_SURFACE,
                    certain ? MiuixShapeTokens.RISK_CERTAIN_STROKE : MiuixShapeTokens.RISK_SUSPECT_STROKE,
                    MiuixShapeTokens.CARD_RADIUS_DP, density));
            risk.setPadding(dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if (("fx-risk-title-certain".equals(role) || "fx-risk-title-suspect".equals(role))
                && view instanceof TextView) {
            TextView title = (TextView) view;
            title.setTextColor("fx-risk-title-certain".equals(role)
                    ? MiuixShapeTokens.RISK_CERTAIN_TEXT : MiuixShapeTokens.RISK_SUSPECT_TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            title.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.CARD_TITLE_SP);
            title.setLetterSpacing(0.005f);
            return;
        }
        if (("fx-card".equals(role) || "fx-card-group".equals(role) || "fx-setting-card".equals(role)) && view instanceof ViewGroup) {
            ViewGroup card = (ViewGroup) view;
            card.setBackground(rounded(MiuixColorTokens.CARD_SURFACE,
                    MiuixColorTokens.CARD_STROKE, MiuixShapeTokens.CARD_RADIUS_DP, density));
            card.setPadding(dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.CARD_VERTICAL_PADDING_DP, density));
            return;
        }
        if ("fx-switch-row".equals(role) && view instanceof android.widget.CompoundButton) {
            android.widget.CompoundButton row = (android.widget.CompoundButton) view;
            row.setTextColor(MiuixColorTokens.PRIMARY_TEXT);
            row.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.SWITCH_LABEL_SP);
            row.setMinimumHeight(dp(MiuixSpacingTokens.ROW_MIN_HEIGHT_DP, density));
            row.setPadding(dp(MiuixSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SWITCH_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.SWITCH_VERTICAL_PADDING_DP, density));
            row.setBackground(rounded(MiuixColorTokens.CARD_SURFACE,
                    MiuixColorTokens.CARD_STROKE, MiuixShapeTokens.SECTION_RADIUS_DP, density));
            return;
        }
        if ("fx-action-row".equals(role) && view instanceof Button) {
            Button action = (Button) view;
            if (FxNativeSkin.shouldPreserveSemanticAction(action)) return;
            action.setAllCaps(false);
            action.setTextColor(MiuixColorTokens.ACCENT);
            action.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                    MiuixTypographyTokens.ACTION_LABEL_SP);
            action.setMinHeight(dp(MiuixSpacingTokens.ACTION_MIN_HEIGHT_DP, density));
            action.setMinWidth(dp(MiuixSpacingTokens.ACTION_MIN_WIDTH_DP, density));
            action.setPadding(dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_HORIZONTAL_PADDING_DP, density),
                    dp(MiuixSpacingTokens.ACTION_VERTICAL_PADDING_DP, density));
            GradientDrawable surface = rounded(MiuixColorTokens.ACTION_BACKGROUND,
                    MiuixColorTokens.ACTION_BORDER, MiuixShapeTokens.ACTION_RADIUS_DP, density);
            GradientDrawable mask = rounded(0xffffffff, 0, MiuixShapeTokens.ACTION_RADIUS_DP, density);
            action.setBackground(new RippleDrawable(
                    ColorStateList.valueOf(MiuixColorTokens.ROW_RIPPLE), surface, mask));
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
