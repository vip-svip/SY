package de.privacyguard.adhook;

import android.content.Intent;
import android.view.View;

import androidx.activity.ComponentActivity;
import androidx.appcompat.app.AlertDialog;
import androidx.compose.ui.platform.ComposeView;

/**
 * Shared host for native feature screens integrated into FX's six
 * primary destinations. The Activity owns the real page and lifecycle;
 * Compose supplies the persistent FX navigation chrome.
 */
public abstract class FxNativeTabActivity extends ComponentActivity {
    private boolean fxTabNavigationStarted;

    /**
     * FX-owned modal builder. Its show() path applies the active global Skin
     * after AndroidX inflates the dialog content and action buttons.
     * Existing callers keep their original listeners and validation callbacks.
     */
    protected final AlertDialog.Builder fxDialogBuilder() {
        return new AlertDialog.Builder(this) {
            @Override
            public AlertDialog show() {
                AlertDialog dialog = create();
                FxNativeSkin.showDialog(FxNativeTabActivity.this, dialog);
                return dialog;
            }
        };
    }

    /** Show a dialog created with a custom OnShowListener without replacing that listener. */
    protected final void showFxDialog(AlertDialog dialog) {
        FxNativeSkin.showDialog(this, dialog);
    }

    protected final void setContentViewWithNativeTabs(View pageContent, int selectedIndex) {
        if (pageContent == null) {
            throw new IllegalArgumentException("pageContent must not be null");
        }
        // All Activity hosts must resolve the same canonical mode model as
        // MainActivity. Do not silently downgrade HUAWEI/iOS skins in integrated
        // feature pages or when legacy aliases are encountered.
        String mode = FxUiMode.read(this).getStorageId();
        // Translate known legacy page/card/text colors into the selected
        // global Skin. Unknown custom and warning colors remain unchanged.
        FxNativeSkin.watch(this, pageContent);

        ComposeView shell = new ComposeView(this);
        androidx.lifecycle.ViewTreeLifecycleOwner.set(shell, this);
        androidx.lifecycle.ViewTreeViewModelStoreOwner.set(shell, this);
        androidx.savedstate.ViewTreeSavedStateRegistryOwner.set(shell, this);
        FxNativeAppShellKt.installFxNativeAppShell(
                shell, pageContent, Math.max(0, Math.min(5, selectedIndex)), mode,
                index -> {
                    if (index < 0 || index > 5 || fxTabNavigationStarted) {
                        return kotlin.Unit.INSTANCE;
                    }
                    fxTabNavigationStarted = true;
                    Intent intent = new Intent(this, MainActivity.class)
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            .putExtra("fx_open_native_tab", index);
                    startActivity(intent);
                    finish();
                    return kotlin.Unit.INSTANCE;
                });
        setContentView(shell);
    }
}
