package de.privacyguard.adhook

import org.junit.Assert.assertEquals
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

    @Test(expected = IllegalArgumentException::class)
    fun rejectsZeroWidthInDimensionCalculation() {
        FxWallpaperStore.scaledDimensions(0, 1080, 1920)
    }
}
