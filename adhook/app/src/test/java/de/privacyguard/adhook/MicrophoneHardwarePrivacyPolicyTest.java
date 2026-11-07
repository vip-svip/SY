package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class MicrophoneHardwarePrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flag) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.audio," + flag + "\n").targets.get("com.example.audio");
    }

    @Test public void inputDeviceHidingIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target t = target("mic_hw_hide=1");
        assertTrue(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "com.example.audio", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(false, 1, "com.example.audio", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 2, "com.example.audio", t));
    }

    @Test public void protectedUnknownAndUnselectedTargetsFailOpen() {
        UnifiedHookConfigParser.Target t = target("mic_hw_hide=1");
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "android", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "system", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "de.privacyguard.adhook", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "org.lsposed.manager", t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, null, t));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1, "com.example.audio", null));
        assertFalse(MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(true, 1,
                "com.example.audio", target("mic_hw_hide=0")));
    }
}
