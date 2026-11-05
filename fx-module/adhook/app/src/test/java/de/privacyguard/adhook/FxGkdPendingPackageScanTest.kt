package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FxGkdPendingPackageScanTest {
    @Test fun firstRequestStartsAndLatestPendingRunsAfterCompletion() {
        val queue = FxGkdPendingPackageScan()
        assertEquals("com.example.alpha", queue.request("com.example.alpha"))
        assertNull(queue.request("com.example.beta"))
        assertEquals("com.example.beta", queue.complete())
        assertNull(queue.complete())
        assertEquals("com.example.gamma", queue.request("com.example.gamma"))
    }

    @Test fun newestPackageReplacesOlderPendingEvents() {
        val queue = FxGkdPendingPackageScan()
        assertEquals("com.example.alpha", queue.request("com.example.alpha"))
        assertNull(queue.request("com.example.beta"))
        assertNull(queue.request("com.example.gamma"))
        assertNull(queue.request("com.example.delta"))
        assertEquals("com.example.delta", queue.complete())
        assertNull(queue.complete())
    }

    @Test fun blankPackageDoesNotOccupyTheActiveSlot() {
        val queue = FxGkdPendingPackageScan()
        assertNull(queue.request("   "))
        assertEquals("com.example.alpha", queue.request("com.example.alpha"))
    }

    @Test fun clearDropsPendingPackageAndReleasesSlot() {
        val queue = FxGkdPendingPackageScan()
        assertEquals("com.example.alpha", queue.request("com.example.alpha"))
        assertNull(queue.request("com.example.beta"))
        queue.clear()
        assertNull(queue.complete())
        assertEquals("com.example.gamma", queue.request("com.example.gamma"))
    }
}
