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

import org.json.JSONObject;

import java.util.regex.Pattern;
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

    public RootBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }

    @JavascriptInterface
    public void exec(String command, String callbackName) {
        if (callbackName == null || !CALLBACK.matcher(callbackName).matches()) return;
        if (command == null || command.length() == 0 || command.length() > 131072) {
            deliver(callbackName, 2, "Root 命令为空或超过 128 KiB 限制", "");
            return;
        }
        try {
            ROOT_EXECUTOR.execute(() -> {
                RootAccess.Result result = RootAccess.execute(command, 110000L, 1024 * 1024);
                deliver(callbackName, result.exitCode, result.output, "");
            });
        } catch (RejectedExecutionException busy) {
            deliver(callbackName, 125, "Root 命令队列已满，请等待当前操作完成后重试", "");
        }
    }

    @JavascriptInterface
    public void saveBase64(String filename, String encoded, String mimeType) {
        try {
            if (encoded == null || encoded.length() > 14 * 1024 * 1024) {
                throw new IllegalArgumentException("导出内容超过 10 MiB 限制");
            }
            byte[] bytes = Base64.decode(encoded, Base64.DEFAULT);
            String safeName = filename == null ? "FX-export.txt"
                    : filename.replaceAll("[^A-Za-z0-9._-]", "_");
            if (safeName.length() == 0) safeName = "FX-export.txt";
            final String outputName = safeName;
            String type = mimeType == null || mimeType.length() == 0
                    ? "application/octet-stream" : mimeType;
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, safeName);
                values.put(MediaStore.MediaColumns.MIME_TYPE, type);
                values.put(MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/FX");
                values.put(MediaStore.MediaColumns.IS_PENDING, 1);
                Uri uri = activity.getContentResolver().insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (uri == null) throw new IllegalStateException("无法创建下载文件");
                try (java.io.OutputStream stream = activity.getContentResolver().openOutputStream(uri)) {
                    if (stream == null) throw new IllegalStateException("无法打开下载文件");
                    stream.write(bytes);
                }
                ContentValues ready = new ContentValues();
                ready.put(MediaStore.MediaColumns.IS_PENDING, 0);
                activity.getContentResolver().update(uri, ready, null, null);
            } else {
                File dir = new File(activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "FX");
                if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("无法创建导出目录");
                try (FileOutputStream stream = new FileOutputStream(new File(dir, safeName))) {
                    stream.write(bytes);
                }
            }
            activity.runOnUiThread(() -> Toast.makeText(activity,
                    "已导出到 Download/FX/" + outputName, Toast.LENGTH_LONG).show());
        } catch (Exception e) {
            activity.runOnUiThread(() -> Toast.makeText(activity,
                    "导出失败：" + e.getMessage(), Toast.LENGTH_LONG).show());
        }
    }

    @JavascriptInterface
    public void openHookManager() {
        activity.runOnUiThread(() -> {
            if (activity instanceof MainActivity) ((MainActivity) activity).showAppListFromBridge();
        });
    }

    private void deliver(String callbackName, int code, String stdout, String stderr) {
        String callback = JSONObject.quote(callbackName);
        String out = JSONObject.quote(stdout == null ? "" : stdout);
        String err = JSONObject.quote(stderr == null ? "" : stderr);
        String script = "(function(){var n=" + callback
                + ";var f=window[n];if(typeof f==='function'){try{f("
                + code + "," + out + "," + err + ")}finally{try{delete window[n]}catch(e){}}}})();";
        webView.post(() -> webView.evaluateJavascript(script, null));
    }
}
