package de.privacyguard.adhook;

/**
 * Per-package, opt-in sensor enumeration policy. Public Android sensor types
 * are assigned to broad privacy families; private/unknown types fail open.
 */
public final class SensorPrivacyPolicy {
    private SensorPrivacyPolicy() {}

    public static boolean isEnabled(UnifiedHookConfigParser.Target target, int type) {
        if (target == null) return false;
        switch (type) {
            // Accelerometer, gravity, linear acceleration and calibrated variants.
            case 1:  // TYPE_ACCELEROMETER
            case 9:  // TYPE_GRAVITY
            case 10: // TYPE_LINEAR_ACCELERATION
            case 35: // TYPE_ACCELEROMETER_UNCALIBRATED
            case 38: // TYPE_ACCELEROMETER_LIMITED_AXES
            case 40: // TYPE_ACCELEROMETER_LIMITED_AXES_UNCALIBRATED
                return target.sensorAccel;
            // Magnetic field and uncalibrated magnetic field.
            case 2:  // TYPE_MAGNETIC_FIELD
            case 14: // TYPE_MAGNETIC_FIELD_UNCALIBRATED
                return target.sensorMagnet;
            // Gyroscope, uncalibrated and limited-axis variants.
            case 4:  // TYPE_GYROSCOPE
            case 16: // TYPE_GYROSCOPE_UNCALIBRATED
            case 39: // TYPE_GYROSCOPE_LIMITED_AXES
            case 41: // TYPE_GYROSCOPE_LIMITED_AXES_UNCALIBRATED
                return target.sensorGyro;
            case 5:  // TYPE_LIGHT
                return target.sensorLight;
            case 6:  // TYPE_PRESSURE
                return target.sensorPressure;
            case 8:  // TYPE_PROXIMITY
                return target.sensorProx;
            // Temperature and humidity sensors.
            case 7:  // TYPE_TEMPERATURE (deprecated; older devices may report it)
            case 12: // TYPE_RELATIVE_HUMIDITY
            case 13: // TYPE_AMBIENT_TEMPERATURE
                return target.sensorEnvironment;
            // Orientation, rotation, pose and hinge/head-tracking sensors.
            case 3:  // TYPE_ORIENTATION (deprecated)
            case 11: // TYPE_ROTATION_VECTOR
            case 15: // TYPE_GAME_ROTATION_VECTOR
            case 20: // TYPE_GEOMAGNETIC_ROTATION_VECTOR
            case 27: // TYPE_DEVICE_ORIENTATION
            case 28: // TYPE_POSE_6DOF
            case 36: // TYPE_HINGE_ANGLE
            case 37: // TYPE_HEAD_TRACKER
            case 42: // TYPE_HEADING
                return target.sensorFusion;
            // Significant motion, steps, gestures and activity detectors.
            case 17: // TYPE_SIGNIFICANT_MOTION
            case 18: // TYPE_STEP_DETECTOR
            case 19: // TYPE_STEP_COUNTER
            case 22: // TYPE_TILT_DETECTOR
            case 23: // TYPE_WAKE_GESTURE
            case 24: // TYPE_GLANCE_GESTURE
            case 25: // TYPE_PICK_UP_GESTURE
            case 26: // TYPE_WRIST_TILT_GESTURE
            case 29: // TYPE_STATIONARY_DETECT
            case 30: // TYPE_MOTION_DETECT
            case 34: // TYPE_LOW_LATENCY_OFFBODY_DETECT
                return target.sensorGesture;
            // Health / biometric signals.
            case 21: // TYPE_HEART_RATE
            case 31: // TYPE_HEART_BEAT
                return target.sensorBiometric;
            // Dynamic sensor metadata, additional-info and vendor-private types
            // are intentionally not blanket-hidden by these user-facing groups.
            default:
                return false;
        }
    }

    public static boolean shouldClampRate(boolean privacyMaster, int processPackageCount,
                                          String packageName, UnifiedHookConfigParser.Target target) {
        return privacyMaster && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName)
                && target != null && target.sensorRateLimit;
    }

    /** Clamp sampling periods below 100 ms to 100 ms (at most 10 Hz). */
    public static int clampSamplingPeriodUs(int requestedPeriodUs) {
        return requestedPeriodUs < 100000 ? 100000 : requestedPeriodUs;
    }

    public static boolean shouldHide(boolean privacyMaster, int processPackageCount,
                                     String packageName, UnifiedHookConfigParser.Target target, int type) {
        return privacyMaster && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName) && isEnabled(target, type);
    }

    private static boolean isProtected(String pkg) {
        return "android".equals(pkg) || "system".equals(pkg)
                || "de.privacyguard.hook".equals(pkg) || "de.privacyguard.adhook".equals(pkg)
                || "org.lsposed.manager".equals(pkg);
    }
}
