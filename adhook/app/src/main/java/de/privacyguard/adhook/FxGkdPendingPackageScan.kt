package de.privacyguard.adhook

/** One active scan plus the latest pending target package; screen nodes are never queued. */
class FxGkdPendingPackageScan {
    private var running = false
    private var latestPendingPackage: String? = null

    @Synchronized
    fun request(packageName: String): String? {
        val requested = packageName.trim()
        if (requested.isEmpty()) return null
        if (!running) {
            running = true
            return requested
        }
        latestPendingPackage = requested
        return null
    }

    /** Keeps the busy slot reserved when returning the next package. */
    @Synchronized
    fun complete(): String? {
        val next = latestPendingPackage
        latestPendingPackage = null
        if (next == null) running = false
        return next
    }

    @Synchronized
    fun clear() {
        latestPendingPackage = null
        running = false
    }
}
