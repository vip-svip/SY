import de.privacyguard.adhook.imported.dia.FxDiaScriptLibraryPolicy;

/** Host-JVM regression for unbounded Dia script-library capacity and input validation. */
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
        expect(FxDiaScriptLibraryPolicy.validateName("line\\nname") != null,
                "control characters rejected");

        char[] longName = new char[4096];
        java.util.Arrays.fill(longName, 'n');
        expect(FxDiaScriptLibraryPolicy.validateName(new String(longName)) == null,
                "long names must not be rejected by an arbitrary character cap");
        expect(FxDiaScriptLibraryPolicy.validateSource("console.log('ok');") == null,
                "normal source accepted");
        expect(FxDiaScriptLibraryPolicy.validateSource("  ") != null,
                "empty source rejected");
        char[] largeSource = new char[2 * 1024 * 1024];
        java.util.Arrays.fill(largeSource, 'x');
        expect(FxDiaScriptLibraryPolicy.validateSource(new String(largeSource)) == null,
                "large source must not be rejected by an arbitrary byte cap");
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
        System.out.println("PASS: Dia Frida script-library validation has no arbitrary size/count cap");
    }
}
