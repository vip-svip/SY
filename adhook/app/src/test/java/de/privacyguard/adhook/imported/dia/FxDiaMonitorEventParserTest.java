package de.privacyguard.adhook.imported.dia;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** Privacy and boundedness tests for Dia's native monitor-event view. */
public final class FxDiaMonitorEventParserTest {
    @Test public void parsesHttpAndWebViewMetadataOnly() {
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(
                "[DIA_HTTP] OkHttp method=GET host=api.example.com status=204 elapsedMs=19\n"
                + "[DIA_WEBVIEW] postUrl host=docs.example.com bodyBytes=32 content=redacted\n");
        assertEquals(2, events.size());
        assertEquals("HTTP", events.get(0).category);
        assertEquals("GET", events.get(0).fields.get("method"));
        assertEquals("api.example.com", events.get(0).fields.get("host"));
        assertEquals("19", events.get(0).fields.get("elapsedMs"));
        assertEquals("WebView", events.get(1).category);
        assertEquals("32", events.get(1).fields.get("bodyBytes"));
        assertFalse(events.get(1).toDisplayString().contains("redacted"));
    }

    @Test public void neverReturnsSqlTextStackTraceOrArbitrarySecrets() {
        String line = "[DIA_SQL] class=android.database.sqlite.SQLiteDatabase method=rawQuery "
                + "args=2 firstStringLength=44 elapsedMs=3 "
                + "sql=select_password_from_users stack=private.User.login token=abc123";
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(line);
        assertEquals(1, events.size());
        String rendered = events.get(0).toDisplayString();
        assertTrue(rendered.contains("rawQuery"));
        assertTrue(rendered.contains("44"));
        assertFalse(rendered.contains("select_password"));
        assertFalse(rendered.contains("private.User"));
        assertFalse(rendered.contains("abc123"));
        assertFalse(events.get(0).fields.containsKey("sql"));
        assertFalse(events.get(0).fields.containsKey("stack"));
        assertFalse(events.get(0).fields.containsKey("token"));
    }

    @Test public void ignoresUnknownTagsAndUnsafeValues() {
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(
                "[DIA_UNKNOWN] token=secret\n"
                + "[DIA_HTTP] method=GET host=example.com/path?token=secret status=200\n"
                + "[DIA_HTTP] method=POST host=good.example status=200");
        assertEquals(2, events.size());
        assertFalse(events.get(0).fields.containsKey("host"));
        assertEquals("good.example", events.get(1).fields.get("host"));
    }

    @Test public void supportsEveryBuiltInMonitorFamily() {
        StringBuilder log = new StringBuilder();
        String[] tags = {"HTTP", "WEBVIEW", "SQL", "ALGORITHM", "NATIVE", "CLASSLOADER",
                "SOCKET", "INTENT", "CLICK", "VIEWGROUP", "FRAGMENT", "THREAD", "STACK",
                "KEY", "RUNTIME", "MEMORY"};
        for (String tag : tags) log.append("[DIA_").append(tag).append("] event\n");
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(log.toString());
        assertEquals(tags.length, events.size());
        assertEquals("HTTP", events.get(0).category);
        assertEquals("内存", events.get(events.size() - 1).category);
    }

    @Test public void retainsOnlyTheNewestThreeHundredEvents() {
        StringBuilder log = new StringBuilder();
        for (int i = 0; i < 350; i++) {
            log.append("[DIA_KEY] keyCode=").append(i).append(" action=0\n");
        }
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(log.toString());
        assertEquals(FxDiaMonitorEventParser.MAX_EVENTS, events.size());
        assertEquals("50", events.get(0).fields.get("keyCode"));
        assertEquals("349", events.get(events.size() - 1).fields.get("keyCode"));
    }

    @Test public void boundsInputAndLineLengths() {
        String huge = "x".repeat(FxDiaMonitorEventParser.MAX_LOG_CHARS + 1000)
                + "\n[DIA_RUNTIME] Runtime.exec invoked; command content omitted";
        assertEquals(1, FxDiaMonitorEventParser.parse(huge).size());
        assertTrue(FxDiaMonitorEventParser.parse(null).isEmpty());
    }
}
