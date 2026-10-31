package de.privacyguard.adhook;

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
        Thread drain = null;
        StringBuilder output = new StringBuilder();
        final int limit = Math.max(1024, Math.min(outputLimit, DEFAULT_OUTPUT_LIMIT));
        try {
            process = new ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true).start();
            final Process running = process;
            drain = new Thread(() -> {
                // Read fixed-size chunks instead of readLine(): a single unbroken
                // output line must not allocate an unbounded String before the cap.
                try (InputStreamReader reader = new InputStreamReader(
                        running.getInputStream(), StandardCharsets.UTF_8)) {
                    char[] chunk = new char[4096];
                    int count;
                    while ((count = reader.read(chunk, 0, chunk.length)) != -1) {
                        synchronized (output) {
                            if (output.length() < limit) {
                                int remaining = limit - output.length();
                                output.append(chunk, 0, Math.min(count, remaining));
                            }
                        }
                        // Continue draining after reaching the cap so su cannot block
                        // on a full pipe; excess text is discarded, not buffered.
                    }
                } catch (Exception ignored) { }
            }, "fx-root-output");
            drain.setDaemon(true);
            drain.start();

            boolean finished = process.waitFor(Math.max(1000L, timeoutMs), TimeUnit.MILLISECONDS);
            if (!finished) {
                terminateAndReap(process);
                closeOutputQuietly(process);
                joinQuietly(drain, 1500L);
                return new Result(124,
                        "Root 命令超时（" + timeoutMs + " ms）。已请求终止并回收 su 进程；"
                                + "su 启动的独立子进程不保证全部退出。",
                        false);
            }
            // First allow the drainer to consume buffered output. A detached child may
            // inherit su's stdout pipe and keep it blocked after su exits; close only then.
            joinQuietly(drain, 2000L);
            if (drain.isAlive()) {
                closeOutputQuietly(process);
                joinQuietly(drain, 1500L);
            }
            int code = process.exitValue();
            String text;
            synchronized (output) { text = output.toString(); }
            String lower = text.toLowerCase();
            boolean denied = code != 0 && (lower.contains("denied")
                    || lower.contains("拒绝") || lower.contains("permission"));
            return new Result(code, text, denied);
        } catch (InterruptedException e) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(drain, 1500L);
            Thread.currentThread().interrupt();
            return new Result(130, "Root 命令等待被中断；已请求终止并回收 su 客户端。", false);
        } catch (Exception e) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(drain, 1500L);
            return new Result(127, e.getClass().getSimpleName() + ": " + e.getMessage(), false);
        }
    }

    /** Close our pipe end so descendants that inherited stdout cannot strand the drain thread. */
    private static void closeOutputQuietly(Process process) {
        if (process == null) return;
        try {
            process.getInputStream().close();
        } catch (Exception ignored) { }
    }

    /** Best-effort cleanup of the su client; this does not claim to kill detached descendants. */
    private static void terminateAndReap(Process process) {
        if (process == null) return;
        try {
            if (process.isAlive()) process.destroy();
            if (!process.waitFor(500, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly();
                process.waitFor(1500, TimeUnit.MILLISECONDS);
            }
        } catch (InterruptedException interrupted) {
            process.destroyForcibly();
            try {
                process.waitFor(1500, TimeUnit.MILLISECONDS);
            } catch (InterruptedException again) {
                Thread.currentThread().interrupt();
            }
            Thread.currentThread().interrupt();
        } catch (Exception ignored) {
            process.destroyForcibly();
        }
    }

    private static void joinQuietly(Thread thread, long timeoutMs) {
        if (thread == null || thread == Thread.currentThread()) return;
        try {
            thread.join(timeoutMs);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }
}
