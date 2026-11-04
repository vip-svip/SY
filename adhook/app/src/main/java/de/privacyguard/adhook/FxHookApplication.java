package de.privacyguard.adhook;

import android.app.Application;

/** Registers the official libXposed module-app Binder listener at process start. */
public final class FxHookApplication extends Application {
    @Override public void onCreate() {
        super.onCreate();
        de.privacyguard.adhook.imported.dia.FxDiaCrashStore.install(this);
        FxLsposedScopeBridge.initialize();
    }
}
