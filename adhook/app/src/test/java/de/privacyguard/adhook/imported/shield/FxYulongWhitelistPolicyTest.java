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

    @Test public void ignoresMalformedPackageNames() {
        Set<String> values = FxYulongWhitelistPolicy.parse(
                ", ../bad, com..bad, package name, not-a-package, com.example.good");
        assertEquals(Collections.singleton("com.example.good"), values);
    }

    @Test public void emptyAndNullValuesProduceEmptyWhitelist() {
        assertTrue(FxYulongWhitelistPolicy.parse(null).isEmpty());
        assertTrue(FxYulongWhitelistPolicy.parse("").isEmpty());
    }

    @Test public void oversizedRawValueFailsOpenInsteadOfSuppressingFindings() {
        char[] value = new char[FxYulongWhitelistPolicy.MAX_RAW_CHARS + 1];
        Arrays.fill(value, 'x');
        assertTrue(FxYulongWhitelistPolicy.parse(new String(value)).isEmpty());
    }

    @Test public void excessiveEntryCountFailsOpenInsteadOfPartiallyTrustingWhitelist() {
        StringBuilder value = new StringBuilder();
        for (int i = 0; i <= FxYulongWhitelistPolicy.MAX_ENTRIES; i++) {
            if (value.length() > 0) value.append(',');
            value.append("com.example.app").append(i);
        }
        assertTrue(FxYulongWhitelistPolicy.parse(value.toString()).isEmpty());
    }

    @Test public void acceptsExactlyTheDocumentedMaximumEntryCount() {
        StringBuilder value = new StringBuilder();
        for (int i = 0; i < FxYulongWhitelistPolicy.MAX_ENTRIES; i++) {
            if (value.length() > 0) value.append(',');
            value.append("com.example.app").append(i);
        }
        assertEquals(FxYulongWhitelistPolicy.MAX_ENTRIES,
                FxYulongWhitelistPolicy.parse(value.toString()).size());
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

    @Test public void serializerRejectsMoreThanTheMaximumEntries() {
        java.util.List<String> values = new java.util.ArrayList<>();
        for (int i = 0; i <= FxYulongWhitelistPolicy.MAX_ENTRIES; i++) {
            values.add("com.example.app" + i);
        }
        assertEquals(null, FxYulongWhitelistPolicy.serialize(values));
    }

    @Test public void serializerRejectsOversizedRawPayload() {
        java.util.List<String> values = new java.util.ArrayList<>();
        String prefix = "com." + repeat('a', 180) + ".";
        for (int i = 0; i < 6000; i++) values.add(prefix + i);
        assertEquals(null, FxYulongWhitelistPolicy.serialize(values));
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
