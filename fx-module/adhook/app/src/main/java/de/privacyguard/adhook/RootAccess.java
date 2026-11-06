package de.privacyguard.adhook;

import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/** KernelSU su broker used by the trusted, locally packaged FX UI. */
public final class RootAccess {
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
        return new Result(code, text, false);
    }

    public static Result execute(String command) {
        return execute(command, 20000L, Integer.MAX_VALUE);
    }

    /** Compatibility overload for callers that already own an in-memory payload. */
    public static Result executeWithInput(String command, byte[] input, long timeoutMs, int outputLimit) {
        if (input == null) {
            return new Result(2, "Root 命令或输入流无效", false);
        }
        return executeWithInput(command, new java.io.ByteArrayInputStream(input), timeoutMs, outputLimit);
    }

    /** Stream an arbitrary-size payload to Root stdin without buffering the complete input. */
    public static Result executeWithInput(String command, java.io.InputStream input,
                                          long timeoutMs, int outputLimit) {
        if (command == null || command.length() == 0 || false || input == null) {
            return new Result(2, "Root 命令或输入流无效", false);
        }
        Process process = null;
        Thread drain = null;
        Thread writer = null;
        StringBuilder output = new StringBuilder();
        final int limit = Math.max(1024, outputLimit);
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
            final java.io.InputStream payload = input;
            writer = new Thread(() -> {
                try (java.io.OutputStream stream = running.getOutputStream()) {
                    byte[] buffer = new byte[64 * 1024];
                    int count;
                    while ((count = payload.read(buffer)) != -1) {
                        if (Thread.currentThread().isInterrupted()) {
                            throw new java.io.IOException("Root input stream cancelled");
                        }
                        stream.write(buffer, 0, count);
                    }
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
            if (writer.isAlive()) {
                writeFailure.compareAndSet(null, new java.io.IOException("stdin writer did not finish"));
                try { process.getOutputStream().close(); } catch (Exception ignored) { }
                joinQuietly(writer, 1000L);
            }
            joinQuietly(drain, 2000L);
            if (drain.isAlive()) {
                closeOutputQuietly(process);
                joinQuietly(drain, 1000L);
            }
            int code = process.exitValue();
            String text;
            synchronized (output) { text = output.toString(); }
            Exception failed = writeFailure.get();
            if (failed != null) {
                if (code == 0) code = 5;
                text = text + (text.isEmpty() ? "" : "\n")
                        + "Root stdin 写入失败：" + failed.getClass().getSimpleName();
            }
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

    /**
     * Stream all Root stdout into a caller-owned file. The full output is never
     * accumulated in memory or truncated by DEFAULT_OUTPUT_LIMIT; only a small
     * diagnostic prefix is retained in Result.output.
     */
    public static Result executeToFile(String command, long timeoutMs, java.io.File destination) {
        if (command == null || command.length() == 0 || command.length() > 131072
                || destination == null) {
            return new Result(2, "Root 命令或输出文件无效", false);
        }
        Process process = null;
        Thread drain = null;
        final java.util.concurrent.atomic.AtomicReference<Exception> outputFailure =
                new java.util.concurrent.atomic.AtomicReference<>();
        final java.io.ByteArrayOutputStream diagnostic = new java.io.ByteArrayOutputStream(4096);
        try {
            java.io.File absolute = destination.getAbsoluteFile();
            java.io.File canonical = absolute.getCanonicalFile();
            java.io.File parent = canonical.getParentFile();
            if (!canonical.equals(absolute) || parent == null || !parent.isDirectory()
                    || (absolute.exists() && (!absolute.isFile() || absolute.isDirectory()))) {
                return new Result(2, "Root 输出目标不是安全的普通文件", false);
            }
            process = new ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true).start();
            final Process running = process;
            final java.io.File target = canonical;
            drain = new Thread(() -> {
                java.io.OutputStream fileOutput = null;
                try {
                    fileOutput = new java.io.FileOutputStream(target, false);
                } catch (Exception error) {
                    outputFailure.compareAndSet(null, error);
                }
                try (java.io.InputStream input = running.getInputStream()) {
                    byte[] buffer = new byte[64 * 1024];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        if (fileOutput != null) {
                            try {
                                fileOutput.write(buffer, 0, count);
                            } catch (Exception error) {
                                outputFailure.compareAndSet(null, error);
                                try { fileOutput.close(); } catch (Exception ignored) { }
                                fileOutput = null;
                            }
                        }
                        synchronized (diagnostic) {
                            int remaining = 8192 - diagnostic.size();
                            if (remaining > 0) diagnostic.write(buffer, 0, Math.min(count, remaining));
                        }
                    }
                    if (fileOutput != null) {
                        fileOutput.flush();
                        if (fileOutput instanceof java.io.FileOutputStream) {
                            ((java.io.FileOutputStream) fileOutput).getFD().sync();
                        }
                    }
                } catch (Exception error) {
                    outputFailure.compareAndSet(null, error);
                } finally {
                    if (fileOutput != null) {
                        try { fileOutput.close(); } catch (Exception ignored) { }
                    }
                }
            }, "fx-root-output-file");
            drain.setDaemon(true);
            drain.start();

            boolean finished = process.waitFor(Math.max(1000L, timeoutMs), TimeUnit.MILLISECONDS);
            if (!finished) {
                terminateAndReap(process);
                closeOutputQuietly(process);
                joinQuietly(drain, 2000L);
                return new Result(124, "Root 命令输出到文件超时；已请求终止并回收 su 进程。", false);
            }
            joinQuietly(drain, 5000L);
            if (drain.isAlive()) {
                closeOutputQuietly(process);
                joinQuietly(drain, 1500L);
                outputFailure.compareAndSet(null,
                        new java.io.IOException("Root output drainer did not finish"));
            }
            int code = process.exitValue();
            String text;
            synchronized (diagnostic) {
                text = new String(diagnostic.toByteArray(), StandardCharsets.UTF_8);
            }
            Exception failed = outputFailure.get();
            if (failed != null) {
                if (code == 0) code = 5;
                text = text + (text.isEmpty() ? "" : "\n")
                        + "Root 输出文件写入失败：" + failed.getClass().getSimpleName();
            }
            String lower = text.toLowerCase();
            boolean denied = code != 0 && (lower.contains("denied")
                    || lower.contains("拒绝") || lower.contains("permission"));
            return new Result(code, text, denied);
        } catch (InterruptedException interrupted) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(drain, 1500L);
            Thread.currentThread().interrupt();
            return new Result(130, "Root 命令输出文件等待被中断；已请求终止并回收 su 客户端。", false);
        } catch (Exception error) {
            terminateAndReap(process);
            closeOutputQuietly(process);
            joinQuietly(drain, 1500L);
            return new Result(127, error.getClass().getSimpleName() + ": " + error.getMessage(), false);
        }
    }

    public static Result execute(String command, long timeoutMs, int outputLimit) {
        if (command == null || command.length() == 0 || command.length() > 131072) {
            return new Result(2, "Root 命令为空", false);
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
