package de.privacyguard.adhook;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.ConsoleMessage;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.webkit.WebViewAssetLoader;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * ClassicWebCompat is a page-level legacy renderer, not an application wrapper.
 * The old bundled WebUI renders VPN/Ad/Privacy/Scripts pages only; FX keeps its
 * native Hook and Settings destinations plus the shared six-tab navigation host.
 */
public final class FxClassicWebCompatActivity extends FxNativeTabActivity {
    static final String EXTRA_TAB_INDEX = "fx_classic_web_tab_index";
    private static final int REQUEST_PICK_FILE = 0x6f62;
    private static final String ASSET_HOST = "appassets.androidplatform.net";
    private static final String ASSET_URL = "https://" + ASSET_HOST + "/assets/webroot/index.html";
    private static final String[] TAB_IDS = {"vpn", "ad", "privacy", "script"};

    private WebView webView;
    private RootBridge rootBridge;
    private ValueCallback<Uri[]> pendingFileChooser;
    private WebViewAssetLoader assetLoader;
    private int selectedTab;
    private boolean pageReady;
    private boolean mainPageLoadFailed;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        selectedTab = clampTab(getIntent() == null ? 0
                : getIntent().getIntExtra(EXTRA_TAB_INDEX, 0));

        webView = new WebView(this);
        webView.setBackgroundColor(0xfff4f6f8);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(false);
        settings.setAllowFileAccess(false);
        // SAF-selected content:// URIs are delivered only through the user-initiated WebChromeClient file chooser.
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setSupportZoom(false);

        assetLoader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        rootBridge = new RootBridge(this, webView);
        webView.addJavascriptInterface(rootBridge, "FXRoot");
        webView.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(
                    WebView view, WebResourceRequest request) {
                Uri uri = request == null ? null : request.getUrl();
                if (isMainHtml(uri)) {
                    WebResourceResponse document = buildClassicHtmlResponse();
                    // Arm only for the exact trusted top-level index request,
                    // before its inline bootstrap and app scripts can call Root.
                    if (request != null && request.isForMainFrame() && rootBridge != null) {
                        rootBridge.setTrustedPage(true);
                    }
                    return document;
                }
                if (isAssetOrigin(uri)) {
                    if (!isTrustedAsset(uri)) return blockedResponse();
                    WebResourceResponse local = assetLoader.shouldInterceptRequest(uri);
                    return local == null ? blockedResponse() : local;
                }
                // Keep fetch/XHR available for user-requested subscription and
                // connectivity operations; CSP blocks remote scripts and frames.
                return null;
            }

            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request == null ? null : request.getUrl();
                if (isTrustedAsset(uri)) return false;
                Toast.makeText(FxClassicWebCompatActivity.this,
                        "Classic 兼容页仅允许打开 FX 内置页面；外部链接未自动打开。",
                        Toast.LENGTH_SHORT).show();
                return true;
            }

            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                Uri uri = Uri.parse(url == null ? "" : url);
                return !isTrustedAsset(uri);
            }

            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                mainPageLoadFailed = false;
                if (rootBridge != null) rootBridge.setTrustedPage(false);
                pageReady = false;
                super.onPageStarted(view, url, favicon);
            }

            @Override public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Uri uri = url == null ? null : Uri.parse(url);
                boolean trustedIndex = isMainHtml(uri) && !mainPageLoadFailed;
                if (rootBridge != null) rootBridge.setTrustedPage(trustedIndex);
                if (!trustedIndex) return;
                pageReady = true;
                selectTab(selectedTab);
            }

            @Override public void onReceivedError(WebView view, WebResourceRequest request,
                                                  android.webkit.WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (request != null && request.isForMainFrame()) {
                    mainPageLoadFailed = true;
                    pageReady = false;
                    if (rootBridge != null) rootBridge.setTrustedPage(false);
                }
            }

            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request,
                                                       WebResourceResponse response) {
                super.onReceivedHttpError(view, request, response);
                if (request != null && request.isForMainFrame()
                        && response != null && response.getStatusCode() >= 400) {
                    mainPageLoadFailed = true;
                    pageReady = false;
                    if (rootBridge != null) rootBridge.setTrustedPage(false);
                }
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onShowFileChooser(WebView view,
                    ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
                if (pendingFileChooser != null) pendingFileChooser.onReceiveValue(null);
                pendingFileChooser = filePathCallback;
                try {
                    Intent picker = fileChooserParams.createIntent();
                    startActivityForResult(picker, REQUEST_PICK_FILE);
                    return true;
                } catch (Exception error) {
                    pendingFileChooser = null;
                    filePathCallback.onReceiveValue(null);
                    Toast.makeText(FxClassicWebCompatActivity.this,
                            "无法打开系统文件选择器：" + error.getMessage(),
                            Toast.LENGTH_LONG).show();
                    return false;
                }
            }

            @Override public boolean onConsoleMessage(ConsoleMessage message) {
                return true;
            }
        });

        setContentViewWithNativeTabs(webView, selectedTab);
        webView.loadUrl(ASSET_URL);
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent != null && intent.hasExtra(EXTRA_TAB_INDEX)) {
            selectTab(clampTab(intent.getIntExtra(EXTRA_TAB_INDEX, selectedTab)));
        }
    }

    /** Called by the shared router when the user switches between Classic pages. */
    public void selectTab(int index) {
        if (index < 0 || index >= TAB_IDS.length) return;
        selectedTab = index;
        if (pageReady && webView != null) {
            String tab = TAB_IDS[index];
            webView.evaluateJavascript(
                    "if(window.__FX_CLASSIC_SELECT_TAB){window.__FX_CLASSIC_SELECT_TAB('"
                            + tab + "');}", null);
        }
    }

    private static int clampTab(int index) {
        return index >= 0 && index < TAB_IDS.length ? index : 0;
    }

    private boolean isAssetOrigin(Uri uri) {
        if (uri == null || !"https".equalsIgnoreCase(uri.getScheme())
                || !ASSET_HOST.equalsIgnoreCase(uri.getHost())) return false;
        int port = uri.getPort();
        return port == -1 || port == 443;
    }

    private boolean isTrustedAsset(Uri uri) {
        String path = uri == null ? null : uri.getPath();
        return isAssetOrigin(uri) && path != null && path.startsWith("/assets/");
    }

    private boolean isMainHtml(Uri uri) {
        return isTrustedAsset(uri) && "/assets/webroot/index.html".equals(uri.getPath());
    }

    private static WebResourceResponse blockedResponse() {
        return new WebResourceResponse("text/plain", "UTF-8",
                new ByteArrayInputStream(new byte[0]));
    }

    private WebResourceResponse buildClassicHtmlResponse() {
        try (InputStream input = getAssets().open("webroot/index.html");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] chunk = new byte[16 * 1024];
            int count;
            while ((count = input.read(chunk)) != -1) output.write(chunk, 0, count);
            String html = new String(output.toByteArray(), StandardCharsets.UTF_8);
            int head = html.toLowerCase(java.util.Locale.ROOT).indexOf("<head");
            int end = head < 0 ? -1 : html.indexOf('>', head);
            if (end < 0) throw new IllegalStateException("Classic WebUI HTML has no head element");
            html = html.substring(0, end + 1) + classicBootstrap() + html.substring(end + 1);
            return new WebResourceResponse("text/html", "UTF-8",
                    new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            String message = "Classic WebUI 加载失败：" + error.getClass().getSimpleName();
            String html = "<!doctype html><meta charset=utf-8><title>FX</title><p>" + message + "</p>";
            return new WebResourceResponse("text/html", "UTF-8",
                    new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
        }
    }

    /** Inject before page scripts so the legacy WebUI detects the native Root bridge at startup. */
    private String classicBootstrap() {
        String csp = "default-src 'self' data: blob:; "
                + "script-src 'self' 'unsafe-inline'; "
                + "style-src 'self' 'unsafe-inline'; "
                + "img-src 'self' data: blob: http: https:; "
                + "font-src 'self' data:; connect-src 'self' http: https:; "
                + "frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'";
        String bridge = "(function(){'use strict';var seq=0;"
                + "function exec(command,options,callbackName){"
                + "if(typeof callbackName==='string'){window.FXRoot.exec(String(command||''),callbackName);return;}"
                + "return new Promise(function(resolve){var name='__fxPromise_'+String(++seq);"
                + "window[name]=function(errno,stdout,stderr){resolve({errno:Number(errno)||0,"
                + "stdout:String(stdout==null?'':stdout),stderr:String(stderr==null?'':stderr)});};"
                + "window.FXRoot.exec(String(command||''),name);});}"
                + "window.ksu={exec:exec,fullScreen:function(){},enableEdgeToEdge:function(){}};"
                + "window.KernelSU=window.ksu;"
                + "function saveBlob(blob,name){return blob.arrayBuffer().then(function(buffer){"
                + "var bytes=new Uint8Array(buffer),binary='';"
                + "for(var i=0;i<bytes.length;i+=32768){binary+=String.fromCharCode.apply(null,bytes.subarray(i,i+32768));}"
                + "window.FXRoot.saveBase64(name,btoa(binary),blob.type||'application/octet-stream');});}"
                + "window.showSaveFilePicker=window.showSaveFilePicker||function(options){"
                + "var name=(options&&options.suggestedName)||'FX-export.bin';"
                + "return Promise.resolve({createWritable:function(){var blob=null;"
                + "return Promise.resolve({write:function(value){blob=value instanceof Blob?value:new Blob([value]);return Promise.resolve();},"
                + "close:function(){return saveBlob(blob||new Blob([]),name);},"
                + "abort:function(){blob=null;return Promise.resolve();}});}});};"
                + "window.__FX_CLASSIC_SELECT_TAB=function(id){"
                + "var button=document.querySelector('.nav-item[data-tab=\"'+id+'\"]');"
                + "if(button&&!button.classList.contains('on'))button.click();};"
                + "})();";
        return "<meta http-equiv=\"Content-Security-Policy\" content=\"" + csp + "\">"
                + "<style>.navbar{display:none!important}</style>"
                + "<script>" + bridge + "</script>";
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_PICK_FILE) return;
        ValueCallback<Uri[]> callback = pendingFileChooser;
        pendingFileChooser = null;
        if (callback == null) return;
        callback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
    }

    @Override protected void onPause() {
        if (webView != null) webView.onPause();
        super.onPause();
    }

    @Override protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
    }

    @Override protected void onDestroy() {
        if (pendingFileChooser != null) {
            pendingFileChooser.onReceiveValue(null);
            pendingFileChooser = null;
        }
        if (rootBridge != null) {
            rootBridge.setTrustedPage(false);
            rootBridge.close();
        }
        if (webView != null) {
            webView.stopLoading();
            webView.removeJavascriptInterface("FXRoot");
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
