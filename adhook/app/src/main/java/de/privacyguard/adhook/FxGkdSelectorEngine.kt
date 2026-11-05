package de.privacyguard.adhook

import li.gkd.selector.MatchOptions
import li.gkd.selector.NodeAdapter
import li.gkd.selector.Selector
import li.gkd.selector.SelectorCompileResult
import li.gkd.selector.SelectorTypeResult
import li.gkd.selector.createDefaultSelectorTypeModel

/**
 * One immutable, per-event view of an Accessibility window tree.
 *
 * Text is copied only for non-editable, non-password nodes, used synchronously
 * for local selector evaluation, and never persisted or logged.
 */
internal class FxGkdNode(
    val nodeKey: Long,
    val className: String?,
    val viewId: String?,
    val text: String?,
    val description: String?,
    val clickable: Boolean,
    val focusable: Boolean,
    val checkable: Boolean,
    val checked: Boolean,
    val editable: Boolean,
    val longClickable: Boolean,
    val visibleToUser: Boolean,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val childIndex: Int,
    val depth: Int,
    val platformHandle: Any? = null
) {
    val children: MutableList<FxGkdNode> = mutableListOf()
    var parent: FxGkdNode? = null

    val width: Int get() = (right - left).coerceAtLeast(0)
    val height: Int get() = (bottom - top).coerceAtLeast(0)
    val viewIdShort: String?
        get() = viewId?.substringAfter(":id/", viewId.substringAfterLast('/'))
}

data class FxGkdSelectorCompilation(
    val selector: Selector?,
    val error: String?
) {
    val isValid: Boolean get() = selector != null && error == null
}

/**
 * Adapter around the exact GKD-XA v1.4.8 selector/parser source compiled in
 * :fx-gkd-selector. This does not substitute a simplified regex matcher.
 */
object FxGkdSelectorEngine {
    private val typeModel by lazy(LazyThreadSafetyMode.PUBLICATION) {
        createDefaultSelectorTypeModel(false)
    }

    @JvmStatic
    fun compile(source: String): FxGkdSelectorCompilation {
        val normalized = source.trim()
        if (normalized.isEmpty() || normalized.length > 512) {
            return FxGkdSelectorCompilation(null, "选择器不能为空，且最多 512 个字符")
        }
        return try {
            when (val parsed = Selector.compile(normalized)) {
                is SelectorCompileResult.Success -> {
                    val selector = parsed.value
                    when (val checked = selector.validateType(typeModel)) {
                        is SelectorTypeResult.Success ->
                            FxGkdSelectorCompilation(selector, null)
                        is SelectorTypeResult.Failure ->
                            FxGkdSelectorCompilation(null, checked.error.message ?: "选择器属性类型无效")
                    }
                }
                is SelectorCompileResult.Failure ->
                    FxGkdSelectorCompilation(null, parsed.error.message ?: "选择器语法无效")
            }
        } catch (error: Exception) {
            FxGkdSelectorCompilation(null, error.message ?: error.javaClass.simpleName)
        }
    }

    @JvmStatic
    internal fun findMatches(
        root: FxGkdNode,
        selector: Selector,
        maximum: Int = 12
    ): List<FxGkdNode> {
        if (maximum <= 0) return emptyList()
        val adapter = FxGkdNodeAdapter
        val matches = if (selector.isMatchRoot) {
            listOfNotNull(selector.match(root, adapter, MatchOptions(fastQuery = false)))
        } else {
            adapter.querySelectorAll(root, selector, MatchOptions(fastQuery = false))
        }
        return matches.take(maximum)
    }

    private object FxGkdNodeAdapter : NodeAdapter<FxGkdNode>() {
        override fun getAttr(target: Any, name: String): Any? {
            val node = target as? FxGkdNode ?: return null
            return when (name) {
                "id" -> node.viewId
                "vid" -> node.viewIdShort
                "name" -> node.className
                "text" -> node.text
                "desc" -> node.description
                "clickable" -> node.clickable
                "focusable" -> node.focusable
                "checkable" -> node.checkable
                "checked" -> node.checked
                "editable" -> node.editable
                "longClickable" -> node.longClickable
                "visibleToUser" -> node.visibleToUser
                "left" -> node.left
                "top" -> node.top
                "right" -> node.right
                "bottom" -> node.bottom
                "width" -> node.width
                "height" -> node.height
                "childCount" -> node.children.size
                "index" -> node.childIndex
                "depth" -> node.depth
                "parent" -> node.parent
                else -> null
            }
        }

        override fun getInvoke(target: Any, name: String, args: List<Any>): Any? {
            val node = target as? FxGkdNode ?: return null
            if (name != "getChild") return null
            val index = (args.firstOrNull() as? Number)?.toInt() ?: return null
            return node.children.getOrNull(index)
        }

        override fun getName(node: FxGkdNode): String? = node.className
        override fun getChildCount(node: FxGkdNode): Int = node.children.size
        override fun getChild(node: FxGkdNode, index: Int): FxGkdNode? = node.children.getOrNull(index)
        override fun getParent(node: FxGkdNode): FxGkdNode? = node.parent
        override fun getNodeKey(node: FxGkdNode): Any = node.nodeKey

        override fun getRoot(node: FxGkdNode): FxGkdNode? {
            val visited = HashSet<Long>()
            var current = node
            while (visited.add(current.nodeKey)) {
                current = current.parent ?: return current
            }
            return null
        }
    }
}
