package de.privacyguard.adhook.imported.dia;

import java.io.File;

/**
 * Deletes only direct regular-file contents of the FX-private minidump folder.
 * Keeps the empty directory in place because the registered Breakpad handler
 * holds this path for the lifetime of the current process.
 * Refuses symbolic links, nested folders and paths resolving outside filesDir.
 */
public final class FxDiaCrashDumpDirectory {
    public static final String DIRECTORY_NAME = "dia-native-crash";

    private FxDiaCrashDumpDirectory() { }

    /**
     * Delete only the single minidump reported by a Breakpad callback.
     * Breakpad's native handler remains registered for this process after
     * capture is disabled, so its callback must discard only the new dump.
     */
    public static boolean deleteDirectDump(File filesRoot, String minidumpPath) {
        if (filesRoot == null || minidumpPath == null || minidumpPath.trim().isEmpty()
                || !filesRoot.isDirectory()) return false;
        try {
            File absoluteRoot = filesRoot.getAbsoluteFile();
            File canonicalRoot = filesRoot.getCanonicalFile();
            if (!absoluteRoot.equals(canonicalRoot)) return false;

            File directory = new File(filesRoot, DIRECTORY_NAME);
            if (!directory.exists()) return true;
            if (!directory.isDirectory()
                    || !directory.getAbsoluteFile().equals(directory.getCanonicalFile())) {
                return false;
            }
            File canonicalDirectory = directory.getCanonicalFile();
            File expectedDirectory = new File(canonicalRoot, DIRECTORY_NAME);
            if (!canonicalDirectory.equals(expectedDirectory)) return false;

            File target = new File(minidumpPath);
            if (!target.isAbsolute()) return false;
            File absoluteTarget = target.getAbsoluteFile();
            File canonicalTarget = target.getCanonicalFile();
            if (!absoluteTarget.equals(canonicalTarget)) return false;
            if (!target.exists()) return true;
            if (!target.isFile()
                    || !canonicalDirectory.equals(canonicalTarget.getParentFile())) {
                return false;
            }
            return target.delete() || !target.exists();
        } catch (java.io.IOException | SecurityException unsafePath) {
            return false;
        }
    }

    public static boolean clear(File filesRoot) {
        if (filesRoot == null || !filesRoot.isDirectory()) return false;
        try {
            File absoluteRoot = filesRoot.getAbsoluteFile();
            File canonicalRoot = filesRoot.getCanonicalFile();
            if (!absoluteRoot.equals(canonicalRoot)) return false;

            File directory = new File(filesRoot, DIRECTORY_NAME);
            // Breakpad is already initialized with this exact output path. A
            // successful clear must leave the directory writable, not remove
            // it and silently disable future native minidump creation.
            if (!directory.exists() && !directory.mkdir() && !directory.isDirectory()) {
                return false;
            }
            if (!directory.isDirectory()) return false;

            File canonicalDirectory = directory.getCanonicalFile();
            File expectedDirectory = new File(canonicalRoot, DIRECTORY_NAME);
            if (!canonicalDirectory.equals(expectedDirectory)) return false;

            File[] entries = directory.listFiles();
            if (entries == null) return false;

            // Validate all children before deleting any of them.
            for (File entry : entries) {
                File canonicalEntry = entry.getCanonicalFile();
                if (!entry.isFile()
                        || !entry.getAbsoluteFile().equals(canonicalEntry)
                        || !canonicalDirectory.equals(canonicalEntry.getParentFile())) {
                    return false;
                }
            }

            for (File entry : entries) {
                if (!entry.delete()) return false;
            }
            File[] remaining = directory.listFiles();
            return directory.isDirectory()
                    && directory.getCanonicalFile().equals(expectedDirectory)
                    && directory.canWrite()
                    && remaining != null && remaining.length == 0;
        } catch (java.io.IOException | SecurityException unsafePath) {
            return false;
        }
    }
}
