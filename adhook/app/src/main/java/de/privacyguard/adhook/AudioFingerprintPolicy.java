package de.privacyguard.adhook;

/** Policy for opt-in, low-amplitude audio sample perturbation. */
public final class AudioFingerprintPolicy {
    private AudioFingerprintPolicy() {}

    public static boolean shouldPerturbSamples(boolean privacyEnabled, int processPackageCount,
                                               String packageName,
                                               UnifiedHookConfigParser.Target target) {
        if (!privacyEnabled || processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        // mic_block is a stronger policy: the modern implementation silences capture.
        return target.audioFpBlock && !target.micBlock;
    }
}
