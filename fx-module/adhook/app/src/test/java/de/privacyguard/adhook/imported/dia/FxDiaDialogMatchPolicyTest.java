package de.privacyguard.adhook.imported.dia;

import org.junit.Test;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public final class FxDiaDialogMatchPolicyTest {
    @Test public void parsesAndDeduplicatesLiteralTerms() {
        List<String> terms = FxDiaDialogMatchPolicy.parseTerms(
                "  Update required  \nupdate required\n网络错误");
        assertEquals(Arrays.asList("Update required", "网络错误"), terms);
        assertEquals("Update required\n网络错误",
                FxDiaDialogMatchPolicy.normalizeTerms("Update required\n网络错误"));
    }

    @Test public void matchesTextByCaseInsensitiveLiteralSubstring() {
        assertTrue(FxDiaDialogMatchPolicy.matchesText("Please UPDATE REQUIRED now",
                Collections.singletonList("update required")));
        assertFalse(FxDiaDialogMatchPolicy.matchesText("Please update now",
                Collections.singletonList("update required")));
        assertFalse(FxDiaDialogMatchPolicy.matchesText("anything", Collections.emptyList()));
    }

    @Test public void matchesResourceIdExactly() {
        List<String> terms = Arrays.asList("com.example:id/alert_close", "btn_cancel");
        assertTrue(FxDiaDialogMatchPolicy.matchesResourceId(0x7f010001,
                "com.example:id/alert_close", "alert_close", terms));
        assertTrue(FxDiaDialogMatchPolicy.matchesResourceId(0x7f010001,
                "com.example:id/other", "btn_cancel", terms));
        assertTrue(FxDiaDialogMatchPolicy.matchesResourceId(0x7f010001,
                "com.example:id/other", "other", Collections.singletonList("0x7f010001")));
        assertFalse(FxDiaDialogMatchPolicy.matchesResourceId(0,
                "com.example:id/alert_close", "alert_close", terms));
    }

    @Test public void acceptsMoreThanThirtyTwoLongTerms() {
        StringBuilder value = new StringBuilder();
        for (int i = 0; i < 40; i++) {
            value.append("term").append(i).append('-').append(repeat('界', 120)).append('\n');
        }
        List<String> terms = FxDiaDialogMatchPolicy.parseTerms(value.toString());
        assertEquals(40, terms.size());
        assertTrue(terms.get(0).length() > 96);
    }

    @Test public void acceptsRawRuleTextOverOneKiB() {
        String value = repeat('界', 400);
        assertEquals(Collections.singletonList(value), FxDiaDialogMatchPolicy.parseTerms(value));
    }

    @Test public void rejectsControlCharacterTerms() {
        invalid("first\u0001second");
    }

    private static String repeat(char value, int count) {
        StringBuilder out = new StringBuilder(count);
        for (int i = 0; i < count; i++) out.append(value);
        return out.toString();
    }

    private static void invalid(String raw) {
        try {
            FxDiaDialogMatchPolicy.parseTerms(raw);
            fail("Expected bounded rule input to be rejected.");
        } catch (IllegalArgumentException expected) {
            // Expected input validation.
        }
    }
}
