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
        public Result(int code, String text, boolean wasDenied) {
            exitCode = code;
            output = text;
            denied = wasDenied;
        }
    }

    /** Create a completed failure result without starting a Root process. */
    public static Result failure(int exitCode, String message) {
        int code = exitCode == 0 ? 1 : exitCode;
        String text = message == null ? "Root 操作未执行" : message;
        if (text.length() > DEFAULT_OUTPUT_LIMIT) {
            text = text.substring(0, DEFAULT_OUTPUT_LIMIT);
        }
        return new Result(code, text, false);
    }

    public static Result execute(String command) {
        return execute(command, 20000L, DEFAULT_OUTPUT_LIMIT);
    }

    /** Execute a root command while streaming a bounded payload to its stdin. */
    public static Result executeWithInput(String command, byte[] input, long timeoutMs, int outputLimit) {
        if (command == null || command.length() == 0 || command.length() > 131072
                || input == null || input.length > 8 * 1024 * 1024) {
            return new Result(2, "Root 命令无效或输入超过 8 MiB 安全上限", false);
        }
        Process process = null;
        Thread drain = null;
        Thread writer = null;
        StringBuilder output = new StringBuilder();
        final int limit = Math.max(1024, Math.min(outputLimit, DEFAULT_OUTPUT_LIMIT));
        final java.util.concurrent.atomic.AtomicReference<Exception> writeFailure =
                new java.util.concurrent.atomic.AtomicReference<>();
        try {
            process = new ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true).start();
            final Process running = process;
            drain = new Thread(() -> {
                try (InputStreamReader reader = new InputStreamReader(
                        running.getInputStream(), StandardCharsets.UTF_8)) {
                    char[] chunk = new char[4096];
                    int count;
                    while ((count = reader.read(chunk, 0, chunk.length)) != -1) {
                        synchronized (output) {
                            if (output.length() < limit) {
                                output.append(chunk, 0, Math.min(count, limit - output.length()));
                            }
                        }
                    }
                } catch (Exception ignored) { }
            }, "fx-root-input-output");
            drain.setDaemon(true);
            drain.start();
            final byte[] payload = input;
            writer = new Thread(() -> {
                try (java.io.OutputStream stream = running.getOutputStream()) {
                    stream.write(payload);
                    stream.flush();
                } catch (Exception error) {
                    writeFailure.set(error);
                }
            }, "fx-root-input-writer");
            writer.setDaemon(true);
            writer.start();

            boolean finished = process.waitFor(Math.max(1000L, timeoutMs), TimeUnit.MILLISECONDS);
            if (!finished) {
                terminateAndReap(process);
                try { process.getOutputStream().close(); } catch (Exception ignored) { }
                closeOutputQuietly(process);
                joinQuietly(writer, 1000L);
                joinQuietly(drain, 1500L);
                return new Result(124, "Root 输入命令超时；已请求终止并回收 su 进程。", false);
            }
            try { process.getOutputStream().close(); } catch (Exception ignored) { }
            joinQuietly(writer, 1500L);
            joinQuietly(drain, 2000L);
            if (drain.isAlive()) {
                closeOutputQuietly(process);
                joinQuietly(drain, 1000L);
            }
            int code = process.exitValue();
            String text;
            synchronized (output) { text = output.toString(); }
            Exception failed = writeFailure.get();
            if (failed != null) text = text + (text.isEmpty() ? "" : "\n")
                    + "Root stdin 写入失败：" + failed.getClass().getSimpleName();
            String lower = text.toLowerCase();
            boolean denied = code != 0 && (lower.contains("denied")
                    || lower.contains("拒绝") || lower.contains("permission"));
            return new Result(code, text, denied);
        } catch (InterruptedException e) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(writer, 1000L);
            joinQuietly(drain, 1000L);
            Thread.currentThread().interrupt();
            return new Result(130, "Root 输入命令等待被中断；已请求终止并回收 su 客户端。", false);
        } catch (Exception e) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(writer, 1000L);
            joinQuietly(drain, 1000L);
            return new Result(127, e.getClass().getSimpleName() + ": " + e.getMessage(), false);
        }
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
