package de.privacyguard.adhook

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Owns a bounded copy of one live AccessibilityNodeInfo tree. The caller must
 * close it immediately after matching/action dispatch; handles are never stored
 * in preferences, logs, broadcasts or long-lived caches.
 */
internal class FxGkdAccessibilitySnapshot private constructor(
    val root: FxGkdNode,
    private val handles: List<AccessibilityNodeInfo>
) : AutoCloseable {
    override fun close() {
        for (node in handles.asReversed()) {
            try {
                node.recycle()
            } catch (_: RuntimeException) {
                // Some Android versions recycle nodes eagerly; cleanup remains best-effort.
            }
        }
    }

    companion object {
        private const val MAX_NODES = 700
        private const val MAX_DEPTH = 32
        private const val MAX_CHILDREN_PER_NODE = 80
        private const val MAX_TEXT_LENGTH = 256

        /**
         * Takes ownership of [rootHandle], including on failure.
         *
         * Text and content-description are not read from password or editable
         * nodes. This keeps message composers, search boxes and credentials out
         * of the selector text surface.
         */
        fun capture(rootHandle: AccessibilityNodeInfo): FxGkdAccessibilitySnapshot? {
            val handles = ArrayList<AccessibilityNodeInfo>()
            var nextKey = 1L

            fun copyNode(
                info: AccessibilityNodeInfo,
                parent: FxGkdNode?,
                index: Int,
                depth: Int
            ): FxGkdNode? {
                if (depth > MAX_DEPTH || handles.size >= MAX_NODES) {
                    try { info.recycle() } catch (_: RuntimeException) {}
                    return null
                }

                handles.add(info)
                val sensitive = info.isPassword || info.isEditable
                val text = if (sensitive) null else info.text?.toString()?.take(MAX_TEXT_LENGTH)
                val description = if (sensitive) null
                    else info.contentDescription?.toString()?.take(MAX_TEXT_LENGTH)
                val bounds = Rect()
                try { info.getBoundsInScreen(bounds) } catch (_: RuntimeException) { bounds.setEmpty() }

                val node = FxGkdNode(
                    nodeKey = nextKey++,
                    className = info.className?.toString(),
                    viewId = info.viewIdResourceName,
                    text = text,
                    description = description,
                    clickable = info.isClickable,
                    focusable = info.isFocusable,
                    checkable = info.isCheckable,
                    checked = info.isChecked,
                    editable = info.isEditable,
                    longClickable = info.isLongClickable,
                    visibleToUser = info.isVisibleToUser,
                    left = bounds.left,
                    top = bounds.top,
                    right = bounds.right,
                    bottom = bounds.bottom,
                    childIndex = index,
                    depth = depth,
                    platformHandle = info
                )
                node.parent = parent

                val childCount = try {
                    info.childCount.coerceIn(0, MAX_CHILDREN_PER_NODE)
                } catch (_: RuntimeException) {
                    0
                }
                for (childIndex in 0 until childCount) {
                    if (handles.size >= MAX_NODES) break
                    val child = try { info.getChild(childIndex) } catch (_: RuntimeException) { null }
                    if (child != null) {
                        copyNode(child, node, childIndex, depth + 1)?.let(node.children::add)
                    }
                }
                return node
            }

            return try {
                val snapshotRoot = copyNode(rootHandle, null, 0, 0) ?: return null
                FxGkdAccessibilitySnapshot(snapshotRoot, handles)
            } catch (_: RuntimeException) {
                for (node in handles.asReversed()) {
                    try { node.recycle() } catch (_: RuntimeException) {}
                }
                null
            }
        }
    }
}
