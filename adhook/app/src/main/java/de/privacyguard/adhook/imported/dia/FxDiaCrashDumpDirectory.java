package de.privacyguard.adhook.imported.dia;

import java.io.File;

/**
 * Deletes only direct regular-file contents of the FX-private minidump folder.
 * Refuses symbolic links, nested folders and paths resolving outside filesDir.
 */
public final class FxDiaCrashDumpDirectory {
    public static final String DIRECTORY_NAME = "dia-native-crash";

    private FxDiaCrashDumpDirectory() { }

    public static boolean clear(File filesRoot) {
        if (filesRoot == null || !filesRoot.isDirectory()) return false;
        try {
            File absoluteRoot = filesRoot.getAbsoluteFile();
            File canonicalRoot = filesRoot.getCanonicalFile();
            if (!absoluteRoot.equals(canonicalRoot)) return false;

            File directory = new File(filesRoot, DIRECTORY_NAME);
            if (!directory.exists()) return true;
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
            return directory.delete();
        } catch (java.io.IOException | SecurityException unsafePath) {
            return false;
        }
    }
}
