package de.privacyguard.adhook.imported.shield;

import org.junit.Test;

import java.util.Arrays;
import java.util.Set;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxYulongBlacklistPolicyTest {
    @Test public void parsesValidEntriesAndDeduplicates() {
        Set<String> values = FxYulongBlacklistPolicy.parse(
                "com.example.app, com.example.app, org.example.tool");
        assertEquals(2, values.size());
        assertTrue(values.contains("com.example.app"));
        assertTrue(values.contains("org.example.tool"));
    }

    @Test public void rejectsEntireListWhenAnyEntryIsInvalid() {
        assertTrue(FxYulongBlacklistPolicy.parse(
                "com.example.good, ../bad, org.example.app").isEmpty());
        assertFalse(FxYulongBlacklistPolicy.isWellFormed(
                "com.example.good, ../bad"));
    }

    @Test public void rejectsEmptyCsvFields() {
        assertTrue(FxYulongBlacklistPolicy.parse("com.example.good,,org.example.app").isEmpty());
        assertFalse(FxYulongBlacklistPolicy.isWellFormed("com.example.good,"));
    }

    @Test public void acceptsNullAndEmptyLists() {
        assertTrue(FxYulongBlacklistPolicy.isWellFormed(null));
        assertTrue(FxYulongBlacklistPolicy.parse(null).isEmpty());
        assertTrue(FxYulongBlacklistPolicy.parse("").isEmpty());
    }

    @Test public void serializerDeduplicatesAndRoundTrips() {
        String encoded = FxYulongBlacklistPolicy.serialize(Arrays.asList(
                "com.example.app", "com.example.app", "org.example.tool"));
        assertEquals("com.example.app,org.example.tool", encoded);
        assertEquals(2, FxYulongBlacklistPolicy.parse(encoded).size());
    }

    @Test public void serializerRejectsInvalidEntriesInsteadOfDroppingThem() {
        assertEquals(null, FxYulongBlacklistPolicy.serialize(
                Arrays.asList("com.example.good", "../bad")));
    }

}
