package de.privacyguard.adhook.imported.dia;

/** Strict parser for the original Dia GPS picker coordinate format. */
public final class FxDiaGpsCoordinateParser {
    private FxDiaGpsCoordinateParser() { }

    public static final class Coordinates {
        public final double latitude;
        public final double longitude;

        private Coordinates(double latitude, double longitude) {
            this.latitude = latitude;
            this.longitude = longitude;
        }
    }

    /** AMap displays longitude first, latitude second. */
    public static Coordinates parseAmapPair(String raw) {
        if (raw == null) throw new IllegalArgumentException("请粘贴经度,纬度。");
        String value = raw.trim();
        if (value.isEmpty()) throw new IllegalArgumentException("请粘贴经度,纬度。");
        String[] parts = value.split("[,，\\s]+");
        if (parts.length != 2) {
            throw new IllegalArgumentException("格式应为：经度,纬度，例如 121.473658,31.230378。");
        }
        double longitude = parseFinite(parts[0], "经度");
        double latitude = parseFinite(parts[1], "纬度");
        return checked(latitude, longitude);
    }

    public static Coordinates parseSeparate(String latitude, String longitude) {
        double lat = parseFinite(latitude, "纬度");
        double lon = parseFinite(longitude, "经度");
        return checked(lat, lon);
    }

    private static double parseFinite(String raw, String label) {
        if (raw == null || raw.trim().isEmpty()) {
            throw new IllegalArgumentException("请输入" + label + "。");
        }
        final double value;
        try {
            value = Double.parseDouble(raw.trim());
        } catch (NumberFormatException invalid) {
            throw new IllegalArgumentException(label + "格式无效。");
        }
        if (Double.isNaN(value) || Double.isInfinite(value)) {
            throw new IllegalArgumentException(label + "必须是有限数字。");
        }
        return value;
    }

    private static Coordinates checked(double latitude, double longitude) {
        if (latitude < -90d || latitude > 90d) {
            throw new IllegalArgumentException("纬度必须在 -90 至 90。");
        }
        if (longitude < -180d || longitude > 180d) {
            throw new IllegalArgumentException("经度必须在 -180 至 180。");
        }
        return new Coordinates(latitude, longitude);
    }
}
