package de.privacyguard.adhook;

import android.app.Activity;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONObject;

import java.util.regex.Pattern;

/** Narrow callback bridge for the bundled FX WebUI; never exposes a Java object model. */
public final class RootBridge {
    private static final Pattern CALLBACK = Pattern.compile(
            "(?:__pgExecCb_[0-9]+_[0-9]+|__pgProbeCb_[0-9]+_[0-9]+|__fxPromise_[0-9]+)");
    private final Activity activity;
    private final WebView webView;

    public RootBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }

    @JavascriptInterface
    public void exec(String command, String callbackName) {
        if (callbackName == null || !CALLBACK.matcher(callbackName).matches()) return;
        if (command == null || command.length() == 0 || command.length() > 65536) {
            deliver(callbackName, 2, "Root 命令为空或超过 64 KiB 限制", "");
            return;
        }
        new Thread(() -> {
            RootAccess.Result result = RootAccess.execute(command, 120000L, 1024 * 1024);
            deliver(callbackName, result.exitCode, result.output, "");
        }, "fx-web-root").start();
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
