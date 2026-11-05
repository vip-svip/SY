package de.privacyguard.adhook.gkd

import li.gkd.selector.NodeAdapter
import li.gkd.selector.Selector
import li.gkd.selector.SelectorCompileResult
import li.gkd.selector.SelectorParseResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Verifies the pinned GKD-XA v1.4.8 selector parser and matcher from FX's
 * single JVM-17 selector module. This test does not start the GKD application
 * or its independent AccessibilityService.
 */
class GkdSelectorSmokeTest {
    private class TestNode(
        val className: String,
        val attributes: Map<String, Any?> = emptyMap()
    ) {
        val children = mutableListOf<TestNode>()
        var parent: TestNode? = null

        fun add(child: TestNode): TestNode {
            child.parent = this
            children += child
            return child
        }
    }

    private class TestAdapter : NodeAdapter<TestNode>() {
        override fun getAttr(target: Any, name: String): Any? {
            val node = target as? TestNode ?: return null
            return when (name) {
                "name" -> node.className
                "childCount" -> node.children.size
                "index" -> node.parent?.children?.indexOfFirst { it === node } ?: 0
                else -> node.attributes[name]
            }
        }

        override fun getName(node: TestNode): String = node.className
        override fun getChildCount(node: TestNode): Int = node.children.size
        override fun getChild(node: TestNode, index: Int): TestNode? = node.children.getOrNull(index)
        override fun getParent(node: TestNode): TestNode? = node.parent
        override fun getNodeKey(node: TestNode): Any = System.identityHashCode(node)
    }

    @Test
    fun compilesAndMatchesAnAccessibilityStyleNodeTree() {
        val root = TestNode("android.view.ViewGroup")
        val button = root.add(
            TestNode(
                "android.widget.Button",
                mapOf("text" to "Skip", "clickable" to true, "enabled" to true)
            )
        )

        val compiled = Selector.compile("android.widget.Button[text='Skip']")
        assertTrue("selector must compile", compiled is SelectorCompileResult.Success)

        val selector = (compiled as SelectorCompileResult.Success).value
        val match = TestAdapter().querySelector(root, selector)
        assertNotNull("selector must find the matching descendant", match)
        assertSame(button, match)
    }

    @Test
    fun exposesStructuredParseAndTokenResults() {
        val parsed = Selector.parse("android.widget.Button[text='Skip']")
        assertTrue(parsed is SelectorParseResult.Success)
        assertTrue(Selector.tokenize("android.widget.Button[text='Skip']").isNotEmpty())
        assertEquals("android.widget.Button[text='Skip']", parsed.value.toString())
    }

    @Test
    fun returnsStructuredFailureForInvalidSyntax() {
        val invalid = Selector.compile("android.widget.Button[text=]")
        assertTrue(invalid is SelectorCompileResult.Failure)
    }
}
