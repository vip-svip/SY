package de.privacyguard.adhook;

import android.app.Application;
import android.os.Handler;
import android.os.Looper;

import io.github.libxposed.service.XposedService;
import io.github.libxposed.service.XposedServiceHelper;

/** Single process owner for FXhook's LSPosed service connection. */
public final class FXhookApplication extends Application implements XposedServiceHelper.OnServiceListener {
    private static volatile XposedService service;
    private static volatile String state = "等待 LSPosed 服务连接";
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    @Override public void onCreate() {
        super.onCreate();
        de.privacyguard.adhook.imported.dia.FxDiaCrashStore.install(this);
        de.privacyguard.adhook.imported.dia.FxDiaNativeCrashCapture.install(this);
        FxLsposedScopeBridge.initialize();
        XposedServiceHelper.registerListener(this);
    }

    @Override public void onServiceBind(XposedService value) {
        service = value;
        state = value.getFrameworkName() + " API " + value.getApiVersion() + " · " + value.getFrameworkVersion();
        MAIN.post(MainActivity::notifyServiceChanged);
    }

    @Override public void onServiceDied(XposedService value) {
        if (service == value) {
            service = null;
            state = "LSPosed 服务已断开";
            MAIN.post(MainActivity::notifyServiceChanged);
        }
    }

    public static XposedService service() { return service; }
    public static String state() { return state; }
}