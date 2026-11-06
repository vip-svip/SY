package de.privacyguard.adhook

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Owns a complete per-event copy of one live AccessibilityNodeInfo tree. The caller must
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
        private const val MAX_DEPTH = 32

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
            var truncated = false

            fun copyNode(
                info: AccessibilityNodeInfo,
                parent: FxGkdNode?,
                index: Int,
                depth: Int
            ): FxGkdNode? {
                if (depth > MAX_DEPTH) {
                    truncated = true
                    try { info.recycle() } catch (_: RuntimeException) {}
                    return null
                }

                // Register ownership before touching platform-backed properties:
                // any getter below may throw if the accessibility node was invalidated.
                handles.add(info)
                val sensitive = info.isPassword || info.isEditable
                val text = if (sensitive) null else info.text?.toString()
                val description = if (sensitive) null
                    else info.contentDescription?.toString()
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

                val reportedChildCount = try {
                    info.childCount.coerceAtLeast(0)
                } catch (_: RuntimeException) {
                    truncated = true
                    0
                }
                for (childIndex in 0 until reportedChildCount) {
                    val child = try {
                        info.getChild(childIndex)
                    } catch (_: RuntimeException) {
                        truncated = true
                        null
                    }
                    if (child == null) {
                        // A child reported by the platform but unavailable to this
                        // snapshot means the tree is incomplete; never match a prefix.
                        truncated = true
                        continue
                    }
                    copyNode(child, node, childIndex, depth + 1)?.let(node.children::add)
                }
                return node
            }

            return try {
                val snapshotRoot = copyNode(rootHandle, null, 0, 0)
                if (snapshotRoot == null || truncated) {
                    for (node in handles.asReversed()) {
                        try { node.recycle() } catch (_: RuntimeException) {}
                    }
                    return null
                }
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
