package de.privacyguard.adhook;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/** KernelSU su broker used by the trusted, locally packaged FX UI. */
public final class RootAccess {
    private static final int DEFAULT_OUTPUT_LIMIT = 1024 * 1024;
    private RootAccess() {}

    public static final class Result {
        public final int exitCode;
        public final String output;
        public final boolean denied;
        Result(int code, String text, boolean wasDenied) {
            exitCode = code;
            output = text;
            denied = wasDenied;
        }
    }

    public static Result execute(String command) {
        return execute(command, 20000L, DEFAULT_OUTPUT_LIMIT);
    }

    public static Result execute(String command, long timeoutMs, int outputLimit) {
        if (command == null || command.length() == 0 || command.length() > 131072) {
            return new Result(2, "Root 命令为空或超过 128 KiB 限制", false);
        }
        Process process = null;
        StringBuilder output = new StringBuilder();
        final int limit = Math.max(1024, Math.min(outputLimit, DEFAULT_OUTPUT_LIMIT));
        try {
            process = new ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true).start();
            final Process running = process;
            Thread drain = new Thread(() -> {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(running.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        synchronized (output) {
                            if (output.length() < limit) {
                                int remaining = limit - output.length();
                                output.append(line, 0, Math.min(line.length(), remaining));
                                if (output.length() < limit) output.append('\n');
                            }
                        }
                    }
                } catch (Exception ignored) { }
            }, "fx-root-output");
            drain.setDaemon(true);
            drain.start();

            boolean finished = process.waitFor(Math.max(1000L, timeoutMs), TimeUnit.MILLISECONDS);
            if (!finished) {
                process.destroy();
                if (!process.waitFor(500, TimeUnit.MILLISECONDS)) {
                    process.destroyForcibly();
                    // Reap the su client before returning; otherwise repeated
                    // timeouts can leave zombie/native process handles behind.
                    process.waitFor(1500, TimeUnit.MILLISECONDS);
                }
                drain.join(1500L);
                return new Result(124,
                        "Root 命令超时（" + timeoutMs + " ms）。已请求终止并回收 su 进程；"
                                + "su 启动的独立子进程不保证全部退出。",
                        false);
            }
            drain.join(2000L);
            int code = process.exitValue();
            String text;
            synchronized (output) { text = output.toString(); }
            String lower = text.toLowerCase();
            boolean denied = code != 0 && (lower.contains("denied")
                    || lower.contains("拒绝") || lower.contains("permission"));
            return new Result(code, text, denied);
        } catch (Exception e) {
            if (process != null) process.destroyForcibly();
            return new Result(127, e.getClass().getSimpleName() + ": " + e.getMessage(), false);
        }
    }
}
