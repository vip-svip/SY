package de.privacyguard.adhook;

import android.location.Location;
import android.os.SystemClock;

/**
 * Real location injection for one opted-in target.
 *
 * Unlike a "reporting" shim, this builds an actual {@link Location} object and hands it
 * to the app's location callbacks: the app receives a working fix with real provider,
 * accuracy, bearing, speed and timestamps, so distance calculations, geofencing,
 * map centring and mock-detection heuristics all see a coherent fix rather than null.
 *
 * The injected fix is derived from the user's configured coordinates and is marked as
 * a GPS provider fix (isFromMockProvider is cleared) because apps commonly refuse or
 * flag mock sources. Every value is opt-in per target and the policy gate fails closed.
 */
public final class LocationInjectionPolicy {
    private LocationInjectionPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    /** Providers whose fix we can synthesise with a coherent speed/altitude reading. */
    public static final String DEFAULT_PROVIDER = "gps";
    public static final String NETWORK_PROVIDER = "network";

    public static boolean shouldInjectLocation(boolean privacyMasterEnabled,
                                               int processPackageCount,
                                               String packageName,
                                               UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        if (target == null || !target.locationSimulation) return false;
        if (target.locationAccessBlock) return false;
        return validCoordinate(target.simulatedLatitude, target.simulatedLongitude);
    }

    /** Latitude must be a real coordinate; (0,0) is a legitimate location, NaN is not. */
    public static boolean validCoordinate(double latitude, double longitude) {
        if (Double.isNaN(latitude) || Double.isInfinite(latitude)) return false;
        if (Double.isNaN(longitude) || Double.isInfinite(longitude)) return false;
        return latitude >= -90d && latitude <= 90d && longitude >= -180d && longitude <= 180d;
    }

    public static boolean validAccuracy(float accuracy) {
        return !Float.isNaN(accuracy) && !Float.isInfinite(accuracy)
                && accuracy >= 0f && accuracy <= 1000f;
    }

    /**
     * Build the fix handed to the target. A fresh object is created per call because
     * apps mutate and cache Location instances; sharing one would leak state between
     * callbacks and make elapsed-realtime checks look frozen.
     */
    /** Immutable projection of the fix values, testable without the Android runtime. */
    public static final class FixValues {
        public final String provider;
        public final double latitude;
        public final double longitude;
        public final float accuracy;
        public final float speed;
        public final float bearing;
        public final double altitude;

        FixValues(String provider, double latitude, double longitude, float accuracy,
                  float speed, float bearing, double altitude) {
            this.provider = provider;
            this.latitude = latitude;
            this.longitude = longitude;
            this.accuracy = accuracy;
            this.speed = speed;
            this.bearing = bearing;
            this.altitude = altitude;
        }
    }

    /**
     * Resolve the values to report as a fix. Pure: no Android objects, so the contract
     * is verifiable in a plain JVM unit test.
     */
    public static FixValues resolveFixValues(UnifiedHookConfigParser.Target target, String provider) {
        String effectiveProvider = provider == null || provider.isEmpty()
                ? DEFAULT_PROVIDER : provider;
        float effectiveAccuracy = validAccuracy(target.simulatedAccuracy)
                ? target.simulatedAccuracy : 5f;
        return new FixValues(effectiveProvider, target.simulatedLatitude,
                target.simulatedLongitude, effectiveAccuracy,
                0f, 0f, 0d);
    }

    public static Location buildFix(UnifiedHookConfigParser.Target target, String provider) {
        FixValues values = resolveFixValues(target, provider);
        Location fix = new Location(values.provider);
        fix.setLatitude(values.latitude);
        fix.setLongitude(values.longitude);
        fix.setAccuracy(values.accuracy);
        fix.setTime(System.currentTimeMillis());
        fix.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
        // A stationary injected fix must not claim movement; a nonzero speed would make
        // navigation UIs show a drifting marker.
        fix.setSpeed(values.speed);
        fix.setBearing(values.bearing);
        fix.setAltitude(values.altitude);
        // Clear the mock flag: the value comes from the user's own configuration, and
        // apps commonly reject or degrade a fix flagged as mock.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.JELLY_BEAN_MR2) {
            try {
                fix.setMock(false);
            } catch (Throwable ignored) {
                // Some OEM Location implementations do not implement setMock.
            }
        }
        return fix;
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
