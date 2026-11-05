package de.privacyguard.adhook

import android.accessibilityservice.AccessibilityService
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo

/**
 * A deliberately narrow first GKD execution slice:
 * - explicitly enabled local rules only;
 * - exact installed user-app package scope;
 * - local selector matching;
 * - click only on visible clickable non-editable, non-password nodes;
 * - one action per event and per-rule cooldown;
 * - no screenshots, network calls, AI, or node/text logging.
 */
object FxGkdAutomationRuntime {
    private data class CompiledRule(
        val source: FxGkdRule,
        val selector: li.gkd.selector.Selector
    )

    @Volatile
    private var cachedSource: List<FxGkdRule>? = null
    @Volatile
    private var cachedCompiled: List<CompiledRule> = emptyList()
    private val lastActionByRule = HashMap<String, Long>()
    private var lastScanAt = 0L

    @JvmStatic
    @Synchronized
    fun invalidateRules() {
        cachedSource = null
        cachedCompiled = emptyList()
        lastActionByRule.clear()
        lastScanAt = 0L
    }

    @JvmStatic
    @Synchronized
    fun process(
        service: AccessibilityService,
        eventPackage: String,
        rootHandle: AccessibilityNodeInfo
    ): Boolean {
        if (!FxGkdRuleStore.isEnabled(service) || !FxAccessibilityService.isConnected()) {
            try { rootHandle.recycle() } catch (_: RuntimeException) {}
            return false
        }
        if (eventPackage.isBlank() || eventPackage == service.packageName ||
            !isInstalledUserApplication(service, eventPackage)
        ) {
            try { rootHandle.recycle() } catch (_: RuntimeException) {}
            return false
        }
        if (!FxGkdRuleStore.hasEnabledRule(service, eventPackage)) {
            try { rootHandle.recycle() } catch (_: RuntimeException) {}
            return false
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastScanAt < 250L) {
            try { rootHandle.recycle() } catch (_: RuntimeException) {}
            return false
        }
        lastScanAt = now

        val rules = getCompiledRules(service).filter {
            it.source.enabled && it.source.packageName == eventPackage
        }
        if (rules.isEmpty()) {
            try { rootHandle.recycle() } catch (_: RuntimeException) {}
            return false
        }

        val snapshot = FxGkdAccessibilitySnapshot.capture(rootHandle) ?: return false
        try {
            for (rule in rules) {
                val lastAction = lastActionByRule[rule.source.id] ?: 0L
                if (now - lastAction < rule.source.cooldownMillis) continue

                val matches = FxGkdSelectorEngine.findMatches(
                    snapshot.root,
                    rule.selector,
                    maximum = 12
                )
                for (candidate in matches) {
                    if (!candidate.visibleToUser || !candidate.clickable ||
                        candidate.editable || candidate.platformHandle !is AccessibilityNodeInfo
                    ) continue

                    val liveNode = candidate.platformHandle
                    // Re-check sensitive/actionable properties on the live node before acting.
                    if (liveNode.isPassword || liveNode.isEditable ||
                        !liveNode.isVisibleToUser || !liveNode.isClickable
                    ) continue
                    // Honor a user disable or per-rule revocation that arrives while
                    // a bounded snapshot is being matched.
                    if (!FxAccessibilityService.isConnected()
                        || !FxGkdRuleStore.isEnabled(service)
                        || !FxGkdRuleStore.isRuleEnabled(service, rule.source.id, eventPackage)
                        || !isTargetStillForeground(service, eventPackage)
                    ) {
                        continue
                    }

                    if (liveNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                        lastActionByRule[rule.source.id] = now
                        return true
                    }
                }
            }
            return false
        } finally {
            snapshot.close()
        }
    }

    private fun isTargetStillForeground(
        service: AccessibilityService,
        packageName: String
    ): Boolean {
        val activeRoot = try {
            service.rootInActiveWindow
        } catch (_: RuntimeException) {
            null
        } ?: return false
        return try {
            activeRoot.packageName?.toString() == packageName
        } catch (_: RuntimeException) {
            false
        } finally {
            try { activeRoot.recycle() } catch (_: RuntimeException) {}
        }
    }

    private fun isInstalledUserApplication(
        service: AccessibilityService,
        packageName: String
    ): Boolean {
        if (!FxGkdRuleStore.isValidPackageName(packageName)) return false
        return try {
            val info = service.packageManager.getApplicationInfo(packageName, 0)
            (info.flags and (
                android.content.pm.ApplicationInfo.FLAG_SYSTEM or
                    android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP
            )) == 0
        } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    @Synchronized
    private fun getCompiledRules(service: AccessibilityService): List<CompiledRule> {
        val source = FxGkdRuleStore.getRules(service)
        if (source != cachedSource) {
            cachedSource = source
            cachedCompiled = source.mapNotNull { rule ->
                if (!rule.enabled) return@mapNotNull null
                val compilation = FxGkdSelectorEngine.compile(rule.selector)
                val selector = compilation.selector ?: return@mapNotNull null
                CompiledRule(rule, selector)
            }
            lastActionByRule.keys.retainAll(source.map { it.id }.toSet())
        }
        return cachedCompiled
    }
}
