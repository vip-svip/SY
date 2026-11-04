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

    @Test public void malformedHtmlAndErrorPayloadsAreRejected() {
        assertTrue(FxYulongVirusDb.parse("<html><body>502 Bad Gateway</body></html>", false).isEmpty());
        assertTrue(FxYulongVirusDb.parse("{\\"error\\":\\"Bad Gateway\\"}", false).isEmpty());
        assertTrue(FxYulongVirusDb.parse("[{\\"error\\":\\"temporary\\"}]", false).isEmpty());
        assertTrue(FxYulongVirusDb.parse("503 Service Unavailable", false).isEmpty());
        assertTrue(FxYulongVirusDb.parse("502 Bad Gateway", true).isEmpty());
    }

    @Test public void packageParserAcceptsOnlyCompleteDottedIdentifiers() {
        assertEquals(new HashSet<>(Arrays.asList("com.example.good", "org.sample.client")),
                FxYulongVirusDb.parse("[\\"com.example.good\\",\\"org.sample.client\\"]", true));
        assertTrue(FxYulongVirusDb.parse("com.example.good\ninvalid package token", true).isEmpty());
        assertTrue(FxYulongVirusDb.parse("https://cdn.example.com/error.html", true).isEmpty());
    }

    @Test public void listStatusSeparatesOldCacheFromLatestAttempt() {
        FxYulongVirusDb.ListStatus status =
                new FxYulongVirusDb.ListStatus("certainPkg", "100% 病毒包名", "https://example.invalid/list");
        status.count = 42;
        status.updatedAt = 1000L;
        assertEquals("本地缓存可用（更新时间未知）", status.statusLabel());

        status.lastAttemptAt = 2000L;
        status.ok = false;
        assertEquals("最近同步失败，沿用旧缓存", status.statusLabel());

        status.count = 0;
        status.updatedAt = 0L;
        assertEquals("最近同步失败，无可用缓存", status.statusLabel());

        status.ok = true;
        assertEquals("最近同步成功", status.statusLabel());
    }
}
