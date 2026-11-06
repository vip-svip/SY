package de.privacyguard.adhook

/** One active scan plus the latest pending target package; screen nodes are never queued. */
class FxGkdPendingPackageScan {
    data class Request internal constructor(
        val packageName: String,
        val generation: Long
    )

    private var running = false
    private var activePackage: String? = null
    private var activeGeneration = 0L
    private var generationCounter = 0L
    private var latestPendingPackage: String? = null

    @Synchronized
    fun request(packageName: String): Request? {
        val requested = packageName.trim()
        if (requested.isEmpty()) return null
        if (!running) {
            running = true
            activePackage = requested
            activeGeneration = ++generationCounter
            return Request(requested, activeGeneration)
        }
        // A repeated event for the in-flight package does not need a second pass.
        if (requested == activePackage) {
            latestPendingPackage = null
            return null
        }
        latestPendingPackage = requested
        return null
    }

    @Synchronized
    fun isActive(generation: Long): Boolean =
        running && activeGeneration == generation

    /** Stale workers cannot release a newer scan after clear/reconfigure. */
    @Synchronized
    fun complete(generation: Long): Request? {
        if (!running || activeGeneration != generation) return null
        val next = latestPendingPackage
        latestPendingPackage = null
        if (next == null) {
            running = false
            activePackage = null
            return null
        }
        activePackage = next
        activeGeneration = ++generationCounter
        return Request(next, activeGeneration)
    }

    @Synchronized
    fun clear() {
        latestPendingPackage = null
        running = false
        activePackage = null
        activeGeneration = ++generationCounter
    }
}
