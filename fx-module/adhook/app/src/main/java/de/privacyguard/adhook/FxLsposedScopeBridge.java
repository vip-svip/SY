package de.privacyguard.adhook;

import io.github.libxposed.service.XposedService;
import io.github.libxposed.service.XposedServiceHelper;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Module-app-side LSPosed scope bridge. Scope changes are requested through
 * libXposed Service so the framework/Manager remains the authority that approves
 * module injection. Manager installation alone is never treated as a live scope.
 */
public final class FxLsposedScopeBridge {
    public interface RequestCallback {
        void onApproved(List<String> approvedPackages);
        void onFailed(String message);
    }

    public static final class Snapshot {
        public final boolean connected;
        public final String frameworkName;
        public final String frameworkVersion;
        public final int apiVersion;
        public final boolean targetInScope;
        public final int scopeCount;
        public final String error;

        private Snapshot(boolean connected, String frameworkName, String frameworkVersion,
                         int apiVersion, boolean targetInScope, int scopeCount, String error) {
            this.connected = connected;
            this.frameworkName = frameworkName;
            this.frameworkVersion = frameworkVersion;
            this.apiVersion = apiVersion;
            this.targetInScope = targetInScope;
            this.scopeCount = scopeCount;
            this.error = error;
        }

        static Snapshot disconnected(String detail) {
            return new Snapshot(false, "", "", 0, false, 0, detail);
        }
    }

    private static final AtomicBoolean REGISTERED = new AtomicBoolean(false);
    private static final CopyOnWriteArrayList<XposedService> SERVICES = new CopyOnWriteArrayList<>();

    private static final XposedServiceHelper.OnServiceListener SERVICE_LISTENER =
            new XposedServiceHelper.OnServiceListener() {
                @Override public void onServiceBind(XposedService service) {
                    if (service != null && !SERVICES.contains(service)) SERVICES.add(service);
                }

                @Override public void onServiceDied(XposedService service) {
                    if (service != null) SERVICES.remove(service);
                }
            };

    private FxLsposedScopeBridge() { }

    /** Call once from Application.onCreate(); the library caches an early Binder delivery. */
    public static void initialize() {
        if (!REGISTERED.compareAndSet(false, true)) return;
        try {
            XposedServiceHelper.registerListener(SERVICE_LISTENER);
        } catch (Throwable error) {
            REGISTERED.set(false);
            android.util.Log.e("FX-LSPosed", "Unable to register Xposed service listener", error);
        }
    }

    private static XposedService activeService() {
        for (XposedService service : SERVICES) {
            if (service != null) return service;
        }
        return null;
    }

    public static boolean isConnected() {
        return activeService() != null;
    }

    public static Snapshot snapshot(String packageName) {
        if (!validPackage(packageName)) return Snapshot.disconnected("目标包名无效。");
        XposedService service = activeService();
        if (service == null) return Snapshot.disconnected(
                "尚未收到 libXposed 服务 Binder。请确认 FX Hook 已在 LSPosed 中启用，并重新打开 FX Hook 后刷新。");
        try {
            List<String> raw = service.getScope();
            List<String> scope = raw == null ? Collections.emptyList() : new ArrayList<>(raw);
            return new Snapshot(true, safe(service.getFrameworkName()), safe(service.getFrameworkVersion()),
                    service.getApiVersion(), scope.contains(packageName), scope.size(), "");
        } catch (RuntimeException error) {
            SERVICES.remove(service);
            return Snapshot.disconnected("读取 LSPosed 作用域失败：" + error.getClass().getSimpleName());
        }
    }

    public static void requestScope(String packageName, RequestCallback callback) {
        if (!validPackage(packageName)) throw new IllegalArgumentException("目标包名无效。");
        XposedService service = activeService();
        if (service == null) throw new IllegalStateException("LSPosed 服务尚未连接。");
        service.requestScope(Collections.singletonList(packageName),
                new XposedService.OnScopeEventListener() {
                    @Override public void onScopeRequestApproved(List<String> approved) {
                        List<String> copy = approved == null ? Collections.emptyList()
                                : Collections.unmodifiableList(new ArrayList<>(approved));
                        if (callback != null) callback.onApproved(copy);
                    }

                    @Override public void onScopeRequestFailed(String message) {
                        if (callback != null) callback.onFailed(safe(message));
                    }
                });
    }

    public static void removeScope(String packageName) {
        if (!validPackage(packageName)) throw new IllegalArgumentException("目标包名无效。");
        XposedService service = activeService();
        if (service == null) throw new IllegalStateException("LSPosed 服务尚未连接。");
        service.removeScope(Collections.singletonList(packageName));
    }

    private static boolean validPackage(String packageName) {
        return packageName != null
                && packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                && !"de.privacyguard.adhook".equals(packageName);
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
