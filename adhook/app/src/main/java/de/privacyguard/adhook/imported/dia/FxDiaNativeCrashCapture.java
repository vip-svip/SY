package de.privacyguard.adhook.imported.dia;

import android.content.Context;

import com.babyte.breakpad.BaByteBreakpad;
import com.babyte.breakpad.callback.NativeCrashCallback;

import java.io.File;
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

        File directory = new File(app.getFilesDir(), FxDiaCrashDumpDirectory.DIRECTORY_NAME);
        if (!FxDiaCrashDumpDirectory.prepare(app.getFilesDir())) {
            status = "Native 崩溃捕获不可用：私有 minidump 目录路径不安全或不可写";
            return false;
        }
        if (!pruneOldMinidumps(app.getFilesDir())) {
            status = "Native 崩溃捕获不可用：minidump 目录含有不安全条目，拒绝注册";
            return false;
        }

        NativeCrashCallback callback = (minidumpPath, nativeInfo, nativeThreadTrack, crashThreadName) -> {
            if (!FxDiaCrashStore.isCaptureEnabled(app)) {
                // Breakpad's native signal handler cannot be unregistered in this process.
                // Discard only this callback's newly emitted dump while capture is disabled.
                if (!FxDiaCrashDumpDirectory.deleteDirectDump(app.getFilesDir(), minidumpPath)) {
                    android.util.Log.w("FXDiaNativeCrash",
                            "capture disabled; refusing unsafe minidump deletion: "
                                    + (minidumpPath == null ? "(null)" : minidumpPath));
                }
                return;
            }
            FxDiaCrashStore.recordNativeCrash(app, minidumpPath, nativeInfo,
                    nativeThreadTrack, crashThreadName, findJvmThreadStack(crashThreadName));
            pruneOldMinidumps(app.getFilesDir());
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

    /** Clear only direct regular files under the app-private minidump directory. */
    public static boolean clearMinidumps(Context context) {
        if (context == null) return false;
        return FxDiaCrashDumpDirectory.clear(context.getFilesDir());
    }

    private static boolean pruneOldMinidumps(File filesRoot) {
        boolean pruned = FxDiaCrashDumpDirectory.prune(filesRoot, 5,
                30L * 24L * 60L * 60L * 1000L, System.currentTimeMillis());
        if (!pruned) {
            android.util.Log.w("FXDiaNativeCrash",
                    "minidump retention skipped: output path contains an unsafe entry or is unavailable");
        }
        return pruned;
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
