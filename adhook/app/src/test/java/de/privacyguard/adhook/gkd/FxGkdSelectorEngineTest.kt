package de.privacyguard.adhook.gkd

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FxGkdSelectorEngineTest {
    @Test
    fun exposesCanonicalSelectorAndTokens() {
        val result = FxGkdSelectorEngine.validate("Button[text='OK']")
        assertTrue(result.valid)
        assertEquals("Button[text=\"OK\"]", result.canonical)
        assertTrue(result.tokens.isNotEmpty())
        assertNotNull(result.tokens.first().kind)
    }

    @Test
    fun reportsUpstreamParserErrorIndex() {
        val result = FxGkdSelectorEngine.validate("Button[text=]")
        assertFalse(result.valid)
        assertEquals(12, result.errorIndex)
        assertNotNull(result.error)
    }

    @Test
    fun rejectsOversizedInputBeforeParsing() {
        val result = FxGkdSelectorEngine.validate("A".repeat(16_385))
        assertFalse(result.valid)
        assertEquals(16_384, result.errorIndex)
    }
}
