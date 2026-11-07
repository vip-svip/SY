package de.privacyguard.adhook;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;

/**
 * Rewrites the process memory map so hook-detection cannot see instrumentation evidence.
 *
 * Two checks are in real use (DeviceWarLock HookDetector / FridaDetector, 285★):
 *
 *  1. "RWX segment" — any line whose permission field is `rwxp` is reported as an active
 *     hook trampoline. Legitimate mappings are never rwx, so those lines are removed.
 *  2. "agent in maps" — a line naming a known instrumentation payload (frida, xposed,
 *     lsposed, magisk, substrate, rezygisk) is reported. Those lines are removed too.
 *
 * The rewrite is line-preserving for everything else, so an SDK that cross-checks the
 * map's total size or the address ordering still sees a coherent map. It is pure
 * string handling, which keeps it unit-testable without the Android runtime.
 */
public final class ProcessMapFilter {
    private ProcessMapFilter() { }

    /** Payload names that prove instrumentation if they appear in a mapping path. */
    private static final String[] AGENT_MARKERS = {
            "frida", "frida-agent", "gadget", "xposed", "lsposed", "edxposed",
            "magisk", "kernelsu", "ksu", "susfs", "substrate", "cydia",
            "rezygisk", "zygisk", "riru", "riru-next", "shamiko",
            "libhook", "libxposed", "libsandhook", "libwhale", "libdobby",
            "libepic", "libpine", "libtreesitter", "libriru"
    };

    /** True when the map line describes an rwx (hook-trampoline) segment. */
    public static boolean isRwxLine(String line) {
        if (line == null) return false;
        // Address range, then the permission field.
        int space = line.indexOf(' ');
        if (space < 0) return false;
        int start = space;
        while (start < line.length() && line.charAt(start) == ' ') start++;
        if (start + 3 > line.length()) return false;
        return line.charAt(start) == 'r'
                && line.charAt(start + 1) == 'w'
                && line.charAt(start + 2) == 'x';
    }

    /** True when the map line names a known instrumentation payload. */
    public static boolean namesAgent(String line) {
        if (line == null) return false;
        String normalized = line.toLowerCase(java.util.Locale.ROOT);
        for (String marker : AGENT_MARKERS) {
            if (normalized.contains(marker)) return true;
        }
        return false;
    }

    /** True when this line must be removed from the reported map. */
    public static boolean shouldHideLine(String line) {
        return isRwxLine(line) || namesAgent(line);
    }

    /** Rewrite a whole map body, keeping every innocent line byte-for-byte. */
    public static String filter(String mapsContent) {
        if (mapsContent == null || mapsContent.isEmpty()) return mapsContent;
        StringBuilder out = new StringBuilder(mapsContent.length());
        BufferedReader reader = new BufferedReader(new StringReader(mapsContent));
        try {
            String line;
            boolean first = true;
            while ((line = reader.readLine()) != null) {
                if (shouldHideLine(line)) continue;
                if (!first) out.append('\n');
                out.append(line);
                first = false;
            }
        } catch (IOException impossible) {
            return mapsContent;
        }
        // A map that lost every line would itself look like a failed read.
        if (out.length() == 0) return mapsContent;
        return out.append('\n').toString();
    }

    /** Same as {@link #filter} but for a byte payload, as read by FileInputStream. */
    public static byte[] filterBytes(byte[] content) {
        if (content == null || content.length == 0) return content;
        String filtered = filter(new String(content, StandardCharsets.UTF_8));
        return filtered.getBytes(StandardCharsets.UTF_8);
    }

    /** Wrap an already-open stream so callers transparently receive a filtered map. */
    public static InputStream wrap(InputStream original, boolean enabled) {
        if (!enabled || original == null) return original;
        try {
            byte[] raw = readFully(original);
            original.close();
            return new ByteArrayInputStream(filterBytes(raw));
        } catch (IOException unreadable) {
            return original;
        }
    }

    private static byte[] readFully(InputStream input) throws IOException {
        java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream(8192);
        byte[] chunk = new byte[4096];
        int count;
        while ((count = input.read(chunk)) != -1) buffer.write(chunk, 0, count);
        return buffer.toByteArray();
    }

    /** Paths whose content carries instrumentation evidence. */
    public static boolean isEvidencePath(String path) {
        if (path == null || path.isEmpty()) return false;
        String normalized = path.toLowerCase(java.util.Locale.ROOT);
        return normalized.equals("/proc/self/maps")
                || normalized.equals("/proc/self/smaps")
                || normalized.equals("/proc/self/task/" + Thread.currentThread().getId() + "/maps")
                || normalized.startsWith("/proc/self/")
                || (normalized.contains("frida") || normalized.contains("xposed")
                    || normalized.contains("magisk") || normalized.contains("lsposed"));
    }
}
