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
        expect("中".equals(FxDiaScriptLibraryPolicy.decodeUtf8(
                        new byte[]{(byte) 0xE4, (byte) 0xB8, (byte) 0xAD})),
                "valid multibyte UTF-8 must be preserved");
        boolean malformedRejected = false;
        try {
            FxDiaScriptLibraryPolicy.decodeUtf8(new byte[]{(byte) 0xC3, 0x28});
        } catch (IllegalArgumentException expected) {
            malformedRejected = true;
        }
        expect(malformedRejected, "malformed UTF-8 must be rejected instead of replacement-decoded");
        expect(FxDiaScriptLibraryPolicy.validateCount(64, true) == null,
                "an existing entry can be replaced at the maximum");
        expect(FxDiaScriptLibraryPolicy.validateCount(64, false) != null,
                "a 65th entry is rejected");
        System.out.println("PASS: Dia Frida script-library name/source/count limits");
    }
}
