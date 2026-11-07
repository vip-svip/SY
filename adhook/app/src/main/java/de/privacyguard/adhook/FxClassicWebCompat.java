package de.privacyguard.adhook;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.webkit.WebViewAssetLoader;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Collections;

/**
 * Visible ClassicWebCompat renderer. It hosts only the app-owned legacy page;
 * the native Compose shell continues to own the six persistent FX tabs.
 * Hook and Settings remain native destinations so the global mode selector
 * and the unified Hook manager are always reachable.
 */
public final class FxClassicWebCompat {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String ORIGIN = "https://" + HOST;
    private static final String ENTRY = ORIGIN + "/assets/webroot/index.html";

    private static final String COMPAT_SHIM =
            "(function(){'use strict';"
            + "var fx=window.FXRoot;if(!fx)return;var seq=0;"
            + "function toResult(errno,stdout,stderr){return {errno:errno,stdout:String(stdout==null?'':stdout),stderr:String(stderr==null?'':stderr)}}"
            + "var bridge={"
            + "exec:function(command,options,callbackName){"
            + "var cmd=String(command==null?'':command);"
            + "if(typeof callbackName==='string'&&callbackName.length){fx.exec(cmd,callbackName);return null;}"
            + "var name='__fxPromise_'+String(Date.now())+String(++seq);"
            + "return new Promise(function(resolve){var settled=false;var timer=setTimeout(function(){finish(-1,'','FX Root bridge timeout')},120000);"
            + "function finish(errno,stdout,stderr){if(settled)return;settled=true;clearTimeout(timer);try{delete window[name]}catch(e){}resolve(toResult(errno,stdout,stderr));}"
            + "window[name]=finish;try{fx.exec(cmd,name)}catch(e){finish(-1,'',String(e&&e.message||e))}"
            + "});},"
            + "saveBase64:function(filename,encoded,mimeType){fx.saveBase64(String(filename||'FX-export.txt'),String(encoded||''),String(mimeType||'application/octet-stream'))},"
            + "openHookManager:function(){fx.openHookManager()},"
            + "fullScreen:function(){},enableEdgeToEdge:function(){}"
            + "};window.ksu=bridge;window.KernelSU=bridge;"
            + "var root=document.documentElement;if(root){var style=document.createElement('style');style.id='fx-classic-native-shell';"
            + "style.textContent='html,body{height:100%!important;overflow:hidden!important}.phone{height:100%!important;min-height:0!important}.phone>.navbar{display:none!important}.phone>.screen{padding-bottom:0!important}';root.appendChild(style);}"
            + "})();";

    private final Activity activity;
    private final FrameLayout root;
    private final WebView webView;
    private RootBridge bridge;
    private final TextView errorView;

    public FxClassicWebCompat(Activity activity, int selectedIndex) {
        if (activity == null) throw new IllegalArgumentException("Activity is required");
        this.activity = activity;
        root = new FrameLayout(activity);
        root.setTag("fx-classic-webcompat-host");
        root.setBackgroundColor(Color.rgb(244, 246, 248));

        webView = new WebView(activity);
        webView.setBackgroundColor(Color.rgb(244, 246, 248));
        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        errorView = new TextView(activity);
        errorView.setTextColor(Color.rgb(80, 92, 108));
        errorView.setTextSize(15f);
        errorView.setGravity(Gravity.CENTER);
        errorView.setPadding(28, 28, 28, 28);
        errorView.setText("旧网页兼容界面暂不可用。请从底部“设置”进入界面模式，切换到默认、液态玻璃、Miuix、HarmonyStyle 或 CupertinoStyle。\n\n原因：本机 WebView 不支持安全的文档开始脚本，或 APK 未包含完整内置页面资源。");
        errorView.setVisibility(View.GONE);
        root.addView(errorView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        try (InputStream ignored = activity.getAssets().open("webroot/index.html")) {
            // The APK build stages this complete, app-owned page into assets/webroot.
        } catch (Exception missingAsset) {
            showError();
            return;
        }

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setLoadsImagesAutomatically(true);
        if (Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false);

        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .setDomain(HOST)
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(activity))
                .build();
        bridge = new RootBridge(activity, webView);
        webView.addJavascriptInterface(bridge, "FXRoot");
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            showError();
            return;
        }
        try {
            WebViewCompat.addDocumentStartJavaScript(
                    webView, COMPAT_SHIM, Collections.singleton(ORIGIN));
        } catch (RuntimeException unsupported) {
            showError();
            return;
        }

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request == null ? null : request.getUrl();
                if (!isTrustedAsset(uri)) return blockedResponse();
                WebResourceResponse response = loader.shouldInterceptRequest(uri);
                if (response != null && request != null && request.isForMainFrame()
                        && uri != null && "/assets/webroot/index.html".equals(uri.getPath())
                        && bridge != null) {
                    // Arm the bridge before the trusted HTML's app scripts execute.
                    bridge.setTrustedPage(true);
                }
                return response == null ? blockedResponse() : response;
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request == null ? null : request.getUrl();
                return !isTrustedAsset(uri);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                Uri uri = url == null ? null : Uri.parse(url);
                return !isTrustedAsset(uri);
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                if (bridge != null) bridge.setTrustedPage(false);
                super.onPageStarted(view, url, favicon);
            }

            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Uri uri = url == null ? null : Uri.parse(url);
                boolean trustedIndex = isTrustedAsset(uri)
                        && "/assets/webroot/index.html".equals(uri.getPath());
                if (bridge != null) bridge.setTrustedPage(trustedIndex);
                if (!trustedIndex) return;
                String tab = tabForIndex(selectedIndex);
                String js = "(function(){var b=document.querySelector('.nav-item[data-tab=\""
                        + tab + "\"]');if(b&&!b.classList.contains('on'))b.click();})();";
                view.evaluateJavascript(js, null);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (request != null && request.isForMainFrame()) showError();
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                                            WebResourceResponse response) {
                super.onReceivedHttpError(view, request, response);
                if (request != null && request.isForMainFrame()
                        && response != null && response.getStatusCode() >= 400) showError();
            }

            @Override
            public void onReceivedSslError(WebView view, android.webkit.SslErrorHandler handler,
                                           android.net.http.SslError error) {
                handler.cancel();
                showError();
            }
        });
        webView.loadUrl(ENTRY);
    }

    public View getView() { return root; }

    public void onResume() {
        if (webView != null) webView.onResume();
    }

    public void onPause() {
        if (webView != null) webView.onPause();
    }

    public void onDestroy() {
        if (bridge != null) {
            bridge.setTrustedPage(false);
            bridge.close();
        }
        webView.stopLoading();
        webView.removeJavascriptInterface("FXRoot");
        webView.setWebViewClient(new WebViewClient());
        webView.destroy();
    }

    private void showError() {
        if (activity.isFinishing() || activity.isDestroyed()) return;
        root.post(() -> {
            if (!activity.isFinishing() && !activity.isDestroyed()) errorView.setVisibility(View.VISIBLE);
        });
    }

    private static boolean isTrustedAsset(Uri uri) {
        return uri != null
                && "https".equalsIgnoreCase(uri.getScheme())
                && HOST.equalsIgnoreCase(uri.getHost())
                && uri.getPath() != null
                && uri.getPath().startsWith("/assets/");
    }

    private static WebResourceResponse blockedResponse() {
        return new WebResourceResponse("text/plain", "UTF-8",
                new ByteArrayInputStream(new byte[0]));
    }

    private static String tabForIndex(int index) {
        switch (index) {
            case 1: return "ad";
            case 2: return "privacy";
            case 3: return "script";
            default: return "vpn";
        }
    }
}
