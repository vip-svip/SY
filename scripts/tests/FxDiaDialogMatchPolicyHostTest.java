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

        rejects("x".repeat(97), "single-term length cap");
        StringBuilder tooMany = new StringBuilder();
        for (int i = 0; i < 33; i++) tooMany.append("term").append(i).append('\n');
        rejects(tooMany.toString(), "unique term count cap");
        rejects("x\u0001y", "control characters rejected");
        rejects("界".repeat(400), "raw UTF-8 byte cap");

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
