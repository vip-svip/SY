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
        require(dumps.mkdir(), "minidump directory must be created");
        Files.write(new File(dumps, "one.dmp").toPath(), "dump-one".getBytes(StandardCharsets.UTF_8));
        Files.write(new File(dumps, "two.dmp").toPath(), "dump-two".getBytes(StandardCharsets.UTF_8));
        require(FxDiaCrashDumpDirectory.clear(root), "regular private minidumps should be cleared");
        require(!dumps.exists(), "minidump directory should be removed after successful clear");

        Path externalFile = temp.resolve("external-secret.dmp");
        Files.write(externalFile, "do-not-delete".getBytes(StandardCharsets.UTF_8));
        require(dumps.mkdir(), "symlink fixture directory must be created");
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
        require(FxDiaCrashDumpDirectory.clear(root), "missing minidump directory is already clear");
        System.out.println("PASS: private minidump clear, symlink refusal, no recursive deletion and idempotent absence");
    }
}
