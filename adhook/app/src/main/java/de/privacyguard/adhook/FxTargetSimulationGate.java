package de.privacyguard.adhook;

import java.util.Set;

/**
 * Fail-open authorization gate for per-app device simulation hooks.
 *
 * Xposed package-ready callbacks can be delivered more than once in a shared
 * process. A process-global interceptor cannot reliably infer which package
 * invoked a framework method when more than one package shares that process.
 * Device test values therefore apply only while exactly one debuggable target
 * package is known for the current process.
 */
public final class FxTargetSimulationGate {
    private FxTargetSimulationGate() { }

    public static boolean isAuthorized(String targetPackage,
                                       String currentPackage,
                                       Set<String> processPackages,
                                       Set<String> debuggablePackages) {
        if (targetPackage == null || targetPackage.isEmpty()
                || currentPackage == null
                || processPackages == null || debuggablePackages == null) {
            return false;
        }
        return targetPackage.equals(currentPackage)
                && processPackages.size() == 1
                && processPackages.contains(targetPackage)
                && debuggablePackages.contains(targetPackage);
    }
}
