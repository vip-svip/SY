package de.privacyguard.adhook;

/**
 * Gate for the four DeviceWarLock detection families not yet covered.
 *
 * Research basis (imxiaoc996/DeviceWarLock, 285★, C++ collectors + JNI detectors):
 *
 *  SandboxDetector   opendir/readdir on /proc, fopen /proc/<pid>/cmdline, popen "ps -ef",
 *                    looking for a second copy of itself (dual-app / sandbox / 分身).
 *  VirtualDetector   CPU architecture (x86/i386 ⇒ emulator), seccomp presence,
 *                    /sys/class/thermal sensor count, ARM register heuristics,
 *                    and a brand-service probe.
 *  NativeDetector    kernel strings and /proc/version.
 *  SystemDetector    /sys/module/dm_verity/parameters/status, /proc/mounts writability of
 *                    /system, /sys/fs/avb presence, /proc/fs/jbd2 and /proc/fs/ext4,
 *                    KernelSU traces, Zygisk traces, and /proc/self/fd readlink targets.
 *
 * All of these reach the device through the same Java boundary this module can guard
 * (File reads of /proc and /sys, Runtime.exec of ps/getprop, and the Build/CPU fields).
 * The gate is per-target, opt-in, fail-closed.
 */
public final class EmulatorSandboxPolicy {
    private EmulatorSandboxPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    public enum Surface {
        /** /proc process enumeration and `ps` output (dual-app / sandbox detection). */
        PROCESS_ENUMERATION,
        /** CPU architecture / ABI reads that reveal an x86 emulator. */
        CPU_ARCHITECTURE,
        /** seccomp availability on the running kernel. */
        SECCOMP_STATUS,
        /** /sys/class/thermal sensor inventory (emulators expose none or a fixed few). */
        THERMAL_SENSORS,
        /** /sys/fs/avb, dm_verity and /proc/mounts writability of /system. */
        SYSTEM_VERITY,
        /** KernelSU / Zygisk traces in /proc and /sys. */
        ROOT_TRACES,
        /** /proc/self/fd readlink targets pointing at injected libraries. */
        FD_TARGETS,
        /** Brand-service probe (OEM SDK presence). */
        BRAND_SERVICES
    }

    /**
     * Whether the target is an inspection tool that must not learn it runs in an
     * emulator, sandbox or modified kernel.
     */
    public static boolean shouldBlock(boolean privacyMasterEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        if (target == null) return false;
        // The emulator/sandbox surfaces are part of the public-security reconnaissance
        // switch: an inspection tool probing them is doing device forensics.
        return target.policeReconBlock;
    }

    public static boolean shouldBlockSurface(boolean privacyMasterEnabled,
                                             int processPackageCount,
                                             String packageName,
                                             UnifiedHookConfigParser.Target target,
                                             Surface surface) {
        if (surface == null) return false;
        return shouldBlock(privacyMasterEnabled, processPackageCount, packageName, target);
    }

    /**
     * Paths whose content reveals sandbox, emulator or kernel modification.
     * Matching is prefix/exact based so an app's own files are never touched.
     */
    public static boolean isEmulatorEvidencePath(String path) {
        if (path == null || path.isEmpty()) return false;
        String normalized = path.toLowerCase(java.util.Locale.ROOT);
        return normalized.equals("/proc/mounts")
                || normalized.startsWith("/proc/self/fd")
                || normalized.startsWith("/proc/fs/jbd2")
                || normalized.startsWith("/proc/fs/ext4")
                || normalized.startsWith("/proc/version")
                || normalized.startsWith("/sys/class/thermal")
                || normalized.equals("/sys/module/dm_verity/parameters/status")
                || normalized.startsWith("/sys/fs/avb")
                || normalized.startsWith("/sys/module/kernelsu")
                || normalized.startsWith("/sys/module/zygisk")
                || normalized.contains("seccomp");
    }

    /**
     * Commands whose output reveals sandbox/dual-app or kernel modification. The SDK
     * runs `ps`, `ps -ef` and `getprop`; these must look like ordinary successful runs
     * that simply show nothing interesting, not like blocked commands.
     */
    public static boolean isEmulatorEvidenceCommand(String command) {
        if (command == null || command.isEmpty()) return false;
        String normalized = command.trim().toLowerCase(java.util.Locale.ROOT);
        return normalized.equals("ps")
                || normalized.equals("ps -ef")
                || normalized.startsWith("ps ")
                || normalized.startsWith("getprop")
                || normalized.contains("/proc/mounts")
                || normalized.contains("dm_verity")
                || normalized.contains("avb");
    }

    /**
     * Filter `ps` output so a second copy of the inspected app (sandbox / 分身) is
     * invisible. Every other line is preserved verbatim.
     */
    public static String filterProcessList(String output, String ownPackage) {
        if (output == null || output.isEmpty()) return output;
        if (ownPackage == null || ownPackage.isEmpty()) return output;
        StringBuilder kept = new StringBuilder(output.length());
        int occurrences = 0;
        for (String line : output.split("\n", -1)) {
            if (line.contains(ownPackage)) {
                occurrences++;
                // Keep the first occurrence: zero copies would itself be suspicious,
                // and the SDK specifically counts "more than one".
                if (occurrences > 1) continue;
            }
            if (kept.length() > 0) kept.append('\n');
            kept.append(line);
        }
        return kept.toString();
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
