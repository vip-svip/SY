package de.privacyguard.adhook;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.TimeUnit;

/** Executes narrowly scoped commands through KernelSU's su interface. */
public final class RootAccess {
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
        Process process = null;
        StringBuilder output = new StringBuilder();
        try {
            process = new ProcessBuilder("su", "-c", command)
                    .redirectErrorStream(true).start();
            boolean finished = process.waitFor(20, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                return new Result(124, "Root 命令超时", false);
            }
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (output.length() < 8192) output.append(line).append('\n');
                }
            }
            int code = process.exitValue();
            String text = output.toString();
            boolean denied = code != 0 && (text.toLowerCase().contains("denied")
                    || text.toLowerCase().contains("拒绝")
                    || text.toLowerCase().contains("permission"));
            return new Result(code, text, denied);
        } catch (Exception e) {
            if (process != null) process.destroyForcibly();
            return new Result(127, e.getClass().getSimpleName() + ": " + e.getMessage(), false);
        }
    }
}
