package de.privacyguard.adhook.gkd

import li.gkd.selector.Selector
import li.gkd.selector.SelectorCompileResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Smoke tests the pinned GKD-XA selector/parser on FX's Java 17 JVM target. */
class GkdSelectorSmokeTest {
    @Test
    fun compilesNativeWidgetAndAttributeSelectors() {
        val widget = Selector.compile("android.widget.TextView")
        assertTrue("widget selector must compile", widget is SelectorCompileResult.Success)

        val attribute = Selector.compile("[text='Skip']")
        assertTrue("attribute selector must compile", attribute is SelectorCompileResult.Success)
        assertEquals("[text='Skip']", (attribute as SelectorCompileResult.Success).value.toString())
    }

    @Test
    fun compilesRelationsAndLogicalExpressions() {
        val relation = Selector.compile("android.widget.TextView > android.widget.Button")
        assertTrue("relation selector must compile", relation is SelectorCompileResult.Success)

        val logical = Selector.compile("(A) || (B) && !(C)")
        assertTrue("logical selector must compile", logical is SelectorCompileResult.Success)
    }

    @Test
    fun reportsInvalidSyntaxWithoutThrowing() {
        val invalid = Selector.compile("A[x=]")
        assertTrue("invalid syntax must return a structured failure", invalid is SelectorCompileResult.Failure)
    }
}
