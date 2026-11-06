package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FxGkdPendingPackageScanTest {
    @Test fun firstRequestStartsAndLatestPendingRunsAfterCompletion() {
        val queue = FxGkdPendingPackageScan()
        val first = queue.request("com.example.alpha")!!
        assertEquals("com.example.alpha", first.packageName)
        assertNull(queue.request("com.example.beta"))
        val next = queue.complete(first.generation)!!
        assertEquals("com.example.beta", next.packageName)
        assertNull(queue.complete(next.generation))
        assertEquals("com.example.gamma", queue.request("com.example.gamma")!!.packageName)
    }

    @Test fun newestPackageReplacesOlderPendingEvents() {
        val queue = FxGkdPendingPackageScan()
        val first = queue.request("com.example.alpha")!!
        assertNull(queue.request("com.example.beta"))
        assertNull(queue.request("com.example.gamma"))
        assertNull(queue.request("com.example.delta"))
        assertEquals("com.example.delta", queue.complete(first.generation)!!.packageName)
    }

    @Test fun blankPackageDoesNotOccupyTheActiveSlot() {
        val queue = FxGkdPendingPackageScan()
        assertNull(queue.request("   "))
        assertEquals("com.example.alpha", queue.request("com.example.alpha")!!.packageName)
    }

    @Test fun clearInvalidatesOldWorkerWithoutReleasingNewScan() {
        val queue = FxGkdPendingPackageScan()
        val old = queue.request("com.example.alpha")!!
        queue.request("com.example.beta")
        queue.clear()
        val current = queue.request("com.example.gamma")!!
        assertFalse(queue.isActive(old.generation))
        assertTrue(queue.isActive(current.generation))
        assertNull(queue.complete(old.generation))
        assertTrue(queue.isActive(current.generation))
        assertNull(queue.complete(current.generation))
    }

    @Test fun repeatedActivePackageDoesNotScheduleDuplicateScan() {
        val queue = FxGkdPendingPackageScan()
        val active = queue.request("com.example.alpha")!!
        queue.request("com.example.beta")
        assertNull(queue.request("com.example.alpha"))
        assertNull(queue.complete(active.generation))
    }
}
