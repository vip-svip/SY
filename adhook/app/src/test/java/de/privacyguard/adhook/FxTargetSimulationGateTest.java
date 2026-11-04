package de.privacyguard.adhook;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxTargetSimulationGateTest {
    private static Set<String> set(String... values) {
        return new HashSet<>(Arrays.asList(values));
    }

    @Test public void allowsOnlyOneExplicitDebuggablePackage() {
        assertTrue(FxTargetSimulationGate.isAuthorized(
                "com.example.debug", "com.example.debug",
                set("com.example.debug"), set("com.example.debug")));
    }

    @Test public void failsOpenWhenMultiplePackagesShareProcess() {
        assertFalse(FxTargetSimulationGate.isAuthorized(
                "com.example.debug", "com.example.debug",
                set("com.example.debug", "com.example.companion"),
                set("com.example.debug", "com.example.companion")));
    }

    @Test public void rejectsCurrentPackageMismatch() {
        assertFalse(FxTargetSimulationGate.isAuthorized(
                "com.example.debug", "com.example.companion",
                set("com.example.debug"), set("com.example.debug")));
    }

    @Test public void rejectsNonDebuggableTargets() {
        assertFalse(FxTargetSimulationGate.isAuthorized(
                "com.example.release", "com.example.release",
                set("com.example.release"), Collections.emptySet()));
    }

    @Test public void rejectsMissingOrEmptyPackageState() {
        assertFalse(FxTargetSimulationGate.isAuthorized(
                null, "com.example.debug",
                set("com.example.debug"), set("com.example.debug")));
        assertFalse(FxTargetSimulationGate.isAuthorized(
                "com.example.debug", "com.example.debug",
                Collections.emptySet(), set("com.example.debug")));
        assertFalse(FxTargetSimulationGate.isAuthorized(
                "com.example.debug", "com.example.debug",
                set("com.example.debug"), Collections.emptySet()));
    }
}
