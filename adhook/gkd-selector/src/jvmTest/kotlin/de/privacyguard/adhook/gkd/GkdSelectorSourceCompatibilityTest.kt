package de.privacyguard.adhook.gkd

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import li.gkd.selector.Selector
import li.gkd.selector.SelectorCompileResult
import li.gkd.selector.SelectorParseResult
import li.gkd.selector.SelectorTokenKind

class GkdSelectorSourceCompatibilityTest {
    @Test
    fun upstreamSelectorCompilesCanonicalGkdExpressions() {
        val expressions = listOf(
            "android.widget.Button",
            "TextView[text='允许']",
            "Button[text='OK']",
            "A > B",
            "A + B",
            "A[text='确定' || text='允许']",
        )
        expressions.forEach { source ->
            val compiled = assertIs<SelectorCompileResult.Success>(Selector.compile(source), source)
            val canonical = compiled.value.toString()
            val roundTrip = assertIs<SelectorCompileResult.Success>(
                Selector.compile(canonical), "$source -> $canonical"
            )
            assertEquals(canonical, roundTrip.value.toString(), source)
        }
    }

    @Test
    fun parserReturnsSourceTokensAndIndexedErrors() {
        val valid = assertIs<SelectorParseResult.Success>(Selector.parse("Button[text='OK']"))
        assertEquals(SelectorTokenKind.Selector, valid.tokens.first().kind)
        val invalid = assertIs<SelectorParseResult.Failure>(Selector.parse("Button[text=]"))
        assertEquals(12, invalid.error.index)
    }
}
