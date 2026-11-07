package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class MediaStorePrivacyPolicyTest {
    @Test public void blocksOnlyOptedInMediaAuthorities() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.gallery,block_mediastore=1\n").targets.get("com.example.gallery");
        assertTrue(MediaStorePrivacyPolicy.shouldBlockMediaStore(true, 1, "com.example.gallery", target,
                "content", "media"));
        assertTrue(MediaStorePrivacyPolicy.shouldBlockMediaStore(true, 1, "com.example.gallery", target,
                "content", "com.android.providers.media.documents"));
        assertFalse(MediaStorePrivacyPolicy.shouldBlockMediaStore(true, 1, "com.example.gallery", target,
                "content", "com.android.externalstorage.documents"));
        assertFalse(MediaStorePrivacyPolicy.shouldBlockMediaStore(true, 2, "com.example.gallery", target,
                "content", "media"));
        assertFalse(MediaStorePrivacyPolicy.shouldBlockMediaStore(true, 1, "android", target,
                "content", "media"));
    }
}
