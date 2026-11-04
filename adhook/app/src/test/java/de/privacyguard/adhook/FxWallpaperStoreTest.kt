package de.privacyguard.adhook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class FxWallpaperStoreTest {
    @Test
    fun doesNotUpscaleImagesSmallerThanTheWallpaperLimit() {
        assertEquals(1280 to 720, FxWallpaperStore.scaledDimensions(1280, 720, 1920))
        assertEquals(1920 to 1080, FxWallpaperStore.scaledDimensions(1920, 1080, 1920))
    }

    @Test
    fun scalesLandscapeImagesTo1920PixelsOnTheLongEdge() {
        assertEquals(1920 to 1080, FxWallpaperStore.scaledDimensions(3840, 2160, 1920))
        assertEquals(1920 to 768, FxWallpaperStore.scaledDimensions(5000, 2000, 1920))
    }

    @Test
    fun scalesPortraitImagesWithoutSwappingOrientation() {
        assertEquals(1152 to 1920, FxWallpaperStore.scaledDimensions(3000, 5000, 1920))
    }

    @Test
    fun choosesPowerOfTwoDecodeSamplingBeforeFinalResize() {
        assertEquals(1, FxWallpaperStore.sampleSizeFor(1920, 1080, 1920))
        assertEquals(2, FxWallpaperStore.sampleSizeFor(3840, 2160, 1920))
        assertEquals(4, FxWallpaperStore.sampleSizeFor(7680, 4320, 1920))
    }

    @Test
    fun rejectsInvalidImageDimensionsAndLimits() {
        assertThrows(IllegalArgumentException::class.java) {
            FxWallpaperStore.scaledDimensions(0, 1080, 1920)
        }
        assertThrows(IllegalArgumentException::class.java) {
            FxWallpaperStore.scaledDimensions(1080, 720, 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            FxWallpaperStore.sampleSizeFor(1080, 720, 0)
        }
    }
}
