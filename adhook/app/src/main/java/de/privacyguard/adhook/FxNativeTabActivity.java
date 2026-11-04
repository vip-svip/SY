package de.privacyguard.adhook;

import android.content.Intent;
import android.view.View;

import androidx.activity.ComponentActivity;
import androidx.compose.ui.platform.ComposeView;

/**
 * Shared host for native imported-suite pages that must retain FX's six
 * primary destinations. The Activity owns the real page and lifecycle;
 * Compose supplies only the persistent native navigation chrome.
 */
public abstract class FxNativeTabActivity extends ComponentActivity {
    private boolean fxTabNavigationStarted;

    protected final void setContentViewWithNativeTabs(View pageContent, int selectedIndex) {
        if (pageContent == null) {
            throw new IllegalArgumentException("pageContent must not be null");
        }
        String mode = getSharedPreferences("fx_ui", MODE_PRIVATE)
                .getString("mode", "classic");
        if (!"classic".equals(mode) && !"glass".equals(mode) && !"miuix".equals(mode)) {
            mode = "classic";
        }

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
