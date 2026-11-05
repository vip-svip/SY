package de.privacyguard.adhook.imported.dia;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

public final class FxDiaGpsCoordinateParserTest {
    @Test public void parsesAmapLongitudeLatitudeOrder() {
        FxDiaGpsCoordinateParser.Coordinates c =
                FxDiaGpsCoordinateParser.parseAmapPair("121.473658,31.230378");
        assertEquals(31.230378d, c.latitude, 0.0000001d);
        assertEquals(121.473658d, c.longitude, 0.0000001d);
    }

    @Test public void acceptsChineseCommaAndWhitespaceSeparators() {
        FxDiaGpsCoordinateParser.Coordinates c =
                FxDiaGpsCoordinateParser.parseAmapPair("121.4， 31.2");
        assertEquals(31.2d, c.latitude, 0.0000001d);
        assertEquals(121.4d, c.longitude, 0.0000001d);
    }

    @Test public void parsesSeparateCoordinateFields() {
        FxDiaGpsCoordinateParser.Coordinates c =
                FxDiaGpsCoordinateParser.parseSeparate("31.2", "121.4");
        assertEquals(31.2d, c.latitude, 0.0000001d);
        assertEquals(121.4d, c.longitude, 0.0000001d);
    }

    @Test public void rejectsMissingOrExtraCoordinates() {
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair(""));
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair("121.4"));
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair("121.4,31.2,5"));
    }

    @Test public void rejectsNonFiniteCoordinates() {
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair("Infinity,31.2"));
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseSeparate("NaN", "121.4"));
    }

    @Test public void rejectsLatitudeAndLongitudeOutsideRanges() {
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair("121.4,90.1"));
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseAmapPair("180.1,31.2"));
        expectInvalid(() -> FxDiaGpsCoordinateParser.parseSeparate("-90.1", "0"));
    }

    private static void expectInvalid(Runnable action) {
        try {
            action.run();
            fail("Expected invalid coordinates to be rejected.");
        } catch (IllegalArgumentException expected) {
            // Expected validation failure.
        }
    }
}
