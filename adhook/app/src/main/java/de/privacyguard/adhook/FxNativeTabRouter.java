package de.privacyguard.adhook;

import android.app.Activity;
import android.content.Intent;

/** One authoritative mapping between the six FX bottom tabs and their native pages. */
public final class FxNativeTabRouter {
    private FxNativeTabRouter() { }

    public static boolean navigate(Activity source, int index) {
        if (source == null || index < 0 || index > 5) return false;

        // Classic is a page-level legacy compatibility renderer for the four
        // WebUI destinations. Hook and Settings remain native FX Activities.
        if (index >= 0 && index <= 3
                && FxUiMode.read(source) == FxUiMode.CLASSIC_WEB_COMPAT) {
            if (source instanceof FxClassicWebCompatActivity) {
                ((FxClassicWebCompatActivity) source).selectTab(index);
                return false;
            }
            Intent classic = new Intent(source, FxClassicWebCompatActivity.class)
                    .putExtra(FxClassicWebCompatActivity.EXTRA_TAB_INDEX, index)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            source.startActivity(classic);
            return true;
        }
        Class<? extends Activity> destination;
        switch (index) {
            case 0:
                destination = FxNativeVpnActivity.class;
                break;
            case 1:
                destination = de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class;
                break;
            case 2:
                destination = FxNativePrivacySettingsActivity.class;
                break;
            case 3:
                destination = FxQuickJsScriptActivity.class;
                break;
            case 4:
                destination = MainActivity.class;
                break;
            case 5:
                destination = FxNativeSettingsActivity.class;
                break;
            default:
                return false;
        }
        if (destination == source.getClass()) return false;
        Intent intent = new Intent(source, destination)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        source.startActivity(intent);
        return true;
    }
}
