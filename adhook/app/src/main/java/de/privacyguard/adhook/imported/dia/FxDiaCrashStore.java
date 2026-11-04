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

    public static boolean isCaptureEnabled(Context context) {
        SharedPreferences p = prefs(context);
        return p.getBoolean("capture_enabled", true)
                && !p.getBoolean("disable_java_crash_capture", false);
    }

    public static void setCaptureEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean("capture_enabled", enabled).commit();
        if (enabled && context.getApplicationContext() instanceof Application) {
            install((Application) context.getApplicationContext());
        }
    }

    public static boolean hasPendingReport(Context context) {
        return prefs(context).getBoolean("has_crash", false);
    }

    public static void clearPendingFlag(Context context) {
        prefs(context).edit().putBoolean("has_crash", false).commit();
    }

    public static FxDiaCrashRecord read(Context context) {
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
            if (json.optInt("schemaVersion", -1) != SCHEMA_VERSION) return null;
            return new FxDiaCrashRecord(
                    json.optLong("timestampMs", 0L), json.optLong("threadId", 0L),
                    json.optString("processName", ""), json.optString("threadName", ""),
                    json.optString("deviceInfo", ""), json.optString("message", ""),
                    json.optString("stack", ""));
        } catch (IOException | JSONException | RuntimeException invalid) {
            return null;
        }
    }

    public static void clear(Context context) {
        crashFile(context).delete();
        prefs(context).edit().putBoolean("has_crash", false).remove("crash_timestamp").commit();
    }

    @Override public void uncaughtException(Thread thread, Throwable error) {
        try {
            if (error != null && isCaptureEnabled(app) && HANDLING.compareAndSet(false, true)) {
                FxDiaCrashRecord record = capture(thread, error);
                write(record);
                prefs(app).edit().putBoolean("has_crash", true)
                        .putLong("crash_timestamp", record.timestampMs).commit();
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
        AtomicFile file = crashFile(app);
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
