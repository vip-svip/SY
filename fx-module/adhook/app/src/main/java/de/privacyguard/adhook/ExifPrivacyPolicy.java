package de.privacyguard.adhook;

/** Pure policy for opt-in read-time EXIF metadata redaction. */
public final class ExifPrivacyPolicy {
    private ExifPrivacyPolicy() {}

    /** Direct coordinate accessors must not expose location even when callers skip tag getters. */
    public static boolean shouldRedactDirectLocation() { return true; }

    public static double altitudeFallback(double defaultValue) { return defaultValue; }

    /** GPS tag family used by both string and numeric ExifInterface accessors. */
    public static boolean isGpsTag(String tag) {
        return tag != null && tag.length() >= 3 && tag.regionMatches(true, 0, "GPS", 0, 3);
    }

    public static boolean shouldRedactTag(String tag) {
        if (tag == null || tag.isEmpty()) return false;
        return isGpsTag(tag)
                || "Make".equals(tag)
                || "Model".equals(tag)
                || tag.startsWith("DateTime")
                || tag.startsWith("OffsetTime")
                || tag.startsWith("SubSecTime")
                || "BodySerialNumber".equals(tag)
                || "LensSerialNumber".equals(tag)
                || "CameraOwnerName".equals(tag)
                || "ImageUniqueID".equals(tag)
                || "Artist".equals(tag)
                || "Copyright".equals(tag)
                || "Software".equals(tag)
                // Free-form fields can contain names, addresses or private notes.
                || "ImageDescription".equals(tag)
                || "DocumentName".equals(tag)
                || "UserComment".equals(tag)
                || "RelatedSoundFile".equals(tag)
                // Host/device-specific metadata can disclose workstation and hardware details.
                || "HostComputer".equals(tag)
                || "MakerNote".equals(tag)
                || "XPAuthor".equals(tag)
                || "XPComment".equals(tag)
                || "XPKeywords".equals(tag)
                || "XPSubject".equals(tag)
                || "XPTitle".equals(tag);
    }
}
