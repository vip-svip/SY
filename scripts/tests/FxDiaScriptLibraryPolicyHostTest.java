import de.privacyguard.adhook.imported.dia.FxDiaScriptLibraryPolicy;

/** Host-JVM regression for the validation limits used by the Dia script library. */
public final class FxDiaScriptLibraryPolicyHostTest {
    private static void expect(boolean value, String label) {
        if (!value) throw new AssertionError(label);
    }

    public static void main(String[] args) {
        expect(FxDiaScriptLibraryPolicy.validateName("  demo  ") == null,
                "trimmed names should be accepted");
        expect("".equals(FxDiaScriptLibraryPolicy.normalizeName("   ")),
                "names should be trimmed");
        expect(FxDiaScriptLibraryPolicy.validateName("") != null, "empty name rejected");
        expect(FxDiaScriptLibraryPolicy.validateName("bad|name") != null, "pipe name rejected");
        expect(FxDiaScriptLibraryPolicy.validateName("line\nname") != null,
                "control characters rejected");

        char[] oversizedName = new char[FxDiaScriptLibraryPolicy.MAX_NAME_CHARS + 1];
        java.util.Arrays.fill(oversizedName, 'n');
        expect(FxDiaScriptLibraryPolicy.validateName(new String(oversizedName)) != null,
                "oversized name rejected");
        expect(FxDiaScriptLibraryPolicy.validateSource("console.log('ok');") == null,
                "normal source accepted");
        expect(FxDiaScriptLibraryPolicy.validateSource("  ") != null,
                "empty source rejected");
        char[] oversizedSource = new char[FxDiaScriptLibraryPolicy.MAX_SOURCE_BYTES + 1];
        java.util.Arrays.fill(oversizedSource, 'x');
        expect(FxDiaScriptLibraryPolicy.validateSource(new String(oversizedSource)) != null,
                "oversized UTF-8 source rejected");
        expect(FxDiaScriptLibraryPolicy.validateCount(64, true) == null,
                "an existing entry can be replaced at the maximum");
        expect(FxDiaScriptLibraryPolicy.validateCount(64, false) != null,
                "a 65th entry is rejected");
        System.out.println("PASS: Dia Frida script-library name/source/count limits");
    }
}
