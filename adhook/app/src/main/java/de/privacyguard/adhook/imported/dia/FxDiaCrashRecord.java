package de.privacyguard.adhook.imported.dia;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Bounded crash report model compatible with Dia 23.11's visible fields. */
public final class FxDiaCrashRecord {
    public static final int MAX_STACK_CHARS = 128 * 1024;
    private static final int MAX_MESSAGE_CHARS = 8192;
    public final long timestampMs;
    public final long threadId;
    public final String processName;
    public final String threadName;
    public final String deviceInfo;
    public final String message;
    public final String stack;

    public FxDiaCrashRecord(long timestampMs, long threadId, String processName,
                            String threadName, String deviceInfo, String message, String stack) {
        this.timestampMs = timestampMs;
        this.threadId = Math.max(0L, threadId);
        this.processName = bounded(processName, 512);
        this.threadName = bounded(threadName, 256);
        this.deviceInfo = bounded(deviceInfo, 1024);
        this.message = bounded(message, MAX_MESSAGE_CHARS);
        this.stack = bounded(stack, MAX_STACK_CHARS);
    }

    public String format(boolean hexEncodeStack) {
        StringBuilder out = new StringBuilder(1024 + stack.length());
        String date = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                .format(new Date(timestampMs));
        out.append("FX 崩溃报告\n")
                .append("时间：").append(date).append('\n')
                .append("进程：").append(processName).append('\n')
                .append("线程：").append(threadName).append(" (ID ").append(threadId).append(")\n")
                .append("设备：").append(deviceInfo).append('\n')
                .append("异常：").append(message).append('\n');
        if (hexEncodeStack) {
            out.append("堆栈（HEX 编码；可逆，不是加密）:\n").append(hexUtf8(stack));
        } else {
            out.append("堆栈:\n").append(stack);
        }
        return out.toString();
    }

    public static String stackTrace(Throwable error) {
        if (error == null) return "(no throwable)";
        StringWriter buffer = new StringWriter();
        PrintWriter writer = new PrintWriter(buffer);
        error.printStackTrace(writer);
        writer.flush();
        return bounded(buffer.toString(), MAX_STACK_CHARS);
    }

    public static String hexUtf8(String value) {
        byte[] bytes = (value == null ? "" : value).getBytes(StandardCharsets.UTF_8);
        char[] hex = "0123456789abcdef".toCharArray();
        char[] out = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int b = bytes[i] & 0xff;
            out[i * 2] = hex[b >>> 4];
            out[i * 2 + 1] = hex[b & 0x0f];
        }
        return new String(out);
    }

    public static String bounded(String value, int maxChars) {
        if (value == null || maxChars < 1) return "";
        if (value.length() <= maxChars) return value;
        String marker = "\n...[truncated]";
        if (maxChars <= marker.length()) return value.substring(0, maxChars);
        return value.substring(0, maxChars - marker.length()) + marker;
    }
}
