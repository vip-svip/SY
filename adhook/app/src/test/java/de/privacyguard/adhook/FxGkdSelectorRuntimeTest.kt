package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FxGkdSelectorRuntimeTest {
    @Test
    fun compilesGkdSelectorSyntaxAndExposesFastQueryMetadata() {
        val result = FxGkdSelectorRuntime.compile(
            "TextView[text='Continue'] + Button[clickable=true]"
        )
        assertTrue("expected a valid GKD selector, got $result", result is FxGkdSelectorRuntime.CompileResult.Ready)
        val ready = result as FxGkdSelectorRuntime.CompileResult.Ready
        assertTrue(ready.fastQueryCount >= 0)
        assertNotNull(ready.source)
    }

    @Test
    fun rejectsSyntaxErrorsWithSourceOffsets() {
        val result = FxGkdSelectorRuntime.compile("TextView[")
        assertTrue(result is FxGkdSelectorRuntime.CompileResult.Rejected)
        val rejected = result as FxGkdSelectorRuntime.CompileResult.Rejected
        assertEquals("syntax", rejected.category)
        assertNotNull(rejected.offset)
        assertFalse(rejected.message.isBlank())
    }

    @Test
    fun rejectsUnknownAccessibilityPropertiesDuringTypeCheck() {
        val result = FxGkdSelectorRuntime.compile("TextView[unknownFxProperty='x']")
        assertTrue(result is FxGkdSelectorRuntime.CompileResult.Rejected)
        val rejected = result as FxGkdSelectorRuntime.CompileResult.Rejected
        assertEquals("type", rejected.category)
        assertNotNull(rejected.offset)
    }

    @Test
    fun enforcesBoundedSelectorSourceLength() {
        val result = FxGkdSelectorRuntime.compile("A".repeat(8_193))
        assertTrue(result is FxGkdSelectorRuntime.CompileResult.Rejected)
        assertEquals(
            "size",
            (result as FxGkdSelectorRuntime.CompileResult.Rejected).category
        )
    }

    @Test
    fun acceptsGkdPropertyMethodsAndRelationshipSyntax() {
        val result = FxGkdSelectorRuntime.compile(
            "@TextView[text.length>0] + Button[clickable=true][visibleToUser=true]"
        )
        assertTrue("expected GKD relationship/property syntax, got $result", result is FxGkdSelectorRuntime.CompileResult.Ready)
    }
}
