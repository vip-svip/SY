package de.privacyguard.adhook.imported.shield;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxYulongWhitelistPolicyTest {
    @Test public void parsesValidPackageNamesAndDeduplicates() {
        Set<String> values = FxYulongWhitelistPolicy.parse(
                "com.example.app, com.example.app, org.example_tool.client");
        assertEquals(2, values.size());
        assertTrue(values.contains("com.example.app"));
        assertTrue(values.contains("org.example_tool.client"));
    }

    @Test public void rejectsWholeWhitelistWhenAnyPackageNameIsMalformed() {
        Set<String> values = FxYulongWhitelistPolicy.parse(
                "com.example.good, ../bad, com..bad, package name, not-a-package");
        assertTrue(values.isEmpty());
        assertFalse(FxYulongWhitelistPolicy.isWellFormed(
                "com.example.good, ../bad"));
    }

    @Test public void rejectsEmptyCsvEntriesInsteadOfPartiallyTrustingTheList() {
        assertTrue(FxYulongWhitelistPolicy.parse("com.example.good,,org.example.app").isEmpty());
        assertFalse(FxYulongWhitelistPolicy.isWellFormed("com.example.good,"));
    }

    @Test public void acceptsEmptyWhitelistAndValidDeduplicatedEntries() {
        assertTrue(FxYulongWhitelistPolicy.isWellFormed(""));
        assertTrue(FxYulongWhitelistPolicy.isWellFormed("com.example.app, com.example.app"));
    }

    @Test public void emptyAndNullValuesProduceEmptyWhitelist() {
        assertTrue(FxYulongWhitelistPolicy.parse(null).isEmpty());
        assertTrue(FxYulongWhitelistPolicy.parse("").isEmpty());
    }

    @Test public void serializerDeduplicatesAndRoundTrips() {
        String encoded = FxYulongWhitelistPolicy.serialize(Arrays.asList(
                "com.example.app", "com.example.app", "org.example.tool"));
        assertEquals("com.example.app,org.example.tool", encoded);
        assertEquals(FxYulongWhitelistPolicy.parse(encoded),
                FxYulongWhitelistPolicy.parse("com.example.app,org.example.tool"));
    }

    @Test public void serializerRejectsInvalidPackageInsteadOfDroppingIt() {
        assertEquals(null, FxYulongWhitelistPolicy.serialize(
                Arrays.asList("com.example.good", "../bad")));
    }

    private static String repeat(char value, int count) {
        char[] chars = new char[count];
        Arrays.fill(chars, value);
        return new String(chars);
    }

    @Test public void packageLookupRejectsInvalidNamesBeforePreferenceRead() {
        assertFalse(FxYulongWhitelistPolicy.isWhitelisted(null, "../bad"));
        assertFalse(FxYulongWhitelistPolicy.isWhitelisted(null, "com..bad"));
    }
}
