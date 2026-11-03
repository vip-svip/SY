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

    @Test public void singleUnitInstructionsRemainSingleUnit() {
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x00)); // nop
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x12)); // const/4
        assertEquals(1, FxDiaDexIndex.instructionWidth(0x27)); // throw
        assertEquals(2, FxDiaDexIndex.instructionWidth(0xfe)); // const-method-handle
        assertEquals(2, FxDiaDexIndex.instructionWidth(0xff)); // const-method-type
    }
}
