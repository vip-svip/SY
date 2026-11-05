package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FxGkdSelectorEngineTest {
    private fun node(
        key: Long,
        className: String,
        text: String? = null,
        clickable: Boolean = false,
        parent: FxGkdNode? = null,
        index: Int = 0
    ) = FxGkdNode(
        nodeKey = key,
        className = className,
        viewId = null,
        text = text,
        description = null,
        clickable = clickable,
        focusable = false,
        checkable = false,
        checked = false,
        editable = false,
        longClickable = false,
        visibleToUser = true,
        left = 0,
        top = index * 20,
        right = 100,
        bottom = (index + 1) * 20,
        childIndex = index,
        depth = if (parent == null) 0 else 1
    ).also { it.parent = parent }

    @Test
    fun matchesUpstreamAttributeAndWidgetSelectors() {
        val root = node(1, "android.widget.LinearLayout")
        val skip = node(2, "android.widget.TextView", text = "Skip", parent = root)
        val action = node(3, "android.widget.Button", text = "Continue", clickable = true, parent = root)
        root.children += listOf(skip, action)

        val textRule = FxGkdSelectorEngine.compile("[text='Skip']")
        assertTrue(textRule.error ?: "text selector should compile", textRule.isValid)
        assertEquals(listOf(skip), FxGkdSelectorEngine.findMatches(root, textRule.selector!!))

        val relationRule = FxGkdSelectorEngine.compile("android.widget.LinearLayout > android.widget.Button")
        assertTrue(relationRule.error ?: "relation selector should compile", relationRule.isValid)
        assertEquals(listOf(action), FxGkdSelectorEngine.findMatches(root, relationRule.selector!!))
    }

    @Test
    fun rejectsInvalidSelectorSyntaxAndUnknownProperties() {
        val invalidSyntax = FxGkdSelectorEngine.compile("A[x=]")
        assertNull(invalidSyntax.selector)
        assertNotNull(invalidSyntax.error)

        val invalidType = FxGkdSelectorEngine.compile("[propertyThatDoesNotExist='x']")
        assertNull(invalidType.selector)
        assertNotNull(invalidType.error)
    }

    @Test
    fun rejectsDeeplyNestedMalformedSelectorWithoutCrashing() {
        // Remains below the input-length guard so this exercises the upstream parser.
        val malformed = "(".repeat(200) + "[text='unterminated"
        val result = FxGkdSelectorEngine.compile(malformed)
        assertNull(result.selector)
        assertNotNull(result.error)
    }

    @Test
    fun respectsSelectorResultLimit() {
        val root = node(1, "android.widget.LinearLayout")
        repeat(20) { index ->
            root.children += node(
                key = index + 2L,
                className = "android.widget.Button",
                text = "Skip",
                clickable = true,
                parent = root,
                index = index
            )
        }
        val selector = FxGkdSelectorEngine.compile("android.widget.Button").selector!!
        assertEquals(5, FxGkdSelectorEngine.findMatches(root, selector, maximum = 5).size)
    }
}
