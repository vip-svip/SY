package de.privacyguard.adhook.imported.dia;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Process;
import android.util.AtomicFile;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/** FX-process-only uncaught Java crash capture with Android handler delegation. */
public final class FxDiaCrashStore implements Thread.UncaughtExceptionHandler {
    private static final String PREFS = "fx_dia_crash";
    private static final String FILE_NAME = "crash.log";
    private static final int SCHEMA_VERSION = 1;
    private static final int MAX_JSON_BYTES = 512 * 1024;
    private static final AtomicBoolean HANDLING = new AtomicBoolean(false);
    private static final AtomicBoolean NATIVE_HANDLING = new AtomicBoolean(false);
    /** Serializes AtomicFile reads, Java/Breakpad writes, pending flags and user clear. */
    private static final Object STORAGE_LOCK = new Object();
    private final Context app;
    private final Thread.UncaughtExceptionHandler delegate;

    private FxDiaCrashStore(Context context, Thread.UncaughtExceptionHandler previous) {
        app = context.getApplicationContext();
        delegate = previous;
    }

    public static synchronized void install(Application application) {
        if (application == null) return;
        Thread.UncaughtExceptionHandler current = Thread.getDefaultUncaughtExceptionHandler();
        if (current instanceof FxDiaCrashStore) return;
        Thread.setDefaultUncaughtExceptionHandler(new FxDiaCrashStore(application, current));
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static SharedPreferences legacyPrefs(Context context) {
        return context.getSharedPreferences("digXposed", Context.MODE_PRIVATE);
    }

    public static boolean isCaptureEnabled(Context context) {
        SharedPreferences p = prefs(context);
        SharedPreferences legacy = legacyPrefs(context);
        return FxDiaCrashCapturePolicy.isEnabled(
                p.getBoolean("capture_enabled", true),
                p.getBoolean("disable_java_crash_capture", false),
                legacy.getBoolean("disable_java_crash_capture", false));
    }

    public static boolean setCaptureEnabled(Context context, boolean enabled) {
        SharedPreferences current = prefs(context);
        if (!enabled) {
            return current.edit().putBoolean("capture_enabled", false).commit();
        }

        // Explicitly re-enabling in FX supersedes the original Dia opt-out.
        // Clear the legacy veto first; if that persistence fails, do not claim
        // that capture has been enabled.
        if (!legacyPrefs(context).edit()
                .remove("disable_java_crash_capture").commit()) {
            return false;
        }
        boolean saved = current.edit()
                .remove("disable_java_crash_capture")
                .putBoolean("capture_enabled", true)
                .commit();
        if (!saved) return false;

        if (context.getApplicationContext() instanceof Application) {
            Application application = (Application) context.getApplicationContext();
            install(application);
            FxDiaNativeCrashCapture.install(application);
        }
        return true;
    }

    public static boolean hasPendingReport(Context context) {
        return prefs(context).getBoolean("has_crash", false)
                || legacyPrefs(context).getBoolean("has_crash", false);
    }

    public static void clearPendingFlag(Context context) {
        prefs(context).edit().putBoolean("has_crash", false).commit();
        legacyPrefs(context).edit().putBoolean("has_crash", false).commit();
    }

    public static FxDiaCrashRecord read(Context context) {
        if (context == null) return null;
        synchronized (STORAGE_LOCK) {
            return readLocked(context);
        }
    }

    private static FxDiaCrashRecord readLocked(Context context) {
        AtomicFile file = crashFile(context);
        try (FileInputStream input = file.openRead();
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int total = 0;
            int count;
            while ((count = input.read(buffer)) != -1) {
                total += count;
                if (total > MAX_JSON_BYTES) return null;
                output.write(buffer, 0, count);
            }
            JSONObject json = new JSONObject(new String(output.toByteArray(), StandardCharsets.UTF_8));
            int schemaVersion = json.optInt("schemaVersion", 0);
            if (schemaVersion == SCHEMA_VERSION) {
                return new FxDiaCrashRecord(
                        json.optLong("timestampMs", file.getBaseFile().lastModified()),
                        json.optLong("threadId", 0L), json.optString("processName", ""),
                        json.optString("threadName", ""), json.optString("deviceInfo", ""),
                        json.optString("message", ""), json.optString("stack", ""));
            }
            // Dia 23.11 wrote an unversioned CrashInfo JSON object directly to crash.log.
            if (schemaVersion == 0 && json.has("processName") && json.has("threadName")
                    && json.has("stack")) {
                return new FxDiaCrashRecord(
                        file.getBaseFile().lastModified(), json.optLong("threadId", 0L),
                        json.optString("processName", ""), json.optString("threadName", ""),
                        json.optString("deviceInfo", ""), json.optString("message", ""),
                        json.optString("stack", ""));
            }
            return null;
        } catch (IOException | JSONException | RuntimeException invalid) {
            return null;
        }
    }

    /**
     * Clear crash metadata and native minidumps as one user-visible operation.
     * Preserve the crash record and pending flags when the dump path is unsafe.
     */
    public static boolean clear(Context context) {
        synchronized (STORAGE_LOCK) {
            if (context == null || !FxDiaNativeCrashCapture.clearMinidumps(context)) return false;

            crashFile(context).delete();
            File base = new File(context.getFilesDir(), FILE_NAME);
            File backup = new File(context.getFilesDir(), FILE_NAME + ".bak");
            File fresh = new File(context.getFilesDir(), FILE_NAME + ".new");
            if (base.exists() || backup.exists() || fresh.exists()) return false;

            boolean currentCleared = prefs(context).edit()
                    .putBoolean("has_crash", false).remove("crash_timestamp").commit();
            boolean legacyCleared = legacyPrefs(context).edit()
                    .putBoolean("has_crash", false).remove("crash_timestamp").commit();
            return currentCleared && legacyCleared;
        }
    }

    /** Persist original Dia Breakpad callback data in the same FX-private crash.log. */
    public static boolean recordNativeCrash(Context context, String minidumpPath,
                                            String nativeInfo, String nativeThreadTrack,
                                            String crashThreadName, String jvmThreadTrack) {
        if (context == null || !isCaptureEnabled(context)
                || !NATIVE_HANDLING.compareAndSet(false, true)) return false;
        Context target = context.getApplicationContext() != null
                ? context.getApplicationContext() : context;
        try {
            Thread callbackThread = Thread.currentThread();
            String processName = target.getPackageName();
            if (Build.VERSION.SDK_INT >= 28) {
                try {
                    String current = Application.getProcessName();
                    if (current != null && !current.trim().isEmpty()) processName = current;
                } catch (RuntimeException ignored) { }
            }
            String device = safe(Build.MANUFACTURER) + " " + safe(Build.MODEL)
                    + " · Android " + safe(Build.VERSION.RELEASE) + " (SDK " + Build.VERSION.SDK_INT + ")";
            String crashingThread = crashThreadName == null || crashThreadName.trim().isEmpty()
                    ? callbackThread.getName() : crashThreadName.trim();
            StringBuilder message = new StringBuilder("Native / Breakpad 崩溃");
            if (minidumpPath != null && !minidumpPath.trim().isEmpty()) {
                message.append("\nMinidump: ").append(minidumpPath);
            }
            if (nativeInfo != null && !nativeInfo.trim().isEmpty()) {
                message.append("\n").append(FxDiaCrashRecord.bounded(nativeInfo, 4096));
            }
            String stack = "Native thread trace:\n"
                    + FxDiaCrashRecord.bounded(nativeThreadTrack, 48 * 1024)
                    + "\nJVM thread snapshot:\n"
                    + FxDiaCrashRecord.bounded(jvmThreadTrack, 48 * 1024);
            FxDiaCrashRecord record = new FxDiaCrashRecord(
                    System.currentTimeMillis(), callbackThread.getId(), processName,
                    crashingThread, device, message.toString(), stack);
            synchronized (STORAGE_LOCK) {
                write(target, record);
                markPending(target, record.timestampMs);
            }
            return true;
        } catch (Throwable ignored) {
            return false;
        } finally {
            NATIVE_HANDLING.set(false);
        }
    }

    private static void markPending(Context context, long timestampMs) {
        prefs(context).edit().putBoolean("has_crash", true)
                .putLong("crash_timestamp", timestampMs).commit();
        legacyPrefs(context).edit().putBoolean("has_crash", true)
                .putLong("crash_timestamp", timestampMs).commit();
    }

    @Override public void uncaughtException(Thread thread, Throwable error) {
        try {
            if (error != null && isCaptureEnabled(app) && HANDLING.compareAndSet(false, true)) {
                FxDiaCrashRecord record = capture(thread, error);
                synchronized (STORAGE_LOCK) {
                    write(app, record);
                    markPending(app, record.timestampMs);
                }
            }
        } catch (Throwable ignored) {
            // Reporting failure must never replace the original fatal exception.
        }

        if (delegate != null && delegate != this) {
            delegate.uncaughtException(thread, error);
        } else {
            Process.killProcess(Process.myPid());
            System.exit(10);
        }
    }

    private FxDiaCrashRecord capture(Thread thread, Throwable error) {
        String processName = app.getPackageName();
        if (Build.VERSION.SDK_INT >= 28) {
            try {
                String current = Application.getProcessName();
                if (current != null && !current.trim().isEmpty()) processName = current;
            } catch (RuntimeException ignored) { }
        }
        String device = safe(Build.MANUFACTURER) + " " + safe(Build.MODEL)
                + " · Android " + safe(Build.VERSION.RELEASE) + " (SDK " + Build.VERSION.SDK_INT + ")";
        String message = error.getMessage();
        if (message == null || message.trim().isEmpty()) message = error.getClass().getName();
        long threadId = thread == null ? 0L : thread.getId();
        String threadName = thread == null ? "unknown" : thread.getName();
        return new FxDiaCrashRecord(System.currentTimeMillis(), threadId,
                processName, threadName, device, message, FxDiaCrashRecord.stackTrace(error));
    }

    private void write(FxDiaCrashRecord record) throws IOException {
        write(app, record);
    }

    private static void write(Context context, FxDiaCrashRecord record) throws IOException {
        JSONObject json = new JSONObject();
        try {
            json.put("schemaVersion", SCHEMA_VERSION);
            json.put("timestampMs", record.timestampMs);
            json.put("threadId", record.threadId);
            json.put("processName", record.processName);
            json.put("threadName", record.threadName);
            json.put("deviceInfo", record.deviceInfo);
            json.put("message", record.message);
            json.put("stack", record.stack);
        } catch (JSONException impossible) {
            throw new IOException("Unable to serialize crash report", impossible);
        }
        AtomicFile file = crashFile(context);
        FileOutputStream output = null;
        try {
            output = file.startWrite();
            byte[] bytes = json.toString().getBytes(StandardCharsets.UTF_8);
            if (bytes.length > MAX_JSON_BYTES) throw new IOException("Crash report exceeds size limit");
            output.write(bytes);
            output.flush();
            output.getFD().sync();
            file.finishWrite(output);
            output = null;
        } finally {
            if (output != null) file.failWrite(output);
        }
    }

    private static AtomicFile crashFile(Context context) {
        return new AtomicFile(new File(context.getFilesDir(), FILE_NAME));
    }

    private static String safe(String value) {
        return value == null || value.trim().isEmpty() ? "unknown" : value.trim();
    }
}
