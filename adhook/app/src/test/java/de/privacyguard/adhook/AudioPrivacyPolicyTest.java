package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AudioPrivacyPolicyTest {
    @Test public void microphoneBlockIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.audio,mic_block=1\n").targets.get("com.example.audio");
        assertTrue(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "com.example.audio", target));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(false, 1, "com.example.audio", target));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 2, "com.example.audio", target));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "android", target));
    }
}
