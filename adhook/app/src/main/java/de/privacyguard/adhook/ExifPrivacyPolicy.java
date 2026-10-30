package de.privacyguard.adhook;

/** Pure policy for opt-in read-time EXIF metadata redaction. */
public final class ExifPrivacyPolicy {
    private ExifPrivacyPolicy() {}

    public static boolean shouldRedactTag(String tag) {
        if (tag == null || tag.isEmpty()) return false;
        return tag.startsWith("GPS")
                || "Make".equals(tag)
                || "Model".equals(tag)
                || tag.startsWith("DateTime");
    }
}
