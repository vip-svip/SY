package de.privacyguard.adhook;

import android.app.Activity;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.content.ContentValues;
import android.net.Uri;
import android.widget.Toast;
import android.util.Base64;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

import org.json.JSONObject;

import java.util.regex.Pattern;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.FutureTask;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Narrow callback bridge for the bundled FX WebUI; never exposes a Java object model. */
public final class RootBridge {
    private static final Pattern CALLBACK = Pattern.compile(
            "(?:__pgExecCb_[0-9]+_[0-9]+|__pgProbeCb_[0-9]+_[0-9]+|__fxPromise_[0-9]+)");
    // Bound concurrent root shells: a burst of WebUI callbacks must not create
    // an unbounded number of privileged processes/threads.
    private static final ThreadPoolExecutor ROOT_EXECUTOR = new ThreadPoolExecutor(
            2, 2, 0L, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(8), runnable -> {
                Thread thread = new Thread(runnable, "fx-web-root");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    private final Activity activity;
    private final WebView webView;
    private volatile boolean closed;
    private final Object taskLock = new Object();
    private final Set<FutureTask<Void>> activeRootTasks = ConcurrentHashMap.newKeySet();

    private final class TrackedRootTask extends FutureTask<Void> {
        TrackedRootTask(String command, String callbackName) {
            super(() -> {
                if (closed || Thread.currentThread().isInterrupted()) return null;
                RootAccess.Result result = RootAccess.execute(command, 110000L, 1024 * 1024);
                deliver(callbackName, result.exitCode, result.output, "");
                return null;
            });
        }

        @Override protected void done() {
            activeRootTasks.remove(this);
        }
    }

    public RootBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }

    public void close() {
        synchronized (taskLock) {
            if (closed) return;
            closed = true;
            for (FutureTask<Void> task : activeRootTasks) task.cancel(true);
            activeRootTasks.clear();
        }
    }

    @JavascriptInterface
    public void exec(String command, String callbackName) {
        if (closed) return;
        if (callbackName == null || !CALLBACK.matcher(callbackName).matches()) return;
        if (command == null || command.length() == 0 || command.length() > 131072) {
            deliver(callbackName, 2, "Root 命令为空或超过 128 KiB 限制", "");
            return;
        }
        TrackedRootTask task = new TrackedRootTask(command, callbackName);
        try {
            synchronized (taskLock) {
                if (closed) return;
                activeRootTasks.add(task);
                ROOT_EXECUTOR.execute(task);
            }
        } catch (RejectedExecutionException busy) {
            activeRootTasks.remove(task);
            deliver(callbackName, 125, "Root 命令队列已满，请等待当前操作完成后重试", "");
        }
    }

    @JavascriptInterface
    public void saveBase64(String filename, String encoded, String mimeType) {
        if (closed || activity.isFinishing()
                || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
        Uri createdUri = null;
        File createdFile = null;
        try {
            if (encoded == null || encoded.length() > 14 * 1024 * 1024) {
                throw new IllegalArgumentException("导出内容超过 10 MiB 限制");
            }
            byte[] bytes = Base64.decode(encoded, Base64.DEFAULT);
            if (bytes.length > 10 * 1024 * 1024) {
                throw new IllegalArgumentException("导出内容超过 10 MiB 限制");
            }
            if (closed || activity.isFinishing()
                    || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
            String safeName = filename == null ? "FX-export.txt"
                    : filename.replaceAll("[^A-Za-z0-9._-]", "_");
            if (safeName.length() == 0 || ".".equals(safeName) || "..".equals(safeName)) {
                safeName = "FX-export.txt";
            }
            String outputName = safeName;
            String type = mimeType == null || mimeType.length() == 0
                    ? "application/octet-stream" : mimeType;
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, safeName);
                values.put(MediaStore.MediaColumns.MIME_TYPE, type);
                values.put(MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/FX");
                values.put(MediaStore.MediaColumns.IS_PENDING, 1);
                createdUri = activity.getContentResolver().insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (createdUri == null) throw new IllegalStateException("无法创建下载文件");
                try (java.io.OutputStream stream = activity.getContentResolver().openOutputStream(createdUri)) {
                    if (stream == null) throw new IllegalStateException("无法打开下载文件");
                    stream.write(bytes);
                    stream.flush();
                }
                if (closed || activity.isFinishing()
                        || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) {
                    activity.getContentResolver().delete(createdUri, null, null);
                    return;
                }
                ContentValues ready = new ContentValues();
                ready.put(MediaStore.MediaColumns.IS_PENDING, 0);
                if (activity.getContentResolver().update(createdUri, ready, null, null) <= 0) {
                    throw new IllegalStateException("无法完成下载文件发布");
                }
            } else {
                File external = activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                if (external == null) throw new IllegalStateException("外部下载目录不可用");
                File dir = new File(external, "FX");
                if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("无法创建导出目录");
                // Never truncate an earlier export when the user exports the same
                // filename again on Android versions without scoped MediaStore writes.
                createdFile = createUniqueFile(dir, safeName);
                outputName = createdFile.getName();
                try (FileOutputStream stream = new FileOutputStream(createdFile)) {
                    stream.write(bytes);
                    stream.flush();
                }
            }
            if (closed || activity.isFinishing()
                    || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
            final String toastName = outputName;
            activity.runOnUiThread(() -> {
                if (!closed && !activity.isFinishing()
                        && (Build.VERSION.SDK_INT < 17 || !activity.isDestroyed())) {
                    Toast.makeText(activity,
                            "已导出到 Download/FX/" + toastName, Toast.LENGTH_LONG).show();
                }
            });
        } catch (Exception e) {
            if (createdUri != null) {
                try { activity.getContentResolver().delete(createdUri, null, null); }
                catch (Exception ignored) { }
            }
            if (createdFile != null && createdFile.exists()) {
                // Remove an incomplete export after a failed write.
                //noinspection ResultOfMethodCallIgnored
                createdFile.delete();
            }
            if (!closed && !activity.isFinishing()
                    && (Build.VERSION.SDK_INT < 17 || !activity.isDestroyed())) {
                final String message = e.getMessage();
                activity.runOnUiThread(() -> {
                    if (!closed && !activity.isFinishing()
                            && (Build.VERSION.SDK_INT < 17 || !activity.isDestroyed())) {
                        Toast.makeText(activity, "导出失败：" + message, Toast.LENGTH_LONG).show();
                    }
                });
            }
        }
    }

    private static File createUniqueFile(File directory, String requestedName) throws IOException {
        int dot = requestedName.lastIndexOf('.');
        String stem = dot > 0 ? requestedName.substring(0, dot) : requestedName;
        String extension = dot > 0 ? requestedName.substring(dot) : "";
        for (int suffix = 0; suffix < 1000; suffix++) {
            String candidate = suffix == 0 ? requestedName
                    : stem + " (" + suffix + ")" + extension;
            File output = new File(directory, candidate);
            if (output.createNewFile()) return output;
            if (!output.exists()) throw new IOException("无法创建导出文件：" + candidate);
        }
        throw new IOException("同名导出文件过多，无法安全创建新文件");
    }

    @JavascriptInterface
    public void openHookManager() {
        if (closed || activity.isFinishing()
                || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
        activity.runOnUiThread(() -> {
            // A bridge call may already be queued when Activity teardown begins.
            // Re-check lifecycle state on the UI thread before touching its views.
            if (!closed && !activity.isFinishing()
                    && (Build.VERSION.SDK_INT < 17 || !activity.isDestroyed())
                    && activity instanceof MainActivity) {
                ((MainActivity) activity).showAppListFromBridge();
            }
        });
    }

    private void deliver(String callbackName, int code, String stdout, String stderr) {
        if (closed || activity.isFinishing()
                || (Build.VERSION.SDK_INT >= 17 && activity.isDestroyed())) return;
        String callback = JSONObject.quote(callbackName);
        String out = JSONObject.quote(stdout == null ? "" : stdout);
        String err = JSONObject.quote(stderr == null ? "" : stderr);
        String script = "(function(){var n=" + callback
                + ";var f=window[n];if(typeof f==='function'){try{f("
                + code + "," + out + "," + err + ")}finally{try{delete window[n]}catch(e){}}}})();";
        webView.post(() -> {
            if (!closed && !activity.isFinishing()
                    && (Build.VERSION.SDK_INT < 17 || !activity.isDestroyed())) {
                webView.evaluateJavascript(script, null);
            }
        });
    }
}
