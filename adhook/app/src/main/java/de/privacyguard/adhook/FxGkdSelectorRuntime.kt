package de.privacyguard.adhook

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import li.gkd.selector.FastQuery
import li.gkd.selector.MatchOptions
import li.gkd.selector.NodeAdapter
import li.gkd.selector.Selector
import li.gkd.selector.SelectorParseResult
import li.gkd.selector.SelectorTypeResult
import li.gkd.selector.createDefaultSelectorTypeModel
import java.util.ArrayDeque

/**
 * GPL-3.0 GKD-XA selector integration for FX's existing AccessibilityService.
 *
 * This component only parses, type-checks and evaluates selectors against a
 * caller-supplied AccessibilityNodeInfo tree. It does not start a second
 * AccessibilityService and it never clicks or changes UI state on its own.
 * Rule scheduling and user-approved actions remain the responsibility of FX.
 */
object FxGkdSelectorRuntime {
    private const val MAX_SELECTOR_CHARS = 8_192
    private const val MAX_CHILDREN_PER_NODE = 200
    private const val MAX_DESCENDANTS_PER_QUERY = 4_000
    private const val MAX_FAST_QUERY_RESULTS = 500
    private const val MAX_PARENT_DEPTH = 256

    private val typeModel by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        createDefaultSelectorTypeModel(webField = false)
    }

    sealed class CompileResult {
        data class Ready internal constructor(
            val source: String,
            internal val selector: Selector,
            val fastQueryCount: Int,
        ) : CompileResult()

        data class Rejected(
            val message: String,
            val offset: Int?,
            val category: String,
        ) : CompileResult()
    }

    /**
     * Parse and statically type-check a GKD-XA selector.
     *
     * The character cap prevents unbounded parser work from untrusted imported
     * rules. Runtime node traversal has separate per-query bounds below.
     */
    @JvmStatic
    fun compile(source: String): CompileResult {
        if (source.isBlank()) {
            return CompileResult.Rejected("选择器不能为空", 0, "empty")
        }
        if (source.length > MAX_SELECTOR_CHARS) {
            return CompileResult.Rejected(
                "选择器超过 $MAX_SELECTOR_CHARS 个字符",
                MAX_SELECTOR_CHARS,
                "size",
            )
        }

        val parsed = try {
            Selector.parse(source)
        } catch (error: RuntimeException) {
            return CompileResult.Rejected(
                error.message ?: "选择器解析失败",
                null,
                "parser",
            )
        }

        if (parsed is SelectorParseResult.Failure) {
            return CompileResult.Rejected(
                parsed.error.message ?: "选择器语法错误",
                parsed.error.index,
                "syntax",
            )
        }
        parsed as SelectorParseResult.Success
        val selector = parsed.value

        return when (val checked = selector.validateType(typeModel)) {
            is SelectorTypeResult.Success -> CompileResult.Ready(
                source = source,
                selector = selector,
                fastQueryCount = selector.fastQueryList.size,
            )
            is SelectorTypeResult.Failure -> CompileResult.Rejected(
                checked.error.message ?: "选择器类型检查失败",
                checked.error.index,
                "type",
            )
        }
    }

    /**
     * Return the first matching node from the supplied window root.
     * This is a read-only match operation; no AccessibilityNodeInfo action is
     * performed. The caller must use a current, non-recycled root from FX's
     * already-authorized AccessibilityService.
     */
    @JvmStatic
    fun findFirst(
        root: AccessibilityNodeInfo,
        compiled: CompileResult.Ready,
        fastQuery: Boolean = true,
    ): AccessibilityNodeInfo? {
        val options = MatchOptions(fastQuery = fastQuery)
        if (compiled.selector.isMatchRoot) {
            return compiled.selector.match(root, ACCESSIBILITY_ADAPTER, options)
        }
        compiled.selector.match(root, ACCESSIBILITY_ADAPTER, options)?.let { return it }
        return ACCESSIBILITY_ADAPTER.querySelector(root, compiled.selector, options)
    }

    /**
     * Enumerate matches with an explicit cap. Callers should run this off the
     * main thread using a fresh root snapshot and discard results on new events.
     */
    @JvmStatic
    fun findAll(
        root: AccessibilityNodeInfo,
        compiled: CompileResult.Ready,
        limit: Int = 100,
        fastQuery: Boolean = true,
    ): List<AccessibilityNodeInfo> {
        val safeLimit = limit.coerceIn(1, MAX_FAST_QUERY_RESULTS)
        val output = ArrayList<AccessibilityNodeInfo>(minOf(safeLimit, 16))
        val seen = HashSet<AccessibilityNodeInfo>()
        val options = MatchOptions(fastQuery = fastQuery)
        if (compiled.selector.isMatchRoot) {
            val rootMatch = compiled.selector.match(root, ACCESSIBILITY_ADAPTER, options)
            return if (rootMatch == null) emptyList() else listOf(rootMatch)
        }

        fun collect(node: AccessibilityNodeInfo?) {
            if (node == null || output.size >= safeLimit || !seen.add(node)) return
            compiled.selector.match(node, ACCESSIBILITY_ADAPTER, options)?.let(output::add)
        }

        // GKD selectors can explicitly target the root. Test it once, then
        // walk descendants incrementally so the result cap bounds memory/work.
        collect(root)
        val candidates = if (fastQuery && compiled.selector.fastQueryList.isNotEmpty()) {
            ACCESSIBILITY_ADAPTER.getFastQueryDescendants(root, compiled.selector.fastQueryList.toList())
        } else {
            ACCESSIBILITY_ADAPTER.getDescendants(root)
        }
        for (candidate in candidates) {
            if (output.size >= safeLimit) break
            collect(candidate)
        }
        return output
    }

    private val ACCESSIBILITY_ADAPTER = object : NodeAdapter<AccessibilityNodeInfo>() {
        override fun getAttr(target: Any, name: String): Any? {
            val node = target as? AccessibilityNodeInfo ?: return null
            return when (name) {
                "id" -> safe { node.viewIdResourceName?.toString() }
                "vid" -> safe {
                    node.viewIdResourceName?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
                }
                "name" -> safe { node.className?.toString() }
                "text" -> safe { node.text?.toString() }
                "desc" -> safe { node.contentDescription?.toString() }
                "clickable" -> safe { node.isClickable }
                "focusable" -> safe { node.isFocusable }
                "checkable" -> safe { node.isCheckable }
                "checked" -> safe { node.isChecked }
                "editable" -> safe { node.isEditable }
                "longClickable" -> safe { node.isLongClickable }
                "visibleToUser" -> safe { node.isVisibleToUser }
                "left", "top", "right", "bottom", "width", "height" -> {
                    val bounds = Rect()
                    safe { node.getBoundsInScreen(bounds) }
                    when (name) {
                        "left" -> bounds.left
                        "top" -> bounds.top
                        "right" -> bounds.right
                        "bottom" -> bounds.bottom
                        "width" -> bounds.width()
                        else -> bounds.height()
                    }
                }
                "childCount" -> safe { node.childCount.coerceAtMost(MAX_CHILDREN_PER_NODE) }
                "index" -> nodeIndex(node)
                "depth" -> nodeDepth(node)
                "parent" -> safe { node.parent }
                else -> null
            }
        }

        override fun getInvoke(target: Any, name: String, args: List<Any>): Any? {
            val node = target as? AccessibilityNodeInfo ?: return null
            if (name != "getChild") return null
            val index = args.firstOrNull() as? Int ?: return null
            if (index < 0 || index >= getChildCount(node)) return null
            return getChild(node, index)
        }

        override fun getName(node: AccessibilityNodeInfo): String? =
            safe { node.className?.toString() }

        override fun getChildCount(node: AccessibilityNodeInfo): Int =
            safe { node.childCount.coerceIn(0, MAX_CHILDREN_PER_NODE) } ?: 0

        override fun getChild(node: AccessibilityNodeInfo, index: Int): AccessibilityNodeInfo? =
            if (index !in 0 until MAX_CHILDREN_PER_NODE) null else safe { node.getChild(index) }

        override fun getParent(node: AccessibilityNodeInfo): AccessibilityNodeInfo? =
            safe { node.parent }

        override fun getNodeKey(node: AccessibilityNodeInfo): Any = node

        override fun getDescendants(node: AccessibilityNodeInfo): Sequence<AccessibilityNodeInfo> =
            sequence {
                val visited = HashSet<AccessibilityNodeInfo>()
                visited.add(node)
                val stack = ArrayDeque<AccessibilityNodeInfo>()
                val initialCount = getChildCount(node)
                for (index in initialCount - 1 downTo 0) {
                    getChild(node, index)?.let(stack::addLast)
                }
                var yielded = 0
                while (stack.isNotEmpty() && yielded < MAX_DESCENDANTS_PER_QUERY) {
                    val current = stack.removeLast()
                    if (!visited.add(current)) continue
                    yielded++
                    yield(current)
                    val count = getChildCount(current)
                    for (index in count - 1 downTo 0) {
                        getChild(current, index)?.let(stack::addLast)
                    }
                }
            }

        override fun getFastQueryDescendants(
            node: AccessibilityNodeInfo,
            fastQueryList: List<FastQuery>,
        ): Sequence<AccessibilityNodeInfo> = sequence {
            val yielded = HashSet<AccessibilityNodeInfo>()
            yielded.add(node)
            var total = 0
            for (query in fastQueryList) {
                if (total >= MAX_FAST_QUERY_RESULTS) break
                val candidates = when (query) {
                    is FastQuery.Id -> safeList {
                        node.findAccessibilityNodeInfosByViewId(query.value)
                    }
                    is FastQuery.Vid -> {
                        val packageName = safe { node.packageName?.toString() }.orEmpty()
                        val resourceId = if (query.value.contains(":id/")) {
                            query.value
                        } else {
                            "$packageName:id/${query.value}"
                        }
                        safeList { node.findAccessibilityNodeInfosByViewId(resourceId) }
                    }
                    is FastQuery.Text -> safeList {
                        node.findAccessibilityNodeInfosByText(query.value)
                    }
                }
                for (candidate in candidates) {
                    if (total >= MAX_FAST_QUERY_RESULTS) break
                    val attribute = when (query) {
                        is FastQuery.Id -> getAttr(candidate, "id")
                        is FastQuery.Vid -> getAttr(candidate, "vid")
                        is FastQuery.Text -> getAttr(candidate, "text")
                    }
                    if (yielded.add(candidate) && query.accepts(attribute?.toString() ?: "")) {
                        total++
                        yield(candidate)
                    }
                }
            }
        }

        private fun nodeIndex(node: AccessibilityNodeInfo): Int? {
            val parent = getParent(node) ?: return 0
            val count = getChildCount(parent)
            for (index in 0 until count) {
                if (getChild(parent, index) == node) return index
            }
            return 0
        }

        private fun nodeDepth(node: AccessibilityNodeInfo): Int? {
            var current = node
            val visited = HashSet<AccessibilityNodeInfo>()
            var depth = 0
            while (visited.add(current)) {
                val parent = getParent(current) ?: return depth
                current = parent
                depth++
                if (depth >= MAX_PARENT_DEPTH) return null
            }
            return null
        }
    }

    private inline fun <T> safe(block: () -> T): T? = try {
        block()
    } catch (_: RuntimeException) {
        null
    }

    private inline fun safeList(block: () -> List<AccessibilityNodeInfo>): List<AccessibilityNodeInfo> =
        safe(block) ?: emptyList()
}
