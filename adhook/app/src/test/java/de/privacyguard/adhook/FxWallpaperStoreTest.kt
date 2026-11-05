package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FxWallpaperStoreTest {
    @Test
    fun scalesLandscapeImagesToThe1920PixelLongEdge() {
        assertEquals(1920 to 960, FxWallpaperStore.scaledDimensions(4000, 2000, 1920))
        assertEquals(1920 to 1080, FxWallpaperStore.scaledDimensions(1920, 1080, 1920))
    }

    @Test
    fun scalesPortraitImagesWithoutChangingAspectRatio() {
        assertEquals(691 to 1920, FxWallpaperStore.scaledDimensions(1080, 3000, 1920))
        assertEquals(720 to 1280, FxWallpaperStore.scaledDimensions(720, 1280, 1920))
    }

    @Test
    fun sampleSizeIsPowerOfTwoAndBoundsDecodeDimensions() {
        assertEquals(2, FxWallpaperStore.sampleSizeFor(4000, 2000, 1920))
        assertEquals(4, FxWallpaperStore.sampleSizeFor(8000, 4000, 1920))
        assertEquals(1, FxWallpaperStore.sampleSizeFor(1600, 900, 1920))
    }

    @Test
    fun leavesSmallImagesUnscaledAndRejectsInvalidDimensions() {
        assertEquals(1280 to 720, FxWallpaperStore.scaledDimensions(1280, 720, 1920))
        val invalid = listOf(Triple(0, 100, 1920), Triple(100, 0, 1920), Triple(100, 100, 0))
        invalid.forEach { (width, height, maxEdge) ->
            var rejected = false
            try {
                FxWallpaperStore.scaledDimensions(width, height, maxEdge)
            } catch (_: IllegalArgumentException) {
                rejected = true
            }
            assertTrue("invalid dimension tuple must be rejected", rejected)
        }
    }

    @Test
    fun sampleSizeNeverReturnsZeroAndAlwaysUsesPowerOfTwo() {
        listOf(
            FxWallpaperStore.sampleSizeFor(640, 480, 1920),
            FxWallpaperStore.sampleSizeFor(4000, 3000, 1920),
            FxWallpaperStore.sampleSizeFor(30000, 20000, 1920)
        ).forEach { sample ->
            assertTrue(sample > 0)
            assertEquals(0, sample and (sample - 1))
        }
    }
}
