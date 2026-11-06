package de.privacyguard.adhook

/**
 * Per-target GKD scan cooldown. Events from one enabled app must not suppress
 * matching work for another enabled app using the shared FX AccessibilityService.
 */
internal class FxGkdPackageScanThrottle(private val intervalMs: Long) {
    private val lastScanAtByPackage = LinkedHashMap<String, Long>()

    @Synchronized
    fun shouldScan(packageName: String, nowMs: Long): Boolean {
        if (packageName.isBlank() || intervalMs < 0L) return false
        val previous = lastScanAtByPackage[packageName]
        if (previous != null && nowMs >= previous && nowMs - previous < intervalMs) {
            return false
        }
        lastScanAtByPackage[packageName] = nowMs
        return true
    }

    @Synchronized
    fun retainPackages(activePackages: Set<String>) {
        lastScanAtByPackage.keys.retainAll(activePackages)
    }

    @Synchronized
    fun clear() {
        lastScanAtByPackage.clear()
    }
}
