package de.privacyguard.adhook;

/** JDK-only executable regression for the EXIF redaction policy. */
public final class ExifPrivacyPolicyHostTest {
    private static void expectRedacted(String tag) {
        if (!ExifPrivacyPolicy.shouldRedactTag(tag))
            throw new AssertionError("expected EXIF tag to be redacted: " + tag);
    }
    private static void expectPreserved(String tag) {
        if (ExifPrivacyPolicy.shouldRedactTag(tag))
            throw new AssertionError("unrelated EXIF tag was redacted: " + tag);
    }
    public static void main(String[] args) {
        for (String tag : new String[] {
                "GPSLatitude", "GPSLongitude", "GPSAltitude", "GPSProcessingMethod",
                "Make", "Model", "DateTime", "DateTimeOriginal", "DateTimeDigitized",
                "OffsetTime", "OffsetTimeOriginal", "SubSecTimeOriginal",
                "BodySerialNumber", "LensSerialNumber", "CameraOwnerName", "ImageUniqueID",
                "Artist", "Copyright", "Software", "XPAuthor", "XPComment",
                "XPKeywords", "XPSubject", "XPTitle"
        }) expectRedacted(tag);
        for (String tag : new String[] {
                "ImageWidth", "ImageLength", "Orientation", "FNumber", "ExposureTime",
                "WhiteBalance", "Flash", "FocalLength"
        }) expectPreserved(tag);
        if (ExifPrivacyPolicy.shouldRedactTag(null) || ExifPrivacyPolicy.shouldRedactTag(""))
            throw new AssertionError("null/empty EXIF tag handling changed");
        if (!ExifPrivacyPolicy.shouldRedactDirectLocation())
            throw new AssertionError("direct GPS coordinate accessors must be redacted");
        if (ExifPrivacyPolicy.altitudeFallback(17.5d) != 17.5d ||
                ExifPrivacyPolicy.altitudeFallback(0.0d) != 0.0d)
            throw new AssertionError("altitude fallback must preserve caller's safe default");
        System.out.println("PASS: EXIF policy redacts GPS, device identity and timestamp tags while preserving unrelated image metadata");
    }
}
