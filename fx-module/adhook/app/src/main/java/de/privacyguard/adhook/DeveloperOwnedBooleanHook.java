package de.privacyguard.adhook;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/**
 * Resolves exact, zero-argument boolean methods for developer-owned Debug builds.
 * A method descriptor is package-scoped and never resolved by fuzzy name matching.
 */
public final class DeveloperOwnedBooleanHook {
    private DeveloperOwnedBooleanHook() {}

    public static Method resolve(ClassLoader loader, String processPackage,
                                String configuredPackage, boolean debuggableBuild,
                                boolean explicitOptIn, String descriptor) {
        if (!MemberTestGate.isEnabled(debuggableBuild, explicitOptIn,
                processPackage, configuredPackage) || loader == null) return null;
        Parsed parsed = parse(descriptor, processPackage);
        if (parsed == null) return null;
        try {
            Class<?> owner = Class.forName(parsed.owner, false, loader);
            Method method = owner.getDeclaredMethod(parsed.method);
            if (method.getReturnType() != boolean.class || method.getParameterTypes().length != 0
                    || Modifier.isAbstract(method.getModifiers())) return null;
            return method;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static Parsed parse(String descriptor, String processPackage) {
        if (descriptor == null || processPackage == null || descriptor.length() > 512) return null;
        int split = descriptor.indexOf('#');
        if (split <= 0 || split == descriptor.length() - 1) return null;
        String owner = descriptor.substring(0, split);
        String signature = descriptor.substring(split + 1);
        if (!owner.startsWith(processPackage + ".") || owner.startsWith("java.")
                || owner.startsWith("android.") || !signature.endsWith("()Z")) return null;
        String method = signature.substring(0, signature.length() - 3);
        if (!method.matches("[A-Za-z_$][A-Za-z0-9_$]*")) return null;
        if (!owner.matches("[A-Za-z_$][A-Za-z0-9_$.]*")) return null;
        return new Parsed(owner, method);
    }

    private static final class Parsed {
        final String owner;
        final String method;
        Parsed(String owner, String method) { this.owner = owner; this.method = method; }
    }
}
