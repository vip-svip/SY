package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AudioPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.audio," + flags + "\n").targets.get("com.example.audio");
    }

    @Test public void microphoneBlockIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("mic_block=1");
        assertTrue(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "com.example.audio", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(false, 1, "com.example.audio", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 2, "com.example.audio", t));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target("mic_block=1");
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "android", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "system", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "de.privacyguard.adhook", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "org.lsposed.manager", t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, null, t));
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1, "com.example.audio", null));
    }

    @Test public void disabledPerAppFlagDoesNotSuppressAudio() {
        assertFalse(AudioPrivacyPolicy.shouldSilenceAudioRecord(true, 1,
                "com.example.audio", target("mic_block=0")));
    }
}
