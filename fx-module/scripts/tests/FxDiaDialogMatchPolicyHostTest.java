package de.privacyguard.adhook.imported.dia;

import java.util.Arrays;
import java.util.List;

/** Standalone JDK regression for the exact production Dialog match policy. */
public final class FxDiaDialogMatchPolicyHostTest {
    private static int passed;

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        passed++;
    }

    private static void rejects(String input, String message) {
        try {
            FxDiaDialogMatchPolicy.parseTerms(input);
        } catch (IllegalArgumentException expected) {
            passed++;
            return;
        }
        throw new AssertionError(message);
    }

    public static void main(String[] args) {
        List<String> textTerms = FxDiaDialogMatchPolicy.parseTerms(
                "更新失败\nPlease sign in\n更新失败\n");
        check(textTerms.equals(Arrays.asList("更新失败", "Please sign in")),
                "newline split and duplicate removal");

        check(FxDiaDialogMatchPolicy.parseTerms("  Foo  \nfoo\n")
                        .equals(Arrays.asList("Foo")),
                "case-insensitive duplicate removal");
        check(FxDiaDialogMatchPolicy.matchesText("提示：PLEASE SIGN IN 后重试", textTerms),
                "case-insensitive literal text match");
        check(!FxDiaDialogMatchPolicy.matchesText("PleaseX sign in", textTerms),
                "literal match must not behave like a regular expression");
        check(!FxDiaDialogMatchPolicy.matchesText("更新失败", java.util.Collections.emptyList()),
                "empty rules never match");
        check(FxDiaDialogMatchPolicy.parseTerms(null).isEmpty(), "null input is safe");
        check(FxDiaDialogMatchPolicy.parseTerms(" \n \t ").isEmpty(), "blank input is safe");

        List<String> idTerms = FxDiaDialogMatchPolicy.parseTerms(
                "com.example:id/alert_close\nbtn_cancel\n0x7f080001\n2131230721");
        check(FxDiaDialogMatchPolicy.matchesResourceId(0x7f080001,
                "com.example:id/alert_close", "alert_close", idTerms),
                "full resource name match");
        check(FxDiaDialogMatchPolicy.matchesResourceId(0x7f080001,
                "com.example:id/alert_close", "alert_close", Arrays.asList("alert_close")),
                "resource entry name match");
        check(FxDiaDialogMatchPolicy.matchesResourceId(0x7f080001, null, null,
                Arrays.asList("0x7f080001")), "hex resource id match");
        check(FxDiaDialogMatchPolicy.matchesResourceId(0x7f080001, null, null,
                Arrays.asList("2131230721")), "decimal resource id match");
        check(!FxDiaDialogMatchPolicy.matchesResourceId(0,
                "com.example:id/alert_close", "alert_close", idTerms),
                "NO_ID never matches");

        StringBuilder largeRules = new StringBuilder();
        String longTerm = "界".repeat(120);
        for (int i = 0; i < 40; i++) {
            largeRules.append("term").append(i).append('-').append(longTerm).append('\n');
        }
        List<String> largeTerms = FxDiaDialogMatchPolicy.parseTerms(largeRules.toString());
        check(largeTerms.size() == 40, "more than 32 unique terms are accepted");
        check(largeTerms.get(0).length() > 96, "long literal terms are accepted");
        check(largeRules.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 1024,
                "rule text beyond 1 KiB is accepted");
        check(FxDiaDialogMatchPolicy.parseTerms("界".repeat(400)).size() == 1,
                "single UTF-8 rule beyond 1 KiB is accepted");
        rejects("x\u0001y", "control characters rejected");

        StringBuilder longText = new StringBuilder();
        for (int i = 0; i < 4300; i++) longText.append('a');
        check(FxDiaDialogMatchPolicy.matchesText(longText, Arrays.asList("a")),
                "long candidate text is truncated to inspection bound");
        check(!FxDiaDialogMatchPolicy.matchesText("x".repeat(4096) + "needle",
                Arrays.asList("needle")), "text beyond inspection bound is not matched");

        try {
            textTerms.add("mutate");
            throw new AssertionError("parsed terms must be immutable");
        } catch (UnsupportedOperationException expected) {
            passed++;
        }
        System.out.println("PASS: " + passed + " Dia Dialog policy host assertions");
    }
}
