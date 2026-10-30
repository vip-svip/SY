package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class LocalAuthorizationProfilerTest {
    static final class LocalStore {
        android.content.SharedPreferences vipPreferences;
        String membershipExpiry;
        boolean isPremiumEnabled() { throw new AssertionError("profiler must not invoke methods"); }
        int unrelatedCounter;
    }
    static final class Unrelated { String title; int count; }
    @Test public void identifiesLocalAuthorizationStorageMetadata() {
        LocalAuthorizationProfiler.Result r=LocalAuthorizationProfiler.inspect(LocalStore.class);
        assertTrue(r.isCandidate());
        boolean found=false;
        for(LocalAuthorizationProfiler.Evidence e:r.evidence) {
            if("vipPreferences".equals(e.member)) {
                found=true;
                assertEquals(LocalAuthorizationProfiler.StorageKind.SHARED_PREFERENCES,e.storageKind);
            }
        }
        assertTrue(found);
    }
    @Test public void ignoresUnrelatedModel() {
        assertFalse(LocalAuthorizationProfiler.inspect(Unrelated.class).isCandidate());
    }
    @Test public void nullInputIsSafe() {
        assertFalse(LocalAuthorizationProfiler.inspect(null).isCandidate());
    }
    @Test public void recognizesEncryptedPreferencesAndDatastore() {
        assertEquals(LocalAuthorizationProfiler.StorageKind.ENCRYPTED_PREFERENCES,
                LocalAuthorizationProfiler.storageKind("androidx.security.crypto.EncryptedSharedPreferences"));
        assertEquals(LocalAuthorizationProfiler.StorageKind.DATASTORE,
                LocalAuthorizationProfiler.storageKind("androidx.datastore.core.DataStore"));
    }
}
