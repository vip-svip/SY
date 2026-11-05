package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class ExifPrivacyPolicyTest {
    @Test public void redactsGpsCoordinatesAndGpsMetadata() {
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSLatitude"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSLongitude"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSAltitude"));
        assertTrue(ExifPrivacyPolicy.isGpsTag("GPSProcessingMethod"));
        assertFalse(ExifPrivacyPolicy.isGpsTag("ImageWidth"));
    }
    @Test public void redactsDeviceAndTimestampMetadata() {
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Make"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Model"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTime"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTimeOriginal"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTimeDigitized"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("OffsetTime"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("OffsetTimeOriginal"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("SubSecTimeOriginal"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("BodySerialNumber"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("LensSerialNumber"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("CameraOwnerName"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("ImageUniqueID"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Artist"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Copyright"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Software"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("MakerNote"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("HostComputer"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("RelatedSoundFile"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("UserComment"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DocumentName"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("ImageDescription"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("XPAuthor"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("XPComment"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("XPKeywords"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("XPSubject"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("XPTitle"));
    }
    @Test public void preservesUnrelatedImageMetadata() {
        assertFalse(ExifPrivacyPolicy.shouldRedactTag("ImageWidth"));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag("ImageLength"));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag("Orientation"));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag("FNumber"));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag("ExposureTime"));
    }
    @Test public void directCoordinateAccessorsAreRedacted() {
        assertTrue(ExifPrivacyPolicy.shouldRedactDirectLocation());
        assertEquals(17.5d, ExifPrivacyPolicy.altitudeFallback(17.5d), 0.0d);
        assertEquals(0.0d, ExifPrivacyPolicy.altitudeFallback(0.0d), 0.0d);
    }
    @Test public void nullAndEmptyTagsAreSafe() {
        assertFalse(ExifPrivacyPolicy.shouldRedactTag(null));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag(""));
    }
}
