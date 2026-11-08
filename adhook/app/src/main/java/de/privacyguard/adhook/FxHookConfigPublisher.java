package de.privacyguard.adhook;

import java.io.ByteArrayInputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Publishes unified Hook payloads through Root stdin, verifies staged bytes,
 * then transactionally replaces all three related files, verifies their final hashes,
 * and restores prior files when any commit step fails.
 */
final class FxHookConfigPublisher {
    private static final int OUTPUT_LIMIT = 16 * 1024;
    private static final long BASE_TIMEOUT_MS = 60000L;
    private FxHookConfigPublisher() { }

    static RootAccess.Result publish(byte[] configBytes, byte[] managedBytes, int androidUser) {
        if (androidUser < 0) return RootAccess.failure(2, "Android user id is invalid");
        return publish(configBytes, managedBytes, Layout.forUser(androidUser));
    }

    static RootAccess.Result publish(byte[] configBytes, byte[] managedBytes, Layout layout) {
        if (configBytes == null || managedBytes == null || layout == null) {
            return RootAccess.failure(2, "Hook config payload or target layout is invalid");
        }
        try {
            String nonce = UUID.randomUUID().toString().replace("-", "");
            Payload remote = new Payload(layout.remotePath(), layout.remotePath() + ".fx-stage-" + nonce,
                    layout.remotePath() + ".fx-backup-" + nonce, configBytes, "0644",
                    "u:object_r:magisk_file:s0");
            Payload nativeOverlay = new Payload(layout.nativePath(), layout.nativePath() + ".fx-stage-" + nonce,
                    layout.nativePath() + ".fx-backup-" + nonce, configBytes, "0600",
                    "u:object_r:magisk_file:s0");
            Payload managed = new Payload(layout.managedPath(), layout.managedPath() + ".fx-stage-" + nonce,
                    layout.managedPath() + ".fx-backup-" + nonce, managedBytes, "0644",
                    "u:object_r:shell_data_file:s0");
            Payload[] payloads = {remote, nativeOverlay, managed};

            RootAccess.Result prepared = RootAccess.execute(
                    prepareCommand(layout, payloads), BASE_TIMEOUT_MS, OUTPUT_LIMIT);
            if (prepared.exitCode != 0) return prepared;

            for (Payload payload : payloads) {
                RootAccess.Result staged = RootAccess.executeWithInput(stageCommand(payload),
                        new ByteArrayInputStream(payload.bytes),
                        transferTimeout(payload.bytes.length), OUTPUT_LIMIT);
                if (staged.exitCode != 0) return cleanupAfterFailure(staged, payloads, false);
            }

            RootAccess.Result committed = RootAccess.execute(
                    commitCommand(layout, payloads), BASE_TIMEOUT_MS, OUTPUT_LIMIT);
            if (committed.exitCode == 0) return committed;
            boolean preserveRecoveryCopies = committed.output != null
                    && committed.output.contains("FX_ROLLBACK_FAILED");
            return cleanupAfterFailure(committed, payloads, preserveRecoveryCopies);
        } catch (Exception error) {
            return RootAccess.failure(1,
                    "Hook config publication failed before commit: " + error.getClass().getSimpleName());
        }
    }

    static final class Layout {
        final String dataRoot;
        final int androidUser;
        final String moduleDir;
        final String legacyDir;
        final String privacyDir;

        Layout(String dataRoot, int androidUser) {
            // The root must be absolute. Production always passes /data through
            // forUser(); the host regression passes a temporary directory, which is
            // absolute on every platform but does not start with "/" on Windows.
            if (dataRoot == null || dataRoot.isEmpty()
                    || !java.nio.file.Paths.get(dataRoot).isAbsolute() || androidUser < 0) {
                throw new IllegalArgumentException("invalid Hook publication layout");
            }
            this.dataRoot = dataRoot;
            this.androidUser = androidUser;
            this.moduleDir = dataRoot + "/adb/lspd/modules/" + androidUser
                    + "/de.privacyguard.adhook/files";
            this.legacyDir = dataRoot + "/local/tmp/privacyguard";
            this.privacyDir = dataRoot + "/adb/privacyguard";
        }

        static Layout forUser(int androidUser) {
            return new Layout("/data", androidUser);
        }

        String remotePath() { return moduleDir + "/fx-hook-targets.conf"; }
        String managedPath() { return legacyDir + "/fx-api101-managed.conf"; }
        String nativePath() {
            return privacyDir + "/fx-native-hook-targets-" + androidUser + ".conf";
        }

        List<String> directories() {
            List<String> values = new ArrayList<>();
            values.add(dataRoot);
            values.add(dataRoot + "/adb");
            values.add(dataRoot + "/adb/lspd");
            values.add(dataRoot + "/adb/lspd/modules");
            values.add(dataRoot + "/adb/lspd/modules/" + androidUser);
            values.add(dataRoot + "/adb/lspd/modules/" + androidUser + "/de.privacyguard.adhook");
            values.add(moduleDir);
            values.add(dataRoot + "/local");
            values.add(dataRoot + "/local/tmp");
            values.add(legacyDir);
            values.add(privacyDir);
            return values;
        }
    }

    private static final class Payload {
        final String target, staged, backup, hash, mode, selinuxContext;
        final byte[] bytes;

        Payload(String target, String staged, String backup, byte[] bytes,
                String mode, String selinuxContext) throws Exception {
            this.target = target;
            this.staged = staged;
            this.backup = backup;
            this.bytes = bytes;
            this.hash = sha256(bytes);
            this.mode = mode;
            this.selinuxContext = selinuxContext;
        }
    }

    private static String prepareCommand(Layout layout, Payload[] payloads) {
        StringBuilder command = new StringBuilder("set -e; umask 077; ");
        for (String directory : layout.directories()) {
            String path = quote(directory);
            command.append("[ ! -L ").append(path).append(" ] && { [ ! -e ").append(path)
                    .append(" ] || [ -d ").append(path)
                    .append(" ]; } || { echo 'unsafe Hook directory'; exit 71; }; ");
        }
        command.append("mkdir -p");
        for (String directory : layout.directories()) command.append(' ').append(quote(directory));
        command.append("; chmod 0755 ").append(quote(layout.moduleDir)).append(' ')
                .append(quote(layout.legacyDir)).append("; ")
                .append("chcon u:object_r:magisk_file:s0 ").append(quote(layout.moduleDir))
                .append(' ').append(quote(layout.privacyDir)).append("; ")
                .append("chcon u:object_r:shell_data_file:s0 ").append(quote(layout.legacyDir)).append("; ");
        for (Payload payload : payloads) {
            String target = quote(payload.target), staged = quote(payload.staged), backup = quote(payload.backup);
            command.append("[ ! -L ").append(target).append(" ] && { [ ! -e ").append(target)
                    .append(" ] || [ -f ").append(target)
                    .append(" ]; } || { echo 'unsafe Hook target'; exit 72; }; ")
                    .append("[ ! -L ").append(staged).append(" ] && [ ! -e ").append(staged)
                    .append(" ] || { echo 'Hook staging path already exists'; exit 73; }; ")
                    .append("[ ! -L ").append(backup).append(" ] && [ ! -e ").append(backup)
                    .append(" ] || { echo 'Hook backup path already exists'; exit 74; }; ");
        }
        command.append("sync");
        return command.toString();
    }

    private static String stageCommand(Payload payload) {
        String staged = quote(payload.staged);
        return "set -e; umask 077; "
                + "[ ! -L " + staged + " ] && [ ! -e " + staged + " ] || exit 75; "
                + "cat > " + staged + "; "
                + "actual=$(sha256sum " + staged + " | cut -d ' ' -f1); "
                + "[ \"$actual\" = " + quote(payload.hash) + " ] || { rm -f " + staged
                + "; echo 'FX_STAGE_HASH_MISMATCH'; exit 76; }; "
                + "chmod " + payload.mode + " " + staged + "; "
                + "chown 0:0 " + staged + "; chcon " + payload.selinuxContext + " "
                + staged + "; sync";
    }

    private static String commitCommand(Layout layout, Payload[] payloads) {
        StringBuilder command = new StringBuilder("set -e; umask 077; ");
        for (String directory : layout.directories()) {
            String path = quote(directory);
            command.append("[ ! -L ").append(path).append(" ] && [ -d ").append(path)
                    .append(" ] || { echo 'Hook directory changed before commit'; exit 77; }; ");
        }
        for (Payload payload : payloads) {
            String target = quote(payload.target), staged = quote(payload.staged), backup = quote(payload.backup);
            command.append("[ ! -L ").append(target).append(" ] && { [ ! -e ").append(target)
                    .append(" ] || [ -f ").append(target)
                    .append(" ]; } || { echo 'Hook target changed before commit'; exit 78; }; ")
                    .append("[ -f ").append(staged).append(" ] && [ ! -L ").append(staged)
                    .append(" ] || { echo 'Hook staged payload missing'; exit 79; }; ")
                    .append("[ ! -L ").append(backup).append(" ] && [ ! -e ").append(backup)
                    .append(" ] || { echo 'Hook backup path changed'; exit 80; }; ")
                    .append("actual=$(sha256sum ").append(staged).append(" | cut -d ' ' -f1); ")
                    .append("[ \"$actual\" = ").append(quote(payload.hash))
                    .append(" ] || { echo 'Hook staged SHA-256 mismatch'; exit 81; }; ");
        }
        command.append("had_remote=0; had_native=0; had_managed=0; ");
        for (int i = 0; i < payloads.length; i++) {
            String flag = i == 0 ? "had_remote" : i == 1 ? "had_native" : "had_managed";
            Payload payload = payloads[i];
            command.append("if [ -e ").append(quote(payload.target)).append(" ]; then cp -p ")
                    .append(quote(payload.target)).append(' ').append(quote(payload.backup))
                    .append("; ").append(flag).append("=1; fi; ");
        }
        command.append("rollback() { rollback_failed=0; ");
        for (int i = 0; i < payloads.length; i++) {
            String flag = i == 0 ? "had_remote" : i == 1 ? "had_native" : "had_managed";
            Payload payload = payloads[i];
            command.append("if [ \"$").append(flag).append("\" = 1 ]; then mv -f ")
                    .append(quote(payload.backup)).append(' ').append(quote(payload.target))
                    .append(" || rollback_failed=1; else rm -f ").append(quote(payload.target))
                    .append(" || rollback_failed=1; fi; ");
        }
        command.append("return \"$rollback_failed\"; }; ");
        appendMoveOrRollback(command, payloads[0], "REMOTE");
        appendMoveOrRollback(command, payloads[1], "NATIVE");
        appendMoveOrRollback(command, payloads[2], "MANAGED");
        for (int i = 0; i < payloads.length; i++) {
            Payload payload = payloads[i];
            String label = i == 0 ? "REMOTE" : i == 1 ? "NATIVE" : "MANAGED";
            command.append("actual=$(sha256sum ").append(quote(payload.target))
                    .append(" 2>/dev/null | cut -d ' ' -f1); ")
                    .append("if [ \"$actual\" != ").append(quote(payload.hash)).append(" ]; then ")
                    .append("if rollback; then echo 'FX_COMMIT_HASH_MISMATCH_").append(label)
                    .append("'; exit 82; else echo 'FX_ROLLBACK_FAILED'; exit 83; fi; fi; ");
        }
        for (Payload payload : payloads) command.append("rm -f ").append(quote(payload.backup)).append("; ");
        command.append("sync; printf 'SHA256=%s\\nAPI101_OVERLAY_SHA256=%s\\nAPI101_OWNERSHIP_SHA256=%s\\n' ")
                .append(quote(payloads[0].hash)).append(' ').append(quote(payloads[1].hash))
                .append(' ').append(quote(payloads[2].hash));
        return command.toString();
    }

    private static void appendMoveOrRollback(StringBuilder command, Payload payload, String label) {
        command.append("if ! mv -f ").append(quote(payload.staged)).append(' ')
                .append(quote(payload.target)).append("; then ")
                .append("if rollback; then echo 'FX_COMMIT_FAILED_").append(label)
                .append("'; exit 84; else echo 'FX_ROLLBACK_FAILED'; exit 83; fi; fi; ");
    }

    private static RootAccess.Result cleanupAfterFailure(RootAccess.Result original,
                                                         Payload[] payloads,
                                                         boolean preserveRecoveryCopies) {
        StringBuilder command = new StringBuilder("rm -f");
        for (Payload payload : payloads) {
            command.append(' ').append(quote(payload.staged));
            if (!preserveRecoveryCopies) command.append(' ').append(quote(payload.backup));
        }
        command.append("; sync");
        RootAccess.Result cleanup = RootAccess.execute(command.toString(), BASE_TIMEOUT_MS, OUTPUT_LIMIT);
        String detail = original.output == null ? "" : original.output;
        if (cleanup.exitCode != 0) detail += "\nHook 临时文件清理失败：" + cleanup.output;
        if (preserveRecoveryCopies) {
            detail += "\n自动回滚未完成；保留备份文件：" + payloads[0].backup
                    + "；" + payloads[1].backup + "；" + payloads[2].backup;
        }
        return new RootAccess.Result(original.exitCode == 0 ? 1 : original.exitCode,
                detail, original.denied);
    }

    private static long transferTimeout(int byteCount) {
        long chunks = ((long) byteCount + 64L * 1024L - 1L) / (64L * 1024L);
        return Math.max(BASE_TIMEOUT_MS, 30000L + chunks * 1000L);
    }

    private static String sha256(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder value = new StringBuilder(digest.length * 2);
        for (byte item : digest) value.append(String.format(java.util.Locale.ROOT,
                "%02x", item & 0xff));
        return value.toString();
    }

    private static String quote(String value) {
        return "'" + value.replace("'", "'\''") + "'";
    }
}
