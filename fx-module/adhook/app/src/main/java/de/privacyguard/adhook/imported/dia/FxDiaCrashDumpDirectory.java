package de.privacyguard.adhook.imported.dia;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Comparator;

/**
 * Safe owner of FX-private Breakpad minidump files.
 *
 * Every operation rejects a symlinked files root, output directory, or child,
 * and refuses unexpected subdirectories before deleting or pruning anything.
 * The output directory is deliberately retained for Breakpad's process-long path.
 */
public final class FxDiaCrashDumpDirectory {
    public static final String DIRECTORY_NAME = "dia-native-crash";
    private static final Object LOCK = new Object();

    private FxDiaCrashDumpDirectory() { }

    public static boolean prepare(File filesRoot) {
        synchronized (LOCK) {
            File directory = checkedDirectory(filesRoot, true);
            return directory != null && directory.canWrite();
        }
    }

    /**
     * Retain at most maxFiles newest direct regular files and remove expired
     * files. No entry is removed until every child has passed validation.
     */
    public static boolean prune(File filesRoot, int maxFiles, long maxAgeMs, long nowMs) {
        synchronized (LOCK) {
            if (maxFiles < 0 || maxAgeMs < 0L) return false;
            File directory = checkedDirectory(filesRoot, true);
            if (directory == null || !directory.canWrite()) return false;
            File[] entries = directory.listFiles();
            if (entries == null) return false;

            for (File entry : entries) {
                if (!isDirectRegularFile(directory, entry)) return false;
            }
            Arrays.sort(entries, Comparator.comparingLong(File::lastModified).reversed());
            long cutoff = nowMs - maxAgeMs;
            int kept = 0;
            for (File entry : entries) {
                boolean expired = entry.lastModified() < cutoff;
                boolean overLimit = !expired && kept >= maxFiles;
                if (expired || overLimit) {
                    if (!isDirectRegularFile(directory, entry)
                            || checkedDirectory(filesRoot, false) == null
                            || !entry.delete()) return false;
                } else {
                    kept++;
                }
            }
            File[] remaining = directory.listFiles();
            if (remaining == null) return false;
            for (File entry : remaining) {
                if (!isDirectRegularFile(directory, entry)) return false;
            }
            return remaining.length <= maxFiles
                    && directory.equals(checkedDirectory(filesRoot, false));
        }
    }

    /** Delete only the single minidump reported by a Breakpad callback. */
    public static boolean deleteDirectDump(File filesRoot, String minidumpPath) {
        synchronized (LOCK) {
            if (filesRoot == null || minidumpPath == null || minidumpPath.trim().isEmpty()) {
                return false;
            }
            try {
                File directory = checkedDirectory(filesRoot, false);
                if (directory == null) return false;
                File target = new File(minidumpPath);
                if (!target.isAbsolute() || !target.getAbsoluteFile().equals(target.getCanonicalFile())) {
                    return false;
                }
                if (!directory.equals(target.getCanonicalFile().getParentFile())) return false;
                if (!target.exists()) return true;
                if (!isDirectRegularFile(directory, target)) return false;
                return target.delete() || !target.exists();
            } catch (IOException | SecurityException unsafePath) {
                return false;
            }
        }
    }

    /** Clear direct regular files while preserving a writable output directory. */
    public static boolean clear(File filesRoot) {
        synchronized (LOCK) {
            File directory = checkedDirectory(filesRoot, true);
            if (directory == null || !directory.canWrite()) return false;
            File[] entries = directory.listFiles();
            if (entries == null) return false;

            // Validate every entry before deleting any, so a nested directory or
            // symlink cannot cause a partial walk into user-controlled paths.
            for (File entry : entries) {
                if (!isDirectRegularFile(directory, entry)) return false;
            }
            for (File entry : entries) {
                if (!isDirectRegularFile(directory, entry)
                        || checkedDirectory(filesRoot, false) == null
                        || !entry.delete()) return false;
            }
            File[] remaining = directory.listFiles();
            if (remaining == null || remaining.length != 0) return false;
            return directory.isDirectory() && directory.canWrite()
                    && directory.equals(checkedDirectory(filesRoot, false));
        }
    }

    private static File checkedDirectory(File filesRoot, boolean create) {
        if (filesRoot == null || !filesRoot.isDirectory()) return null;
        try {
            File rootAbsolute = filesRoot.getAbsoluteFile();
            File rootCanonical = filesRoot.getCanonicalFile();
            if (!rootAbsolute.equals(rootCanonical)) return null;
            File directory = new File(filesRoot, DIRECTORY_NAME);
            if (!directory.exists() && create && !directory.mkdir() && !directory.isDirectory()) {
                return null;
            }
            if (!directory.exists() || !directory.isDirectory()
                    || !directory.getAbsoluteFile().equals(directory.getCanonicalFile())) return null;
            File expected = new File(rootCanonical, DIRECTORY_NAME);
            File canonicalDirectory = directory.getCanonicalFile();
            return expected.equals(canonicalDirectory) ? canonicalDirectory : null;
        } catch (IOException | SecurityException unsafePath) {
            return null;
        }
    }

    private static boolean isDirectRegularFile(File directory, File entry) {
        if (directory == null || entry == null || !entry.isFile()) return false;
        try {
            File absolute = entry.getAbsoluteFile();
            File canonical = entry.getCanonicalFile();
            return absolute.equals(canonical) && directory.equals(canonical.getParentFile());
        } catch (IOException | SecurityException unsafePath) {
            return false;
        }
    }
}
