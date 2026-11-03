package de.privacyguard.adhook.imported.dia;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

/** Dalvik instruction-boundary regression tests for the read-only DEX indexer. */
public final class FxDiaDexIndexTest {
    @Test public void constWideConsumesOpcodeAndFourLiteralCodeUnits() {
        assertEquals(5, FxDiaDexIndex.instructionWidth(0x18));
    }

    @Test public void multiUnitInstructionsRetainTheirEncodedWidths() {
        assertEquals(2, FxDiaDexIndex.instructionWidth(0x02)); // move/from16
        assertEquals(3, FxDiaDexIndex.instructionWidth(0x03)); // move/16
        assertEquals(3, FxDiaDexIndex.instructionWidth(0x1b)); // const-string/jumbo
        assertEquals(3, FxDiaDexIndex.instructionWidth(0x2b)); // packed-switch
        assertEquals(3, FxDiaDexIndex.instructionWidth(0x6e)); // invoke-virtual
        assertEquals(4, FxDiaDexIndex.instructionWidth(0xfa)); // invoke-polymorphic
    }

    @Test public void customInvokeInstructionsConsumeThreeCodeUnits() {
        // These opcodes reference call_site_ids rather than method_ids. The
        // indexer intentionally omits their call edges but must still skip
        // the complete instruction so later invoke edges remain aligned.
        assertEquals(3, FxDiaDexIndex.instructionWidth(0xfc)); // invoke-custom
        assertEquals(3, FxDiaDexIndex.instructionWidth(0xfd)); // invoke-custom/range
    }

    @Test public void decodesAsciiAndModifiedNull() throws Exception {
        assertEquals("Dia", FxDiaDexIndex.decodeMutf8(
                new byte[] {'D', 'i', 'a', 0}, 0, 3));
        assertEquals("\\u0000", FxDiaDexIndex.decodeMutf8(
                new byte[] {(byte) 0xc0, (byte) 0x80, 0}, 0, 1));
    }

    @Test public void decodesThreeByteCharactersAndUtf16SurrogatePairs() throws Exception {
        assertEquals("猫", FxDiaDexIndex.decodeMutf8(
                new byte[] {(byte) 0xe7, (byte) 0x8c, (byte) 0xab, 0}, 0, 1));
        assertEquals("😀", FxDiaDexIndex.decodeMutf8(
                new byte[] {(byte) 0xed, (byte) 0xa0, (byte) 0xbd,
                        (byte) 0xed, (byte) 0xb8, (byte) 0x80, 0}, 0, 2));
    }

    @Test public void rejectsMalformedModifiedUtf8AndLengthMismatch() throws Exception {
        assertMalformed(new byte[] {(byte) 0xc2, 'A', 0}, 1);
        assertMalformed(new byte[] {'A', 0}, 2);
        assertMalformed(new byte[] {(byte) 0xf0, (byte) 0x9f, (byte) 0x98, (byte) 0x80, 0}, 2);
    }

    private static void assertMalformed(byte[] bytes, int utf16Length) {
        try {
            FxDiaDexIndex.decodeMutf8(bytes, 0, utf16Length);
            throw new AssertionError("expected malformed DEX MUTF-8 to be rejected");
        } catch (java.io.IOException expected) {
            // expected
        }
    }

    @Test public void singleUnitInstructionsRemainSingleUnit() {
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x00)); // nop
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x12)); // const/4
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x27)); // throw
        assertEquals(2, FxDiaDexIndex.instructionWidth(0xfe)); // const-method-handle
        assertEquals(2, FxDiaDexIndex.instructionWidth(0xff)); // const-method-type
    }
}
