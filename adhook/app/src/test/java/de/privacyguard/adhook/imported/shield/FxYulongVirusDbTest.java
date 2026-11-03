package de.privacyguard.adhook.imported.shield;

import org.junit.Test;
import java.util.Arrays;
import java.util.HashSet;
import static org.junit.Assert.*;

/** Regression coverage for the migrated Yulong five-list matching rules. */
public final class FxYulongVirusDbTest {
    private FxYulongVirusDb.Data sample() {
        return new FxYulongVirusDb.Data(
                new HashSet<>(Arrays.asList("com.bad.certain")),
                new HashSet<>(Arrays.asList("Danger App")),
                new HashSet<>(Arrays.asList("com.bad.suspect")),
                new HashSet<>(Arrays.asList("可疑工具")),
                new HashSet<>(Arrays.asList("stealer", "trojan")));
    }

    @Test public void exactPackageAndCaseInsensitiveNameMatchAsCertain() {
        FxYulongVirusDb.Data db = sample();
        assertTrue(db.isCertain("com.bad.certain", "ordinary"));
        assertTrue(db.isCertain("com.good.app", "dAnGeR aPp"));
    }

    @Test public void suspectPackageNameAndKeywordAreDistinguished() {
        FxYulongVirusDb.Data db = sample();
        assertEquals("包名命中可疑库", db.matchSuspect("com.bad.suspect", "ordinary"));
        assertEquals("应用名称命中可疑库", db.matchSuspect("com.good.app", "可疑工具"));
        assertEquals("包名含关键字", db.matchSuspect("org.trojan.client", "ordinary"));
        assertEquals("名称含关键字", db.matchSuspect("com.good.app", "Hidden Stealer Tool"));
        assertNull(db.matchSuspect("com.good.app", "ordinary"));
    }

    @Test public void blacklistCombinesCertainAndSuspectListsButNotKeywords() {
        FxYulongVirusDb.Data db = sample();
        assertTrue(db.isBlacklisted("com.bad.certain", "ordinary"));
        assertTrue(db.isBlacklisted("com.bad.suspect", "ordinary"));
        assertTrue(db.isBlacklisted("com.good.app", "可疑工具"));
        assertFalse(db.isBlacklisted("org.trojan.client", "ordinary"));
    }

    @Test public void totalCountsAllFiveLists() {
        assertEquals(6, sample().total());
    }
}
