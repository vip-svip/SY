import de.privacyguard.adhook.imported.dia.FxDiaCrashDumpDirectory;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Host-JVM behavior tests for private minidump deletion and path safety. */
public final class FxDiaCrashDumpDirectoryHostTest {
    private static void require(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }

    private static File child(File root) {
        return new File(root, FxDiaCrashDumpDirectory.DIRECTORY_NAME);
    }

    public static void main(String[] args) throws Exception {
        Path temp = Files.createTempDirectory("fx-crash-dump-clear-");
        File root = temp.resolve("files").toFile();
        require(root.mkdir(), "private files fixture must be created");

        File dumps = child(root);
        require(FxDiaCrashDumpDirectory.clear(root),
                "missing minidump directory should be created for the already-registered Breakpad path");
        require(dumps.isDirectory() && dumps.canWrite(),
                "empty minidump output directory must remain writable after clear");

        Files.write(new File(dumps, "one.dmp").toPath(), "dump-one".getBytes(StandardCharsets.UTF_8));
        Files.write(new File(dumps, "two.dmp").toPath(), "dump-two".getBytes(StandardCharsets.UTF_8));
        require(FxDiaCrashDumpDirectory.clear(root), "regular private minidumps should be cleared");
        require(dumps.isDirectory() && dumps.canWrite(),
                "minidump directory must remain writable for future Breakpad crashes");
        File[] afterClear = dumps.listFiles();
        require(afterClear != null && afterClear.length == 0,
                "successful clear must remove all dump files while retaining the output directory");
        Files.write(new File(dumps, "after-clear.dmp").toPath(),
                "future-crash".getBytes(StandardCharsets.UTF_8));
        require(new File(dumps, "after-clear.dmp").isFile(),
                "future Breakpad minidump must be writable without restarting the FX process");
        require(FxDiaCrashDumpDirectory.clear(root), "post-clear minidump should also be removable");

        Path externalFile = temp.resolve("external-secret.dmp");
        Files.write(externalFile, "do-not-delete".getBytes(StandardCharsets.UTF_8));
        require(dumps.isDirectory(), "symlink-entry fixture must reuse the preserved output directory");
        Files.createSymbolicLink(new File(dumps, "linked.dmp").toPath(), externalFile);
        require(!FxDiaCrashDumpDirectory.clear(root), "symlinked dump entry must be rejected");
        require(Files.exists(externalFile), "symlink target must remain untouched");
        require(dumps.isDirectory(), "directory must remain when validation fails");

        Files.delete(new File(dumps, "linked.dmp").toPath());
        File nested = new File(dumps, "unexpected");
        require(nested.mkdir(), "nested fixture directory must be created");
        File nestedSecret = new File(nested, "keep.txt");
        Files.write(nestedSecret.toPath(), "keep".getBytes(StandardCharsets.UTF_8));
        require(!FxDiaCrashDumpDirectory.clear(root), "nested directory must be rejected");
        require(nestedSecret.isFile(), "nested data must remain untouched");

        Files.delete(nestedSecret.toPath());
        require(nested.delete(), "nested fixture directory should be removable");
        require(dumps.delete(), "empty child fixture should be removable");
        Path externalDirectory = Files.createTempDirectory(temp, "external-dumps-");
        Path externalKeep = externalDirectory.resolve("keep.dmp");
        Files.write(externalKeep, "outside".getBytes(StandardCharsets.UTF_8));
        Files.createSymbolicLink(dumps.toPath(), externalDirectory);
        require(!FxDiaCrashDumpDirectory.clear(root), "symlinked minidump directory must be rejected");
        require(Files.exists(externalKeep), "external minidump must remain untouched");

        Files.delete(dumps.toPath());
        require(FxDiaCrashDumpDirectory.clear(root), "missing minidump directory should be recreated");
        require(dumps.isDirectory() && dumps.canWrite(),
                "recreated minidump directory must be writable after a prior path removal");
        System.out.println("PASS: private minidump clear preserves or recreates writable Breakpad path, rejects symlinks and nested directories");
    }
}
