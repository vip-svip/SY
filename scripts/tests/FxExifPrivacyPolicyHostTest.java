package de.privacyguard.adhook;

/** JDK-only regression for the shared EXIF privacy policy. */
public final class FxExifPrivacyPolicyHostTest {
    private static void expect(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        String[] privateTags = {
            "GPSLatitude", "GPSLongitude", "GPSAltitude", "GPSProcessingMethod",
            "Make", "Model", "DateTime", "DateTimeOriginal", "DateTimeDigitized",
            "OffsetTime", "OffsetTimeOriginal", "SubSecTimeOriginal",
            "BodySerialNumber", "LensSerialNumber", "CameraOwnerName",
            "ImageUniqueID", "Artist", "Copyright", "Software",
            "ImageDescription",
            "DocumentName",
            "UserComment",
            "RelatedSoundFile",
            "HostComputer",
            "MakerNote",
            "XPAuthor", "XPComment", "XPKeywords", "XPSubject", "XPTitle"
        };
        for (String tag : privateTags)
            expect(ExifPrivacyPolicy.shouldRedactTag(tag), "must redact " + tag);
        String[] publicTags = {
            "ImageWidth", "ImageLength", "Orientation", "FNumber", "ExposureTime"
        };
        for (String tag : publicTags)
            expect(!ExifPrivacyPolicy.shouldRedactTag(tag), "must preserve " + tag);
        expect(ExifPrivacyPolicy.isGpsTag("GPSProcessingMethod"), "GPS family detection");
        expect(!ExifPrivacyPolicy.isGpsTag("ImageWidth"), "non-GPS family detection");
        expect(!ExifPrivacyPolicy.shouldRedactTag(null), "null tag must be safe");
        expect(!ExifPrivacyPolicy.shouldRedactTag(""), "empty tag must be safe");
        expect(ExifPrivacyPolicy.shouldRedactDirectLocation(), "direct coordinate accessors must be redacted");
        expect(Double.compare(17.5d, ExifPrivacyPolicy.altitudeFallback(17.5d)) == 0,
                "altitude fallback must preserve caller default");
        expect(Double.compare(-4.25d, ExifPrivacyPolicy.altitudeFallback(-4.25d)) == 0,
                "altitude fallback must preserve negative caller default");
        System.out.println("PASS: EXIF GPS, device identity, timestamp and author metadata redaction policy");
    }
}
