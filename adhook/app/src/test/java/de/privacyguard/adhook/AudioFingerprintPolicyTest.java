package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AudioFingerprintPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.audio," + flags + "\n").targets.get("com.example.audio");
    }

    @Test public void perturbationIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("audio_fp_block=1");
        assertTrue(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "com.example.audio", t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(false, 1, "com.example.audio", t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 2, "com.example.audio", t));
    }

    @Test public void microphoneSilenceTakesPrecedenceOverPerturbation() {
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "com.example.audio",
                target("audio_fp_block=1,mic_block=1")));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target("audio_fp_block=1");
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "android", t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "de.privacyguard.adhook", t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "org.lsposed.manager", t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, null, t));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "com.example.audio", null));
        assertFalse(AudioFingerprintPolicy.shouldPerturbSamples(true, 1, "com.example.audio",
                target("audio_fp_block=0")));
    }
}
