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
    @Test public void nullAndEmptyTagsAreSafe() {
        assertFalse(ExifPrivacyPolicy.shouldRedactTag(null));
        assertFalse(ExifPrivacyPolicy.shouldRedactTag(""));
    }
}
