package de.privacyguard.adhook;

import android.app.Activity;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

/**
 * Shared skin-token adapter for migrated native Activities.
 *
 * The original imported screens use a small set of legacy literal colors.
 * Translate only those known legacy tokens; preserve custom user content,
 * status colors, warning/error colors, and all non-color drawables.
 */
final class FxNativeSkin {
    private FxNativeSkin() { }

    private static final class Palette {
        final int background;
        final int surface;
        final int surfaceVariant;
        final int divider;
        final int primaryText;
        final int secondaryText;

        Palette(int background, int surface, int surfaceVariant, int divider,
                int primaryText, int secondaryText) {
            this.background = background;
            this.surface = surface;
            this.surfaceVariant = surfaceVariant;
            this.divider = divider;
            this.primaryText = primaryText;
            this.secondaryText = secondaryText;
        }
    }

    static void apply(Activity activity, View pageContent) {
        if (activity == null || pageContent == null) return;
        FxUiMode mode = FxUiMode.read(activity);
        Palette palette = palette(mode);
        boolean wallpaperActive = FxWallpaperStore.currentPath(activity) != null;
        transformKnownLegacyTokens(pageContent, palette, wallpaperActive);
        // Root surface is always the Presentation backdrop. With a selected
        // wallpaper it must be transparent; child cards remain styled surfaces.
        pageContent.setBackgroundColor(wallpaperActive ? 0x00000000 : palette.background);
    }

    private static Palette palette(FxUiMode mode) {
        switch (mode) {
            case FX_LIQUID_NATIVE:
                return new Palette(0xffe8eef4, 0xddefffff, 0xccefffff,
                        0x66ffffff, 0xff24394c, 0xff718091);
            case MIUIX_STYLE:
                return new Palette(0xfff3f5fa, 0xffeaf0fb, 0xffe5ecf8,
                        0xffd8e1ef, 0xff202b3c, 0xff718091);
            case HUAWEI_HARMONY_STYLE:
                return new Palette(0xfff1f5fa, 0xfff8fbff, 0xffeaf2fc,
                        0x332878d0, 0xff1d2f43, 0xff64788f);
            case IOS_CUPERTINO_STYLE:
                return new Palette(0xfff2f2f7, 0xeaffffff, 0xffe5e5ea,
                        0x1f8e8e93, 0xff1c1c1e, 0xff6c6c70);
            case CLASSIC_WEB_COMPAT:
            default:
                return new Palette(0xfff4f6f8, 0xffffffff, 0xffe9eef3,
                        0xffe3e8ee, 0xff17212b, 0xff66727e);
        }
    }

    private static void transformKnownLegacyTokens(View view, Palette palette,
                                                    boolean wallpaperActive) {
        Drawable background = view.getBackground();
        if (background instanceof ColorDrawable) {
            int oldColor = ((ColorDrawable) background).getColor();
            Integer replacement = replacementBackground(oldColor, palette, wallpaperActive);
            if (replacement != null) {
                view.setBackground(new ColorDrawable(replacement));
            }
        }

        if (view instanceof TextView) {
            TextView text = (TextView) view;
            int oldColor = text.getCurrentTextColor();
            Integer replacement = replacementText(oldColor, palette);
            if (replacement != null) text.setTextColor(replacement);
        }

        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                transformKnownLegacyTokens(group.getChildAt(i), palette, wallpaperActive);
            }
        }
    }

    private static Integer replacementBackground(int color, Palette p,
                                                  boolean wallpaperActive) {
        switch (color) {
            case 0xfff7f8fa:
            case 0xfff4f6f8:
                return wallpaperActive ? 0x00000000 : p.background;
            case 0xfff0f3f7:
            case 0xffffffff:
                return p.surface;
            case 0xffe9eef3:
            case 0xffe5e5ea:
                return p.surfaceVariant;
            case 0xffe3e8ee:
                return p.divider;
            default:
                return null;
        }
    }

    private static Integer replacementText(int color, Palette p) {
        switch (color) {
            case 0xff17212b:
                return p.primaryText;
            case 0xff617080:
            case 0xff66727e:
            case 0xff718091:
                return p.secondaryText;
            default:
                return null;
        }
    }
}
