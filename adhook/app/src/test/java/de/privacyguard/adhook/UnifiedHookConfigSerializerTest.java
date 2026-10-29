package de.privacyguard.adhook;

import org.junit.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.*;

public class UnifiedHookConfigSerializerTest {
    private static Map<String, UnifiedHookConfigParser.Target> target(boolean ads, boolean privacy) {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", new UnifiedHookConfigParser.Target(
                ads, false, false, false, privacy));
        return targets;
    }

    @Test
    public void roundTripsAllIndependentMasterSwitchCombinations() {
        boolean[][] combinations = {
                {true, false}, {false, true}, {false, false}, {true, true}
        };
        for (boolean[] combination : combinations) {
            String text = UnifiedHookConfigSerializer.serialize(
                    combination[0], combination[1], target(true, true));
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
            assertEquals(combination[0], parsed.adsEnabled);
            assertEquals(combination[1], parsed.privacyEnabled);
            assertEquals(combination[0], parsed.isAdsEnabledFor("com.example.app"));
            assertEquals(combination[1], parsed.isPrivacyEnabledFor("com.example.app"));
            assertFalse(parsed.isAdsEnabledFor("com.notselected.app"));
            assertFalse(parsed.isPrivacyEnabledFor("com.notselected.app"));
        }
    }

    @Test
    public void outputIsDeterministicAndSortsPackageNames() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("org.example.zed", new UnifiedHookConfigParser.Target(false, true, false, false, false));
        targets.put("com.example.alpha", new UnifiedHookConfigParser.Target(true, false, false, false, true));
        String first = UnifiedHookConfigSerializer.serialize(true, true, targets);
        String second = UnifiedHookConfigSerializer.serialize(true, true, targets);
        assertEquals(first, second);
        assertTrue(first.indexOf("com.example.alpha") < first.indexOf("org.example.zed"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesProtectedSystemPackages() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("android", new UnifiedHookConfigParser.Target(false, false, false, false, true));
        UnifiedHookConfigSerializer.serialize(false, true, targets);
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesNullTargetRows() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", null);
        UnifiedHookConfigSerializer.serialize(true, false, targets);
    }
}
