package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class ExifPrivacyPolicyTest {
    @Test public void redactsGpsCoordinatesAndGpsMetadata() {
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSLatitude"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSLongitude"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("GPSAltitude"));
    }
    @Test public void redactsDeviceAndTimestampMetadata() {
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Make"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("Model"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTime"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTimeOriginal"));
        assertTrue(ExifPrivacyPolicy.shouldRedactTag("DateTimeDigitized"));
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
