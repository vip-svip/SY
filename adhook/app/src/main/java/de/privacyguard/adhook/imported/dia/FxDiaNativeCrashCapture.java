package de.privacyguard.adhook.imported.dia;

import android.content.Context;

import com.babyte.breakpad.BaByteBreakpad;
import com.babyte.breakpad.callback.NativeCrashCallback;

import java.io.File;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Map;

/** Installs the original Dia Breakpad handler only in the FX application process. */
public final class FxDiaNativeCrashCapture {
    private static volatile boolean installed;
    private static volatile String status = "尚未初始化";
    private static volatile NativeCrashCallback registeredCallback;

    private FxDiaNativeCrashCapture() { }

    public static synchronized boolean install(Context context) {
        if (context == null) {
            status = "Native 崩溃捕获不可用：Context 不存在";
            return false;
        }
        Context app = context.getApplicationContext() != null
                ? context.getApplicationContext() : context;
        if (!FxDiaCrashStore.isCaptureEnabled(app)) {
            status = "Native 崩溃捕获已关闭";
            return false;
        }
        if (installed) return true;
        if (!BaByteBreakpad.isLibraryLoaded()) {
            status = "Native 崩溃捕获不可用：当前 ABI 未加载原版 libbreakpad.so";
            return false;
        }

        File directory = new File(app.getFilesDir(), "dia-native-crash");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            status = "Native 崩溃捕获不可用：无法创建私有 minidump 目录";
            return false;
        }
        if (!directory.isDirectory() || !directory.canWrite()) {
            status = "Native 崩溃捕获不可用：私有 minidump 目录不可写";
            return false;
        }
        pruneOldMinidumps(directory);

        NativeCrashCallback callback = (minidumpPath, nativeInfo, nativeThreadTrack, crashThreadName) -> {
            if (!FxDiaCrashStore.isCaptureEnabled(app)) return;
            FxDiaCrashStore.recordNativeCrash(app, minidumpPath, nativeInfo,
                    nativeThreadTrack, crashThreadName, findJvmThreadStack(crashThreadName));
            pruneOldMinidumps(directory);
        };
        try {
            registeredCallback = callback;
            BaByteBreakpad.INSTANCE.initBreakpad(directory.getAbsolutePath(), callback);
            installed = true;
            status = "Native Breakpad 已在 FX 主进程注册；minidump 保存在 FX 私有目录";
            return true;
        } catch (Throwable error) {
            registeredCallback = null;
            status = "Native 崩溃捕获初始化失败：" + error.getClass().getSimpleName();
            return false;
        }
    }

    public static String statusLine(Context context) {
        if (context != null && !FxDiaCrashStore.isCaptureEnabled(context)) {
            return "Native 崩溃捕获未启用。";
        }
        return status + "。";
    }

    private static void pruneOldMinidumps(File directory) {
        File[] files = directory.listFiles();
        if (files == null || files.length == 0) return;
        Arrays.sort(files, Comparator.comparingLong(File::lastModified).reversed());
        long cutoff = System.currentTimeMillis() - 30L * 24L * 60L * 60L * 1000L;
        int kept = 0;
        for (File candidate : files) {
            if (!candidate.isFile()) continue;
            if (candidate.lastModified() < cutoff || kept >= 5) {
                try { candidate.delete(); } catch (SecurityException ignored) { }
            } else {
                kept++;
            }
        }
    }

    static String findJvmThreadStack(String threadName) {
        String wanted = threadName == null ? "" : threadName.trim();
        StringBuilder output = new StringBuilder();
        try {
            for (Map.Entry<Thread, StackTraceElement[]> entry : Thread.getAllStackTraces().entrySet()) {
                Thread thread = entry.getKey();
                if (thread == null || !thread.getName().equals(wanted)) continue;
                output.append("Thread: ").append(thread.getName())
                        .append(" (").append(thread.getId()).append(")\n");
                for (StackTraceElement frame : entry.getValue()) {
                    output.append("    at ").append(frame).append('\n');
                    if (output.length() >= FxDiaCrashRecord.MAX_STACK_CHARS / 2) break;
                }
                break;
            }
        } catch (Throwable ignored) { }
        if (output.length() == 0) {
            output.append("No matching JVM thread snapshot was available for native crash thread: ")
                    .append(wanted.isEmpty() ? "(unknown)" : wanted).append('\n');
        }
        return FxDiaCrashRecord.bounded(output.toString(), FxDiaCrashRecord.MAX_STACK_CHARS / 2);
    }
}
