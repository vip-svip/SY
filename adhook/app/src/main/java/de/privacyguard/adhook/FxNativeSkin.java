package de.privacyguard.adhook;

import android.app.Activity;
import androidx.appcompat.app.AlertDialog;
import android.os.Handler;
import android.os.Looper;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.content.res.ColorStateList;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.TextView;
import android.widget.Button;
import android.widget.Switch;
import android.widget.EditText;
import android.widget.Spinner;
import java.util.WeakHashMap;

/**
 * Shared skin-token adapter for migrated native Activities.
 *
 * The original imported screens use a small set of legacy literal colors.
 * Translate only those known legacy tokens; preserve custom user content,
 * status colors, warning/error colors, and all non-color drawables.
 */
final class FxNativeSkin {
    private FxNativeSkin() { }

    // A weak registry prevents duplicate listeners if a page is re-mounted.
    // The snapshot is mutable so repeat watch() calls update the live mode/wallpaper
    // instead of leaving the listener with stale values captured on first attach.
    private static final class SkinSnapshot {
        volatile FxUiMode mode;
        volatile boolean wallpaperActive;

        SkinSnapshot(FxUiMode mode, boolean wallpaperActive) {
            this.mode = mode;
            this.wallpaperActive = wallpaperActive;
        }
    }
    private static final WeakHashMap<View, SkinSnapshot> WATCHED = new WeakHashMap<>();
    private static final WeakHashMap<View, FxUiMode> BUTTON_SKINS = new WeakHashMap<>();
    private static final WeakHashMap<View, FxUiMode> SWITCH_SKINS = new WeakHashMap<>();
    private static final WeakHashMap<View, FxUiMode> FORM_SKINS = new WeakHashMap<>();
    // Tagged component renderers run from the debounced global-layout walker.
    // Cache the last (mode, role) to avoid replacing Drawables on every layout.
    private static final WeakHashMap<View, String> TAGGED_COMPONENT_SKINS = new WeakHashMap<>();

    private static final long REAPPLY_DEBOUNCE_MS = 80L;

    static void watch(Activity activity, View pageContent) {
        if (activity == null || pageContent == null) return;
        FxUiMode mode = FxUiMode.read(activity);
        boolean wallpaperActive = FxWallpaperStore.currentPath(activity) != null;
        apply(activity, pageContent, mode, wallpaperActive);
        final SkinSnapshot snapshot;
        synchronized (WATCHED) {
            SkinSnapshot existing = WATCHED.get(pageContent);
            if (existing != null) {
                existing.mode = mode;
                existing.wallpaperActive = wallpaperActive;
                return;
            }
            snapshot = new SkinSnapshot(mode, wallpaperActive);
            WATCHED.put(pageContent, snapshot);
        }

        Handler mainHandler = new Handler(Looper.getMainLooper());
        Runnable reapplyAfterLayout = () -> {
            if (!activity.isFinishing() && !activity.isDestroyed()
                    && pageContent.isAttachedToWindow()) {
                // Read the current snapshot on every pass. The same root View may
                // be rebound after a mode/wallpaper change; never replay stale Skin.
                apply(activity, pageContent, snapshot.mode, snapshot.wallpaperActive);
            }
        };
        // Debounce repeated layout notifications: a burst of async list rows is
        // re-skinned once after the current layout transaction settles, not once
        // per frame or once per inserted child.
        ViewTreeObserver.OnGlobalLayoutListener layoutListener =
                () -> {
                    if (activity.isFinishing() || activity.isDestroyed()) return;
                    mainHandler.removeCallbacks(reapplyAfterLayout);
                    mainHandler.postDelayed(reapplyAfterLayout, REAPPLY_DEBOUNCE_MS);
                };
        pageContent.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            private ViewTreeObserver observedTree;

            @Override public void onViewAttachedToWindow(View view) {
                ViewTreeObserver observer = view.getViewTreeObserver();
                if (observer.isAlive()) {
                    observedTree = observer;
                    observer.addOnGlobalLayoutListener(layoutListener);
                    mainHandler.removeCallbacks(reapplyAfterLayout);
                    mainHandler.postDelayed(reapplyAfterLayout, REAPPLY_DEBOUNCE_MS);
                }
            }

            @Override public void onViewDetachedFromWindow(View view) {
                if (observedTree != null && observedTree.isAlive()) {
                    observedTree.removeOnGlobalLayoutListener(layoutListener);
                }
                observedTree = null;
                mainHandler.removeCallbacks(reapplyAfterLayout);
            }
        });
    }

    static final class Palette {
        final int background;
        final int surface;
        final int surfaceVariant;
        final int divider;
        final int primaryText;
        final int secondaryText;
        final int actionBackground;
        final int actionBorder;
        final int accent;
        final int switchOffTrack;
        final int cornerRadiusDp;
        final int inputBorder;
        final int cardCornerRadiusDp;
        final float buttonTextSizeSp;
        final int buttonMinHeightDp;
        final int buttonMinWidthDp;
        final int buttonHorizontalPaddingDp;
        final int buttonVerticalPaddingDp;
        final float buttonElevationDp;
        final float switchTextSizeSp;
        final int switchHorizontalPaddingDp;
        final int switchVerticalPaddingDp;
        final float choiceTextSizeSp;
        final float inputTextSizeSp;
        final int inputMinHeightDp;

        // Legacy 24-argument constructor retained for Classic/Liquid/Miuix call sites.
        Palette(int background, int surface, int surfaceVariant, int divider,
                int primaryText, int secondaryText, int actionBackground,
                int actionBorder, int accent, int switchOffTrack, int cornerRadiusDp,
                int inputBorder, float buttonTextSizeSp, int buttonMinHeightDp,
                int buttonMinWidthDp, int buttonHorizontalPaddingDp, int buttonVerticalPaddingDp,
                float buttonElevationDp, float switchTextSizeSp, int switchHorizontalPaddingDp,
                int switchVerticalPaddingDp, float choiceTextSizeSp,
                float inputTextSizeSp, int inputMinHeightDp) {
            this(background, surface, surfaceVariant, divider, primaryText, secondaryText,
                    actionBackground, actionBorder, accent, switchOffTrack, cornerRadiusDp,
                    inputBorder, Math.max(16, cornerRadiusDp - 4), buttonTextSizeSp,
                    buttonMinHeightDp, buttonMinWidthDp, buttonHorizontalPaddingDp,
                    buttonVerticalPaddingDp, buttonElevationDp, switchTextSizeSp,
                    switchHorizontalPaddingDp, switchVerticalPaddingDp, choiceTextSizeSp,
                    inputTextSizeSp, inputMinHeightDp);
        }

        // Full constructor for independently tokenized Harmony and Cupertino renderers.
        Palette(int background, int surface, int surfaceVariant, int divider,
                int primaryText, int secondaryText, int actionBackground,
                int actionBorder, int accent, int switchOffTrack, int cornerRadiusDp,
                int inputBorder, int cardCornerRadiusDp, float buttonTextSizeSp,
                int buttonMinHeightDp, int buttonMinWidthDp, int buttonHorizontalPaddingDp,
                int buttonVerticalPaddingDp, float buttonElevationDp, float switchTextSizeSp,
                int switchHorizontalPaddingDp, int switchVerticalPaddingDp,
                float choiceTextSizeSp, float inputTextSizeSp, int inputMinHeightDp) {
            this.background = background;
            this.surface = surface;
            this.surfaceVariant = surfaceVariant;
            this.divider = divider;
            this.primaryText = primaryText;
            this.secondaryText = secondaryText;
            this.actionBackground = actionBackground;
            this.actionBorder = actionBorder;
            this.accent = accent;
            this.switchOffTrack = switchOffTrack;
            this.cornerRadiusDp = cornerRadiusDp;
            this.inputBorder = inputBorder;
            this.cardCornerRadiusDp = cardCornerRadiusDp;
            this.buttonTextSizeSp = buttonTextSizeSp;
            this.buttonMinHeightDp = buttonMinHeightDp;
            this.buttonMinWidthDp = buttonMinWidthDp;
            this.buttonHorizontalPaddingDp = buttonHorizontalPaddingDp;
            this.buttonVerticalPaddingDp = buttonVerticalPaddingDp;
            this.buttonElevationDp = buttonElevationDp;
            this.switchTextSizeSp = switchTextSizeSp;
            this.switchHorizontalPaddingDp = switchHorizontalPaddingDp;
            this.switchVerticalPaddingDp = switchVerticalPaddingDp;
            this.choiceTextSizeSp = choiceTextSizeSp;
            this.inputTextSizeSp = inputTextSizeSp;
            this.inputMinHeightDp = inputMinHeightDp;
        }
    }

    static boolean beginTaggedComponentRender(View view, FxUiMode mode, String role) {
        if (view == null || mode == null || role == null) return false;
        String token = mode.getStorageId() + "|" + role;
        synchronized (TAGGED_COMPONENT_SKINS) {
            if (token.equals(TAGGED_COMPONENT_SKINS.get(view))) return false;
            TAGGED_COMPONENT_SKINS.put(view, token);
            return true;
        }
    }

    static void apply(Activity activity, View pageContent) {
        if (activity == null || pageContent == null) return;
        apply(activity, pageContent, FxUiMode.read(activity),
                FxWallpaperStore.currentPath(activity) != null);
    }

    /**
     * Apply presentation tokens to a detached dialog/sheet subtree. Unlike
     * apply(), this does not replace the dialog's root surface or attach a
     * layout observer; it styles only the supplied controls and tagged rows.
     */
    static void applyComponents(Activity activity, View content) {
        if (activity == null || content == null) return;
        FxUiMode mode = FxUiMode.read(activity);
        boolean wallpaperActive = FxWallpaperStore.currentPath(activity) != null;
        transformKnownLegacyTokens(activity, content, mode, palette(mode), wallpaperActive);
    }

    /**
     * Show a native FX modal and apply the active Skin after Android has
     * inflated its title, content and action buttons. A second pass is posted
     * after the first layout so custom EditText/List rows are included too.
     */
    static void showDialog(Activity activity, AlertDialog dialog) {
        if (activity == null || dialog == null
                || activity.isFinishing() || activity.isDestroyed()) return;
        dialog.show();
        android.view.Window window = dialog.getWindow();
        if (window == null) return;
        View decor = window.getDecorView();
        applyComponents(activity, decor);
        decor.post(() -> {
            if (activity.isFinishing() || activity.isDestroyed()
                    || !dialog.isShowing()) return;
            android.view.Window currentWindow = dialog.getWindow();
            if (currentWindow != null) {
                applyComponents(activity, currentWindow.getDecorView());
            }
        });
    }

    private static void apply(Activity activity, View pageContent,
                              FxUiMode mode, boolean wallpaperActive) {
        if (activity == null || pageContent == null) return;
        Palette palette = palette(mode);
        transformKnownLegacyTokens(activity, pageContent, mode, palette, wallpaperActive);
        // Root surface is always the Presentation backdrop. With a selected
        // wallpaper it must be transparent; child cards remain styled surfaces.
        int rootColor = wallpaperActive ? 0x00000000 : palette.background;
        Drawable rootBackground = pageContent.getBackground();
        // Only normalize known neutral root/page colors. Imported screens may
        // intentionally provide a gradient, selector, ripple or custom Drawable;
        // the Skin adapter must never replace those user/source-owned backgrounds.
        if (isKnownPageBackground(rootBackground, palette, rootColor)
                && (!(rootBackground instanceof ColorDrawable)
                || ((ColorDrawable) rootBackground).getColor() != rootColor)) {
            pageContent.setBackgroundColor(rootColor);
        }
    }

    private static boolean isKnownPageBackground(Drawable background, Palette palette,
                                                  int targetColor) {
        if (background == null) return true;
        if (!(background instanceof ColorDrawable)) return false;
        int color = ((ColorDrawable) background).getColor();
        return color == targetColor
                || color == 0xfff7f8fa
                || color == 0xfff4f6f8
                || color == 0xffe8eef4
                || color == 0xfff3f5fa
                || color == palette.background;
    }

    private static Palette palette(FxUiMode mode) {
        switch (mode) {
            case FX_LIQUID_NATIVE:
                return new Palette(0xffe8eef4, 0xddefffff, 0xccefffff,
                        0x66ffffff, 0xff24394c, 0xff718091,
                        0xf2ffffff, 0x99ffffff, 0xff0088ff, 0xffc5d0dc, 24, 0x88ffffff, 24, 14f, 46, 64, 16, 9, 2f, 15f, 16, 10, 15f, 14f, 48);
            case MIUIX_STYLE:
                return new Palette(0xfff3f5fa, 0xffeaf0fb, 0xffe5ecf8,
                        0xffd8e1ef, 0xff202b3c, 0xff718091,
                        0xffe5ecf8, 0xffd8e1ef, 0xff3478f6, 0xffc3ccda, 20, 0xffcbd7e8, 20, 14f, 46, 64, 16, 10, 0f, 15f, 16, 10, 15f, 14f, 48);
            case HUAWEI_HARMONY_STYLE:
                return HarmonySkinRenderer.palette();
            case IOS_CUPERTINO_STYLE:
                return CupertinoSkinRenderer.palette();
            case CLASSIC_WEB_COMPAT:
            default:
                return new Palette(0xfff4f6f8, 0xffffffff, 0xffe9eef3,
                        0xffe3e8ee, 0xff17212b, 0xff66727e,
                        0xffedf1f5, 0xffdce3eb, 0xff1769aa, 0xffc4cbd4, 8, 0xffc6d0dc, 12, 14f, 46, 64, 16, 9, 0f, 15f, 16, 10, 15f, 14f, 48);
        }
    }

    private static void transformKnownLegacyTokens(Activity activity, View view,
                                                    FxUiMode mode, Palette palette,
                                                    boolean wallpaperActive) {
        Drawable background = view.getBackground();
        int legacyBackgroundColor = Integer.MIN_VALUE;
        if (background instanceof ColorDrawable) {
            legacyBackgroundColor = ((ColorDrawable) background).getColor();
        } else if (background instanceof GradientDrawable) {
            // Imported Activity pages frequently use solid GradientDrawable cards.
            // Adapt only a single-color drawable with a known legacy token; do not
            // flatten gradients, selectors, ripples or arbitrary user drawables.
            ColorStateList fill = ((GradientDrawable) background).getColor();
            if (fill != null) legacyBackgroundColor = fill.getDefaultColor();
        }
        if (legacyBackgroundColor != Integer.MIN_VALUE) {
            float density = activity.getResources().getDisplayMetrics().density;
            Drawable replacement = replacementBackgroundDrawable(
                    legacyBackgroundColor, palette, wallpaperActive, density);
            if (replacement != null) view.setBackground(replacement);
        }

        if (view instanceof TextView) {
            TextView text = (TextView) view;
            int oldColor = text.getCurrentTextColor();
            Integer replacement = replacementText(oldColor, palette);
            if (replacement != null && replacement != oldColor) text.setTextColor(replacement);
        }

        // Form controls are a shared presentation surface across the five Skins.
        // Their text/hint hierarchy is normalized; only known framework drawables
        // receive tint so app-owned custom field backgrounds are never replaced.
        if (view instanceof EditText) {
            applyTextInputSkin(activity, (EditText) view, mode, palette);
        } else if (view instanceof Spinner) {
            applySpinnerSkin(activity, (Spinner) view, mode, palette);
        }

        // Switch, CheckBox and RadioButton can also match the generic Button
        // inheritance check. Dispatch the specialized controls first so their
        // thumb/track or button tint adapters are actually reached.
        if (view instanceof Switch) {
            applySwitchSkin(activity, (Switch) view, mode, palette);
        } else if (view instanceof android.widget.CompoundButton) {
            applyChoiceControlSkin(activity, (android.widget.CompoundButton) view, mode, palette);
        } else if (view instanceof Button) {
            applyButtonSkin(activity, (Button) view, mode, palette);
        }

        // Tagged page titles, section headers, cards and action rows are
        // rendered by the dedicated Harmony/Cupertino component adapters.
        if (mode == FxUiMode.HUAWEI_HARMONY_STYLE) {
            HarmonySkinRenderer.applyTaggedComponent(activity, view, mode);
        } else if (mode == FxUiMode.IOS_CUPERTINO_STYLE) {
            CupertinoSkinRenderer.applyTaggedComponent(activity, view, mode);
        }

        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                transformKnownLegacyTokens(activity, group.getChildAt(i), mode, palette, wallpaperActive);
            }
        }
    }

    private static void applyButtonSkin(Activity activity, Button button,
                                        FxUiMode mode, Palette palette) {
        // Preserve semantic action buttons. Warning, destructive and success
        // actions use explicit red/amber/green tokens in the source screens;
        // recoloring them as a generic accent button would erase their meaning.
        if (shouldPreserveSemanticAction(button)) {
            return;
        }
        synchronized (BUTTON_SKINS) {
            if (BUTTON_SKINS.get(button) == mode) return;
            BUTTON_SKINS.put(button, mode);
        }
        float density = activity.getResources().getDisplayMetrics().density;
        GradientDrawable surface = new GradientDrawable();
        surface.setColor(palette.actionBackground);
        surface.setCornerRadius(palette.cornerRadiusDp * density);
        if (palette.actionBorder != 0) {
            surface.setStroke(Math.max(1, Math.round(density)), palette.actionBorder);
        }
        GradientDrawable mask = new GradientDrawable();
        mask.setColor(0xffffffff);
        mask.setCornerRadius(palette.cornerRadiusDp * density);
        button.setBackground(new RippleDrawable(
                ColorStateList.valueOf(withAlpha(palette.accent, 0x33)),
                surface, mask));
        button.setAllCaps(false);
        button.setTextColor(palette.accent);
        button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, palette.buttonTextSizeSp);
        button.setMinHeight(Math.round(palette.buttonMinHeightDp * density));
        button.setMinWidth(Math.round(palette.buttonMinWidthDp * density));
        button.setPadding(Math.round(palette.buttonHorizontalPaddingDp * density),
                Math.round(palette.buttonVerticalPaddingDp * density),
                Math.round(palette.buttonHorizontalPaddingDp * density),
                Math.round(palette.buttonVerticalPaddingDp * density));
        button.setElevation(Math.round(palette.buttonElevationDp * density));
    }

    static boolean shouldPreserveSemanticAction(Button button) {
        return button != null && (isSemanticActionColor(button.getCurrentTextColor())
                || isSemanticActionBackground(button.getBackground()));
    }

    private static boolean isSemanticActionBackground(Drawable background) {
        return background instanceof ColorDrawable
                && isSemanticActionColor(((ColorDrawable) background).getColor());
    }

    private static boolean isSemanticActionColor(int color) {
        switch (color) {
            // Destructive / error
            case 0xff9b2c2c:
            case 0xffa32620:
            case 0xffa12d2d:
            // Warning / risk
            case 0xfffff6e8:
            case 0xff7a4b13:
            case 0xff79552b:
            // Success / trusted
            case 0xff237347:
            case 0xff24734a:
                return true;
            default:
                return false;
        }
    }

    private static void applyTextInputSkin(Activity activity, EditText control,
                                            FxUiMode mode, Palette palette) {
        synchronized (FORM_SKINS) {
            if (FORM_SKINS.get(control) == mode) return;
            FORM_SKINS.put(control, mode);
        }
        float density = activity.getResources().getDisplayMetrics().density;
        control.setTextColor(palette.primaryText);
        control.setHintTextColor(palette.secondaryText);
        control.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, palette.inputTextSizeSp);
        control.setMinimumHeight(Math.max(control.getMinimumHeight(),
                Math.round(palette.inputMinHeightDp * density)));
        tintKnownFormBackground(control, palette);
    }

    private static void applySpinnerSkin(Activity activity, Spinner control,
                                         FxUiMode mode, Palette palette) {
        synchronized (FORM_SKINS) {
            if (FORM_SKINS.get(control) == mode) return;
            FORM_SKINS.put(control, mode);
        }
        float density = activity.getResources().getDisplayMetrics().density;
        control.setMinimumHeight(Math.max(control.getMinimumHeight(),
                Math.round(palette.inputMinHeightDp * density)));
        tintKnownFormBackground(control, palette);
    }

    private static void tintKnownFormBackground(View control, Palette palette) {
        Drawable background = control.getBackground();
        if (background == null) return;
        // Only tint stock Android wrapper/state backgrounds. App-owned custom
        // Drawable classes are deliberately left untouched by the global Skin.
        String className = background.getClass().getName();
        boolean platformBackground =
                "android.graphics.drawable.InsetDrawable".equals(className)
                || "android.graphics.drawable.StateListDrawable".equals(className)
                || "android.graphics.drawable.RippleDrawable".equals(className)
                || "android.graphics.drawable.LayerDrawable".equals(className);
        if (!platformBackground) return;
        int[][] states = new int[][] {
                new int[] { android.R.attr.state_focused },
                new int[] {}
        };
        control.setBackgroundTintList(new ColorStateList(
                states, new int[] { palette.accent, palette.inputBorder }));
    }

    private static void applySwitchSkin(Activity activity, Switch control,
                                        FxUiMode mode, Palette palette) {
        synchronized (SWITCH_SKINS) {
            if (SWITCH_SKINS.get(control) == mode) return;
            SWITCH_SKINS.put(control, mode);
        }
        float density = activity.getResources().getDisplayMetrics().density;
        int[][] states = new int[][] {
                new int[] { android.R.attr.state_checked },
                new int[] {}
        };
        control.setThumbTintList(new ColorStateList(states,
                new int[] { 0xffffffff, 0xfff8f9fb }));
        control.setTrackTintList(new ColorStateList(states,
                new int[] { palette.accent, palette.switchOffTrack }));
        control.setTextColor(palette.primaryText);
        control.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, palette.switchTextSizeSp);
        control.setPadding(Math.round(palette.switchHorizontalPaddingDp * density),
                Math.round(palette.switchVerticalPaddingDp * density),
                Math.round(palette.switchHorizontalPaddingDp * density),
                Math.round(palette.switchVerticalPaddingDp * density));
    }

    private static void applyChoiceControlSkin(Activity activity,
                                                android.widget.CompoundButton control,
                                                FxUiMode mode, Palette palette) {
        synchronized (SWITCH_SKINS) {
            if (SWITCH_SKINS.get(control) == mode) return;
            SWITCH_SKINS.put(control, mode);
        }
        control.setButtonTintList(new ColorStateList(
                new int[][] { new int[] { android.R.attr.state_checked }, new int[] {} },
                new int[] { palette.accent, palette.switchOffTrack }));
        control.setTextColor(palette.primaryText);
        control.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, palette.choiceTextSizeSp);
        float density = activity.getResources().getDisplayMetrics().density;
        control.setPadding(Math.round(palette.switchHorizontalPaddingDp * density),
                Math.round(palette.switchVerticalPaddingDp * density),
                Math.round(palette.switchHorizontalPaddingDp * density),
                Math.round(palette.switchVerticalPaddingDp * density));
    }

    private static int withAlpha(int color, int alpha) {
        return (color & 0x00ffffff) | ((alpha & 0xff) << 24);
    }

    private static Drawable replacementBackgroundDrawable(int color, Palette p,
                                                            boolean wallpaperActive, float density) {
        switch (color) {
            case 0xfff7f8fa:
            case 0xfff4f6f8:
                // Root/page surfaces reveal the Compose wallpaper when selected.
                return new ColorDrawable(wallpaperActive ? 0x00000000 : p.background);
            case 0xfff0f3f7:
            case 0xffffffff:
                // Only known neutral legacy card tokens receive rounded surfaces.
                return roundedSurface(p.surface, Math.max(10, p.cardCornerRadiusDp - 4) * density, p.divider);
            case 0xffe9eef3:
            case 0xffe5e5ea:
                return roundedSurface(p.surfaceVariant, Math.max(8, p.cardCornerRadiusDp - 8) * density, p.divider);
            case 0xffe3e8ee:
                return new ColorDrawable(p.divider);
            default:
                // Preserve arbitrary custom drawables and semantic status colors.
                return null;
        }
    }

    private static GradientDrawable roundedSurface(int color, float radiusPx, int strokeColor) {
        GradientDrawable surface = new GradientDrawable();
        surface.setColor(color);
        surface.setCornerRadius(radiusPx);
        if (strokeColor != 0) surface.setStroke(1, strokeColor);
        return surface;
    }

    private static Integer replacementText(int color, Palette p) {
        switch (color) {
            // Legacy primary text tokens used by the native VPN, Hook and editor pages.
            case 0xff17212b:
            case 0xff263443:
            case 0xff263238:
            case 0xff344451:
                return p.primaryText;

            // Neutral helper/metadata tokens. Warning, error and success colors
            // (red/amber/green) are intentionally not included here.
            case 0xff617080:
            case 0xff66727e:
            case 0xff718091:
            case 0xff697681:
            case 0xff687582:
            case 0xff687681:
            case 0xff536170:
            case 0xff526170:
            case 0xff75808a:
            case 0xff637080:
            case 0xff667784:
            case 0xff596775:
            case 0xff37474f:
                return p.secondaryText;

            // Legacy blue link/selection colors follow the selected Skin accent.
            case 0xff155a9c:
            case 0xff276b9a:
            case 0xff3478f6:
            case 0xff1769aa:
                return p.accent;
            default:
                return null;
        }
    }
}
