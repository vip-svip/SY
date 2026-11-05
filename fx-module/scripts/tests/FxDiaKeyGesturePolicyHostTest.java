package de.privacyguard.adhook.imported.dia;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** Standalone JDK tests for original Dia ActivityKey trigger semantics. */
public final class FxDiaKeyGesturePolicyHostTest {
    private static int passed;

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
        passed++;
    }

    private static List<Integer> event(FxDiaKeyGesturePolicy policy, int key, long time) {
        return policy.onKeyDown(key, time, 0);
    }

    public static void main(String[] args) {
        FxDiaKeyGesturePolicy policy = new FxDiaKeyGesturePolicy();

        check(event(policy, 25, 1000L).isEmpty(), "first volume-down press");
        check(event(policy, 25, 1500L).equals(Arrays.asList(0)),
                "volume-down double press emits trigger 0");

        policy.reset();
        event(policy, 25, 1000L);
        check(event(policy, 25, 1400L).equals(Arrays.asList(0)),
                "second volume-down press emits double");
        check(event(policy, 25, 1800L).equals(Arrays.asList(0, 2)),
                "third volume-down press emits double and triple");

        policy.reset();
        event(policy, 4, 1000L);
        check(event(policy, 4, 1500L).equals(Arrays.asList(1)),
                "Back double press emits trigger 1");

        policy.reset();
        event(policy, 4, 1000L);
        check(event(policy, 4, 1400L).equals(Arrays.asList(1)),
                "second Back press emits double");
        check(event(policy, 4, 1800L).equals(Arrays.asList(1, 3)),
                "third Back press emits double and triple");

        policy.reset();
        event(policy, 24, 1000L);
        check(event(policy, 24, 1500L).equals(Arrays.asList(4)),
                "volume-up double press emits trigger 4");

        policy.reset();
        check(policy.onLongPress(4).equals(Collections.singletonList(5)),
                "Back long press emits trigger 5");
        check(policy.onLongPress(24).isEmpty(), "volume-up long press is ignored");

        policy.reset();
        event(policy, 25, 1000L);
        check(event(policy, 24, 1300L).equals(Collections.singletonList(6)),
                "volume-down/up chord emits trigger 6");
        policy.reset();
        event(policy, 24, 1000L);
        check(event(policy, 25, 1399L).equals(Arrays.asList(6)),
                "reverse chord order is supported");

        policy.reset();
        event(policy, 25, 1000L);
        check(policy.onKeyDown(25, 1500L, 1).isEmpty(),
                "repeat key-down event is ignored");
        check(event(policy, 25, 3100L).isEmpty(),
                "multi-press outside the time window does not fire");

        policy.reset();
        event(policy, 4, 1000L);
        event(policy, 4, 1300L);
        policy.reset();
        check(event(policy, 4, 1400L).isEmpty(),
                "reset clears previous gesture timestamps");

        // A process can host multiple packages. Interleaved presses must remain
        // independent instead of combining one package's timestamps with another.
        FxDiaKeyGesturePolicyRegistry registry = new FxDiaKeyGesturePolicyRegistry();
        FxDiaKeyGesturePolicy firstPackage = registry.forPackage("com.example.first");
        FxDiaKeyGesturePolicy secondPackage = registry.forPackage("com.example.second");
        check(firstPackage != null && secondPackage != null && firstPackage != secondPackage,
                "registry allocates independent gesture state per package");
        check(firstPackage.onKeyDown(25, 1000L, 0).isEmpty(),
                "first package first press starts its own sequence");
        check(secondPackage.onKeyDown(25, 1400L, 0).isEmpty(),
                "second package press does not join first package sequence");
        check(firstPackage.onKeyDown(25, 1500L, 0).equals(Arrays.asList(0)),
                "first package double press survives interleaved second package event");
        check(secondPackage.onKeyDown(25, 1900L, 0).equals(Arrays.asList(0)),
                "second package completes only its own double press");
        registry.remove("com.example.first");
        check(registry.forPackage("com.example.first") != firstPackage,
                "removing a package resets its previous gesture timestamps");

        check(FxDiaKeyGesturePolicy.hasOverlappingTriggers(0, 2),
                "volume-down double and triple gestures overlap");
        check(FxDiaKeyGesturePolicy.hasOverlappingTriggers(1, 3),
                "Back double and triple gestures overlap");
        check(FxDiaKeyGesturePolicy.hasOverlappingTriggers(0, 6),
                "volume-down double can overlap with volume chord");
        check(FxDiaKeyGesturePolicy.hasOverlappingTriggers(4, 6),
                "volume-up double can overlap with volume chord");
        check(!FxDiaKeyGesturePolicy.hasOverlappingTriggers(0, 4),
                "different volume-key double gestures do not overlap");
        check(!FxDiaKeyGesturePolicy.hasOverlappingTriggers(-1, 6),
                "disabled actions do not conflict");

        System.out.println("PASS: " + passed + " Dia key gesture host assertions");
    }
}
