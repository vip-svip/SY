package de.privacyguard.adhook;

import android.app.Activity;
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
    private static final WeakHashMap<View, Boolean> WATCHED = new WeakHashMap<>();
    private static final WeakHashMap<View, FxUiMode> BUTTON_SKINS = new WeakHashMap<>();
    private static final WeakHashMap<View, FxUiMode> SWITCH_SKINS = new WeakHashMap<>();

    private static final long REAPPLY_DEBOUNCE_MS = 80L;

    static void watch(Activity activity, View pageContent) {
        if (activity == null || pageContent == null) return;
        FxUiMode mode = FxUiMode.read(activity);
        boolean wallpaperActive = FxWallpaperStore.currentPath(activity) != null;
        apply(activity, pageContent, mode, wallpaperActive);
        synchronized (WATCHED) {
            if (WATCHED.containsKey(pageContent)) return;
            WATCHED.put(pageContent, Boolean.TRUE);
        }

        Handler mainHandler = new Handler(Looper.getMainLooper());
        Runnable reapplyAfterLayout = () -> {
            if (!activity.isFinishing() && !activity.isDestroyed()
                    && pageContent.isAttachedToWindow()) {
                // Reuse the Activity's initial presentation snapshot. Skin/wallpaper
                // changes rebuild the page shell, so layout passes never hit disk or
                // SharedPreferences while walking a potentially large app list.
                apply(activity, pageContent, mode, wallpaperActive);
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

    private static final class Palette {
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

        Palette(int background, int surface, int surfaceVariant, int divider,
                int primaryText, int secondaryText, int actionBackground,
                int actionBorder, int accent, int switchOffTrack, int cornerRadiusDp) {
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
        }
    }

    static void apply(Activity activity, View pageContent) {
        if (activity == null || pageContent == null) return;
        apply(activity, pageContent, FxUiMode.read(activity),
                FxWallpaperStore.currentPath(activity) != null);
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
        if (!(rootBackground instanceof ColorDrawable)
                || ((ColorDrawable) rootBackground).getColor() != rootColor) {
            pageContent.setBackgroundColor(rootColor);
        }
    }

    private static Palette palette(FxUiMode mode) {
        switch (mode) {
            case FX_LIQUID_NATIVE:
                return new Palette(0xffe8eef4, 0xddefffff, 0xccefffff,
                        0x66ffffff, 0xff24394c, 0xff718091,
                        0xf2ffffff, 0x99ffffff, 0xff0088ff, 0xffc5d0dc, 24);
            case MIUIX_STYLE:
                return new Palette(0xfff3f5fa, 0xffeaf0fb, 0xffe5ecf8,
                        0xffd8e1ef, 0xff202b3c, 0xff718091,
                        0xffe5ecf8, 0xffd8e1ef, 0xff3478f6, 0xffc3ccda, 20);
            case HUAWEI_HARMONY_STYLE:
                return new Palette(0xfff1f5fa, 0xfff8fbff, 0xffeaf2fc,
                        0x332878d0, 0xff1d2f43, 0xff64788f,
                        0xffe8f1fc, 0xffc9dcf5, 0xff2878d0, 0xffc2ccd8, 16);
            case IOS_CUPERTINO_STYLE:
                return new Palette(0xfff2f2f7, 0xeaffffff, 0xffe5e5ea,
                        0x1f8e8e93, 0xff1c1c1e, 0xff6c6c70,
                        0xffe5e5ea, 0x1f8e8e93, 0xff007aff, 0xffd1d1d6, 18);
            case CLASSIC_WEB_COMPAT:
            default:
                return new Palette(0xfff4f6f8, 0xffffffff, 0xffe9eef3,
                        0xffe3e8ee, 0xff17212b, 0xff66727e,
                        0xffedf1f5, 0xffdce3eb, 0xff1769aa, 0xffc4cbd4, 8);
        }
    }

    private static void transformKnownLegacyTokens(Activity activity, View view,
                                                    FxUiMode mode, Palette palette,
                                                    boolean wallpaperActive) {
        Drawable background = view.getBackground();
        if (background instanceof ColorDrawable) {
            int oldColor = ((ColorDrawable) background).getColor();
            float density = activity.getResources().getDisplayMetrics().density;
            Drawable replacement = replacementBackgroundDrawable(oldColor, palette, wallpaperActive, density);
            if (replacement != null) view.setBackground(replacement);
        }

        if (view instanceof TextView) {
            TextView text = (TextView) view;
            int oldColor = text.getCurrentTextColor();
            Integer replacement = replacementText(oldColor, palette);
            if (replacement != null && replacement != oldColor) text.setTextColor(replacement);
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
        if (isSemanticActionColor(button.getCurrentTextColor())
                || isSemanticActionBackground(button.getBackground())) {
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
        button.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                mode == FxUiMode.IOS_CUPERTINO_STYLE ? 15 : 14);
        button.setMinHeight(Math.round((mode == FxUiMode.IOS_CUPERTINO_STYLE ? 44 : 46) * density));
        button.setMinWidth(Math.round(64 * density));
        button.setPadding(Math.round(16 * density), Math.round(9 * density),
                Math.round(16 * density), Math.round(9 * density));
        button.setElevation(Math.round((mode == FxUiMode.FX_LIQUID_NATIVE ? 2 : 0) * density));
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
        control.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP,
                mode == FxUiMode.IOS_CUPERTINO_STYLE ? 16 : 15);
        control.setPadding(Math.round(16 * density), Math.round(10 * density),
                Math.round(16 * density), Math.round(10 * density));
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
                return roundedSurface(p.surface, Math.max(10, p.cornerRadiusDp - 4) * density, p.divider);
            case 0xffe9eef3:
            case 0xffe5e5ea:
                return roundedSurface(p.surfaceVariant, Math.max(8, p.cornerRadiusDp - 8) * density, p.divider);
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
