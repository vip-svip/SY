package de.privacyguard.adhook.imported.dia;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * Keeps ActivityKey gesture timing isolated per target package.
 * Android processes can host multiple packages; sharing one decoder lets
 * one package's volume/Back presses contaminate another package's sequence.
 */
public final class FxDiaKeyGesturePolicyRegistry {
    private final ConcurrentMap<String, FxDiaKeyGesturePolicy> policies =
            new ConcurrentHashMap<>();

    public FxDiaKeyGesturePolicy forPackage(String packageName) {
        if (packageName == null || packageName.trim().isEmpty()) return null;
        return policies.computeIfAbsent(packageName, ignored -> new FxDiaKeyGesturePolicy());
    }

    public void remove(String packageName) {
        if (packageName == null || packageName.trim().isEmpty()) return;
        policies.remove(packageName);
    }

    public void clear() {
        policies.clear();
    }
}
