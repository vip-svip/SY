package de.privacyguard.adhook

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FxGkdPackageScanThrottleTest {
    @Test
    fun cooldownIsIsolatedByTargetPackage() {
        val throttle = FxGkdPackageScanThrottle(250L)

        assertTrue(throttle.shouldScan("com.example.alpha", 1_000L))
        assertFalse(throttle.shouldScan("com.example.alpha", 1_100L))
        assertTrue(throttle.shouldScan("com.example.beta", 1_100L))
        assertFalse(throttle.shouldScan("com.example.alpha", 1_249L))
        assertTrue(throttle.shouldScan("com.example.alpha", 1_250L))
    }

    @Test
    fun removedRulePackagesReleaseTheirCooldownState() {
        val throttle = FxGkdPackageScanThrottle(250L)

        assertTrue(throttle.shouldScan("com.example.alpha", 1_000L))
        throttle.retainPackages(setOf("com.example.beta"))
        assertTrue(throttle.shouldScan("com.example.alpha", 1_100L))
    }

    @Test
    fun invalidationClearsAllPackageCooldowns() {
        val throttle = FxGkdPackageScanThrottle(250L)

        assertTrue(throttle.shouldScan("com.example.alpha", 1_000L))
        throttle.clear()
        assertTrue(throttle.shouldScan("com.example.alpha", 1_100L))
    }
}
