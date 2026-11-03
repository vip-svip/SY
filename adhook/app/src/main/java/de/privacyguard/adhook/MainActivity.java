package de.privacyguard.adhook;

import androidx.activity.ComponentActivity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebChromeClient;
import android.webkit.ValueCallback;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.WebView;
import androidx.webkit.WebViewAssetLoader;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.*;
import android.util.Base64;
import org.json.JSONObject;
import org.json.JSONArray;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Unified FX APP shell: bundled full management UI plus native per-app Hook manager. */
public final class MainActivity extends ComponentActivity {
    private LinearLayout root;
    private EditText search;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final List<ApplicationInfo> filtered = new ArrayList<>();
    // Cache labels/icons once; search must not repeatedly query PackageManager.
    private final Map<String, String> appLabels = new HashMap<>();
    // Keep the icon cache bounded: users may page through hundreds of installed apps.
    private final Map<String, Drawable> appIcons = new LinkedHashMap<String, Drawable>(80, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, Drawable> eldest) {
            return size() > 80;
        }
    };
    // Visible rows use placeholders while PackageManager decodes icons off the UI thread.
    private final Map<String, ImageView> appIconViews = new HashMap<>();
    private volatile Thread appIconLoaderThread;
    private int appIconLoadGeneration;
    private static final int MAX_APP_ROWS_PER_PAGE = 40;
    private String selectedPackage;
    private String selectedLabel;
    private WebView webView;
    private RootBridge rootBridge;
    private TextView rootStatus;
    private LinearLayout nativeVpnControls;
    private ScrollView nativePageScroll;
    private LinearLayout nativePageContent;
    private LinearLayout nativeScriptRows;
    private TextView nativeScriptStatus;
    private TextView nativeDashboardStatus;
    private Switch nativeVpnSwitch;
    private TextView nativeVpnState;
    private Button nativeVpnNodeButton;
    private final List<Button> nativeVpnModeButtons = new ArrayList<>();
    private LinearLayout nativeVpnSubRows;
    private TextView nativeVpnSubStatus;
    private int nativeVpnSubOperationGeneration;
    private AlertDialog nativeCertificateDialog;
    private boolean syncingNativeVpn;
    private boolean nativeVpnOperationBusy;
    private String lastNativeVpnMode = "direct";
    private final AtomicBoolean nativeVpnStatusQueued = new AtomicBoolean(false);
    private final Handler nativeVpnHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService nativeVpnExecutor = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "fx-native-vpn");
        thread.setDaemon(true);
        return thread;
    });
    private final Runnable nativeVpnPoll = new Runnable() {
        @Override public void run() {
            if (isFinishing() || hookUiVisible || settingsUiVisible || lastWebTabIndex != 0 || webView == null || !webUiReady) return;
            syncNativeVpnControls();
            nativeVpnHandler.postDelayed(this, 5000L);
        }
    };
    private boolean hookUiVisible;
    private boolean hookTargetVisible;
    private boolean hookHubVisible;
    private boolean settingsUiVisible;
    private String uiMode = "classic";
    private int selectedBottomTab = 0;
    private int lastWebTabIndex = 0;
    private boolean webViewLoaded;
    private boolean webUiReady;
    private String pendingWebPage;
    private String pendingRestorePackage;
    private ValueCallback<Uri[]> fileChooserCallback;
    private volatile Thread hookPublisherThread;
    private volatile Thread hookStatusThread;
    private int hookStatusGeneration;
    private volatile Thread appLoaderThread;
    private int appLoadGeneration;
    private boolean appsLoaded;
    private static final int REQUEST_FILE_PICKER = 4101;
    private static final int REQUEST_NATIVE_SCRIPT_FILE = 4102;
    private static final int REQUEST_NATIVE_SCRIPT_EXPORT = 4103;
    private String pendingNativeScriptExport;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        uiMode = normalizeUiMode(getSharedPreferences("fx_ui", MODE_PRIVATE)
                .getString("mode", "classic"));
        boolean restoreHookScreen = false;
        boolean restoreSettingsScreen = false;
        String restoreHookKind = "";
        if (state != null) {
            lastWebTabIndex = Math.max(0, Math.min(5,
                    state.getInt("fx_last_web_tab", 0)));
            selectedBottomTab = Math.max(0, Math.min(5,
                    state.getInt("fx_selected_bottom_tab", lastWebTabIndex)));
            pendingWebPage = webPageForBottomTab(lastWebTabIndex);
            restoreHookScreen = state.getBoolean("fx_hook_screen_visible", selectedBottomTab == 4);
            activePrivacySection = state.getString("fx_privacy_section");
            restoreSettingsScreen = state.getBoolean("fx_settings_screen", false);
            restoreHookKind = state.getString("fx_hook_screen", "list");
            if ("target".equals(restoreHookKind)) {
                pendingRestorePackage = state.getString("fx_selected_package");
            }
        }
        if (restoreHookScreen) {
            if ("hub".equals(restoreHookKind)) showHookHub();
            else showAppList(activePrivacySection);
        } else if (restoreSettingsScreen) {
            showSettings();
        } else {
            showDashboard();
        }
    }

    @Override protected void onResume() {
        super.onResume();
        if (webView != null && !hookUiVisible) {
            webView.onResume();
            webView.resumeTimers();
        }
        if (!hookUiVisible && !settingsUiVisible) startNativeVpnPolling();
    }

    @Override protected void onPause() {
        stopNativeVpnPolling();
        if (webView != null) {
            webView.onPause();
            webView.pauseTimers();
        }
        super.onPause();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putInt("fx_last_web_tab", lastWebTabIndex);
        outState.putInt("fx_selected_bottom_tab", selectedBottomTab);
        outState.putBoolean("fx_settings_screen", settingsUiVisible);
        outState.putBoolean("fx_hook_screen_visible", hookUiVisible);
        if (hookUiVisible) {
            if (activePrivacySection != null) outState.putString("fx_privacy_section", activePrivacySection);
            boolean restoringTarget = hookTargetVisible || pendingRestorePackage != null;
            String hookScreen = hookHubVisible ? "hub" : restoringTarget ? "target" : "list";
            outState.putString("fx_hook_screen", hookScreen);
            String targetPackage = pendingRestorePackage != null
                    ? pendingRestorePackage : selectedPackage;
            if ("target".equals(hookScreen) && targetPackage != null) {
                outState.putString("fx_selected_package", targetPackage);
            }
        }
        super.onSaveInstanceState(outState);
    }

    private static boolean isTrustedAssetUrl(Uri uri) {
        return uri != null
                && "https".equalsIgnoreCase(uri.getScheme())
                && "appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())
                && uri.getPort() == -1
                && uri.getUserInfo() == null
                && uri.getPath() != null
                && uri.getPath().startsWith("/assets/");
    }

    private static boolean isTrustedDocumentUrl(Uri uri) {
        return isTrustedAssetUrl(uri)
                && "/assets/webroot/index.html".equals(uri.getPath());
    }

    private String webPageForBottomTab(int index) {
        switch (index) {
            case 1: return "pageHosts";
            case 2: return "pagePrivacy";
            case 3: return "pageScript";
            case 5: return "pageMore";
            default: return "pageVpn";
        }
    }

    private void showDashboard() { showWebDashboard(); }

    private void showWebDashboard() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        settingsUiVisible = false;
        // A restored target is only valid while the app-list restoration is still active.
        pendingRestorePackage = null;
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        selectedBottomTab = lastWebTabIndex;
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff4f6f8);

        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(14), dp(6), dp(10), dp(6));
        toolbar.setBackgroundColor(0xff101820);
        TextView brand = new TextView(this);
        brand.setText("FX");
        brand.setTextSize(20);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setTextColor(0xffffffff);
        toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
        rootStatus = new TextView(this);
        rootStatus.setText("Root 检查中");
        rootStatus.setTextSize(10);
        rootStatus.setMaxLines(2);
        rootStatus.setEllipsize(android.text.TextUtils.TruncateAt.END);
        rootStatus.setTextColor(0xffd8e0e8);
        rootStatus.setPadding(dp(8), dp(8), dp(8), dp(8));
        rootStatus.setMaxWidth(dp(132));
        rootStatus.setGravity(Gravity.CENTER_VERTICAL | Gravity.END);
        rootStatus.setOnClickListener(v -> checkRoot(rootStatus, true));
        toolbar.addView(rootStatus, new LinearLayout.LayoutParams(dp(132), -2));
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));
        if (webView == null) {
        webUiReady = false;
        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true); // only user-selected content:// URIs are exposed by the native picker
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setSafeBrowsingEnabled(true);

        WebViewAssetLoader.AssetsPathHandler fallback =
                new WebViewAssetLoader.AssetsPathHandler(MainActivity.this);
        WebViewAssetLoader.PathHandler handler = assetPath -> {
            if ("webroot/index.html".equals(assetPath)) {
                try (InputStream in = getAssets().open(assetPath);
                     ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[8192];
                    int n;
                    while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
                    String html = new String(out.toByteArray(), StandardCharsets.UTF_8);
                    String shim = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'\">"
                        + "<script>(function(){var seq=0;window.ksu={exec:function(cmd,opts,cb){if(typeof cb==='string'){FXRoot.exec(String(cmd),cb);return null;}return new Promise(function(resolve){var n='__fxPromise_'+(++seq);window[n]=function(errno,stdout,stderr){resolve({errno:errno,stdout:stdout,stderr:stderr});};FXRoot.exec(String(cmd),n);});},fullScreen:function(){},enableEdgeToEdge:function(){}};window.KernelSU=window.ksu;window.FXNative={openHookManager:function(){FXRoot.openHookManager();}};window.showSaveFilePicker=async function(opts){var name=(opts&&opts.suggestedName)||'FX-export.txt';return {createWritable:async function(){var value='';return {write:async function(v){value=v;},close:async function(){var blob=value instanceof Blob?value:new Blob([value],{type:'text/plain;charset=utf-8'});var reader=new FileReader();reader.onloadend=function(){var data=String(reader.result||'').split(',').pop();FXRoot.saveBase64(name,data,blob.type||'text/plain');};reader.readAsDataURL(blob);}};}};};})();</script>";
                    int headEnd = html.toLowerCase().lastIndexOf("</head>");
                    if (headEnd >= 0) html = html.substring(0, headEnd)
                            + "<style id='fx-native-nav-hide'>"
                            + "#screen>.navbar,#screen .navbar,#bottomNav,#bottom-nav,.bottom-nav,"
                            + ".bottom-navbar,.bottom-tabs,.bottom-tab-bar,.tab-bar,.tabbar,"
                            + ".nav-bottom,.navigation-bottom{display:none!important}"
                            + "#screen{padding-bottom:0!important;margin-bottom:0!important}"
                            + "#vpnStatusCard .vpn-toggle-wrap,#vpnModeSeg{display:none!important}"
                            + "</style>"
                            + shim + html.substring(headEnd);
                    return new WebResourceResponse("text/html", "UTF-8",
                            new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
                } catch (Exception e) {
                    return new WebResourceResponse("text/plain", "UTF-8",
                            new ByteArrayInputStream(("FX UI asset error: " + e).getBytes(StandardCharsets.UTF_8)));
                }
            }
            return fallback.handle(assetPath);
        };
        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", handler).build();
        rootBridge = new RootBridge(this, webView);
        webView.addJavascriptInterface(rootBridge, "FXRoot");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, JsPromptResult result) {
                EditText input = new EditText(MainActivity.this);
                input.setText(defaultValue);
                new AlertDialog.Builder(MainActivity.this).setMessage(message).setView(input)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm(input.getText().toString()))
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                ValueCallback<Uri[]> previous = fileChooserCallback;
                fileChooserCallback = null;
                deliverFileChooserResult(previous, null);
                fileChooserCallback = callback;
                try {
                    Intent intent = params.createIntent();
                    startActivityForResult(intent, REQUEST_FILE_PICKER);
                    return true;
                } catch (Exception e) {
                    // WebView requires every accepted file-chooser callback to be completed,
                    // including the failure path; otherwise the page can remain stuck waiting.
                    ValueCallback<Uri[]> pending = fileChooserCallback;
                    fileChooserCallback = null;
                    deliverFileChooserResult(pending, null);
                    Toast.makeText(MainActivity.this, "无法打开文件选择器：" + e.getMessage(),
                            Toast.LENGTH_LONG).show();
                    return true;
                }
            }
        });
        webView.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String scheme = uri.getScheme();
                if ("data".equalsIgnoreCase(scheme) || "blob".equalsIgnoreCase(scheme)) return null;
                if (!isTrustedAssetUrl(uri)) {
                    return new WebResourceResponse("text/plain", "UTF-8",
                            new ByteArrayInputStream(new byte[0]));
                }
                return loader.shouldInterceptRequest(uri);
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                // addJavascriptInterface is visible to every frame. Refuse iframe and
                // off-origin document navigations so only the packaged UI can reach RootBridge.
                return !request.isForMainFrame() || !isTrustedDocumentUrl(request.getUrl());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return !isTrustedDocumentUrl(Uri.parse(url));
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request,
                    WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (request.isForMainFrame()) {
                    webUiReady = false;
                    webViewLoaded = false;
                    pendingWebPage = webPageForBottomTab(lastWebTabIndex);
                    Toast.makeText(MainActivity.this,
                            "FX 页面加载失败，点击底部任一标签可重试。",
                            Toast.LENGTH_LONG).show();
                }
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request,
                    WebResourceResponse response) {
                super.onReceivedHttpError(view, request, response);
                if (request.isForMainFrame() && response.getStatusCode() >= 400) {
                    webUiReady = false;
                    webViewLoaded = false;
                    pendingWebPage = webPageForBottomTab(lastWebTabIndex);
                    Toast.makeText(MainActivity.this,
                            "FX 页面资源异常（HTTP " + response.getStatusCode()
                                    + "），点击底部任一标签可重试。",
                            Toast.LENGTH_LONG).show();
                }
            }
            @Override public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                if (isTrustedDocumentUrl(Uri.parse(url))) {
                    webUiReady = true;
                    applyWebUiMode();
                    syncNativeVpnControls();
                    startNativeVpnPolling();
                    if (lastWebTabIndex == 3 && nativeScriptRows != null
                            && nativeScriptStatus != null && nativeScriptRows.getParent() != null) {
                        refreshNativeScriptList(nativeScriptRows, nativeScriptStatus);
                    }
                    if (lastWebTabIndex == 0 && nativeVpnSubRows != null
                            && nativeVpnSubStatus != null && nativeVpnSubRows.getParent() != null) {
                        refreshNativeVpnSubscriptions();
                    }
                    if (pendingWebPage != null) {
                        String pending = pendingWebPage;
                        pendingWebPage = null;
                        navigateWebPage(pending);
                    }
                }
            }
        });
        } else {
            ViewParent parent = webView.getParent();
            if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
            webView.onResume();
            webView.resumeTimers();
        }
        // The bundled WebView is retained as a hidden compatibility/runtime bridge only.
        // All visible management pages below are native Android views; no WebView pixels
        // are exposed to the user or accessibility tree.
        webView.setVisibility(View.INVISIBLE);
        webView.setAlpha(0f);
        webView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        root.addView(webView, new LinearLayout.LayoutParams(1, 1));

        nativePageScroll = new ScrollView(this);
        nativePageScroll.setFillViewport(true);
        nativePageScroll.setClipToPadding(false);
        nativePageScroll.setPadding(0, 0, 0, dp(84));
        nativePageContent = new LinearLayout(this);
        nativePageContent.setOrientation(LinearLayout.VERTICAL);
        nativePageContent.setPadding(0, dp(8), 0, dp(12));
        nativePageScroll.addView(nativePageContent, new ScrollView.LayoutParams(-1, -2));
        root.addView(nativePageScroll, new LinearLayout.LayoutParams(-1, 0, 1));
        mountNativeShell(root);
        renderNativePage(lastWebTabIndex);
        if (webUiReady) applyWebUiMode();
        if (!webViewLoaded) {
            checkRoot(rootStatus, false, () -> {
                if (!webViewLoaded) {
                    webView.loadUrl("https://appassets.androidplatform.net/assets/webroot/index.html");
                    webViewLoaded = true;
                }
            });
        } else {
            checkRoot(rootStatus, false);
        }
        startNativeVpnPolling();
    }


    private interface NativeCommandCallback { void onComplete(RootAccess.Result result); }

    private String nativeModuleCommand(String body) {
        return "MP=; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "[ -f \"$d/module.prop\" ] && { MP=\"$d\"; break; }; done; "
                + "[ -n \"$MP\" ] || exit 20; " + body;
    }

    private void runNativeModuleCommand(String body, long timeout, NativeCommandCallback callback) {
        nativeVpnExecutor.execute(() -> {
            RootAccess.Result result;
            try {
                result = RootAccess.execute(nativeModuleCommand(body), timeout, 1024 * 1024);
            } catch (RuntimeException error) {
                result = new RootAccess.Result(1, error.toString(), false);
            }
            RootAccess.Result finalResult = result;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (callback != null) callback.onComplete(finalResult);
            });
        });
    }

    private void addNativeCard(String heading, String description) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        card.setBackground(uiPanelDrawable());
        TextView h = new TextView(this);
        h.setText(heading);
        h.setTextSize(16);
        h.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        h.setTextColor(0xff17212b);
        TextView d = new TextView(this);
        d.setText(description);
        d.setTextSize(12);
        d.setTextColor(0xff718091);
        d.setPadding(0, dp(5), 0, 0);
        card.addView(h);
        card.addView(d);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(6));
        content.addView(card, lp);
    }

    private Button nativeAction(String label, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setOnClickListener(v -> { if (action != null) action.run(); });
        return button;
    }

    private void addNativeActionCard(String heading, String description, String actionLabel, Runnable action) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(16), dp(12), dp(16), dp(8));
        card.setBackground(uiPanelDrawable());
        TextView title = new TextView(this);
        title.setText(heading);
        title.setTextSize(15);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xff17212b);
        TextView detail = new TextView(this);
        detail.setText(description);
        detail.setTextSize(12);
        detail.setTextColor(0xff718091);
        detail.setPadding(0, dp(4), 0, dp(4));
        card.addView(title);
        card.addView(detail);
        card.addView(nativeAction(actionLabel, action));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(12), dp(4), dp(12), dp(6));
        content.addView(card, params);
    }

    private void addNativeSettingEntry(String heading, String summary, String detail) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(10), dp(14), dp(10));
        card.setBackground(uiPanelDrawable());
        TextView title = new TextView(this);
        title.setText(heading);
        title.setTextSize(15);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xff17212b);
        TextView description = new TextView(this);
        description.setText(summary);
        description.setTextSize(12);
        description.setTextColor(0xff718091);
        description.setPadding(0, dp(4), 0, dp(6));
        card.addView(title);
        card.addView(description);
        card.addView(nativeAction("查看说明", () -> new AlertDialog.Builder(this)
                .setTitle(heading).setMessage(detail)
                .setPositiveButton("关闭", null).show()));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(6));
        content.addView(card, lp);
    }

    private void buildNativeHostsPage() {
        content.addView(title("广告与 Hosts", 22));
        TextView intro = new TextView(this);
        intro.setText("统一管理本地 Hosts、订阅过滤规则与系统实际生效的 hosts。三类数据分开显示，不把订阅缓存当成本地文件。");
        intro.setTextColor(0xff718091);
        intro.setPadding(dp(18), 0, dp(18), dp(10));
        content.addView(intro);
        section("本地 Android Hosts");
        TextView hostsStatus = new TextView(this);
        hostsStatus.setText("正在读取本地 hosts 文件状态…");
        hostsStatus.setTextColor(0xff536170);
        hostsStatus.setPadding(dp(18), dp(6), dp(18), dp(8));
        content.addView(hostsStatus);
        LinearLayout hostActions = new LinearLayout(this);
        hostActions.setOrientation(LinearLayout.VERTICAL);
        hostActions.addView(nativeAction("打开本地 Hosts 分页编辑器", () -> showHostsEditor("hosts", 1)));
        hostActions.addView(nativeAction("导出到外部编辑器", this::exportHostsForExternal));
        hostActions.addView(nativeAction("从外部编辑器同步", this::importHostsFromExternal));
        hostActions.addView(nativeAction("查看系统实际生效 Hosts", () -> showHostsEditor("system-hosts", 1)));
        content.addView(hostActions);
        refreshHostsStatus(hostsStatus);

        section("订阅与过滤规则");
        LinearLayout ruleActions = new LinearLayout(this);
        ruleActions.setOrientation(LinearLayout.VERTICAL);
        ruleActions.addView(nativeAction("管理广告过滤订阅 / 规则源", () ->
                showNativeManagedListDialog("ruleList", "广告过滤订阅")));
        ruleActions.addView(nativeAction("添加广告过滤订阅", () ->
                showNativeManagedListAddDialog("ruleList", "添加广告过滤订阅", true)));
        ruleActions.addView(nativeAction("管理域名白名单", () ->
                showNativeManagedListDialog("domainList", "域名白名单")));
        ruleActions.addView(nativeAction("管理自定义黑名单", () ->
                showNativeManagedListDialog("blockList", "自定义黑名单")));
        ruleActions.addView(nativeAction("查看 FX 内置规则", () -> showNativeListDialog("fx", "FX 内置规则")));
        ruleActions.addView(nativeAction("查看 Hosts 本地条目", () -> showNativeListDialog("hosts_local", "本地 Hosts 条目")));
        ruleActions.addView(nativeAction("应用 Hosts 与过滤规则", this::applyNativeHosts));
        content.addView(ruleActions);
    }

    private void refreshHostsStatus(TextView target) {
        runNativeModuleCommand("sh \"$MP/scripts/fileedit.sh\" stat hosts", 30000L, result -> {
            try {
                if (result.exitCode != 0) throw new IllegalStateException(result.output);
                JSONObject json = new JSONObject(result.output.trim());
                if (!json.optBoolean("ok", false)) throw new IllegalStateException(json.optString("err", "读取失败"));
                target.setText("本地文件：/data/adb/privacyguard/local/hosts\n"
                        + "行数：" + json.optInt("lines", 0) + " · 大小：" + json.optLong("size", 0)
                        + " bytes · 数据源：本地手动维护");
            } catch (Exception error) {
                target.setText("本地 Hosts 状态读取失败：" + error.getMessage());
            }
        });
    }

    private void showHostsEditor(String spec, int page) {
        if (page < 1) page = 1;
        final int requestedPage = page;
        runNativeModuleCommand("sh \"$MP/scripts/fileedit.sh\" page " + shellQuote(spec)
                + " " + requestedPage + " 200 65536", 45000L, result -> {
            try {
                if (result.exitCode != 0) throw new IllegalStateException(result.output);
                JSONObject json = new JSONObject(result.output.trim());
                if (!json.optBoolean("ok", false)) throw new IllegalStateException(json.optString("err", "分页读取失败"));
                byte[] bytes = android.util.Base64.decode(json.optString("b64", ""), android.util.Base64.DEFAULT);
                String text = new String(bytes, StandardCharsets.UTF_8);
                boolean readOnly = "system-hosts".equals(spec);
                int start = json.optInt("start", requestedPage);
                int lines = json.optInt("lines", 0);
                int total = json.optInt("total", 0);

                LinearLayout panel = new LinearLayout(this);
                panel.setOrientation(LinearLayout.VERTICAL);
                panel.setPadding(dp(12), dp(6), dp(12), dp(4));
                TextView info = new TextView(this);
                info.setText((readOnly ? "只读视图 · /system/etc/hosts" : "本地源 · /data/adb/privacyguard/local/hosts")
                        + "\n第 " + start + "–" + Math.max(start, start + lines - 1) + " 行 / 共 " + total + " 行");
                info.setTextColor(0xff718091);
                panel.addView(info);
                EditText editor = new EditText(this);
                editor.setText(text);
                editor.setTextSize(12);
                editor.setTypeface(Typeface.MONOSPACE);
                editor.setGravity(Gravity.TOP | Gravity.START);
                editor.setSingleLine(false);
                editor.setMinLines(12);
                editor.setMaxLines(18);
                editor.setInputType(android.text.InputType.TYPE_CLASS_TEXT
                        | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
                        | android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
                editor.setEnabled(!readOnly);
                ScrollView editorScroll = new ScrollView(this);
                editorScroll.addView(editor, new ScrollView.LayoutParams(-1, -2));
                panel.addView(editorScroll, new LinearLayout.LayoutParams(-1, dp(340)));
                LinearLayout nav = new LinearLayout(this);
                nav.setOrientation(LinearLayout.HORIZONTAL);
                Button previous = nativeAction("上一页", () -> {
                    if (editor.getText().toString().equals(text)) showHostsEditor(spec, Math.max(1, start - 200));
                    else new AlertDialog.Builder(this).setMessage("当前页有未保存修改，确定放弃并翻页？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("放弃", (d, w) -> showHostsEditor(spec, Math.max(1, start - 200))).show();
                });
                previous.setEnabled(start > 1);
                Button next = nativeAction("下一页", () -> {
                    if (editor.getText().toString().equals(text)) showHostsEditor(spec, start + 200);
                    else new AlertDialog.Builder(this).setMessage("当前页有未保存修改，确定放弃并翻页？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("放弃", (d, w) -> showHostsEditor(spec, start + 200)).show();
                });
                next.setEnabled(start + lines <= total);
                nav.addView(previous, new LinearLayout.LayoutParams(0, -2, 1));
                nav.addView(next, new LinearLayout.LayoutParams(0, -2, 1));
                panel.addView(nav);
                AlertDialog dialog = new AlertDialog.Builder(this)
                        .setTitle(readOnly ? "系统 Hosts（只读）" : "本地 Hosts 编辑器")
                        .setView(panel)
                        .setNegativeButton("关闭", null)
                        .create();
                if (!readOnly) {
                    dialog.setButton(AlertDialog.BUTTON_POSITIVE, "保存并应用", (d, w) -> {});
                }
                dialog.setOnShowListener(d -> {
                    if (!readOnly) dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                        writeHostsPage(spec, start, lines, editor.getText().toString(), dialog);
                    });
                });
                dialog.show();
            } catch (Exception error) {
                new AlertDialog.Builder(this).setTitle("Hosts 读取失败")
                        .setMessage(error.getMessage()).setPositiveButton("重试", (d, w) -> showHostsEditor(spec, requestedPage))
                        .setNegativeButton("关闭", null).show();
            }
        });
    }

    private void writeHostsPage(String spec, int start, int originalLines, String text, AlertDialog dialog) {
        String encoded = android.util.Base64.encodeToString(text.getBytes(StandardCharsets.UTF_8),
                android.util.Base64.NO_WRAP);
        String command = "tmp=$(mktemp /data/local/tmp/fx-hosts.XXXXXXXX) || exit 41; "
                + "trap 'rm -f \"$tmp\"' EXIT; "
                + "printf '%s' " + shellQuote(encoded) + " | base64 -d > \"$tmp\" || exit 42; "
                + "sh \"$MP/scripts/fileedit.sh\" replacepage " + shellQuote(spec) + " "
                + start + " " + originalLines + " \"$tmp\"";
        runNativeModuleCommand(command, 60000L, result -> {
            try {
                JSONObject json = new JSONObject(result.output.trim());
                if (result.exitCode != 0 || !json.optBoolean("ok", false))
                    throw new IllegalStateException(json.optString("err", result.output));
                dialog.dismiss();
                Toast.makeText(this, "本地 Hosts 已保存，正在应用…", Toast.LENGTH_SHORT).show();
                applyNativeHosts();
            } catch (Exception error) {
                new AlertDialog.Builder(this).setTitle("保存失败")
                        .setMessage("原文件未确认更新：" + error.getMessage())
                        .setPositiveButton("知道了", null).show();
            }
        });
    }

    private void applyNativeHosts() {
        runNativeModuleCommand("sh \"$MP/scripts/apply.sh\"", 120000L, result -> {
            if (result.exitCode == 0) {
                Toast.makeText(this, "Hosts / 过滤规则应用完成", Toast.LENGTH_LONG).show();
            } else {
                new AlertDialog.Builder(this).setTitle("应用失败")
                        .setMessage(result.output).setPositiveButton("知道了", null).show();
            }
        });
    }

    private void exportHostsForExternal() {
        runNativeModuleCommand("sh \"$MP/scripts/fileedit.sh\" export hosts", 30000L, result -> {
            try {
                JSONObject json = new JSONObject(result.output.trim());
                if (result.exitCode != 0 || !json.optBoolean("ok", false))
                    throw new IllegalStateException(json.optString("err", result.output));
                getSharedPreferences("fx_hosts_external", MODE_PRIVATE).edit()
                        .putString("path", json.optString("path", ""))
                        .putString("hash", json.optString("baseHash", "")).apply();
                new AlertDialog.Builder(this).setTitle("已导出 Hosts")
                        .setMessage("文件已复制到：\n" + json.optString("path")
                                + "\n请使用外部编辑器修改后，返回 FX 点击“从外部编辑器同步”。")
                        .setPositiveButton("知道了", null).show();
            } catch (Exception error) {
                new AlertDialog.Builder(this).setMessage("导出失败：" + error.getMessage())
                        .setPositiveButton("知道了", null).show();
            }
        });
    }

    private void importHostsFromExternal() {
        android.content.SharedPreferences state = getSharedPreferences("fx_hosts_external", MODE_PRIVATE);
        String path = state.getString("path", "");
        String hash = state.getString("hash", "");
        if (path.isEmpty() || hash.isEmpty()) {
            Toast.makeText(this, "请先导出本地 Hosts，再用外部编辑器修改副本。", Toast.LENGTH_LONG).show();
            return;
        }
        runNativeModuleCommand("sh \"$MP/scripts/fileedit.sh\" import-external hosts "
                + shellQuote(path) + " " + shellQuote(hash), 60000L, result -> {
            try {
                JSONObject json = new JSONObject(result.output.trim());
                if (result.exitCode != 0 || !json.optBoolean("ok", false))
                    throw new IllegalStateException(json.optString("err", result.output));
                state.edit().remove("path").remove("hash").apply();
                Toast.makeText(this, "外部 Hosts 已同步，正在应用…", Toast.LENGTH_LONG).show();
                applyNativeHosts();
            } catch (Exception error) {
                new AlertDialog.Builder(this).setTitle("同步失败")
                        .setMessage(error.getMessage()).setPositiveButton("知道了", null).show();
            }
        });
    }

    private void showNativeManagedListDialog(String listId, String title) {
        runNativeModuleCommand("sh \"$MP/scripts/native-managed-lists.sh\" list " + shellQuote(listId),
                30000L, result -> {
            if (result.exitCode != 0) {
                new AlertDialog.Builder(this).setTitle(title + "读取失败")
                        .setMessage(result.output == null ? "无法读取设备端列表。" : result.output.trim())
                        .setPositiveButton("重试", (d, w) -> showNativeManagedListDialog(listId, title))
                        .setNegativeButton("关闭", null).show();
                return;
            }
            String[] lines = (result.output == null ? "" : result.output.trim()).split("\\r?\\n");
            if (lines.length == 0 || !"FXLIST1".equals(lines[0])) {
                new AlertDialog.Builder(this).setTitle(title + "读取失败")
                        .setMessage("设备端列表响应格式错误。")
                        .setPositiveButton("重试", (d, w) -> showNativeManagedListDialog(listId, title))
                        .setNegativeButton("关闭", null).show();
                return;
            }
            List<Integer> rowIndices = new ArrayList<>();
            List<String> rowValues = new ArrayList<>();
            List<String> rowNotes = new ArrayList<>();
            List<Boolean> rowEnabled = new ArrayList<>();
            List<String> labels = new ArrayList<>();
            for (int i = 1; i < lines.length; i++) {
                String line = lines[i];
                if (line.trim().isEmpty()) continue;
                String[] parts = line.split("\\|", 4);
                if (parts.length != 4) continue;
                try {
                    int rowIndex = Integer.parseInt(parts[0]);
                    String value = parts[1];
                    String note = parts[2];
                    boolean enabled = "1".equals(parts[3]);
                    rowIndices.add(rowIndex);
                    rowValues.add(value);
                    rowNotes.add(note);
                    rowEnabled.add(enabled);
                    labels.add((enabled ? "● " : "○ ") + (note.isEmpty() ? value : note)
                            + (value.isEmpty() || value.equals(note) ? "" : "\\n" + value));
                } catch (NumberFormatException ignored) { }
            }
            String[] items = labels.toArray(new String[0]);
            new AlertDialog.Builder(this).setTitle(title)
                    .setItems(items, (dialog, which) -> showNativeManagedListItemActions(
                            listId, title, rowIndices.get(which), rowValues.get(which),
                            rowNotes.get(which), rowEnabled.get(which)))
                    .setPositiveButton("添加", (dialog, which) ->
                            showNativeManagedListAddDialog(listId, title, "ruleList".equals(listId)))
                    .setNegativeButton("关闭", null).show();
            if (items.length == 0) {
                Toast.makeText(this, "当前列表为空，可点击“添加”创建条目", Toast.LENGTH_SHORT).show();
            }
        });
    }    private void showNativeManagedListItemActions(String listId, String title, int index,
                                                   String value, String note, boolean enabled) {
        String[] actions = {enabled ? "停用" : "启用", "编辑", "删除"};
        new AlertDialog.Builder(this).setTitle(note.isEmpty() ? title : note)
                .setItems(actions, (dialog, which) -> {
                    if (which == 0) mutateNativeManagedList(listId, index, "toggle", "", !enabled, title);
                    else if (which == 1) showNativeManagedListEditDialog(listId, title, index, value, note);
                    else new AlertDialog.Builder(this).setMessage("确定删除此条目？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除", (d, w) ->
                                    mutateNativeManagedList(listId, index, "delete", "", false, title)).show();
                }).show();
    }

    private void showNativeManagedListAddDialog(String listId, String title, boolean subscription) {
        EditText value = new EditText(this);
        value.setSingleLine(false);
        value.setMinLines(subscription ? 2 : 1);
        value.setHint(subscription ? "粘贴规则订阅 URL（https://…）" : "输入域名或规则内容");
        EditText note = new EditText(this);
        note.setSingleLine(true);
        note.setHint("名称（可选）");
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(6), dp(16), dp(4));
        panel.addView(value);
        panel.addView(note);
        new AlertDialog.Builder(this).setTitle(title)
                .setView(panel).setNegativeButton("取消", null)
                .setPositiveButton("添加", (dialog, which) -> {
                    String v = value.getText().toString().trim();
                    if (v.isEmpty()) {
                        Toast.makeText(this, "内容不能为空", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    if (subscription && !v.matches("(?i)^https?://.+")) {
                        Toast.makeText(this, "订阅地址必须以 http:// 或 https:// 开头", Toast.LENGTH_LONG).show();
                        return;
                    }
                    String n = note.getText().toString().trim();
                    mutateNativeManagedList(listId, -1, "add", v, true, title, n.isEmpty() ? v : n);
                }).show();
    }    private void showNativeManagedListEditDialog(String listId, String title, int index,
                                                  String oldValue, String oldNote) {
        EditText value = new EditText(this);
        value.setText(oldValue);
        value.setSingleLine(false);
        value.setMinLines(2);
        EditText note = new EditText(this);
        note.setText(oldNote);
        note.setHint("名称");
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(6), dp(16), dp(4));
        panel.addView(value);
        panel.addView(note);
        new AlertDialog.Builder(this).setTitle("编辑条目")
                .setView(panel).setNegativeButton("取消", null)
                .setPositiveButton("保存", (d, w) -> {
                    String v = value.getText().toString().trim();
                    if (v.isEmpty()) {
                        Toast.makeText(this, "内容不能为空", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    mutateNativeManagedList(listId, index, "edit", v, true, title,
                            note.getText().toString().trim());
                }).show();
    }

    private void mutateNativeManagedList(String listId, int index, String operation,
                                          String newValue, boolean enabled, String title) {
        mutateNativeManagedList(listId, index, operation, newValue, enabled, title, "");
    }

    private void mutateNativeManagedList(String listId, int index, String operation,
                                          String newValue, boolean enabled, String title, String newNote) {
        String command = "sh \"$MP/scripts/native-managed-lists.sh\" "
                + shellQuote(operation) + " " + shellQuote(listId);
        switch (operation) {
            case "add":
                command += " " + shellQuote(newValue) + " " + shellQuote(newNote);
                break;
            case "edit":
                command += " " + index + " " + shellQuote(newValue) + " "
                        + shellQuote(newNote) + " " + (enabled ? "1" : "0");
                break;
            case "toggle":
                command += " " + index + " " + (enabled ? "1" : "0");
                break;
            case "delete":
                command += " " + index;
                break;
            default:
                Toast.makeText(this, "未知列表操作：" + operation, Toast.LENGTH_SHORT).show();
                return;
        }
        runNativeModuleCommand(command, 180000L, result -> {
            if (result.exitCode == 0) {
                Toast.makeText(this, "列表已保存并应用。", Toast.LENGTH_LONG).show();
                showNativeManagedListDialog(listId, title);
            } else {
                String detail = result.output == null ? "设备端保存或应用失败。" : result.output.trim();
                new AlertDialog.Builder(this).setTitle("列表更新失败")
                        .setMessage(detail)
                        .setPositiveButton("重试", (d, w) ->
                                mutateNativeManagedList(listId, index, operation, newValue, enabled, title, newNote))
                        .setNegativeButton("关闭", null).show();
            }
        });
    }    private void showNativeListDialog(String listName, String title) {
        runNativeModuleCommand(". \"$MP/scripts/util.sh\"; pg_list " + shellQuote(listName),
                30000L, result -> {
            if (result.exitCode != 0) {
                Toast.makeText(this, "读取列表失败：" + result.output, Toast.LENGTH_LONG).show();
                return;
            }
            String value = result.output == null || result.output.trim().isEmpty()
                    ? "当前列表为空。" : result.output.trim();
            new AlertDialog.Builder(this).setTitle(title).setMessage(value)
                    .setPositiveButton("关闭", null).show();
        });
    }

    private void buildNativePrivacyPage() {
        content.addView(title("隐私保护", 22));
        TextView intro = new TextView(this);
        intro.setText("按应用管理广告标识、剪贴板、Wi-Fi 扫描、位置、麦克风、摄像头、通知、传感器与媒体隐私。设备标识等系统级防护单独列在下方；具体应用规则在 Hook 页面配置。");
        intro.setTextColor(0xff718091);
        intro.setPadding(dp(18), 0, dp(18), dp(10));
        content.addView(intro);
        section("设备授权与 Hook 状态");
        TextView state = new TextView(this);
        state.setText("正在读取 Root、LSPosed 与 Remote Files 状态…");
        state.setTextColor(0xff536170);
        state.setPadding(dp(18), dp(8), dp(18), dp(10));
        content.addView(state);
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.addView(nativeAction("打开应用级 Hook 配置", this::showAppList));
        actions.addView(nativeAction("打开 Root / LSPosed 授权中心", this::showHookHub));
        actions.addView(nativeAction("刷新隐私状态", () -> refreshNativePrivacyStatus(state)));
        content.addView(actions);
        refreshNativePrivacyStatus(state);

        TextView privacyMasterHint = new TextView(this);
        privacyMasterHint.setText("使用方式：进入目标应用后，先开启「隐私保护总开关」，再开启对应分类的具体策略；只读会员状态诊断不受该总开关控制。关闭总开关会停用该应用的隐私 Hook。");
        privacyMasterHint.setTextColor(0xff697681);
        privacyMasterHint.setPadding(dp(18), dp(4), dp(18), dp(12));
        content.addView(privacyMasterHint);

        section("保护功能 · 按应用配置");
        addNativeActionCard("应用内广告标识", "为选定应用统一 Google / Huawei 广告标识；不修改 Android ID 或系统广告设置。", "选择应用配置", () -> showAppList("标识与追踪"));
        addNativeActionCard("剪贴板读取与隔离", "分别配置剪贴板读取阻断和剪贴板隔离；两项策略可按应用独立设置。", "配置剪贴板保护", () -> showAppList("剪贴板保护"));
        addNativeActionCard("Wi-Fi 扫描保护", "按应用限制 Wi-Fi 扫描 API；不拦截网络连接、DNS、VPN 或套接字流量。", "配置 Wi-Fi 隐私", () -> showAppList("Wi-Fi 网络隐私"));
        addNativeActionCard("位置访问保护", "按应用限制位置访问；不会伪造定位或更改系统定位权限。", "配置位置保护", () -> showAppList("位置隐私"));
        addNativeActionCard("麦克风保护", "分别配置录音启动阻断与录音静音策略；启用前请确认对录音功能的影响。", "配置麦克风保护", () -> showAppList("麦克风保护"));
        addNativeActionCard("摄像头访问保护", "按应用限制摄像头访问；策略由 Hook 目标配置发布。", "配置摄像头保护", () -> showAppList("设备访问"));
        addNativeActionCard("传感器访问与采样", "管理加速度计、陀螺仪、光线、磁场、气压、距离传感器及采样频率限制。", "配置传感器保护", () -> showAppList("传感器保护"));
        addNativeActionCard("通知监听与权限提示", "分别管理通知监听注册阻断和通知权限提示隐藏。", "配置通知保护", () -> showAppList("通知保护"));
        addNativeActionCard("媒体查询与 EXIF", "管理媒体库查询元数据清理以及图片、视频 EXIF 元数据清理。", "配置媒体隐私", () -> showAppList("媒体隐私"));
        addNativeActionCard("只读会员状态诊断", "仅记录目标应用可观察的会员状态诊断信息，不修改购买结果、令牌或服务端授权。", "配置只读诊断", () -> showAppList("会员诊断"));

        // These are privacy/security policies, not application preferences.
        // Keep their native controls on the Privacy destination where users expect them.
        section("高级隐私与系统防护");
        addNativeSettingsCategory("Root / 模块隐藏", "rootPanel");
        addNativeSettingsCategory("高级网络防护", "advPanel");
        addNativeSettingsCategory("网络隐私", "netPanel");
        addNativeSettingsCategory("权限与 API", "permPanel");
        addNativeSettingsCategory("传感器", "sensorPanel");
        addNativeSettingsCategory("位置隐私", "locationPanel");
        addNativeSettingsCategory("设备标识", "devicePanel");
        addNativeSettingsCategory("音频 / 相机 / 媒体", "mediaPanel");
        addNativeSettingsCategory("文件与存储", "filePanel");
        addNativeSettingsCategory("通知与剪贴板", "notifyPanel");
        addNativeSettingsCategory("内核防护", "kernelPanel");
        addNativeSettingsCategory("其他系统隐私", "miscPanel");
    }

    private void refreshNativePrivacyStatus(TextView target) {
        runNativeModuleCommand("sh \"$MP/scripts/status.sh\" json", 30000L, result -> {
            try {
                if (result.exitCode != 0) throw new IllegalStateException(result.output);
                JSONObject json = new JSONObject(result.output.trim());
                target.setText("Root：" + (json.optBoolean("root", false) ? "已授权" : "未授权")
                        + " · LSPosed：" + json.optString("lsposed_status", json.optString("lsposed", "unknown"))
                        + "\nRemote Files：" + json.optString("hook_remote_status", "unknown")
                        + " · 已发布目标：" + json.optInt("hook_native_targets", 0)
                        + "\n隐私目标：" + json.optInt("hook_native_privacy_targets", 0)
                        + " · Wi-Fi 扫描目标：" + json.optInt("hook_native_wifi_scan_targets", 0)
                        + " · 通知目标：" + json.optInt("hook_native_notification_listen_targets", 0));
            } catch (Exception error) {
                target.setText("隐私状态读取失败：" + error.getMessage());
            }
        });
    }

    private void buildNativeScriptPage() {
        content.addView(title("脚本中心", 22));
        TextView intro = new TextView(this);
        intro.setText("管理脚本订阅、启停、导入与运行记录。列表和开关直接读写模块设置；运行状态以同步结果和引擎日志为准。");
        intro.setTextColor(0xff718091);
        intro.setPadding(dp(18), 0, dp(18), dp(10));
        content.addView(intro);
        section("脚本管理");
        TextView status = new TextView(this);
        status.setText("正在读取脚本列表…");
        status.setTextColor(0xff536170);
        status.setPadding(dp(18), dp(6), dp(18), dp(8));
        content.addView(status);
        LinearLayout rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        nativeScriptRows = rows;
        nativeScriptStatus = status;
        content.addView(rows);
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.addView(nativeAction("添加脚本 / 订阅", this::showNativeScriptAddDialog));
        actions.addView(nativeAction("从文件导入脚本", this::pickNativeScriptFile));
        actions.addView(nativeAction("导出脚本配置", this::exportNativeScripts));
        actions.addView(nativeAction("刷新脚本订阅", this::refreshNativeScripts));
        actions.addView(nativeAction("查看脚本运行日志", this::showNativeScriptLogs));
        actions.addView(nativeAction("查看 MITM / 证书状态", () -> showNativeMitmStatus()));
        actions.addView(nativeAction("管理系统 CA 信任（MITM / HTTPS）", this::showNativeCertificateManager));
        content.addView(actions);
        refreshNativeScriptList(rows, status);
    }

    private String nativeScriptStoreCommand(String action, String... args) {
        StringBuilder command = new StringBuilder("sh \"$MP/scripts/jsruntime/native-list.sh\" ").append(action);
        for (String arg : args) command.append(' ').append(arg);
        return command.toString();
    }

    private static String encodeNativeScriptArgument(String value) {
        return Base64.encodeToString((value == null ? "" : value).getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    private static String decodeNativeScriptArgument(String value) {
        return new String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8);
    }

    private static String decodeNativeScriptValue(String value) {
        String decoded = decodeNativeScriptArgument(value);
        if (decoded.startsWith("FXSRC_B64:")) {
            return new String(Base64.decode(decoded.substring("FXSRC_B64:".length()), Base64.DEFAULT),
                    StandardCharsets.UTF_8);
        }
        return decoded;
    }

    private static int nativeScriptUtf8Bytes(String value) {
        return value == null ? 0 : value.getBytes(StandardCharsets.UTF_8).length;
    }

    private static boolean isSupportedNativeScriptValue(String raw) {
        if (raw == null) return false;
        String value = raw.trim();
        if (value.isEmpty()) return false;
        if (value.regionMatches(true, 0, "https://", 0, 8)) {
            Uri parsed = Uri.parse(value);
            String host = parsed.getHost();
            return host != null && !host.isEmpty() && parsed.getUserInfo() == null
                    && !value.matches(".*\\s+.*");
        }
        if (value.regionMatches(true, 0, "http://", 0, 7)) return false;
        // Other URI schemes are not fetched by the module synchronizer.
        return !value.matches("^[A-Za-z][A-Za-z0-9+.-]*://.*");
    }

    private void syncNativeScriptRuntime() {
        runNativeModuleCommand("sh \"$MP/scripts/jsruntime/sync-subs.sh\"", 60000L, result -> {
            if (result.exitCode != 0 && nativeScriptStatus != null
                    && nativeScriptStatus.getParent() != null) {
                nativeScriptStatus.setText(nativeScriptStatus.getText()
                        + "\n配置已保存，但运行时订阅同步失败：" + result.output.trim());
            }
        });
    }

    private void refreshNativeScriptList(LinearLayout rows, TextView status) {
        status.setText("正在从模块 settings.conf 读取脚本列表…");
        runNativeModuleCommand(nativeScriptStoreCommand("list"), 30000L, result -> {
            if (rows.getParent() == null || status.getParent() == null) return;
            if (result.exitCode != 0) {
                status.setText("脚本列表读取失败：" + result.output.trim());
                return;
            }
            try {
                String[] lines = result.output.split("\\r?\\n");
                if (lines.length == 0 || !"FXSCRIPT1".equals(lines[0].trim())) {
                    throw new IllegalStateException("模块返回了无法识别的脚本列表格式");
                }
                rows.removeAllViews();
                int count = 0;
                int enabled = 0;
                for (int i = 1; i < lines.length; i++) {
                    if (lines[i].trim().isEmpty()) continue;
                    String[] fields = lines[i].split("\\|", -1);
                    if (fields.length != 3) throw new IllegalStateException("脚本条目字段数量错误");
                    final int index = count++;
                    final String valueText = decodeNativeScriptValue(fields[0]);
                    final String note = decodeNativeScriptArgument(fields[1]);
                    final boolean on = "1".equals(fields[2]);
                    if (on) enabled++;
                    LinearLayout row = new LinearLayout(this);
                    row.setOrientation(LinearLayout.VERTICAL);
                    row.setPadding(dp(14), dp(10), dp(14), dp(8));
                    row.setBackground(uiPanelDrawable());
                    TextView name = new TextView(this);
                    name.setText(note.isEmpty() ? valueText : note);
                    name.setTextColor(0xff17212b);
                    name.setTextSize(14);
                    name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                    TextView source = new TextView(this);
                    source.setText((valueText.startsWith("https://") ? "HTTPS 订阅 · " : "本地 JS 源码 · 可手动运行 QuickJS-NG · ") + valueText);
                    source.setTextColor(0xff718091);
                    source.setTextSize(10);
                    source.setMaxLines(2);
                    source.setEllipsize(android.text.TextUtils.TruncateAt.END);
                    row.addView(name);
                    row.addView(source);
                    LinearLayout ops = new LinearLayout(this);
                    ops.setGravity(Gravity.CENTER_VERTICAL);
                    Switch enabledSwitch = new Switch(this);
                    enabledSwitch.setText(valueText.startsWith("https://") ? "订阅启用" : "保存状态");
                    enabledSwitch.setChecked(on);
                    enabledSwitch.setOnCheckedChangeListener((button, checked) ->
                            setNativeScriptEnabled(index, checked, rows, status, enabledSwitch, on));
                    ops.addView(enabledSwitch, new LinearLayout.LayoutParams(0, -2, 1));
                    row.setOnClickListener(v -> new AlertDialog.Builder(this)
                            .setTitle(note.isEmpty() ? "脚本详情" : note)
                            .setMessage(valueText).setPositiveButton("关闭", null).show());
                    if (!valueText.startsWith("https://")) {
                        Button run = nativeAction("运行", () -> confirmRunNativeLocalScript(index, note, valueText, rows, status));
                        run.setEnabled(on);
                        ops.addView(run);
                    }
                    ops.addView(nativeAction("编辑", () -> editNativeScript(index, valueText, note, rows, status)));
                    ops.addView(nativeAction("删除", () -> new AlertDialog.Builder(this)
                            .setMessage("确定删除该脚本条目？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除", (d, w) -> deleteNativeScript(index, rows, status)).show()));
                    row.addView(ops);
                    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
                    lp.setMargins(dp(12), dp(3), dp(12), dp(4));
                    rows.addView(row, lp);
                }
                status.setText("脚本条目：" + count + " · 已启用：" + enabled
                        + " · 配置来源：模块 settings.conf · 本地 JS 可手动调用 QuickJS-NG 执行");
                if (count == 0) {
                    TextView empty = new TextView(this);
                    empty.setText("暂无脚本条目。可添加 HTTPS 订阅或导入本地 JS 源码；启用本地源码后可手动运行。");
                    empty.setTextColor(0xff718091);
                    empty.setPadding(dp(18), dp(16), dp(18), dp(16));
                    rows.addView(empty);
                }
            } catch (Exception error) {
                status.setText("脚本列表解析失败：" + error.getMessage());
            }
        });
    }

    private static String nativeScriptSha256(String value) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256")
                    .digest((value == null ? "" : value).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte b : digest) hex.append(String.format(java.util.Locale.ROOT, "%02x", b & 0xff));
            return hex.toString();
        } catch (Exception error) {
            throw new IllegalStateException("无法计算脚本校验值", error);
        }
    }

    private void confirmRunNativeLocalScript(int index, String name, String source,
                                             LinearLayout rows, TextView status) {
        new AlertDialog.Builder(this).setTitle("运行本地 JavaScript")
                .setMessage("即将通过 FX QuickJS-NG 执行本地脚本"
                        + (name == null || name.trim().isEmpty() ? "" : "「" + name + "」")
                        + "。脚本会使用 FX 明确提供的宿主 API；只运行你信任的源码。")
                .setNegativeButton("取消", null)
                .setPositiveButton("运行", (dialog, which) ->
                        runNativeLocalScript(index, nativeScriptSha256(source), rows, status))
                .show();
    }

    private void runNativeLocalScript(int index, String expectedSha256, LinearLayout rows, TextView status) {
        status.setText("正在通过 QuickJS-NG 执行本地脚本…");
        runNativeModuleCommand("sh \"$MP/scripts/jsruntime/local-run.sh\" " + (index + 1)
                        + " " + expectedSha256,
                30000L, result -> {
                    String output = result.output == null ? "" : result.output.trim();
                    try {
                        JSONObject response = new JSONObject(output);
                        boolean ok = result.exitCode == 0 && response.optBoolean("ok", false);
                        status.setText(ok ? "本地脚本执行完成 · QuickJS-NG" : "本地脚本执行失败 · " +
                                response.optString("error", "模块未确认执行结果"));
                        new AlertDialog.Builder(this).setTitle(ok ? "脚本执行完成" : "脚本执行失败")
                                .setMessage(response.toString(2))
                                .setPositiveButton("关闭", null).show();
                    } catch (Exception error) {
                        status.setText("脚本执行结果解析失败：" + error.getMessage());
                        new AlertDialog.Builder(this).setTitle("脚本执行结果无效")
                                .setMessage(output.isEmpty() ? error.getMessage() : output)
                                .setPositiveButton("关闭", null).show();
                    }
                });
    }

    private void setNativeScriptEnabled(int index, boolean enabled, LinearLayout rows, TextView status,
                                        Switch control, boolean previous) {
        control.setEnabled(false);
        runNativeModuleCommand(nativeScriptStoreCommand("toggle", String.valueOf(index + 1), enabled ? "1" : "0"),
                30000L, result -> {
                    if (result.exitCode == 0 && result.output.contains("OK")) {
                        control.setEnabled(true);
                        control.setOnCheckedChangeListener((button, checked) ->
                                setNativeScriptEnabled(index, checked, rows, status, control, enabled));
                        Toast.makeText(this, "脚本状态已保存到模块配置", Toast.LENGTH_SHORT).show();
                        refreshNativeScriptList(rows, status);
                        syncNativeScriptRuntime();
                    } else {
                        restoreNativeScriptSwitch(index, control, previous, rows, status);
                        status.setText("脚本状态保存失败，已恢复原状态：" + result.output.trim());
                    }
                });
    }

    private void restoreNativeScriptSwitch(int index, Switch control, boolean previous,
                                            LinearLayout rows, TextView status) {
        control.setOnCheckedChangeListener(null);
        control.setChecked(previous);
        control.setEnabled(true);
        control.setOnCheckedChangeListener((button, checked) ->
                setNativeScriptEnabled(index, checked, rows, status, control, previous));
    }

    private void editNativeScript(int index, String oldValue, String oldNote,
                                  LinearLayout rows, TextView status) {
        EditText value = new EditText(this);
        value.setText(oldValue);
        value.setSingleLine(false);
        value.setMinLines(4);
        value.setGravity(Gravity.TOP | Gravity.START);
        value.setHint("HTTPS 订阅 URL 或本地 JavaScript 源码（最多 64 KiB）");
        EditText note = new EditText(this);
        note.setText(oldNote);
        note.setSingleLine(true);
        note.setHint("脚本名称（可选）");
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(6), dp(16), dp(4));
        panel.addView(value);
        panel.addView(note);
        new AlertDialog.Builder(this).setTitle("编辑脚本")
                .setView(panel).setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) -> {
                    String updatedValue = value.getText().toString();
                    String trimmedValue = updatedValue.trim();
                    if (trimmedValue.regionMatches(true, 0, "https://", 0, 8)) updatedValue = trimmedValue;
                    String updatedNote = note.getText().toString().trim();
                    if (!isSupportedNativeScriptValue(updatedValue) || nativeScriptUtf8Bytes(updatedValue) > 64 * 1024) {
                        Toast.makeText(this, "仅接受 HTTPS 订阅 URL 或本地 JS 源码，且长度不得超过 64 KiB；不接受明文 HTTP", Toast.LENGTH_LONG).show();
                        return;
                    }
                    if (updatedNote.isEmpty()) updatedNote = updatedValue.length() > 80
                            ? updatedValue.substring(0, 80) : updatedValue;
                    String command = nativeScriptStoreCommand("update", String.valueOf(index + 1),
                            encodeNativeScriptArgument(updatedValue), encodeNativeScriptArgument(updatedNote));
                    runNativeModuleCommand(command, 30000L, result -> {
                        if (result.exitCode == 0 && result.output.contains("OK")) {
                            Toast.makeText(this, "脚本配置已保存", Toast.LENGTH_SHORT).show();
                            refreshNativeScriptList(rows, status);
                            syncNativeScriptRuntime();
                        } else {
                            Toast.makeText(this, "脚本保存失败：" + result.output.trim(), Toast.LENGTH_LONG).show();
                        }
                    });
                }).show();
    }

    private void deleteNativeScript(int index, LinearLayout rows, TextView status) {
        runNativeModuleCommand(nativeScriptStoreCommand("delete", String.valueOf(index + 1)), 30000L, result -> {
            if (result.exitCode == 0 && result.output.contains("OK")) {
                Toast.makeText(this, "脚本条目已删除", Toast.LENGTH_SHORT).show();
                refreshNativeScriptList(rows, status);
                syncNativeScriptRuntime();
            } else {
                Toast.makeText(this, "删除失败：" + result.output.trim(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void showNativeScriptAddDialog() {
        EditText input = new EditText(this);
        input.setSingleLine(false);
        input.setMinLines(3);
        input.setHint("粘贴 HTTPS 订阅 URL 或本地 JS 源码");
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(6), dp(12), dp(4));
        TextView hint = new TextView(this);
        hint.setText("HTTPS 订阅会由脚本同步器处理，并要求受支持的 FX / userscript URL 匹配元数据。本地 JS 源码保存后不会自动执行；启用条目后，可在脚本列表中点击「运行」手动调用 FX QuickJS-NG。运行前会再次确认，执行结果与错误会显示在页面中。明文 HTTP 订阅会被拒绝。");
        hint.setTextColor(0xff718091);
        panel.addView(hint);
        panel.addView(input);
        new AlertDialog.Builder(this).setTitle("添加脚本 / 订阅")
                .setView(panel)
                .setNegativeButton("取消", null)
                .setPositiveButton("添加", (d, w) -> addNativeScriptValue(input.getText().toString(), "手动添加"))
                .show();
    }

    private void pickNativeScriptFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        try {
            startActivityForResult(intent, REQUEST_NATIVE_SCRIPT_FILE);
        } catch (Exception error) {
            Toast.makeText(this, "无法打开系统文件选择器：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void addNativeScriptValue(String raw, String sourceName) {
        String value = raw == null ? "" : raw;
        String trimmedValue = value.trim();
        if (trimmedValue.regionMatches(true, 0, "https://", 0, 8)) value = trimmedValue;
        if (!isSupportedNativeScriptValue(value) || nativeScriptUtf8Bytes(value) > 64 * 1024) {
            Toast.makeText(this, "仅接受 HTTPS 订阅 URL 或本地 JS 源码，且长度不得超过 64 KiB；不接受明文 HTTP", Toast.LENGTH_LONG).show();
            return;
        }
        String note = sourceName == null || sourceName.trim().isEmpty()
                ? (value.length() > 80 ? value.substring(0, 80) : value) : sourceName.trim();
        String command = nativeScriptStoreCommand("add", encodeNativeScriptArgument(value),
                encodeNativeScriptArgument(note), "1");
        runNativeModuleCommand(command, 30000L, result -> {
            if (isFinishing() || isDestroyed()) return;
            if (result.exitCode == 0 && result.output.contains("OK")) {
                Toast.makeText(this, "脚本条目已保存到模块配置", Toast.LENGTH_SHORT).show();
                if (nativeScriptRows != null && nativeScriptStatus != null) {
                    refreshNativeScriptList(nativeScriptRows, nativeScriptStatus);
                }
                syncNativeScriptRuntime();
            } else {
                Toast.makeText(this, "脚本未保存：" + result.output.trim(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void importNativeScriptDocument(String payload) {
        try {
            JSONObject document = new JSONObject(payload);
            if (!"FX-SCRIPT-LIST".equals(document.optString("format"))
                    || document.optInt("version", -1) != 1) {
                throw new IllegalArgumentException("不支持的脚本配置格式或版本");
            }
            JSONArray entries = document.optJSONArray("scripts");
            if (entries == null || entries.length() == 0 || entries.length() > 128) {
                throw new IllegalArgumentException("脚本条目数量必须为 1–128");
            }
            for (int i = 0; i < entries.length(); i++) {
                JSONObject entry = entries.optJSONObject(i);
                if (entry == null) throw new IllegalArgumentException("第 " + (i + 1) + " 项不是有效对象");
                Object rawValue = entry.opt("value");
                Object rawName = entry.opt("name");
                Object rawEnabled = entry.opt("enabled");
                if (!(rawValue instanceof String) || !(rawName instanceof String)
                        || (entry.has("enabled") && !(rawEnabled instanceof Boolean))) {
                    throw new IllegalArgumentException("第 " + (i + 1) + " 项字段类型错误");
                }
                String value = (String) rawValue;
                String name = (String) rawName;
                if (!isSupportedNativeScriptValue(value) || value.length() > 64 * 1024) {
                    throw new IllegalArgumentException("第 " + (i + 1) + " 项脚本内容无效或超过 64 KiB");
                }
                if (name.length() > 512) throw new IllegalArgumentException("第 " + (i + 1) + " 项名称超过 512 字符");
            }
            importNativeScriptEntry(entries, 0, 0, 0);
        } catch (Exception error) {
            Toast.makeText(this, "脚本配置导入失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void importNativeScriptEntry(JSONArray entries, int index, int imported, int failed) {
        if (index >= entries.length()) {
            Toast.makeText(this, "脚本配置导入结束：成功 " + imported + " 项，失败 " + failed + " 项",
                    Toast.LENGTH_LONG).show();
            if (nativeScriptRows != null && nativeScriptStatus != null) {
                refreshNativeScriptList(nativeScriptRows, nativeScriptStatus);
            }
            syncNativeScriptRuntime();
            return;
        }
        JSONObject entry = entries.optJSONObject(index);
        if (entry == null) {
            importNativeScriptEntry(entries, index + 1, imported, failed + 1);
            return;
        }
        String value = entry.optString("value", "");
        String name = entry.optString("name", "");
        String enabled = entry.optBoolean("enabled", true) ? "1" : "0";
        String command = nativeScriptStoreCommand("add", encodeNativeScriptArgument(value),
                encodeNativeScriptArgument(name), enabled);
        runNativeModuleCommand(command, 30000L, result -> {
            boolean ok = result.exitCode == 0 && result.output.contains("OK");
            importNativeScriptEntry(entries, index + 1, imported + (ok ? 1 : 0), failed + (ok ? 0 : 1));
        });
    }

    private void exportNativeScripts() {
        runNativeModuleCommand(nativeScriptStoreCommand("list"), 30000L, result -> {
            if (result.exitCode != 0) {
                Toast.makeText(this, "读取脚本配置失败：" + result.output.trim(), Toast.LENGTH_LONG).show();
                return;
            }
            try {
                String[] lines = result.output.split("\\r?\\n");
                if (lines.length == 0 || !"FXSCRIPT1".equals(lines[0].trim())) {
                    throw new IllegalStateException("脚本列表协议不匹配");
                }
                JSONArray entries = new JSONArray();
                for (int i = 1; i < lines.length; i++) {
                    if (lines[i].trim().isEmpty()) continue;
                    String[] fields = lines[i].split("\\|", -1);
                    if (fields.length != 3) throw new IllegalStateException("脚本条目字段错误");
                    JSONObject entry = new JSONObject();
                    entry.put("value", decodeNativeScriptValue(fields[0]));
                    entry.put("kind", decodeNativeScriptValue(fields[0]).startsWith("https://") ? "https-subscription" : "local-source");
                    entry.put("name", decodeNativeScriptArgument(fields[1]));
                    entry.put("enabled", "1".equals(fields[2]));
                    entries.put(entry);
                }
                JSONObject document = new JSONObject();
                document.put("format", "FX-SCRIPT-LIST");
                document.put("version", 1);
                document.put("scripts", entries);
                pendingNativeScriptExport = document.toString(2);
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/json");
                intent.putExtra(Intent.EXTRA_TITLE, "fx-scripts.json");
                startActivityForResult(intent, REQUEST_NATIVE_SCRIPT_EXPORT);
            } catch (Exception error) {
                Toast.makeText(this, "导出准备失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void refreshNativeScripts() {
        if (nativeScriptStatus != null) nativeScriptStatus.setText("正在同步已启用的 HTTPS 脚本订阅…");
        runNativeModuleCommand("sh \"$MP/scripts/jsruntime/sync-subs.sh\"", 60000L, result -> {
            if (result.exitCode == 0) {
                Toast.makeText(this, "脚本订阅同步完成：" + result.output.trim(), Toast.LENGTH_LONG).show();
            } else {
                Toast.makeText(this, "脚本配置未变；订阅同步失败：" + result.output.trim(), Toast.LENGTH_LONG).show();
            }
            if (nativeScriptRows != null && nativeScriptStatus != null
                    && nativeScriptRows.getParent() != null) refreshNativeScriptList(nativeScriptRows, nativeScriptStatus);
        });
    }

    private void showNativeScriptLogs() {
        runNativeModuleCommand("for f in /data/adb/privacyguard/jsruntime/local-run.log /data/adb/privacyguard/jsruntime/scheduler.log; do "
                + "if [ -f \"$f\" ]; then echo \"--- $f ---\"; tail -n 160 \"$f\"; fi; done; "
                + "test -f /data/adb/privacyguard/jsruntime/local-run.log -o -f /data/adb/privacyguard/jsruntime/scheduler.log "
                + "|| echo '暂无脚本运行日志'", 30000L, result ->
                new AlertDialog.Builder(this).setTitle("脚本运行日志")
                        .setMessage(result.output).setPositiveButton("关闭", null).show());
    }

    private void showNativeMitmStatus() {
        runNativeModuleCommand("sh \"$MP/scripts/status.sh\" json", 30000L, result -> {
            try {
                JSONObject json = new JSONObject(result.output.trim());
                new AlertDialog.Builder(this).setTitle("MITM / 证书状态")
                        .setMessage("模块版本：" + json.optString("version", "unknown")
                                + "\nDNS 转发：" + json.optString("dns_forward_status", "unknown")
                                + "\nLSPosed：" + json.optString("lsposed_status", "unknown")
                                + "\n说明：此状态接口不代表 CA 已被系统信任，也不代表 HTTPS 流量已成功解密。")
                        .setPositiveButton("关闭", null).show();
            } catch (Exception error) {
                Toast.makeText(this, "状态读取失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void startNativeVpnPolling() {
        nativeVpnHandler.removeCallbacks(nativeVpnPoll);
        if (!hookUiVisible && !settingsUiVisible && webUiReady && webView != null) {
            nativeVpnHandler.postDelayed(nativeVpnPoll, 1000L);
        }
    }

    private void stopNativeVpnPolling() {
        nativeVpnHandler.removeCallbacks(nativeVpnPoll);
    }

    /**
     * Owns the visible content for the four operational tabs. The bundled WebView
     * is kept off-screen solely as a compatibility bridge while feature backends
     * are migrated; it is never mounted as page content.
     */
    private void renderNativePage(int index) {
        if (nativePageContent == null) return;
        nativePageContent.removeAllViews();
        content = nativePageContent;
        nativeVpnControls = null;
        nativeVpnSwitch = null;
        nativeVpnState = null;
        nativeVpnNodeButton = null;
        nativeVpnModeButtons.clear();

        switch (index) {
            case 0:
                content.addView(title("VPN 控制中心", 22));
                TextView vpnIntro = new TextView(this);
                vpnIntro.setText("原生 Android 控件 · 状态由模块 status.sh 和 VPN 后端读取");
                vpnIntro.setTextColor(0xff718091);
                vpnIntro.setPadding(dp(18), 0, dp(18), dp(10));
                content.addView(vpnIntro);
                buildNativeVpnControls();
                content.addView(nativeVpnControls, new LinearLayout.LayoutParams(-1, -2));
                section("VPN / DNS / 分流策略");
                content.addView(nativeAction("高级文本 / 列表 / 选项编辑器",
                        this::showNativeVpnAdvancedEditor));
                addNativeSettingsCategory("DNS、分流与连接策略", "vpnPanel");
                buildNativeVpnSubscriptionPanel();
                addNativeSettingEntry("连接诊断", "VPN 服务、核心进程、DNS 转发与规则状态", "状态以模块 status.sh 的实时结果为准；配置已保存不等于 VPN 已运行。");
                syncNativeVpnControls();
                startNativeVpnPolling();
                break;
            case 1:
                buildNativeHostsPage();
                break;
            case 2:
                buildNativePrivacyPage();
                break;
            case 3:
                buildNativeScriptPage();
                break;
            default:
                content.addView(title("FX", 22));
                break;
        }
    }

    private void showNativeVpnAdvancedEditor() {
        runNativeModuleCommand("sh \"$MP/scripts/native-vpn-config.sh\" list", 30000L, result -> {
            if (result.exitCode != 0) {
                new AlertDialog.Builder(this).setTitle("VPN 高级设置读取失败")
                        .setMessage(result.output == null ? "无法读取设备端 [conf:vpn]。" : result.output.trim())
                        .setPositiveButton("重试", (d, w) -> showNativeVpnAdvancedEditor())
                        .setNegativeButton("关闭", null).show();
                return;
            }
            String[] lines = (result.output == null ? "" : result.output.trim()).split("\\r?\\n");
            if (lines.length == 0 || !"FXVPNCONF1".equals(lines[0])) {
                new AlertDialog.Builder(this).setTitle("VPN 高级设置读取失败")
                        .setMessage("设备端配置响应格式错误。")
                        .setPositiveButton("重试", (d, w) -> showNativeVpnAdvancedEditor())
                        .setNegativeButton("关闭", null).show();
                return;
            }
            Map<String, String> values = new HashMap<>();
            for (int i = 1; i < lines.length; i++) {
                String[] parts = lines[i].split("\\|", 2);
                if (parts.length == 2) values.put(parts[0], parts[1]);
            }
            String[] keys = {
                    "local_ip", "local_port", "mixed_port", "remote_dns", "cn_dns",
                    "test_url", "auto_update_h", "chnroute_url", "app_mode",
                    "core_ver", "core_auto", "core_bin", "log_level", "hosts_cache_min",
                    "pick_min_ms", "pick_test_timeout", "pick_max_nodes", "hide_level",
                    "hide_mtu_clamp", "hide_udp_block_all", "hide_icmp_block_all", "hide_dot_block"
            };
            List<String> availableKeys = new ArrayList<>();
            List<String> labels = new ArrayList<>();
            for (String key : keys) {
                if (!values.containsKey(key)) continue;
                availableKeys.add(key);
                String value = values.get(key);
                String shown = value.isEmpty() ? "（自动 / 空）" : value;
                labels.add(nativeVpnAdvancedLabel(key) + "\n" + shown);
            }
            String[] rows = labels.toArray(new String[0]);
            new AlertDialog.Builder(this).setTitle("VPN 高级参数")
                    .setItems(rows, (dialog, which) ->
                            showNativeVpnAdvancedItemDialog(availableKeys.get(which), values.get(availableKeys.get(which))))
                    .setPositiveButton("刷新", (dialog, which) -> showNativeVpnAdvancedEditor())
                    .setNegativeButton("关闭", null).show();
        });
    }

    private String nativeVpnAdvancedLabel(String key) {
        switch (key) {
            case "local_ip": return "本地监听地址";
            case "local_port": return "本地代理端口";
            case "mixed_port": return "HTTP / SOCKS 混合端口";
            case "remote_dns": return "远端 DNS";
            case "cn_dns": return "国内直连 DNS";
            case "test_url": return "节点延迟测试 URL";
            case "auto_update_h": return "订阅自动更新间隔（小时）";
            case "chnroute_url": return "中国大陆 IP 段源";
            case "app_mode": return "分应用代理模式";
            case "core_ver": return "sing-box 核心版本";
            case "core_auto": return "核心自动下载";
            case "core_bin": return "自定义核心路径";
            case "log_level": return "核心日志级别";
            case "hosts_cache_min": return "Hosts / 规则缓存有效期（分钟）";
            case "pick_min_ms": return "自动选优最低延迟（毫秒）";
            case "pick_test_timeout": return "节点测速超时（秒）";
            case "pick_max_nodes": return "自动选优最大节点数";
            case "hide_level": return "隐藏强度";
            case "hide_mtu_clamp": return "MTU / MSS Clamp";
            case "hide_udp_block_all": return "阻断全部 UDP";
            case "hide_icmp_block_all": return "阻断 ICMP";
            case "hide_dot_block": return "阻断 DNS-over-TLS";
            default: return key;
        }
    }

    private void showNativeVpnAdvancedItemDialog(String key, String currentValue) {
        if ("app_mode".equals(key)) {
            showNativeVpnAdvancedChoice(key, currentValue,
                    new String[]{"仅列表应用走代理", "列表应用直连"},
                    new String[]{"only", "bypass"});
            return;
        }
        if ("core_auto".equals(key) || "hide_mtu_clamp".equals(key)
                || "hide_udp_block_all".equals(key) || "hide_icmp_block_all".equals(key)
                || "hide_dot_block".equals(key)) {
            showNativeVpnAdvancedChoice(key, currentValue, new String[]{"关闭", "开启"}, new String[]{"0", "1"});
            return;
        }
        if ("log_level".equals(key)) {
            showNativeVpnAdvancedChoice(key, currentValue,
                    new String[]{"trace", "debug", "info", "warn", "error", "fatal", "panic"},
                    new String[]{"trace", "debug", "info", "warn", "error", "fatal", "panic"});
            return;
        }
        if ("hide_level".equals(key)) {
            showNativeVpnAdvancedChoice(key, currentValue,
                    new String[]{"L0 基础", "L1 默认", "L2 增强"},
                    new String[]{"0", "1", "2"});
            return;
        }

        EditText input = new EditText(this);
        input.setText(currentValue);
        input.setSingleLine(false);
        input.setMinLines(1);
        input.setSelectAllOnFocus(true);
        if ("local_port".equals(key) || "mixed_port".equals(key) || "auto_update_h".equals(key)
                || "hosts_cache_min".equals(key) || "pick_min_ms".equals(key)
                || "pick_test_timeout".equals(key) || "pick_max_nodes".equals(key)) {
            input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        }
        input.setHint(nativeVpnAdvancedHint(key));
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(nativeVpnAdvancedLabel(key))
                .setMessage(nativeVpnAdvancedDescription(key))
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) ->
                        saveNativeVpnAdvancedValue(key, input.getText().toString().trim()));
        if ("core_bin".equals(key) || "mixed_port".equals(key)) {
            builder.setNeutralButton("清空", (dialog, which) -> saveNativeVpnAdvancedValue(key, ""));
        }
        builder.show();
    }

    private String nativeVpnAdvancedHint(String key) {
        if ("local_port".equals(key)) return "1–65535";
        if ("mixed_port".equals(key)) return "留空表示本地端口 + 1";
        if ("auto_update_h".equals(key)) return "1–720 小时";
        if ("hosts_cache_min".equals(key)) return "0–10080 分钟";
        if ("pick_min_ms".equals(key)) return "1–2000 毫秒";
        if ("pick_test_timeout".equals(key)) return "1–60 秒";
        if ("pick_max_nodes".equals(key)) return "1–200";
        if ("core_bin".equals(key)) return "绝对路径；留空使用自动下载核心";
        return "";
    }

    private String nativeVpnAdvancedDescription(String key) {
        if ("local_port".equals(key) || "mixed_port".equals(key))
            return "两个端口必须不同，避免 redirect 与 mixed 入站冲突。保存后会重新生成核心配置。";
        if ("app_mode".equals(key))
            return "此模式控制分应用代理名单，不等同于广告过滤应用白名单。";
        if ("hide_level".equals(key))
            return "L0 基础、L1 默认、L2 增强。更高强度可能影响部分应用网络连接。";
        if ("core_bin".equals(key))
            return "指定可执行核心的绝对路径。路径必须由你在设备上预先放置并授权。";
        return "修改会写入 FX 的 [conf:vpn]，并触发模块重新应用；保存成功不代表 VPN 核心已经运行。";
    }

    private void showNativeVpnAdvancedChoice(String key, String currentValue,
                                              String[] labels, String[] values) {
        int selected = 0;
        for (int i = 0; i < values.length; i++) if (values[i].equals(currentValue)) selected = i;
        final int[] choice = {selected};
        new AlertDialog.Builder(this).setTitle(nativeVpnAdvancedLabel(key))
                .setSingleChoiceItems(labels, selected, (dialog, which) -> choice[0] = which)
                .setNegativeButton("取消", null)
                .setPositiveButton("应用", (dialog, which) ->
                        saveNativeVpnAdvancedValue(key, values[choice[0]]))
                .show();
    }

    private void saveNativeVpnAdvancedValue(String key, String value) {
        String command = "sh \"$MP/scripts/native-vpn-config.sh\" set "
                + shellQuote(key) + " " + shellQuote(value);
        runNativeModuleCommand(command, 120000L, result -> {
            if (result.exitCode == 0) {
                Toast.makeText(this, "VPN 参数已保存并应用。", Toast.LENGTH_LONG).show();
                showNativeVpnAdvancedEditor();
                syncNativeVpnControls();
            } else {
                new AlertDialog.Builder(this).setTitle("VPN 参数保存失败")
                        .setMessage(result.output == null ? "设备端拒绝了本次修改。" : result.output.trim())
                        .setPositiveButton("知道了", null).show();
            }
        });
    }

    private void refreshNativeModuleStatus(TextView target, int pageIndex) {
        if (target == null || isFinishing() || isDestroyed()) return;
        target.setText("正在读取设备端状态…");
        Thread worker = new Thread(() -> {
            RootAccess.Result result = RootAccess.execute(
                    "MP=; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do [ -f \"$d/module.prop\" ] && { MP=\"$d\"; break; }; done; [ -n \"$MP\" ] || { echo 'FX_MODULE_NOT_FOUND'; exit 20; }; sh \"$MP/scripts/status.sh\" json",
                    30000L, 128 * 1024);
            String display;
            if (result.exitCode != 0) {
                display = "无法读取设备端模块状态（退出码 " + result.exitCode + "）。\n"
                        + (result.output == null ? "" : result.output.trim());
            } else {
                try {
                    JSONObject state = new JSONObject(result.output.trim());
                    StringBuilder summary = new StringBuilder();
                    summary.append("FX 模块状态读取成功\n");
                    if (pageIndex == 1) {
                        summary.append("Hosts / 规则：").append(state.optString("hosts_status", "状态字段未提供")).append('\n');
                        summary.append("广告过滤：").append(state.optString("ad_status", "状态字段未提供")).append('\n');
                    } else if (pageIndex == 2) {
                        summary.append("隐私保护：").append(state.optString("privacy_status", "状态字段未提供")).append('\n');
                        summary.append("FX 应用 UID：").append(android.os.Process.myUid()).append('\n');
                    } else {
                        summary.append("脚本引擎：").append(state.optString("script_engine_status", "状态字段未提供")).append('\n');
                        summary.append("QuickJS：").append(state.optString("quickjs_status", "状态字段未提供")).append('\n');
                    }
                    summary.append("\n完整后端状态：\n").append(state.toString(2));
                    display = summary.toString();
                } catch (Exception malformed) {
                    display = "设备端返回了非 JSON 状态：\n"
                            + (result.output == null ? "" : result.output.trim());
                }
            }
            if (display.length() > 12000) display = display.substring(0, 12000) + "\n…（已截断）";
            final String message = display;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || target.getParent() == null) return;
                target.setText(message);
            });
        }, "fx-native-page-status-" + pageIndex);
        worker.setDaemon(true);
        worker.start();
    }

    /** Native VPN controls call the existing, validated WebUI transaction pipeline.
     *  The old HTML switch/mode strip is hidden to prevent duplicate controls. */
    private void buildNativeVpnControls() {
        nativeVpnControls = new LinearLayout(this);
        nativeVpnControls.setOrientation(LinearLayout.VERTICAL);
        nativeVpnControls.setPadding(dp(14), dp(10), dp(14), dp(10));
        nativeVpnControls.setBackgroundColor(0xfff4f6f8);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(10), dp(14), dp(10));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xffffffff);
        bg.setCornerRadius(dp(18));
        bg.setStroke(dp(1), 0x1f607d8b);
        card.setBackground(bg);

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(this);
        title.setText("VPN 控制");
        title.setTextSize(17);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xff17212b);
        head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        nativeVpnSwitch = new Switch(this);
        nativeVpnSwitch.setText("代理总开关");
        nativeVpnSwitch.setTextColor(0xff263238);
        nativeVpnSwitch.setThumbTintList(android.content.res.ColorStateList.valueOf(0xffffffff));
        nativeVpnSwitch.setTrackTintList(new android.content.res.ColorStateList(
                new int[][] { new int[] { android.R.attr.state_checked }, new int[] {} },
                new int[] { 0x6678a9d8, 0x33ffffff }));
        nativeVpnSwitch.setOnCheckedChangeListener((button, checked) -> {
            if (syncingNativeVpn) return;
            button.setEnabled(false);
            nativeVpnState.setText("正在请求 VPN 后端切换…");
            invokeNativeVpnApi("setEnabled", Boolean.toString(checked));
        });
        head.addView(nativeVpnSwitch);
        card.addView(head);

        nativeVpnState = new TextView(this);
        nativeVpnState.setText("正在读取 VPN 后端状态…");
        nativeVpnState.setTextSize(12);
        nativeVpnState.setTextColor(0xff667784);
        nativeVpnState.setPadding(0, dp(4), 0, dp(8));
        card.addView(nativeVpnState);

        nativeVpnNodeButton = new Button(this);
        nativeVpnNodeButton.setAllCaps(false);
        nativeVpnNodeButton.setText("选择节点 · 尚未选择");
        nativeVpnNodeButton.setTextSize(13);
        nativeVpnNodeButton.setMaxLines(1);
        nativeVpnNodeButton.setEllipsize(android.text.TextUtils.TruncateAt.END);
        nativeVpnNodeButton.setOnClickListener(v -> showNativeVpnNodePicker());
        card.addView(nativeVpnNodeButton, new LinearLayout.LayoutParams(-1, dp(44)));
        Button latencyTest = nativeAction("测试当前节点延迟", null);
        latencyTest.setOnClickListener(v -> testNativeVpnSelectedNodeLatency(latencyTest));
        card.addView(latencyTest, new LinearLayout.LayoutParams(-1, dp(42)));

        LinearLayout modes = new LinearLayout(this);
        modes.setGravity(Gravity.CENTER_VERTICAL);
        modes.setOrientation(LinearLayout.HORIZONTAL);
        String[] labels = {"直连", "全局", "规则"};
        String[] values = {"direct", "global", "rule"};
        nativeVpnModeButtons.clear();
        for (int i = 0; i < values.length; i++) {
            final String mode = values[i];
            Button button = new Button(this);
            button.setAllCaps(false);
            button.setText(labels[i]);
            button.setTextSize(12);
            button.setMinHeight(dp(40));
            button.setPadding(dp(2), 0, dp(2), 0);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(42), 1);
            lp.setMargins(dp(2), dp(6), dp(2), 0);
            button.setOnClickListener(v -> {
                button.setEnabled(false);
                invokeNativeVpnApi("setMode", org.json.JSONObject.quote(mode));
            });
            nativeVpnModeButtons.add(button);
            modes.addView(button, lp);
        }
        card.addView(modes);
        nativeVpnControls.addView(card, new LinearLayout.LayoutParams(-1, -2));
    }

    private void testNativeVpnSelectedNodeLatency(Button button) {
        if (webView == null || !webUiReady) {
            Toast.makeText(this, "VPN 节点列表尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        button.setEnabled(false);
        button.setText("读取当前节点…");
        webView.evaluateJavascript("(function(){return window.FXNativeVpn?window.FXNativeVpn.snapshot():'{}'})()", value -> {
            if (isFinishing() || isDestroyed()) return;
            try {
                Object decoded = new org.json.JSONTokener(value == null ? "null" : value).nextValue();
                if (!(decoded instanceof String)) throw new IllegalStateException("节点状态格式错误");
                JSONObject snapshot = new JSONObject((String) decoded);
                org.json.JSONArray nodes = snapshot.optJSONArray("nodes");
                JSONObject selected = null;
                if (nodes != null) for (int i = 0; i < nodes.length(); i++) {
                    JSONObject node = nodes.optJSONObject(i);
                    if (node != null && node.optBoolean("selected", false)) { selected = node; break; }
                }
                if (selected == null) throw new IllegalStateException("请先选择一个代理节点；直连模式无需测速");
                String proto = selected.optString("proto", "");
                String host = selected.optString("host", "");
                String port = selected.optString("port", "");
                if (proto.isEmpty() || host.isEmpty() || !port.matches("[0-9]{1,5}")
                        || Integer.parseInt(port) < 1 || Integer.parseInt(port) > 65535) {
                    throw new IllegalStateException("当前节点缺少有效的协议、主机或端口信息");
                }
                button.setText("正在测试 " + host + ":" + port + "…");
                runNativeModuleCommand("sh \"$MP/scripts/vpntest.sh\" "
                        + shellQuote(proto) + " " + shellQuote(host) + " " + port,
                        15000L, result -> {
                    button.setEnabled(true);
                    try {
                        if (result.exitCode != 0) throw new IllegalStateException(result.output);
                        JSONObject measured = new JSONObject(result.output.trim());
                        int ms = measured.optInt("ms", -2);
                        if (ms >= 0) {
                            String latency = ms == 0 ? "<1 ms" : ms + " ms";
                            button.setText("延迟 " + latency + " · 重新测试");
                            Toast.makeText(this, "节点延迟：" + latency, Toast.LENGTH_SHORT).show();
                        } else if (ms == -1) {
                            button.setText("节点不可达 · 重新测试");
                        } else {
                            button.setText("测速不可用 · 重新测试");
                            Toast.makeText(this, measured.optString("detail", "设备缺少 curl / nc 测速工具"),
                                    Toast.LENGTH_LONG).show();
                        }
                    } catch (Exception error) {
                        button.setText("测速失败 · 重新测试");
                        Toast.makeText(this, "节点测速失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
                    }
                });
            } catch (Exception error) {
                button.setEnabled(true);
                button.setText("测试当前节点延迟");
                Toast.makeText(this, error.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void buildNativeVpnSubscriptionPanel() {
        section("节点与订阅");
        TextView status = new TextView(this);
        status.setText("正在读取 VPN 订阅…");
        status.setTextColor(0xff718091);
        status.setPadding(dp(16), dp(6), dp(16), dp(8));
        content.addView(status);
        nativeVpnSubStatus = status;

        LinearLayout rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        content.addView(rows);
        nativeVpnSubRows = rows;

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(nativeAction("添加订阅 / 节点", this::showNativeVpnSubscriptionDialog),
                new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(nativeAction("更新全部", this::refreshAllNativeVpnSubscriptions),
                new LinearLayout.LayoutParams(0, -2, 1));
        content.addView(actions);
        refreshNativeVpnSubscriptions();
    }

    private void refreshNativeVpnSubscriptions() {
        if (nativeVpnSubRows == null || nativeVpnSubStatus == null) return;
        if (webView == null || !webUiReady) {
            nativeVpnSubStatus.setText("订阅配置桥正在初始化…");
            return;
        }
        nativeVpnSubStatus.setText("正在读取订阅列表…");
        String js = "(function(){if(typeof subsLoad!=='function')return JSON.stringify({ready:false});"
                + "var a=subsLoad()||[];return JSON.stringify({ready:true,items:a.map(function(s,i){"
                + "return {i:i,url:String(s.url||''),note:String(s.note||''),on:!!s.on};})});})()";
        webView.evaluateJavascript(js, value -> {
            try {
                Object decoded = new org.json.JSONTokener(value == null ? "null" : value).nextValue();
                if (!(decoded instanceof String)) throw new IllegalStateException("订阅列表响应格式错误");
                JSONObject snapshot = new JSONObject((String) decoded);
                if (!snapshot.optBoolean("ready", false)) throw new IllegalStateException("订阅配置尚未就绪");
                org.json.JSONArray items = snapshot.optJSONArray("items");
                nativeVpnSubRows.removeAllViews();
                int count = items == null ? 0 : items.length();
                int enabled = 0;
                for (int i = 0; i < count; i++) {
                    JSONObject item = items.optJSONObject(i);
                    if (item == null) continue;
                    final int index = item.optInt("i", i);
                    final String url = item.optString("url", "");
                    final String note = item.optString("note", "");
                    final boolean on = item.optBoolean("on", false);
                    if (on) enabled++;
                    LinearLayout row = new LinearLayout(this);
                    row.setOrientation(LinearLayout.VERTICAL);
                    row.setPadding(dp(12), dp(8), dp(12), dp(8));
                    row.setBackground(uiPanelDrawable());
                    TextView title = new TextView(this);
                    title.setText(note.isEmpty() ? url : note);
                    title.setTextSize(14);
                    title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                    title.setTextColor(0xff17212b);
                    TextView source = new TextView(this);
                    source.setText(url);
                    source.setTextSize(10);
                    source.setTextColor(0xff718091);
                    source.setMaxLines(2);
                    source.setEllipsize(android.text.TextUtils.TruncateAt.END);
                    row.addView(title);
                    row.addView(source);
                    LinearLayout ops = new LinearLayout(this);
                    ops.setGravity(Gravity.CENTER_VERTICAL);
                    Switch toggle = new Switch(this);
                    toggle.setText("启用");
                    toggle.setChecked(on);
                    toggle.setOnCheckedChangeListener((button, checked) ->
                            setNativeVpnSubscriptionEnabled(index, checked));
                    ops.addView(toggle, new LinearLayout.LayoutParams(0, -2, 1));
                    ops.addView(nativeAction("更新", () -> updateNativeVpnSubscription(index, url)));
                    ops.addView(nativeAction("详情", () -> new AlertDialog.Builder(this)
                            .setTitle(note.isEmpty() ? "VPN 订阅" : note)
                            .setMessage(url).setPositiveButton("关闭", null).show()));
                    ops.addView(nativeAction("删除", () -> new AlertDialog.Builder(this)
                            .setMessage("删除该订阅？仅清理确认只属于此订阅的节点。")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除", (d, w) -> deleteNativeVpnSubscription(index)).show()));
                    row.addView(ops);
                    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
                    lp.setMargins(dp(12), dp(3), dp(12), dp(4));
                    nativeVpnSubRows.addView(row, lp);
                }
                nativeVpnSubStatus.setText("订阅：" + count + " · 已启用：" + enabled
                        + " · 节点数以 VPN 后端状态为准");
                if (count == 0) {
                    TextView empty = new TextView(this);
                    empty.setText("暂无订阅。可添加机场 URL 或直接导入 vmess / vless / trojan / ss / Clash 节点链接。");
                    empty.setTextColor(0xff718091);
                    empty.setPadding(dp(16), dp(12), dp(16), dp(12));
                    nativeVpnSubRows.addView(empty);
                }
            } catch (Exception error) {
                nativeVpnSubStatus.setText("订阅列表读取失败：" + error.getMessage());
            }
        });
    }

    private void showNativeVpnSubscriptionDialog() {
        EditText input = new EditText(this);
        input.setSingleLine(false);
        input.setMinLines(2);
        input.setHint("粘贴机场订阅 URL 或代理节点链接");
        new AlertDialog.Builder(this).setTitle("添加 VPN 订阅 / 节点")
                .setMessage("支持 Base64 / URI 列表 / Clash YAML 订阅，以及 vmess、vless、trojan、ss、ssr、hysteria2、tuic、anytls、socks5 节点链接。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("导入", (d, w) ->
                        startNativeVpnSubscriptionImport(input.getText().toString().trim()))
                .show();
    }

    private void startNativeVpnSubscriptionImport(String raw) {
        if (raw == null || raw.isEmpty()) {
            Toast.makeText(this, "订阅地址或节点链接不能为空", Toast.LENGTH_SHORT).show();
            return;
        }
        if (webView == null || !webUiReady) {
            Toast.makeText(this, "VPN 订阅运行桥尚未就绪", Toast.LENGTH_LONG).show();
            return;
        }
        final int generation = ++nativeVpnSubOperationGeneration;
        if (nativeVpnSubStatus != null) nativeVpnSubStatus.setText("正在下载 / 解析订阅并保存节点…");
        String js = "(function(){var u=" + JSONObject.quote(raw) + ";"
                + "window.__fxNativeVpnSubResult=null;"
                + "var direct=/^(vmess|vless|trojan|ss|ssr|hysteria2?|tuic|anytls|socks5?):\\/\\//i.test(u);"
                + "var task=direct?Promise.resolve(u):window.fetchSub(u);"
                + "task.then(function(body){if(!String(body||'').trim())throw new Error('订阅内容为空');"
                + "return window.importFromText(direct?'':u,body);})"
                + ".then(function(ok){window.__fxNativeVpnSubResult=JSON.stringify({ok:ok===true});})"
                + ".catch(function(e){window.__fxNativeVpnSubResult=JSON.stringify({ok:false,error:String((e&&e.message)||e)});});"
                + "return true;})()";
        webView.evaluateJavascript(js, value -> {
            if (value == null || "false".equals(value)) {
                finishNativeVpnSubscriptionImport(generation, false, "订阅导入任务未能启动");
                return;
            }
            pollNativeVpnSubscriptionImport(generation, System.currentTimeMillis() + 120000L);
        });
    }

    private void pollNativeVpnSubscriptionImport(int generation, long deadline) {
        if (generation != nativeVpnSubOperationGeneration || isFinishing() || isDestroyed()) return;
        if (webView == null || !webUiReady) {
            finishNativeVpnSubscriptionImport(generation, false, "订阅运行桥已断开");
            return;
        }
        webView.evaluateJavascript("(function(){var r=window.__fxNativeVpnSubResult;"
                + "if(!r)return null;window.__fxNativeVpnSubResult=null;return r;})()", value -> {
            if (generation != nativeVpnSubOperationGeneration || isFinishing() || isDestroyed()) return;
            if (value == null || "null".equals(value)) {
                if (System.currentTimeMillis() >= deadline) {
                    finishNativeVpnSubscriptionImport(generation, false, "订阅导入超时，请查看运行日志");
                } else {
                    nativeVpnHandler.postDelayed(
                            () -> pollNativeVpnSubscriptionImport(generation, deadline), 400L);
                }
                return;
            }
            try {
                Object decoded = new org.json.JSONTokener(value).nextValue();
                if (!(decoded instanceof String)) throw new IllegalStateException("导入结果格式错误");
                JSONObject result = new JSONObject((String) decoded);
                finishNativeVpnSubscriptionImport(generation, result.optBoolean("ok", false),
                        result.optString("error", "订阅导入失败"));
            } catch (Exception error) {
                finishNativeVpnSubscriptionImport(generation, false, error.getMessage());
            }
        });
    }

    private void finishNativeVpnSubscriptionImport(int generation, boolean success, String error) {
        if (generation != nativeVpnSubOperationGeneration || isFinishing() || isDestroyed()) return;
        if (success) {
            Toast.makeText(this, "VPN 订阅 / 节点导入成功", Toast.LENGTH_LONG).show();
            refreshNativeVpnSubscriptions();
            syncNativeVpnControls();
        } else {
            Toast.makeText(this, "VPN 订阅导入失败：" + error, Toast.LENGTH_LONG).show();
            if (nativeVpnSubStatus != null) nativeVpnSubStatus.setText("导入失败：" + error);
        }
    }

    private void setNativeVpnSubscriptionEnabled(int index, boolean enabled) {
        if (webView == null || !webUiReady) return;
        String js = "(function(){if(typeof subsLoad!=='function'||typeof subsSave!=='function')return false;"
                + "var a=subsLoad();if(!a[" + index + "])return false;a[" + index + "].on="
                + (enabled ? "true" : "false") + ";subsSave(a);pgSave();renderSubs();vpnStatus();return true;})()";
        webView.evaluateJavascript(js, value ->
                nativeVpnHandler.postDelayed(this::refreshNativeVpnSubscriptions, 500L));
    }

    private void deleteNativeVpnSubscription(int index) {
        if (webView == null || !webUiReady) return;
        String js = "(function(){if(typeof subsLoad!=='function'||typeof subsSave!=='function')return false;"
                + "var a=subsLoad();if(!a[" + index + "])return false;var u=a[" + index + "].url;"
                + "a.splice(" + index + ",1);subsSave(a);var n=currentNodes();"
                + "n.forEach(function(x){if(x._sourceTracked&&Array.isArray(x._sources))x._sources=x._sources.filter(function(y){return y!==u})});"
                + "n=n.filter(function(x){return !(x._sourceTracked&&Array.isArray(x._sources)&&x._sources.length===0)});"
                + "saveNodes(n);pgSave();renderSubs();renderNodes();vpnStatus();return true;})()";
        webView.evaluateJavascript(js, value -> {
            Toast.makeText(this, "订阅已删除", Toast.LENGTH_SHORT).show();
            nativeVpnHandler.postDelayed(this::refreshNativeVpnSubscriptions, 500L);
            syncNativeVpnControls();
        });
    }

    private void updateNativeVpnSubscription(int index, String url) {
        if (webView == null || !webUiReady || url == null || url.isEmpty()) return;
        final int generation = ++nativeVpnSubOperationGeneration;
        if (nativeVpnSubStatus != null) nativeVpnSubStatus.setText("正在更新订阅…");
        String js = "(function(){var u=" + JSONObject.quote(url)
                + ";window.__fxNativeVpnSubResult=null;"
                + "window.fetchSub(u).then(function(body){if(!String(body||'').trim())throw new Error('订阅内容为空');"
                + "return window.importFromText(u,body);})"
                + ".then(function(ok){window.__fxNativeVpnSubResult=JSON.stringify({ok:ok===true});})"
                + ".catch(function(e){window.__fxNativeVpnSubResult=JSON.stringify({ok:false,error:String((e&&e.message)||e)});});"
                + "return true;})()";
        webView.evaluateJavascript(js, value -> {
            if (value == null || "false".equals(value)) {
                finishNativeVpnSubscriptionImport(generation, false, "订阅更新任务未能启动");
                return;
            }
            pollNativeVpnSubscriptionImport(generation, System.currentTimeMillis() + 120000L);
        });
    }

    private void refreshAllNativeVpnSubscriptions() {
        if (webView == null || !webUiReady) {
            Toast.makeText(this, "VPN 订阅运行桥尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        webView.evaluateJavascript("(function(){if(typeof applyRun!=='function')return false;"
                + "applyRun('vpn-sub',{label:'正在更新全部 VPN 订阅…'});return true;})()", value -> {
            Toast.makeText(this, "已请求更新全部订阅", Toast.LENGTH_LONG).show();
            nativeVpnHandler.postDelayed(this::refreshNativeVpnSubscriptions, 2500L);
        });
    }

    private static String shellQuote(String value) {
        return "'" + String.valueOf(value).replace("'", "'\\''") + "'";
    }

    private String nativeVpnRootCommand(String action, String value) {
        String module = "MP=; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do [ -f \"$d/module.prop\" ] && { MP=\"$d\"; break; }; done; [ -n \"$MP\" ] || exit 20; ";
        String util = ". \"$MP/scripts/util.sh\" || exit 21; ";
        if ("status".equals(action)) return module + "sh \"$MP/scripts/status.sh\"";
        if ("mode".equals(action)) {
            String mode = shellQuote(value);
            return module + util
                    + "old_mode=$(pg_get vpn_mode direct); "
                    + "pg_set vpn_mode " + mode + " || exit 31; "
                    + "new_mode=" + mode + "; "
                    + "if [ \"$new_mode\" = direct ]; then sh \"$MP/scripts/apply.sh\" fast; "
                    + "else node=$(pg_get vpn_node '__FX_NO_NODE__'); [ \"$node\" = '__FX_NO_NODE__' ] && node=''; "
                    + "if [ -z \"$node\" ]; then pg_set vpn_mode \"$old_mode\" || :; echo 'VPN_NO_NODE_SELECTED'; exit 32; fi; "
                    + "sh \"$MP/scripts/apply.sh\"; fi; rc=$?; "
                    + "if [ \"$rc\" -ne 0 ]; then pg_set vpn_mode \"$old_mode\"; "
                    + "if [ \"$old_mode\" = direct ]; then sh \"$MP/scripts/apply.sh\" fast >/dev/null 2>&1; "
                    + "else sh \"$MP/scripts/apply.sh\" >/dev/null 2>&1; fi; fi; exit \"$rc\"";
        }
        if ("node".equals(action)) {
            String key = shellQuote(value);
            return module + util
                    + "old_node=$(pg_get vpn_node '__FX_NO_NODE__'); [ \"$old_node\" = '__FX_NO_NODE__' ] && old_node=''; mode=$(pg_get vpn_mode direct); "
                    + "pg_set vpn_node " + key + " || exit 31; "
                    + "if [ \"$mode\" = direct ]; then exit 0; fi; "
                    + "sh \"$MP/scripts/apply.sh\"; rc=$?; "
                    + "if [ \"$rc\" -ne 0 ]; then pg_set vpn_node \"$old_node\"; "
                    + "if [ \"$mode\" = direct ]; then sh \"$MP/scripts/apply.sh\" fast >/dev/null 2>&1; "
                    + "else sh \"$MP/scripts/apply.sh\" >/dev/null 2>&1; fi; fi; exit \"$rc\"";
        }
        return "exit 22";
    }

    private void invokeNativeVpnApi(String method, String argument) {
        final String action;
        final String value;
        try {
            if ("setMode".equals(method)) {
                Object decoded = new org.json.JSONTokener(argument).nextValue();
                if (!(decoded instanceof String)) throw new IllegalArgumentException("模式参数无效");
                value = (String) decoded;
                if (!java.util.Arrays.asList("direct", "global", "rule", "tun").contains(value))
                    throw new IllegalArgumentException("不支持的 VPN 模式");
                action = "mode";
            } else if ("setEnabled".equals(method)) {
                boolean enabled = Boolean.parseBoolean(argument);
                value = enabled ? ("direct".equals(lastNativeVpnMode) ? "global" : lastNativeVpnMode) : "direct";
                action = "mode";
            } else if ("selectNode".equals(method)) {
                Object decoded = new org.json.JSONTokener(argument).nextValue();
                if (!(decoded instanceof String)) throw new IllegalArgumentException("节点参数无效");
                value = (String) decoded;
                if (!value.matches("[A-Za-z0-9._:-]{1,512}"))
                    throw new IllegalArgumentException("节点标识包含非法字符");
                action = "node";
            } else {
                throw new IllegalArgumentException("未知 VPN 操作");
            }
        } catch (Exception invalid) {
            Toast.makeText(this, "VPN 操作参数错误：" + invalid.getMessage(), Toast.LENGTH_SHORT).show();
            return;
        }
        if (nativeVpnOperationBusy) return;
        nativeVpnOperationBusy = true;
        if (nativeVpnSwitch != null) nativeVpnSwitch.setEnabled(false);
        if (nativeVpnNodeButton != null) nativeVpnNodeButton.setEnabled(false);
        for (Button button : nativeVpnModeButtons) button.setEnabled(false);
        if (nativeVpnState != null) nativeVpnState.setText("正在通过 Root 后端应用 VPN 设置…");
        nativeVpnExecutor.execute(() -> {
            final RootAccess.Result result;
            try {
                result = RootAccess.execute(nativeVpnRootCommand(action, value),
                        120000L, 1024 * 1024);
            } catch (RuntimeException failure) {
                runOnUiThread(() -> {
                    nativeVpnOperationBusy = false;
                    if (isFinishing() || isDestroyed()) return;
                    Toast.makeText(this, "VPN 操作异常：" + failure.getMessage(),
                            Toast.LENGTH_LONG).show();
                    syncNativeVpnControls();
                });
                return;
            }
            runOnUiThread(() -> {
                nativeVpnOperationBusy = false;
                if (isFinishing() || isDestroyed()) return;
                if (result.exitCode != 0) {
                    Toast.makeText(this, "VPN 操作失败（退出码 " + result.exitCode + "）：" + result.output,
                            Toast.LENGTH_LONG).show();
                }
                refreshWebUiAfterNativeVpn();
                syncNativeVpnControls();
            });
        });
    }

    private void refreshWebUiAfterNativeVpn() {
        if (webView == null || !webUiReady || isFinishing() || isDestroyed()) return;
        // Reload the persisted module config for display only. Native controls never
        // invoke WebUI actions; this prevents the WebView's cached node/mode model
        // from showing stale values after the direct RootAccess transaction.
        webView.evaluateJavascript(
                "(function(){if(typeof pgLoad!=='function')return false;"
                + "return pgLoad().then(function(){"
                + "if(typeof pgApplySwitches==='function')pgApplySwitches();"
                + "if(typeof pgRenderLists==='function')pgRenderLists();"
                + "if(typeof renderNodes==='function')renderNodes();"
                + "if(typeof vpnStatus==='function')vpnStatus();"
                + "if(typeof pgRefreshStatus==='function')return pgRefreshStatus();"
                + "return true;});})()", null);
    }

    private void showNativeVpnNodePicker() {
        if (webView == null || !webUiReady) {
            Toast.makeText(this, "VPN 后端尚未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        webView.evaluateJavascript("(function(){return window.FXNativeVpn?window.FXNativeVpn.snapshot():'{}'})()", value -> {
            if (isFinishing() || isDestroyed() || value == null) return;
            try {
                Object decoded = new org.json.JSONTokener(value).nextValue();
                if (!(decoded instanceof String)) throw new IllegalStateException("节点数据格式错误");
                org.json.JSONObject snapshot = new org.json.JSONObject((String) decoded);
                org.json.JSONArray nodes = snapshot.optJSONArray("nodes");
                if (nodes == null || nodes.length() == 0) {
                    new AlertDialog.Builder(this).setTitle("选择节点")
                            .setMessage("当前没有可用节点。直连模式不需要节点；请先导入订阅后再选择代理节点。")
                            .setPositiveButton("知道了", null).show();
                    return;
                }
                List<String> labels = new ArrayList<>();
                List<Integer> indices = new ArrayList<>();
                int selected = -1;
                for (int i = 0; i < nodes.length(); i++) {
                    org.json.JSONObject node = nodes.optJSONObject(i);
                    if (node == null || !node.optBoolean("enabled", false)) continue;
                    String nodeName = node.optString("name", "").trim();
                    String endpoint = node.optString("host", "") + ":" + node.optString("port", "");
                    String label = nodeName.isEmpty() ? endpoint : nodeName + " · " + endpoint;
                    if (label.length() > 80) label = label.substring(0, 77) + "…";
                    labels.add(label);
                    indices.add(node.optInt("index", i));
                    if (node.optBoolean("selected", false)) selected = labels.size() - 1;
                }
                if (labels.isEmpty()) {
                    new AlertDialog.Builder(this).setTitle("选择节点").setMessage("没有启用的可用节点。")
                            .setPositiveButton("知道了", null).show();
                    return;
                }
                final int[] chosen = { selected };
                new AlertDialog.Builder(this).setTitle("选择 VPN 节点")
                        .setSingleChoiceItems(labels.toArray(new String[0]), selected,
                                (dialog, which) -> chosen[0] = which)
                        .setPositiveButton("应用", (dialog, which) -> {
                            int nodeIndex = indices.get(chosen[0]);
                            org.json.JSONObject selectedNode = nodes.optJSONObject(nodeIndex);
                            if (selectedNode != null) invokeNativeVpnApi("selectNode",
                                    org.json.JSONObject.quote(selectedNode.optString("key", "")));
                        })
                        .setNegativeButton("取消", null).show();
            } catch (Exception e) {
                Toast.makeText(this, "读取节点列表失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }

    private void syncNativeVpnControls() {
        if (nativeVpnSwitch == null || nativeVpnState == null || isFinishing() || isDestroyed()
                || nativeVpnOperationBusy || !nativeVpnStatusQueued.compareAndSet(false, true)) return;
        nativeVpnExecutor.execute(() -> {
            RootAccess.Result result;
            try {
                result = RootAccess.execute(nativeVpnRootCommand("status", ""), 20000L, 1024 * 1024);
            } finally {
                nativeVpnStatusQueued.set(false);
            }
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || nativeVpnSwitch == null) return;
                try {
                    if (result.exitCode != 0) throw new IllegalStateException(result.output);
                    org.json.JSONObject state = new org.json.JSONObject(result.output.trim());
                    String mode = state.optString("vpn_mode", "direct");
                    lastNativeVpnMode = mode;
                    boolean liveOn = state.optBoolean("vpn_on", false);
                    String modeLabel = "direct".equals(mode) ? "直连"
                            : "global".equals(mode) ? "全局"
                            : "rule".equals(mode) ? "规则"
                            : "tun".equals(mode) ? "TUN" : mode;
                    syncingNativeVpn = true;
                    nativeVpnSwitch.setChecked(!"direct".equals(mode) && liveOn);
                    syncingNativeVpn = false;
                    String live = "direct".equals(mode) ? "直连：未接管流量"
                            : liveOn ? "status.sh 确认：代理正在运行"
                            : "已保存代理模式，但后端尚未确认运行";
                    String node = state.optString("vpn_node", "");
                    nativeVpnState.setText("模式：" + modeLabel + " · " + live
                            + (node.isEmpty() ? " · 尚未选择节点" : " · 节点已配置"));
                    nativeVpnSwitch.setEnabled(true);
                    if (nativeVpnNodeButton != null) {
                        nativeVpnNodeButton.setEnabled(true);
                        nativeVpnNodeButton.setText(node.isEmpty() ? "选择节点 · 尚未选择" : "更换节点 · 已选择");
                        nativeVpnNodeButton.setContentDescription(node.isEmpty()
                                ? "尚未选择 VPN 节点，点击选择"
                                : "已选择 VPN 节点，点击更换");
                    }
                    String[] modes = {"direct", "global", "rule"};
                    for (int i = 0; i < nativeVpnModeButtons.size() && i < modes.length; i++) {
                        boolean active = modes[i].equals(mode);
                        Button button = nativeVpnModeButtons.get(i);
                        button.setEnabled(true);
                        button.setSelected(active);
                        button.setBackgroundTintList(android.content.res.ColorStateList.valueOf(
                                active ? 0xffdcecff : 0xffeef2f5));
                        button.setTextColor(active ? 0xff155a9c : 0xff37474f);
                    }
                } catch (Exception error) {
                    syncingNativeVpn = false;
                    nativeVpnSwitch.setEnabled(false);
                    nativeVpnState.setText("VPN 状态读取失败；Root 后端未返回有效 status.sh 状态");
                }
            });
        });
    }

    private void pauseAndDetachWebView() {
        stopNativeVpnPolling();
        nativeVpnSubOperationGeneration++;
        if (webView == null) return;
        webView.onPause();
        webView.pauseTimers();
        ViewParent parent = webView.getParent();
        if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
    }

    private void mountNativeShell(View pageContent) {
        androidx.compose.ui.platform.ComposeView shell =
                new androidx.compose.ui.platform.ComposeView(this);
        // ComposeView is created and composed before setContentView attaches it.
        // Explicitly propagate this ComponentActivity's owners so Compose can
        // create a lifecycle-aware WindowRecomposer on all supported ROMs.
        androidx.lifecycle.ViewTreeLifecycleOwner.set(shell, this);
        androidx.lifecycle.ViewTreeViewModelStoreOwner.set(shell, this);
        androidx.savedstate.ViewTreeSavedStateRegistryOwner.set(shell, this);
        FxNativeAppShellKt.installFxNativeAppShell(
                shell, pageContent, selectedBottomTab, uiMode,
                index -> {
                    handleNativeTabSelection(index);
                    return kotlin.Unit.INSTANCE;
                });
        setContentView(shell);
    }

    private void handleNativeTabSelection(int index) {
        if (index == 5) {
            selectedBottomTab = 5;
            showSettings();
        } else if (index == 4) {
            selectedBottomTab = 4;
            showAppList();
        } else if (index >= 0 && index <= 3) {
            selectedBottomTab = index;
            lastWebTabIndex = index;
            if (hookUiVisible || settingsUiVisible || nativePageContent == null) showWebDashboard();
            else renderNativePage(index);
        }
    }

    private void styleBottomItem(TextView item, int index) {
        boolean selected = index == selectedBottomTab;
        int accent = "glass".equals(uiMode) ? 0xff276b9a : "miuix".equals(uiMode) ? 0xff3478f6 : 0xff1769aa;
        item.setTextColor(selected ? accent : 0xff526170);
        item.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
    }

    private void navigateWebPage(String pageId) {
        if (webView == null) return;
        if (!webUiReady) {
            pendingWebPage = pageId;
            // A failed first load must be retryable from the native tab bar.
            if (!webViewLoaded) {
                webViewLoaded = true;
                webView.loadUrl("https://appassets.androidplatform.net/assets/webroot/index.html");
            }
            return;
        }
        String tab;
        switch (pageId) {
            case "pageVpn": tab = "vpn"; break;
            case "pageHosts": tab = "hosts"; break;
            case "pageAd": tab = "ad"; break; // compatibility with older bundled WebUI builds
            case "pagePrivacy": tab = "privacy"; break;
            case "pageScript": tab = "script"; break;
            case "pageMore": tab = "more"; break;
            default: return;
        }
        String script = "(function(){"
                + "var id=" + JSONObject.quote(pageId) + ";"
                + "var page=document.getElementById(id);"
                + "if(id==='pageHosts'&&!page){id='pageAd';page=document.getElementById(id);}"
                + "if(!page||!page.children.length)return false;"
                + "var navTab='" + (tab.equals("hosts") ? "ad" : tab) + "';"
                + "try{var ae=document.activeElement;if(ae&&/^(INPUT|TEXTAREA|SELECT)$/.test(ae.tagName))ae.blur();}catch(e){}"
                + "['editor','stylePanel','langPanel','confirmBar'].forEach(function(x){var el=document.getElementById(x);if(el)el.classList.remove('on');});"
                + "var oldPage=document.querySelector('#screen .page.on');if(oldPage)oldPage.scrollTop=0;"
                + "var pages=document.querySelectorAll('#screen .page');"
                + "for(var p=0;p<pages.length;p++)pages[p].classList.remove('on');"
                + "page.classList.add('on');page.scrollTop=0;"
                + "var navItems=document.querySelectorAll('#screen .nav-item');"
                + "for(var n=0;n<navItems.length;n++){"
                + "navItems[n].classList.toggle('on',navItems[n].getAttribute('data-tab')===navTab);}"
                + "window.currentTab=navTab;"
                + "var title=document.getElementById('pageTitle');"
                + "var lang=window.lang==='en'?'en':'zh';"
                + "var labels={zh:{vpn:'VPN',ad:'广告',privacy:'隐私',script:'脚本'},en:{vpn:'VPN',ad:'Ad',privacy:'Privacy',script:'Scripts'}};"
                + "if(title)title.textContent=labels[lang][navTab]||navTab;"
                + "window.dispatchEvent(new Event('resize'));"
                + "return page.classList.contains('on')&&getComputedStyle(page).display!=='none';"
                + "})()";
        webView.evaluateJavascript(script, value -> {
            if (value == null || "false".equals(value) || "null".equals(value)) {
                Toast.makeText(MainActivity.this,
                        "该功能页面未能加载，请检查内置 WebUI 页面资源。",
                        Toast.LENGTH_LONG).show();
            }
        });
    }

    private void showHookHub() {
        cancelAppIconLoad();
        // Do not resurrect a stale target if the user leaves the restored app list.
        pendingRestorePackage = null;
        pauseAndDetachWebView();
        hookUiVisible = true;
        settingsUiVisible = false;
        selectedBottomTab = 4;
        hookTargetVisible = false;
        hookHubVisible = true;
        base("Hook 与系统授权");
        TextView intro = new TextView(this);
        intro.setText("统一管理应用级 Hook、LSPosed 作用域和无障碍服务。Root、LSPosed、无障碍是三种独立授权，必须分别确认状态。");
        intro.setPadding(dp(18), dp(8), dp(18), dp(16));
        intro.setTextColor(0xff536170);
        content.addView(intro);
        section("最近一次配置发布");
        android.content.SharedPreferences publishState =
                getSharedPreferences("fx_hook_publish", MODE_PRIVATE);
        String lastHash = publishState.getString("sha256", "");
        long lastPublishedAt = publishState.getLong("published_at", 0L);
        TextView publishStatus = new TextView(this);
        publishStatus.setPadding(dp(18), dp(10), dp(18), dp(12));
        if (lastHash.isEmpty() || lastPublishedAt <= 0L) {
            publishStatus.setText("尚无成功发布记录。保存配置后，这里会显示设备端写入校验结果；该记录不代表 LSPosed 已启用或目标进程已注入。");
        } else {
            java.text.DateFormat dateFormat = java.text.DateFormat.getDateTimeInstance(
                    java.text.DateFormat.MEDIUM, java.text.DateFormat.MEDIUM);
            publishStatus.setText("设备端写入成功（" + dateFormat.format(new java.util.Date(lastPublishedAt))
                    + "）\nSHA-256：" + lastHash
                    + "\nRemote Files：" + publishState.getString("remote_path", "未知")
                    + "\n此记录只证明文件写入与哈希校验成功，不证明 LSPosed 作用域、热加载或目标进程注入状态。");
        }
        content.addView(publishStatus);
        section("LSPosed Remote Files 实时状态");
        TextView remoteStatus = new TextView(this);
        remoteStatus.setText("正在读取设备端 Remote Files 状态…");
        remoteStatus.setPadding(dp(18), dp(10), dp(18), dp(12));
        content.addView(remoteStatus);
        Button refreshRemote = new Button(this);
        refreshRemote.setText("刷新 Remote Files 状态");
        refreshRemote.setOnClickListener(v -> refreshHookRemoteStatus(remoteStatus));
        content.addView(refreshRemote);
        refreshHookRemoteStatus(remoteStatus);
        section("KernelSU / Root");
        TextView rootState = new TextView(this);
        rootState.setText("正在检查 Root 授权与 FX 模块状态…");
        rootState.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(rootState);
        Button refreshRoot = new Button(this);
        refreshRoot.setText("刷新 Root 状态");
        refreshRoot.setOnClickListener(v -> checkRoot(rootState, false));
        content.addView(refreshRoot);
        Button requestRoot = new Button(this);
        requestRoot.setText("申请 / 重新检查 Root 权限");
        requestRoot.setOnClickListener(v -> checkRoot(rootState, true));
        content.addView(requestRoot);
        checkRoot(rootState, false);
        section("LSPosed");
        TextView ls = new TextView(this);
        ls.setText(isLsposedManagerInstalled()
                ? "已检测到 LSPosed Manager。注意：这只证明管理器已安装；框架是否运行、FX 模块是否启用、目标应用作用域及进程注入状态均无法由 FX 独立可靠读取，当前均标记为“未知”，请在 Manager 中逐项确认。"
                : "未检测到 LSPosed Manager。框架运行状态、FX 模块启用状态、目标应用作用域及进程注入状态均为未知；请先安装并配置兼容的 LSPosed 框架。");
        ls.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(ls);
        Button manager = new Button(this);
        manager.setText("打开 LSPosed Manager");
        manager.setOnClickListener(v -> openLsposedManager());
        content.addView(manager);
        Button targets = new Button(this);
        targets.setText("应用 Hook 配置");
        targets.setOnClickListener(v -> showAppList());
        content.addView(targets);
        section("Android 无障碍");
        TextView accessibility = new TextView(this);
        boolean accessibilityEnabled = isAccessibilityEnabled();
        android.content.SharedPreferences accessibilityPrefs =
                getSharedPreferences("fx_accessibility", MODE_PRIVATE);
        boolean accessibilityConnected = FxAccessibilityService.isConnected()
                && accessibilityPrefs.getBoolean("service_connected", false)
                && accessibilityPrefs.getInt("service_pid", -1) == android.os.Process.myPid();
        accessibility.setText(!accessibilityEnabled
                ? "无障碍服务：未启用（需由用户在系统设置中手动开启）"
                : accessibilityConnected ? "无障碍服务：系统已启用，FX 服务已连接"
                : "无障碍服务：系统已启用，等待 FX 服务连接");
        accessibility.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(accessibility);
        Button settings = new Button(this);
        settings.setText("打开无障碍设置");
        settings.setOnClickListener(v -> {
            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
            catch (Exception e) { Toast.makeText(this, "无法打开系统无障碍设置", Toast.LENGTH_LONG).show(); }
        });
        content.addView(settings);
        Button status = new Button(this);
        status.setText("刷新无障碍 / LSPosed 检测");
        status.setOnClickListener(v -> showHookHub());
        content.addView(status);
        Button back = new Button(this);
        back.setText("返回 FX 控制中心");
        back.setOnClickListener(v -> showWebDashboard());
        content.addView(back);
    }

    private void addModeOption(RadioGroup group, int id, String title, String detail) {
        RadioButton option = new RadioButton(this);
        option.setId(id);
        option.setText(title + "\n" + detail);
        option.setTextSize(15);
        option.setPadding(dp(14), dp(10), dp(14), dp(10));
        option.setMinHeight(dp(64));
        option.setBackground(uiPanelDrawable());
        group.addView(option, new RadioGroup.LayoutParams(-1, -2));
    }

    private void showSettings() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        if (webView == null) showWebDashboard();
        else pauseAndDetachWebView();
        stopNativeVpnPolling();
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        settingsUiVisible = true;
        selectedBottomTab = 5;
        base("设置");
        // Settings is app-wide only: never attach the hidden WebView compatibility bridge here.
        // Feature controls belong to VPN, Ad/Hosts, Privacy, Scripts, and Hook destinations.
        TextView intro = new TextView(this);
        intro.setText("全局设置：界面模式、应用授权与运行诊断。VPN、Hosts、隐私保护、脚本和 Hook 的功能配置均在各自主页面管理。");
        intro.setTextColor(0xff66727e);
        intro.setPadding(dp(18), dp(4), dp(18), dp(14));
        content.addView(intro);
        section("迁移应用");
        addNativeActionCard("Dia 23.11",
                "三级入口 · Hook、设备模拟、Frida、脚本、开发监控与规则页面",
                "打开 Dia 23.11", () -> showImportedSuite("dia"));
        addNativeActionCard("游龙广告插件 7.0.1",
                "三级入口 · 广告过滤、DNS、VPN / Root Proxy、HTTPS 与诊断页面",
                "打开游龙广告插件", () -> showImportedSuite("yulong-ad"));
        addNativeActionCard("游龙安全护盾 9.9.60",
                "三级入口 · 安全中心、病毒库、应用扫描、Stellar 与救援恢复四级页面",
                "打开安全护盾", () -> showImportedSuite("yulong-shield"));
        section("界面模式");
        TextView note = new TextView(this);
        note.setText("以下模式选择器由 Kotlin + Jetpack Compose 原生渲染。Miuix 使用官方 Miuix 组件；Liquid Glass 使用 Kyant Backdrop 的背景采样、模糊与 Lens 效果。六个主页面均由 Android 原生视图承载；内置 WebView 仅作为尚未替换完毕的兼容运行桥，不显示网页像素。");
        note.setTextColor(0xff66727e);
        note.setPadding(dp(18), dp(4), dp(18), dp(8));
        content.addView(note);
        androidx.compose.ui.platform.ComposeView designModePanel =
                new androidx.compose.ui.platform.ComposeView(this);
        // This ComposeView is a sibling of the main shell, not its descendant.
        // Bind all three owners before setContent() so the settings panel can
        // create a lifecycle-aware recomposer and resolve saved state/ViewModels.
        androidx.lifecycle.ViewTreeLifecycleOwner.set(designModePanel, this);
        androidx.lifecycle.ViewTreeViewModelStoreOwner.set(designModePanel, this);
        androidx.savedstate.ViewTreeSavedStateRegistryOwner.set(designModePanel, this);
        FxDesignModePanelKt.installFxDesignModePanel(designModePanel, uiMode, selected -> {
            if (selected == null || selected.equals(uiMode)) return kotlin.Unit.INSTANCE;
            uiMode = selected;
            getSharedPreferences("fx_ui", MODE_PRIVATE).edit()
                    .putString("mode", uiMode).apply();
            applyWebUiMode();
            Toast.makeText(MainActivity.this, "界面模式已切换", Toast.LENGTH_SHORT).show();
            showSettings();
            return kotlin.Unit.INSTANCE;
        });
        content.addView(designModePanel,
                new LinearLayout.LayoutParams(-1, dp(360)));
        // Settings is reserved for app-wide preferences and diagnostics.
        // Operational VPN/privacy controls live on their matching primary tabs.
        section("模块与运行状态");
        TextView runtimeStatus = new TextView(this);
        runtimeStatus.setText("点击刷新，读取设备端 FX 模块状态。");
        runtimeStatus.setTextColor(0xff344451);
        runtimeStatus.setPadding(dp(16), dp(12), dp(16), dp(12));
        runtimeStatus.setBackground(uiPanelDrawable());
        content.addView(runtimeStatus);
        Button refreshRuntime = new Button(this);
        refreshRuntime.setAllCaps(false);
        refreshRuntime.setText("刷新模块状态与诊断信息");
        refreshRuntime.setOnClickListener(v -> refreshNativeModuleStatus(runtimeStatus, 2));
        content.addView(refreshRuntime);
        section("系统授权");
        Button accessibilitySettings = new Button(this);
        accessibilitySettings.setAllCaps(false);
        accessibilitySettings.setText("打开 Android 无障碍设置");
        accessibilitySettings.setOnClickListener(v -> {
            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
            catch (Exception e) { Toast.makeText(this, "无法打开系统无障碍设置", Toast.LENGTH_LONG).show(); }
        });
        content.addView(accessibilitySettings);
        Button appDetails = new Button(this);
        appDetails.setAllCaps(false);
        appDetails.setText("打开 FX Hook 应用信息");
        appDetails.setOnClickListener(v -> {
            try {
                Intent intent = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivity(intent);
            } catch (Exception e) {
                Toast.makeText(this, "无法打开应用信息", Toast.LENGTH_LONG).show();
            }
        });
        content.addView(appDetails);
        section("运行日志");
        content.addView(nativeAction("查看最近 FX 模块日志", this::showNativeRuntimeLogs));
    }

    private String importedSuiteTitle(String suite) {
        if ("dia".equals(suite)) return "Dia 23.11";
        if ("yulong-shield".equals(suite)) return "游龙安全护盾 9.9.60";
        return "游龙广告插件 7.0.1";
    }

    private String[][] importedSuiteSections(String suite) {
        if ("dia".equals(suite)) return new String[][] {
            {"应用与模块", "应用选择", "目标应用", "模块配置", "模块功能", "Activity 入口与禁用", "隐藏应用"},
            {"Hook 功能", "方法 Hook", "对话框与通知", "剪贴板", "传感器", "网络与代理", "按键控制", "文件与 so 库"},
            {"设备模拟", "设备属性", "位置与 GPS", "Wi-Fi 模拟", "网络类型模拟", "时间与时区", "应用版本", "签名信息"},
            {"Frida 与脚本", "Frida 环境", "Frida 注入", "监听模式", "JS 脚本列表", "脚本编辑器", "运行日志"},
            {"开发与监控", "Native 方法", "函数重写", "HTTP 监控", "HTTP 代理", "Socket 监控", "Intent 监控", "Shell/Process 监控", "方法堆栈", "View 点击监控", "ViewGroup 层级监控", "Fragment 生命周期", "Thread 启动监控", "ClassLoader 监控", "JSON 操作", "数据库监控", "算法监控", "Dex 查找与解析", "内存快照"},
            {"规则与数据", "规则组", "规则列表", "运行日志", "本地备份", "GitHub 备份", "WebDAV 备份", "全局设置"}
        };
        if ("yulong-shield".equals(suite)) return new String[][] {
            {"安全中心", "安全护盾首页", "防护级别", "防护状态", "实时守护", "每日安全总结"},
            {"病毒库与名单", "病毒库管理", "病毒库同步", "白名单管理", "管控应用列表"},
            {"应用扫描", "已安装应用扫描", "安装后自动检测", "APK 内容特征扫描", "扫描结果"},
            {"Stellar 金龙", "Stellar 特权管理", "应用授权", "能力作用域", "始终允许命令"},
            {"救援与恢复", "悬浮救援入口", "音量键触发", "摇动触发", "开机恢复", "守护运行状态"}
        };
        return new String[][] {
            {"首页与防护", "广告拦截开关", "防护级别", "防护状态", "统计", "每日防护总结"},
            {"过滤列表与规则", "过滤列表", "过滤器设置", "添加过滤列表", "自定义规则", "规则编辑", "白名单域名", "黑名单域名", "计划任务"},
            {"DNS 设置", "DNS 服务器", "上游 DNS", "备用 DNS", "自定义 DNS", "DNS 协议", "分离 DNS 区域", "DNS 日志"},
            {"应用管理", "应用白名单", "用户应用", "系统应用", "按应用设置", "应用统计", "应用网络拦截"},
            {"VPN 与 Root Proxy", "VPN 保护", "VPN 状态", "自动重连", "信任的网络", "Root 代理模式", "iptables DNS 重定向"},
            {"HTTPS 与证书", "HTTPS 过滤", "根 CA 证书", "保存证书", "安装证书", "验证证书", "过滤 HTTP/3 (QUIC)"},
            {"日志与诊断", "DNS 查询日志", "导出本地日志", "分享日志", "崩溃报告", "隐私与诊断"},
            {"通用设置", "界面", "主题色", "网络切换延迟", "电池优化", "设置导入", "设置导出", "关于"}
        };
    }

    private void showImportedSuite(String suite) {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        pauseAndDetachWebView();
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        settingsUiVisible = true;
        selectedBottomTab = 5;
        String title = importedSuiteTitle(suite);
        base(title);
        TextView intro = new TextView(this);
        intro.setText("按原软件的功能分类进入独立页面。能够复用 FX 原生功能的页面会直接打开对应控制页；尚未完成运行时移植的功能会明确标注，不显示伪造的开关或运行状态。");
        intro.setTextColor(0xff66727e);
        intro.setPadding(dp(16), dp(8), dp(16), dp(12));
        content.addView(intro);
        for (String[] section : importedSuiteSections(suite)) {
            String category = section[0];
            addNativeActionCard(category, (section.length - 1) + " 个原始功能页面",
                    "进入 " + category, () -> showImportedSuiteCategory(suite, category));
        }
        content.addView(nativeAction("返回 FX 设置", this::showSettings));
    }

    private void showImportedSuiteCategory(String suite, String category) {
        String title = importedSuiteTitle(suite);
        base(title + " · " + category);
        for (String[] section : importedSuiteSections(suite)) {
            if (!section[0].equals(category)) continue;
            TextView intro = new TextView(this);
            intro.setText("原功能页面分类：" + category);
            intro.setTextColor(0xff66727e);
            intro.setPadding(dp(16), dp(6), dp(16), dp(10));
            content.addView(intro);
            for (int i = 1; i < section.length; i++) {
                final String page = section[i];
                addNativeActionCard(page, "原软件四级页面入口",
                        "打开 " + page, () -> openImportedSuitePage(suite, category, page));
            }
            break;
        }
        content.addView(nativeAction("返回 " + title, () -> showImportedSuite(suite)));
    }

    private void openImportedNativeTab(int index) {
        lastWebTabIndex = Math.max(0, Math.min(3, index));
        selectedBottomTab = lastWebTabIndex;
        pendingWebPage = webPageForBottomTab(lastWebTabIndex);
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        settingsUiVisible = false;
        showWebDashboard();
    }

    private void openImportedSuitePage(String suite, String category, String page) {
        if ("yulong-ad".equals(suite)) {
            switch (page) {
                case "统计": case "每日防护总结":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdSummaryActivity.class));
                    return;
                case "应用统计":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAppStatsActivity.class));
                    return;
                case "白名单域名": case "黑名单域名": case "自定义规则": case "规则编辑":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "域名名单"));
                    return;
                case "过滤器设置": case "添加过滤列表":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "过滤列表"));
                    return;
                case "广告拦截开关": case "防护级别": case "防护状态":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "首页与防护"));
                    return;
                case "DNS 服务器": case "上游 DNS": case "备用 DNS":
                case "自定义 DNS": case "DNS 协议": case "分离 DNS 区域":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "DNS 设置"));
                    return;
                case "VPN 保护": case "VPN 状态": case "自动重连":
                case "信任的网络": case "Root 代理模式": case "iptables DNS 重定向":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "VPN 与 Root Proxy"));
                    return;
                case "HTTPS 过滤": case "根 CA 证书": case "保存证书":
                case "安装证书": case "验证证书": case "过滤 HTTP/3 (QUIC)":
                    showNativeCertificateManager();
                    return;
                case "DNS 日志": case "DNS 查询日志":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongDnsActivity.class));
                    return;
                case "导出本地日志": case "分享日志": case "崩溃报告": case "隐私与诊断":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                            .putExtra("suite_page", "日志与诊断"));
                    return;
                case "界面": case "主题色": case "网络切换延迟":
                case "电池优化": case "设置导入": case "设置导出": case "关于":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.ad.FxYulongAdGeneralActivity.class));
                    return;
            }
        }
        if ("yulong-ad".equals(suite) && "计划任务".equals(page)) {
            startActivity(new Intent(this,
                    de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                    .putExtra("suite_page", "计划任务"));
            return;
        }
        if ("yulong-ad".equals(suite) && "DNS 日志".equals(page)) {
            startActivity(new Intent(this,
                    de.privacyguard.adhook.imported.ad.FxYulongDnsActivity.class));
            return;
        }
        if ("yulong-shield".equals(suite)) {
            switch (page) {
                case "安全护盾首页": case "防护级别": case "防护状态":
                case "实时守护": case "悬浮救援入口":
                case "音量键触发": case "摇动触发": case "开机恢复":
                case "守护运行状态":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.FxYulongShieldActivity.class));
                    return;
                case "每日安全总结":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.FxYulongDailySummaryActivity.class));
                    return;
                case "病毒库管理": case "病毒库同步":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.FxYulongVirusDatabaseActivity.class));
                    return;
                case "白名单管理":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.WhitelistActivity.class));
                    return;
                case "管控应用列表":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.BlacklistActivity.class));
                    return;
                case "已安装应用扫描": case "安装后自动检测":
                case "APK 内容特征扫描": case "扫描结果":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.shield.FxYulongScanActivity.class));
                    return;
                case "Stellar 特权管理": case "应用授权":
                case "能力作用域": case "始终允许命令":
                    startActivity(new Intent(this,
                            roro.stellar.manager.authorization.FxStellarManagerActivity.class));
                    return;
                default:
                    showImportedSuitePendingPage(suite, category, page,
                            "该安全护盾原功能已登记；尚无对应独立四级实现。不会显示无效开关或伪造运行状态。");
                    return;
            }
        }
        if ("dia".equals(suite)) {
            switch (page) {
                case "Activity 入口与禁用":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaActivityBrowserActivity.class)
                            .putExtra("launcher_only", false));
                    return;
                case "隐藏应用":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaActivityBrowserActivity.class)
                            .putExtra("launcher_only", true)
                            .putExtra("dia_page", page));
                    return;
                case "方法 Hook": case "函数重写":
                    showAppList("自定义 Hook");
                    return;
                case "Native 方法":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFridaActivity.class)
                            .putExtra("dia_page", page));
                    return;
                case "规则组": case "规则列表":
                    showAppList("自定义 Hook");
                    return;
                case "应用版本":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaSignatureActivity.class));
                    return;
                case "按键控制":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFridaActivity.class)
                            .putExtra("dia_page", page));
                    return;
                case "应用选择": case "目标应用": case "模块配置": case "模块功能":
                    showAppList();
                    return;
                case "对话框与通知": case "剪贴板":
                    showNativeSettingsGroup("notifyPanel", "Dia · " + page);
                    return;
                case "传感器":
                    showNativeSettingsGroup("sensorPanel", "Dia · 传感器");
                    return;
                case "HTTP 监控": case "SQL 监控": case "算法监控":
                case "Socket 监控": case "Intent 监控": case "Shell/Process 监控":
                case "方法堆栈": case "View 点击监控": case "ViewGroup 层级监控":
                case "Fragment 生命周期": case "Thread 启动监控": case "ClassLoader 监控":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFridaActivity.class)
                            .putExtra("dia_page", page));
                    return;
                case "网络与代理": case "HTTP 代理":
                    showNativeSettingsGroup("netPanel", "Dia · " + page);
                    return;
                case "设备属性":
                    showAppList("设备标识模拟");
                    return;
                case "Wi-Fi 模拟":
                    showAppList("Wi-Fi 环境模拟");
                    return;
                case "网络类型模拟":
                    showAppList("网络类型模拟");
                    return;
                case "文件与 so 库":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFileActivity.class));
                    return;
                case "位置与 GPS":
                    showAppList("位置隐私");
                    return;
                case "时间与时区":
                    showAppList("时间与时区模拟");
                    return;
                case "JS 脚本列表": case "脚本编辑器":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFridaActivity.class)
                            .putExtra("dia_page", page));
                    return;
                case "JSON 操作":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaJsonActivity.class));
                    return;
                case "规则组": case "规则列表":
                    showAppList("自定义 Hook");
                    return;
                case "运行日志":
                    showNativeRuntimeLogs();
                    return;
                case "全局设置":
                    showSettings();
                    return;
                case "Frida 环境": case "Frida 注入": case "监听模式":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaFridaActivity.class)
                            .putExtra("dia_page", page));
                    return;
                case "本地备份":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaBackupActivity.class));
                    return;
                case "GitHub 备份": case "WebDAV 备份":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaBackupActivity.class));
                    return;
                case "Dex 查找与解析":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaDexBrowserActivity.class));
                    return;
                case "签名信息":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaSignatureActivity.class));
                    return;
                case "数据库监控": case "内存快照":
                    startActivity(new Intent(this,
                            de.privacyguard.adhook.imported.dia.FxDiaInspectorActivity.class)
                            .putExtra("dia_mode", "数据库监控".equals(page) ? "database" : "memory"));
                    return;
                default:
                    showImportedSuitePendingPage(suite, category, page,
                            "该 Dia 页面已登记到迁移目录；对应运行逻辑尚未移植完成。当前不会创建无效开关，也不会修改目标应用或系统状态。");
                    return;
            }
        }

        if (category.equals("首页与防护") || category.equals("过滤列表与规则")
                || category.equals("DNS 设置") || category.equals("通用设置")
                || category.equals("日志与诊断") || category.equals("VPN 与 Root Proxy")) {
            String targetPage = page;
            if (category.equals("首页与防护")) targetPage = "首页与防护";
            else if (category.equals("过滤列表与规则")) targetPage = "过滤列表";
            else if (category.equals("DNS 设置")) targetPage = "DNS 设置";
            else if (category.equals("VPN 与 Root Proxy")) targetPage = "VPN 与 Root Proxy";
            else if (category.equals("通用设置")) targetPage = "通用设置";
            else if (category.equals("日志与诊断")) targetPage = "日志与诊断";
            startActivity(new Intent(this,
                    de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class)
                    .putExtra("suite_page", targetPage));
            return;
        }
        if (category.equals("应用管理")) {
            if (page.equals("应用白名单")) {
                startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.ad.FxYulongAppWhitelistActivity.class));
                return;
            }
            if (page.equals("用户应用") || page.equals("系统应用") || page.equals("按应用设置")) {
                showImportedVpnAppManager();
                return;
            }
            if (page.equals("应用网络拦截")) {
                startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.ad.FxYulongFirewallActivity.class));
                return;
            }
            if (page.equals("应用统计")) {
                startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.ad.FxYulongAppStatsActivity.class));
                return;
            }
            showImportedSuitePendingPage(suite, category, page,
                    "游龙原版独立应用防火墙（移动数据/Wi-Fi 阻断与时间计划）尚未迁移。这里仅提供已接入 FX VPN 后端的分应用路由管理，不将路由例外伪装成断网防火墙。");
            return;
        }
        if (category.equals("HTTPS 与证书")) {
            showNativeCertificateManager();
            return;
        }
        if (category.equals("日志与诊断")) {
            showNativeRuntimeLogs();
            return;
        }
        if (category.equals("通用设置")) {
            showSettings();
            return;
        }
        showImportedSuitePendingPage(suite, category, page,
                "游龙广告插件 7.0.1 的独立应用过滤与 Root Proxy 运行时尚未迁入。现阶段可使用 FX 的 Hosts、DNS / VPN、证书和日志原生控制页；不会把 FX 状态冒充为原插件状态。");
    }

    /**
     * Yulong 7.0.1 application-management screen, backed by FX's single VPN route.
     * The [list:vpn_app] package list is independent of Hook target scope.
     */
    private void showImportedVpnAppManager() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        pauseAndDetachWebView();
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        settingsUiVisible = true;
        selectedBottomTab = 5;
        base("游龙广告插件 · 应用管理");

        TextView intro = new TextView(this);
        intro.setText("管理指定应用是否加入 FX 分应用 VPN 路由列表。FX 继续使用唯一的 VPN/TUN；不会启动游龙第二个 VpnService。此页面只设置路由范围，不等同于阻断移动数据/Wi-Fi 的独立防火墙。");
        intro.setTextColor(0xff66727e);
        intro.setPadding(dp(16), dp(8), dp(16), dp(12));
        content.addView(intro);

        TextView status = new TextView(this);
        status.setText("正在读取设备端分应用路由配置…");
        status.setPadding(dp(16), dp(6), dp(16), dp(8));
        content.addView(status);

        Switch master = new Switch(this);
        master.setText("启用分应用 VPN 路由");
        master.setTextSize(15);
        master.setPadding(dp(16), dp(10), dp(16), dp(10));
        content.addView(master);

        RadioGroup modeGroup = new RadioGroup(this);
        modeGroup.setOrientation(RadioGroup.HORIZONTAL);
        RadioButton onlyMode = new RadioButton(this);
        onlyMode.setText("仅列表应用走代理");
        onlyMode.setId(View.generateViewId());
        RadioButton bypassMode = new RadioButton(this);
        bypassMode.setText("列表应用直连");
        bypassMode.setId(View.generateViewId());
        modeGroup.addView(onlyMode);
        modeGroup.addView(bypassMode);
        content.addView(modeGroup);

        TextView modeHint = new TextView(this);
        modeHint.setText("仅列表应用走代理：只把选中的应用接入 FX 节点。列表应用直连：选中的应用绕过 FX 节点，其余应用按当前 VPN 模式处理。");
        modeHint.setTextSize(12);
        modeHint.setTextColor(0xff718091);
        modeHint.setPadding(dp(16), dp(2), dp(16), dp(10));
        content.addView(modeHint);

        EditText query = new EditText(this);
        query.setSingleLine(true);
        query.setHint("搜索应用名称或包名");
        query.setPadding(dp(14), dp(8), dp(14), dp(8));
        content.addView(query, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        content.addView(rows);

        final Map<String, Boolean> selected = new HashMap<>();
        final List<ApplicationInfo> installedApps = new ArrayList<>();
        final Map<String, String> labels = new HashMap<>();
        final boolean[] loadingConfig = {true};
        final boolean[] routeMaster = {false};
        final String[] routeMode = {"bypass"};
        final boolean[] suppressMasterListener = {false};
        final boolean[] suppressModeListener = {false};

        Runnable renderRows = () -> {
            if (rows.getParent() == null) return;
            rows.removeAllViews();
            String filter = query.getText() == null ? "" : query.getText().toString().trim().toLowerCase(Locale.ROOT);
            int shown = 0;
            for (ApplicationInfo info : installedApps) {
                String pkg = info.packageName == null ? "" : info.packageName;
                String label = labels.getOrDefault(pkg, pkg);
                if (!filter.isEmpty() && !label.toLowerCase(Locale.ROOT).contains(filter)
                        && !pkg.toLowerCase(Locale.ROOT).contains(filter)) continue;
                shown++;
                LinearLayout row = new LinearLayout(this);
                row.setOrientation(LinearLayout.VERTICAL);
                row.setPadding(dp(12), dp(7), dp(12), dp(7));
                row.setBackground(uiPanelDrawable());
                TextView name = new TextView(this);
                name.setText(label);
                name.setTextSize(14);
                name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                name.setTextColor(0xff17212b);
                TextView packageName = new TextView(this);
                packageName.setText(pkg);
                packageName.setTextSize(10);
                packageName.setTextColor(0xff718091);
                Switch enabled = new Switch(this);
                final boolean[] revertingRow = {false};
                enabled.setText("加入列表");
                enabled.setChecked(Boolean.TRUE.equals(selected.get(pkg)));
                enabled.setOnCheckedChangeListener((button, checked) -> {
                    if (loadingConfig[0] || revertingRow[0]) return;
                    button.setEnabled(false);
                    String command = "sh \"$MP/scripts/vpn-apps.sh\" apply-item "
                            + shellQuote(pkg) + " " + (checked ? "1" : "0");
                    runNativeModuleCommand(command, 120000L, result -> {
                        button.setEnabled(true);
                        if (result.exitCode != 0) {
                            revertingRow[0] = true;
                            button.setChecked(!checked);
                            revertingRow[0] = false;
                            new AlertDialog.Builder(this).setTitle("分应用配置未应用")
                                    .setMessage(result.output == null ? "模块未确认配置应用成功。" : result.output.trim())
                                    .setPositiveButton("关闭", null).show();
                        } else {
                            selected.put(pkg, checked);
                            status.setText("分应用列表已更新并重新应用。");
                        }
                    });
                });
                row.addView(name);
                row.addView(packageName);
                row.addView(enabled);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
                lp.setMargins(dp(12), dp(2), dp(12), dp(3));
                rows.addView(row, lp);
            }
            if (shown == 0) {
                TextView empty = new TextView(this);
                empty.setText("没有符合搜索条件的应用。");
                empty.setPadding(dp(16), dp(18), dp(16), dp(18));
                rows.addView(empty);
            }
        };

        query.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) { renderRows.run(); }
            public void afterTextChanged(Editable s) {}
        });

        master.setOnCheckedChangeListener((button, checked) -> {
            if (loadingConfig[0] || suppressMasterListener[0]) return;
            boolean anySelected = false;
            for (Boolean value : selected.values()) {
                if (Boolean.TRUE.equals(value)) { anySelected = true; break; }
            }
            if (checked && !anySelected) {
                suppressMasterListener[0] = true;
                master.setChecked(false);
                suppressMasterListener[0] = false;
                new AlertDialog.Builder(this).setTitle("先选择应用")
                        .setMessage("启用分应用 VPN 路由前，至少需要选择一个应用。")
                        .setPositiveButton("知道了", null).show();
                return;
            }
            master.setEnabled(false);
            runNativeModuleCommand("sh \"$MP/scripts/vpn-apps.sh\" apply-master " + (checked ? "1" : "0"),
                    120000L, result -> {
                master.setEnabled(true);
                if (result.exitCode != 0) {
                    suppressMasterListener[0] = true;
                    master.setChecked(!checked);
                    suppressMasterListener[0] = false;
                    status.setText("分应用开关未应用：" + (result.output == null ? "" : result.output.trim()));
                } else {
                    routeMaster[0] = checked;
                    status.setText(checked ? "分应用 VPN 路由已应用。" : "已关闭分应用 VPN 路由。");
                }
            });
        });

        modeGroup.setOnCheckedChangeListener((group, checkedId) -> {
            if (loadingConfig[0] || suppressModeListener[0]) return;
            String wanted = checkedId == onlyMode.getId() ? "only" : "bypass";
            runNativeModuleCommand("sh \"$MP/scripts/vpn-apps.sh\" apply-mode " + wanted,
                    120000L, result -> {
                if (result.exitCode != 0) {
                    suppressModeListener[0] = true;
                    modeGroup.check("only".equals(routeMode[0]) ? onlyMode.getId() : bypassMode.getId());
                    suppressModeListener[0] = false;
                    status.setText("路由模式未应用：" + (result.output == null ? "" : result.output.trim()));
                } else {
                    routeMode[0] = wanted;
                    status.setText("分应用路由模式已切换。");
                }
            });
        });

        runNativeModuleCommand("sh \"$MP/scripts/vpn-apps.sh\" list", 30000L, config -> {
            if (config.exitCode != 0) {
                loadingConfig[0] = false;
                status.setText("无法读取分应用 VPN 配置：" + (config.output == null ? "" : config.output.trim()));
                master.setEnabled(false);
                onlyMode.setEnabled(false);
                bypassMode.setEnabled(false);
                return;
            }
            try {
                String[] lines = (config.output == null ? "" : config.output).split("\\r?\\n");
                if (lines.length == 0 || !"FXVPNAPP1".equals(lines[0].trim())) {
                    throw new IllegalStateException("模块返回了无法识别的分应用列表格式");
                }
                for (int i = 1; i < lines.length; i++) {
                    String line = lines[i].trim();
                    if (line.startsWith("master=")) routeMaster[0] = "1".equals(line.substring(7));
                    else if (line.startsWith("mode=")) routeMode[0] = line.substring(5).trim();
                    else if (!line.isEmpty()) {
                        String[] fields = line.split("\\|", -1);
                        if (fields.length == 3 && fields[0].matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_-]+)+"))
                            selected.put(fields[0], "1".equals(fields[2]));
                    }
                }
                master.setChecked(routeMaster[0]);
                onlyMode.setChecked("only".equals(routeMode[0]));
                bypassMode.setChecked(!"only".equals(routeMode[0]));
                loadingConfig[0] = false;
                status.setText("已读取 " + selected.size() + " 个分应用路由条目。当前模式："
                        + ("only".equals(routeMode[0]) ? "仅列表应用走代理" : "列表应用直连")
                        + "；请确认主 VPN 已正常运行后再启用分应用路由。");

                Thread loader = new Thread(() -> {
                    List<ApplicationInfo> loaded = new ArrayList<>();
                    Map<String, String> names = new HashMap<>();
                    try {
                        PackageManager pm = getPackageManager();
                        for (ApplicationInfo info : pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                            if (info == null || info.packageName == null || info.packageName.equals(getPackageName())) continue;
                            loaded.add(info);
                            String label;
                            try { label = String.valueOf(pm.getApplicationLabel(info)); }
                            catch (Throwable ignored) { label = info.packageName; }
                            names.put(info.packageName, label);
                        }
                        Collections.sort(loaded, (a, b) -> names.getOrDefault(a.packageName, a.packageName)
                                .compareToIgnoreCase(names.getOrDefault(b.packageName, b.packageName)));
                    } catch (Throwable error) {
                        runOnUiThread(() -> status.setText("应用列表读取失败：" + error.getClass().getSimpleName()));
                        return;
                    }
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed() || rows.getParent() == null) return;
                        installedApps.clear();
                        installedApps.addAll(loaded);
                        labels.clear();
                        labels.putAll(names);
                        renderRows.run();
                    });
                }, "FxYulongAppRoutes");
                loader.setDaemon(true);
                loader.start();
            } catch (Exception error) {
                loadingConfig[0] = false;
                status.setText("分应用列表解析失败：" + error.getMessage());
                master.setEnabled(false);
                onlyMode.setEnabled(false);
                bypassMode.setEnabled(false);
            }
        });

        content.addView(nativeAction("重新读取应用路由状态", this::showImportedVpnAppManager));
        content.addView(nativeAction("返回游龙广告插件应用管理", () -> showImportedSuiteCategory("yulong-ad", "应用管理")));
    }

    private void showImportedSuitePendingPage(String suite, String category, String page, String detail) {
        String title = importedSuiteTitle(suite);
        base(title + " · " + page);
        content.addView(title(page, 21));
        TextView description = new TextView(this);
        description.setText(detail);
        description.setTextColor(0xff66727e);
        description.setPadding(dp(16), dp(10), dp(16), dp(16));
        content.addView(description);
        content.addView(nativeAction("返回 " + category, () -> showImportedSuiteCategory(suite, category)));
    }

    private void addNativeSettingsCategory(String label, String panelId) {
        Button button = nativeAction(label + "  ›", () -> showNativeSettingsGroup(panelId, label));
        button.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
        content.addView(button, new LinearLayout.LayoutParams(-1, dp(48)));
    }

    private void showNativeSettingsGroup(String panelId, String title) {
        try {
            java.util.Scanner scanner = new java.util.Scanner(
                    getAssets().open("native-privacy-settings.json"), "UTF-8");
            scanner.useDelimiter("\\A");
            String json = scanner.hasNext() ? scanner.next() : "";
            scanner.close();
            JSONObject schema = new JSONObject(json);
            if (schema.optInt("schema_version", 0) != 1) {
                throw new IllegalStateException("隐私设置架构版本不受支持");
            }
            org.json.JSONArray panels = schema.optJSONArray("panels");
            JSONObject found = null;
            if (panels != null) {
                for (int i = 0; i < panels.length(); i++) {
                    JSONObject candidate = panels.optJSONObject(i);
                    if (candidate != null && panelId.equals(candidate.optString("id"))) {
                        found = candidate;
                        break;
                    }
                }
            }
            if (found == null) throw new IllegalStateException("找不到原生隐私设置分组：" + panelId);
            // Keep the parsed panel local to this invocation; no WebView DOM is consulted.
            renderNativePrivacySettingsGroup(found, title);
        } catch (Exception error) {
            new AlertDialog.Builder(this).setTitle(title + "读取失败")
                    .setMessage(error.getMessage()).setPositiveButton("关闭", null).show();
        }
    }

    private void renderNativePrivacySettingsGroup(JSONObject panelSchema, String title) {
        runNativeModuleCommand("sh \"$MP/scripts/native-privacy-settings.sh\" list", 30000L, result -> {
            try {
                if (result.exitCode != 0) {
                    throw new IllegalStateException("无法读取模块真实配置：" + result.output);
                }
                java.util.HashMap<String, String> values = new java.util.HashMap<>();
                String[] lines = (result.output == null ? "" : result.output).split("\\r?\\n");
                for (String line : lines) {
                    if (line.startsWith("[")) break;
                    int equals = line.indexOf('=');
                    if (equals <= 0) continue;
                    String key = line.substring(0, equals).trim();
                    if (key.matches("[A-Za-z0-9_.-]{1,96}")) {
                        values.put(key, line.substring(equals + 1).trim());
                    }
                }
                org.json.JSONArray items = panelSchema.optJSONArray("items");
                int count = items == null ? 0 : items.length();
                LinearLayout panel = new LinearLayout(this);
                panel.setOrientation(LinearLayout.VERTICAL);
                panel.setPadding(dp(12), dp(6), dp(12), dp(6));
                TextView summary = new TextView(this);
                summary.setText("配置来源：模块 Root 原生接口（仅返回布尔隐私开关，不向 App 暴露订阅与脚本内容）。开关保存后调用模块 apply.sh；应用失败会单独提示。");
                summary.setTextColor(0xff718091);
                summary.setPadding(dp(6), dp(4), dp(6), dp(10));
                panel.addView(summary);
                if (count == 0) {
                    TextView empty = new TextView(this);
                    empty.setText("此分组没有可用的设置项。");
                    empty.setPadding(dp(8), dp(12), dp(8), dp(12));
                    panel.addView(empty);
                }
                for (int i = 0; i < count; i++) {
                    JSONObject item = items.optJSONObject(i);
                    if (item == null) continue;
                    String key = item.optString("key", "");
                    if (!key.matches("[A-Za-z0-9_.-]{1,96}")) continue;
                    String label = item.optString("title", key);
                    String description = item.optString("description", "");
                    boolean checked = "1".equals(values.get(key));
                    LinearLayout row = new LinearLayout(this);
                    row.setOrientation(LinearLayout.VERTICAL);
                    row.setPadding(dp(12), dp(8), dp(12), dp(8));
                    row.setBackground(uiPanelDrawable());
                    LinearLayout top = new LinearLayout(this);
                    top.setGravity(Gravity.CENTER_VERTICAL);
                    TextView name = new TextView(this);
                    name.setText(label);
                    name.setTextSize(14);
                    name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                    name.setTextColor(0xff17212b);
                    top.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
                    Switch toggle = new Switch(this);
                    toggle.setTag(key);
                    toggle.setChecked(checked);
                    toggle.setOnCheckedChangeListener((button, enabled) ->
                            setNativePrivacySetting(key, enabled, !enabled, button));
                    top.addView(toggle);
                    row.addView(top);
                    if (!description.isEmpty()) {
                        TextView detail = new TextView(this);
                        detail.setText(description);
                        detail.setTextSize(11);
                        detail.setTextColor(0xff718091);
                        detail.setPadding(0, dp(3), 0, 0);
                        row.addView(detail);
                    }
                    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
                    lp.setMargins(dp(2), dp(3), dp(2), dp(3));
                    panel.addView(row, lp);
                }
                ScrollView scroll = new ScrollView(this);
                nativeScroll = scroll;
                scroll.addView(panel);
                new AlertDialog.Builder(this).setTitle(title)
                        .setView(scroll).setPositiveButton("关闭", null).show();
                loadNativePrivacyEditEntries(panelSchema.optString("id"), panel);
            } catch (Exception error) {
                new AlertDialog.Builder(this).setTitle(title + "读取失败")
                        .setMessage(error.getMessage()).setPositiveButton("重试", (d, w) ->
                                showNativeSettingsGroup(panelSchema.optString("id"), title))
                        .setNegativeButton("关闭", null).show();
            }
        });
    }


    // Preserve existing non-boolean advanced settings while their native config
    // schema is being migrated. The controls are native Android buttons, but
    // their metadata/value/save path remains a compatibility bridge for now.
    private void loadNativePrivacyEditEntries(String panelId, LinearLayout panel) {
        if (!"vpnPanel".equals(panelId)) return;
        TextView heading = new TextView(this);
        heading.setText("文本、列表与组合参数");
        heading.setTextColor(0xff718091);
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.setPadding(dp(8), dp(14), dp(8), dp(4));
        panel.addView(heading);

        TextView note = new TextView(this);
        note.setText("高级参数现在由原生编辑器直接读写 [conf:vpn]，包括监听端口、DNS、核心、测速、缓存、自动选优与隐藏强度。");
        note.setTextColor(0xff718091);
        note.setPadding(dp(8), dp(2), dp(8), dp(8));
        panel.addView(note);

        Button open = new Button(this);
        open.setAllCaps(false);
        open.setText("打开原生 VPN 高级参数编辑器");
        open.setOnClickListener(v -> showNativeVpnAdvancedEditor());
        panel.addView(open, new LinearLayout.LayoutParams(-1, -2));
    }
    private void setNativePrivacySetting(String key, boolean enabled, boolean previous,
                                         android.widget.CompoundButton control) {
        if (control == null) return;
        if (!key.matches("[A-Za-z0-9_.-]{1,96}")) {
            finishNativePrivacySetting(control, previous, false, "设置键无效");
            return;
        }
        control.setEnabled(false);
        String command = "sh \"$MP/scripts/native-privacy-settings.sh\" set "
                + key + " " + (enabled ? "1" : "0");
        runNativeModuleCommand(command, 120000L, result -> {
            if (result.exitCode == 0) {
                finishNativePrivacySetting(control, enabled, true, "已保存并请求应用");
            } else if (result.exitCode == 10) {
                // The config write succeeded but apply failed. Keep the persisted value visible.
                finishNativePrivacySetting(control, enabled, true,
                        "配置已保存，但模块应用失败；请查看模块日志");
            } else {
                finishNativePrivacySetting(control, previous, false,
                        result.output == null || result.output.trim().isEmpty()
                                ? "模块未确认保存" : result.output.trim());
            }
        });
    }

    private void finishNativePrivacySetting(android.widget.CompoundButton control, boolean checked,
                                            boolean success, String message) {
        if (control == null) return;
        control.setEnabled(true);
        control.setOnCheckedChangeListener(null);
        control.setChecked(checked);
        control.setOnCheckedChangeListener((button, enabled) ->
                setNativePrivacySetting(String.valueOf(button.getTag()), enabled, !enabled, button));
        Toast.makeText(this, message, success ? Toast.LENGTH_SHORT : Toast.LENGTH_LONG).show();
    }

    private void showNativeCertificateManager() {
        runNativeModuleCommand("sh \"$MP/scripts/certmgr.sh\" builtin list", 30000L, result -> {
            try {
                if (result.exitCode != 0) throw new IllegalStateException(result.output);
                String output = result.output == null ? "" : result.output;
                int begin = output.indexOf('{'), end = output.lastIndexOf('}');
                if (begin < 0 || end <= begin) throw new IllegalStateException("证书状态没有返回有效 JSON");
                JSONObject state = new JSONObject(output.substring(begin, end + 1));
                if (!state.optBoolean("ok", false)) throw new IllegalStateException("证书管理器未确认状态");
                showNativeCertificateList(state);
            } catch (Exception error) {
                new AlertDialog.Builder(this).setTitle("证书状态读取失败")
                        .setMessage(error.getMessage()).setPositiveButton("重试", (d, w) ->
                                showNativeCertificateManager())
                        .setNegativeButton("关闭", null).show();
            }
        });
    }

    private void showNativeCertificateList(JSONObject state) {
        org.json.JSONArray certs = state.optJSONArray("certs");
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(10), dp(6), dp(10), dp(6));
        int count = certs == null ? 0 : certs.length();
        for (int i = 0; i < count; i++) {
            JSONObject cert = certs.optJSONObject(i);
            if (cert == null) continue;
            String id = cert.optString("id", "");
            if (!"pg_mitm_ca".equals(id) && !"pg_https_ca".equals(id)) continue;
            String name = cert.optString("name", id);
            boolean released = cert.optBoolean("released", false);
            boolean disabled = cert.optBoolean("disabled", false);
            boolean system = cert.optBoolean("system", false);
            boolean apex = cert.optBoolean("apex", false);
            String apexNs = cert.optString("apex_ns", "not-applicable");
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackground(uiPanelDrawable());
            TextView title = new TextView(this);
            title.setText(name + " · " + id);
            title.setTextSize(14);
            title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            title.setTextColor(0xff17212b);
            TextView status = new TextView(this);
            status.setText("子模块：" + (released ? "已释放" : "未安装")
                    + " · 开关：" + (disabled ? "已禁用" : "未禁用")
                    + "\n系统 CA 文件：" + (system ? "存在" : "未发现")
                    + " · APEX：" + (apex ? apexNs : "不适用"));
            status.setTextSize(11);
            status.setTextColor(0xff718091);
            status.setPadding(0, dp(4), 0, dp(6));
            card.addView(title);
            card.addView(status);
            LinearLayout actions = new LinearLayout(this);
            actions.setOrientation(LinearLayout.HORIZONTAL);
            Button enable = new Button(this);
            enable.setAllCaps(false);
            enable.setText("启用");
            enable.setEnabled(!released || disabled || !system || (apex && !"verified".equals(apexNs)));
            enable.setOnClickListener(v -> runNativeCertificateAction("enable", id));
            actions.addView(enable, new LinearLayout.LayoutParams(0, dp(44), 1));
            Button disable = new Button(this);
            disable.setAllCaps(false);
            disable.setText("禁用");
            disable.setEnabled(released && !disabled);
            disable.setOnClickListener(v -> runNativeCertificateAction("disable", id));
            actions.addView(disable, new LinearLayout.LayoutParams(0, dp(44), 1));
            Button remove = new Button(this);
            remove.setAllCaps(false);
            remove.setText("移除");
            remove.setEnabled(released);
            remove.setOnClickListener(v -> new AlertDialog.Builder(this)
                    .setTitle("移除系统 CA")
                    .setMessage("将移除 " + id + " 子模块并同步解除其系统信任。此操作不会写入用户证书区。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("确认移除", (d, w) -> runNativeCertificateAction("remove", id)).show());
            actions.addView(remove, new LinearLayout.LayoutParams(0, dp(44), 1));
            card.addView(actions);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(2), dp(3), dp(2), dp(5));
            list.addView(card, lp);
        }
        if (count == 0) {
            TextView empty = new TextView(this);
            empty.setText("没有发现内置 CA 条目。");
            empty.setPadding(dp(14), dp(14), dp(14), dp(14));
            list.addView(empty);
        }
        TextView summary = new TextView(this);
        summary.setText("系统信任状态以 certmgr 的实际 /system 与 Android 14+ Conscrypt APEX 校验结果为准；“已释放”不等于“已受信任”。");
        summary.setTextColor(0xff718091);
        summary.setTextSize(11);
        summary.setPadding(dp(8), dp(8), dp(8), dp(8));
        list.addView(summary);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(list);
        nativeCertificateDialog = new AlertDialog.Builder(this).setTitle("系统 CA 管理")
                .setView(scroll)
                .setNeutralButton("同步信任状态", (d, w) -> runNativeCertificateAction("sync", null))
                .setPositiveButton("刷新", (d, w) -> showNativeCertificateManager())
                .setNegativeButton("关闭", null).create();
        nativeCertificateDialog.show();
    }

    private void runNativeCertificateAction(String action, String id) {
        if (nativeCertificateDialog != null && nativeCertificateDialog.isShowing()) {
            nativeCertificateDialog.dismiss();
        }
        if (!"enable".equals(action) && !"disable".equals(action)
                && !"remove".equals(action) && !"sync".equals(action)) return;
        String command = "sh \"$MP/scripts/certmgr.sh\" builtin " + action
                + (id == null ? "" : " " + shellQuote(id));
        runNativeModuleCommand(command, 120000L, result -> {
            String output = result.output == null ? "" : result.output.trim();
            boolean ok = false;
            String detail = output;
            try {
                int begin = output.indexOf('{'), end = output.lastIndexOf('}');
                if (begin >= 0 && end > begin) {
                    JSONObject response = new JSONObject(output.substring(begin, end + 1));
                    ok = result.exitCode == 0 && response.optBoolean("ok", false);
                    detail = response.optString("detail", output);
                }
            } catch (Exception ignored) { }
            Toast.makeText(this, (ok ? "证书操作完成：" : "证书操作未确认：") + detail,
                    Toast.LENGTH_LONG).show();
            nativeVpnHandler.postDelayed(this::showNativeCertificateManager, 900L);
        });
    }

    private void showNativeRuntimeLogs() {
        runNativeModuleCommand("find /data/adb/privacyguard -type f -name '*.log' -print 2>/dev/null | head -n 8 | while IFS= read -r f; do [ -f \"$f\" ] || continue; echo \"===== $f =====\"; tail -n 80 \"$f\"; done", 30000L, result -> {
            String output = result.output == null ? "" : result.output.trim();
            if (output.isEmpty()) output = "当前没有可读取的 FX 模块日志。";
            if (output.length() > 24000) output = output.substring(0, 24000) + "\\n…（已截断）";
            ScrollView scroll = new ScrollView(this);
            TextView text = new TextView(this);
            text.setText(output);
            text.setTextIsSelectable(true);
            text.setTypeface(Typeface.MONOSPACE);
            text.setTextSize(11);
            text.setPadding(dp(14), dp(12), dp(14), dp(12));
            scroll.addView(text);
            new AlertDialog.Builder(this).setTitle("FX 运行日志")
                    .setView(scroll).setPositiveButton("关闭", null).show();
        });
    }

    private void refreshHookRemoteStatus(TextView target) {
        Thread previous = hookStatusThread;
        if (previous != null) previous.interrupt();
        final int generation = ++hookStatusGeneration;
        target.setText("正在读取设备端 Remote Files 状态…");
        Thread worker = new Thread(() -> {
            RootAccess.Result result = RootAccess.execute(
                    "sh /data/adb/modules/privacyguard/scripts/status.sh json",
                    30000L, 64 * 1024);
            String display;
            if (result.exitCode != 0) {
                String detail = result.output == null ? "" : result.output.trim();
                if (detail.length() > 500) detail = detail.substring(0, 500) + "…";
                display = "Remote Files 状态读取失败（退出码 " + result.exitCode + "）。"
                        + (detail.isEmpty() ? "" : "\n" + detail);
            } else {
                try {
                    JSONObject status = new JSONObject(result.output.trim());
                    String remote = status.optString("hook_remote_status", "unknown");
                    String remoteLabel;
                    if ("ok".equals(remote)) remoteLabel = "最近一次发布成功";
                    else if ("failed".equals(remote)) remoteLabel = "最近一次发布失败";
                    else if ("framework_missing".equals(remote)) remoteLabel = "未检测到 LSPosed 框架";
                    else remoteLabel = "未知 / 尚无状态文件";
                    if (!"1".equals(status.optString("hook_native_config_found", "0"))) {
                        display = "Remote Files：" + remoteLabel
                                + "（目标数 " + status.optInt("hook_remote_targets", 0) + "）"
                                + "\n未找到原生 FX Hook 配置文件；请先保存并发布配置。"
                                + "\n此状态不证明 LSPosed 作用域或目标进程已注入。";
                    } else {
                        display = "Remote Files：" + remoteLabel
                                + "（目标数 " + status.optInt("hook_remote_targets", 0) + "）"
                                + " · 原生配置用户数 " + status.optInt("hook_native_config_users", 0)
                                + " · 原生目标数 " + status.optInt("hook_native_targets", 0)
                                + "\n通知权限提示：主开关 " + status.optString("hook_native_notification_permission_hide_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_notification_permission_hide_targets", 0)
                                + "\n通知监听阻止：主开关 " + status.optString("hook_native_notification_listen_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_notification_listen_targets", 0)
                                + "\n剪贴板隔离：主开关 " + status.optString("hook_native_clipboard_isolate_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_clipboard_isolate_targets", 0)
                                + "\n会员只读诊断：启用 " + status.optString("hook_native_member_diag_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_member_diag_targets", 0)
                                + "\n隐私 Hook：主开关 " + status.optString("hook_native_privacy_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_privacy_targets", 0)
                                + "\nWi-Fi 扫描限制：主开关 " + status.optString("hook_native_wifi_scan_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_wifi_scan_targets", 0)
                                + "\n此状态仅反映设备端原生配置和发布状态；不证明 LSPosed 作用域或目标进程已注入。";
                    }
                } catch (Exception malformed) {
                    // Older module revisions print key/value text instead of JSON.
                    // Show the bounded raw status rather than falsely reporting that
                    // the device-side command failed.
                    String raw = result.output == null ? "" : result.output.trim();
                    if (raw.length() > 4000) raw = raw.substring(0, 4000) + "\n…（内容已截断）";
                    display = raw.isEmpty()
                            ? "设备端状态脚本没有返回可显示的状态。"
                            : "设备端状态输出（原始格式）：\n" + raw;
                }
            }
            final String message = display;
            if (hookStatusThread == Thread.currentThread()) hookStatusThread = null;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != hookStatusGeneration
                        || !hookUiVisible || !hookHubVisible) return;
                target.setText(message);
            });
        }, "fx-hook-remote-status");
        worker.setDaemon(true);
        hookStatusThread = worker;
        worker.start();
    }

    private void cancelHookStatusRefresh() {
        hookStatusGeneration++;
        Thread worker = hookStatusThread;
        hookStatusThread = null;
        if (worker != null) worker.interrupt();
    }

    private boolean isLsposedManagerInstalled() {
        try {
            getPackageManager().getPackageInfo("org.lsposed.manager", 0);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private void openLsposedManager() {
        try {
            Intent launch = getPackageManager().getLaunchIntentForPackage("org.lsposed.manager");
            if (launch != null) startActivity(launch);
            else Toast.makeText(this, "未找到 LSPosed Manager，请确认已安装", Toast.LENGTH_LONG).show();
        } catch (Exception e) {
            Toast.makeText(this, "打开 LSPosed Manager 失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private boolean isAccessibilityEnabled() {
        String enabled = android.provider.Settings.Secure.getString(
                getContentResolver(), android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        return enabled != null && (enabled.contains(getPackageName() + "/.FxAccessibilityService")
                || enabled.contains(getPackageName() + "/" + getPackageName() + ".FxAccessibilityService"));
    }

    @Override protected void onDestroy() {
        nativeVpnHandler.removeCallbacksAndMessages(null);
        nativeVpnExecutor.shutdownNow();
        nativeVpnModeButtons.clear();
        nativeVpnSwitch = null;
        nativeVpnNodeButton = null;
        nativeVpnState = null;
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        Thread publisher = hookPublisherThread;
        hookPublisherThread = null;
        if (publisher != null) publisher.interrupt();
        Thread appLoader = appLoaderThread;
        appLoaderThread = null;
        appLoadGeneration++;
        if (appLoader != null) appLoader.interrupt();

        // Complete pending WebView callbacks before tearing down the view. Otherwise
        // a cancelled document picker can retain the old Activity across recreation.
        ValueCallback<Uri[]> pendingFileChooser = fileChooserCallback;
        fileChooserCallback = null;
        deliverFileChooserResult(pendingFileChooser, null);
        if (rootBridge != null) {
            rootBridge.close();
            rootBridge = null;
        }
        if (webView != null) {
            webView.stopLoading();
            ViewParent parent = webView.getParent();
            if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
            webView.removeJavascriptInterface("FXRoot");
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
            webView = null;
        }
        webViewLoaded = false;
        webUiReady = false;
        pendingWebPage = null;
        super.onDestroy();
    }


    private static void deliverFileChooserResult(ValueCallback<Uri[]> callback, Uri[] result) {
        if (callback == null) return;
        try {
            callback.onReceiveValue(result);
        } catch (RuntimeException ignored) {
            // A stale WebView callback must never abort Activity cleanup or navigation.
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_NATIVE_SCRIPT_EXPORT) {
            String payload = pendingNativeScriptExport;
            pendingNativeScriptExport = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null || payload == null) return;
            try (java.io.OutputStream output = getContentResolver().openOutputStream(data.getData())) {
                if (output == null) throw new IllegalStateException("无法写入目标文件");
                output.write(payload.getBytes(StandardCharsets.UTF_8));
                output.flush();
                Toast.makeText(this, "脚本配置已导出", Toast.LENGTH_SHORT).show();
            } catch (Exception error) {
                Toast.makeText(this, "导出失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
            }
            return;
        }
        if (requestCode == REQUEST_NATIVE_SCRIPT_FILE) {
            if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
            Uri uri = data.getData();
            try (InputStream input = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选文件");
                byte[] buffer = new byte[8192];
                int total = 0, count;
                while ((count = input.read(buffer)) != -1) {
                    total += count;
                    if (total > 1024 * 1024) throw new IllegalStateException("脚本文件超过 1 MiB");
                    output.write(buffer, 0, count);
                }
                String name = uri.getLastPathSegment();
                String content = new String(output.toByteArray(), StandardCharsets.UTF_8);
                boolean isScriptJson = false;
                try {
                    isScriptJson = "FX-SCRIPT-LIST".equals(new JSONObject(content).optString("format"));
                } catch (Exception ignored) { }
                if ((name != null && name.toLowerCase(Locale.ROOT).endsWith(".json")) || isScriptJson) {
                    importNativeScriptDocument(content);
                } else {
                    addNativeScriptValue(content, name == null ? "文件导入" : name);
                }
            } catch (Exception error) {
                Toast.makeText(this, "脚本导入失败：" + error.getMessage(), Toast.LENGTH_LONG).show();
            }
            return;
        }
        if (requestCode == REQUEST_FILE_PICKER && fileChooserCallback != null) {
            ValueCallback<Uri[]> pending = fileChooserCallback;
            fileChooserCallback = null;
            Uri[] results = null;
            try {
                results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
            } catch (RuntimeException malformedResult) {
                // Always complete the accepted WebView callback, even if the picker
                // returns a malformed result or the provider disappears.
            }
            deliverFileChooserResult(pending, results);
        }
    }

    @Override public void onBackPressed() {
        if (hookTargetVisible) { showAppList(); return; }
        if (settingsUiVisible) { showDashboard(); return; }
        if (hookUiVisible && !hookHubVisible) { showHookHub(); return; }
        if (hookHubVisible) { showWebDashboard(); return; }
        if (webView != null && webView.canGoBack()) { webView.goBack(); return; }
        super.onBackPressed();
    }

    public void showAppListFromBridge() { showAppList(); }

    private void checkRoot(TextView state, boolean request) {
        checkRoot(state, request, null);
    }

    private void checkRoot(TextView state, boolean request, Runnable afterCheck) {
        state.setText(request ? "正在请求 KernelSU 授权…" : "正在检查 Root…");
        new Thread(() -> {
            RootAccess.Result result = RootAccess.execute("id -u; if [ -s /data/adb/modules/privacyguard/module.prop ] && grep -qx 'version=1.0.0' /data/adb/modules/privacyguard/module.prop; then if [ -e /data/adb/modules/privacyguard/disable ]; then echo FX_MODULE=disabled; elif [ -e /data/adb/modules/privacyguard/remove ]; then echo FX_MODULE=remove-pending; else echo FX_MODULE=enabled; fi; else echo FX_MODULE=missing; fi; (command -v ksud >/dev/null 2>&1 || test -x /data/adb/ksu/bin/ksud) && echo KSU_TOOL=present || echo KSU_TOOL=not-found");
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (result.exitCode == 0 && result.output.trim().startsWith("0")) {
                    String moduleState = result.output.contains("FX_MODULE=enabled") ? "模块启用标记存在"
                            : result.output.contains("FX_MODULE=disabled") ? "模块已禁用"
                            : result.output.contains("FX_MODULE=remove-pending") ? "模块待卸载"
                            : "模块缺失/版本不符";
                    state.setText("Root UID 0 · FX " + moduleState + " · KSU 工具 "
                            + (result.output.contains("KSU_TOOL=present") ? "存在" : "未检测到"));
                } else if (result.denied) {
                    state.setText("尚未获得 Root 授权。请在 KernelSU 管理器中允许 FX 应用。");
                } else {
                    state.setText("Root 不可用或请求失败：\\n" + result.output);
                }
                if (afterCheck != null) afterCheck.run();
            });
        }, "fx-root-check").start();
    }

    private String normalizeUiMode(String mode) {
        if ("miuix".equals(mode) || "glass".equals(mode) || "web".equals(mode)
                || "classic".equals(mode)) return mode;
        return "classic";
    }

    private int dp(float v) { return (int)(v * getResources().getDisplayMetrics().density + .5f); }
    private int uiBackgroundColor() {
        if ("miuix".equals(uiMode)) return 0xfff3f5fa;
        if ("glass".equals(uiMode)) return 0xffe8eef4;
        return 0xfff4f6f8;
    }
    private int uiSurfaceColor() {
        if ("miuix".equals(uiMode)) return 0xffeaf0fb;
        if ("glass".equals(uiMode)) return 0xddefffff;
        return 0xffffffff;
    }
    private GradientDrawable roundedDrawable(int color, int strokeColor) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp("glass".equals(uiMode) ? 24 : "miuix".equals(uiMode) ? 20 : 8));
        if (strokeColor != 0) d.setStroke(dp(1), strokeColor);
        return d;
    }
    private android.graphics.drawable.Drawable uiPanelDrawable() {
        return roundedDrawable(uiSurfaceColor(), "glass".equals(uiMode) ? 0x66ffffff : 0);
    }
    private void applyWebUiMode() {
        if (webView == null || !webUiReady) return;
        // Only the explicit legacy mode styles the WebView. Miuix and Liquid Glass
        // are native Compose renderers; do not imitate either with injected CSS.
        String css = "classic".equals(uiMode)
                ? "body{background:#f4f6f8!important;color:#17212b!important}" +
                  ".card,.panel,.setting-card,.section,.list-item,.config-card{border-radius:8px!important;box-shadow:none!important}" +
                  "button,.btn,input,select,textarea{border-radius:6px!important}"
                : "";
        String js = "(function(){var id='fx-interface-mode-style';var old=document.getElementById(id);if(old)old.remove();" +
                (css.isEmpty() ? "" : "var s=document.createElement('style');s.id=id;s.textContent=" + JSONObject.quote(css) + ";document.head.appendChild(s);") + "})()";
        webView.evaluateJavascript(js, null);
    }
    private TextView title(String value, int size) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD); t.setTextColor("glass".equals(uiMode) ? 0xff24394c : "miuix".equals(uiMode) ? 0xff202b3c : 0xff17212b);
        t.setPadding(dp(18), dp(14), dp(18), dp(10)); return t;
    }
    private void base(String heading) {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(uiBackgroundColor());
        ScrollView scroll = new ScrollView(this);
        scroll.setClipToPadding(false);
        scroll.setPadding(0, 0, 0, dp(76));
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.addView(title("FX", 25));
        TextView h = title(heading, 18);
        h.setPadding(dp(18), dp(2), dp(18), dp(12));
        content.addView(h);
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, -1));
        this.content = content;
        mountNativeShell(root);
    }

    private void attachHiddenWebViewBridge() {
        if (webView == null || root == null) return;
        ViewParent parent = webView.getParent();
        if (parent instanceof ViewGroup && parent != root) ((ViewGroup) parent).removeView(webView);
        webView.setVisibility(View.INVISIBLE);
        webView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        webView.onResume();
        webView.resumeTimers();
        if (webView.getParent() == null) root.addView(webView, new LinearLayout.LayoutParams(1, 1));
    }

    private LinearLayout content;
    private ScrollView nativeScroll;
    private String pendingPrivacySection;
    // Preserve the originating Privacy category while navigating through the app picker
    // and per-app editor. The pending field is only a scroll request; the active field is
    // the navigation context and survives editor rebuilds and return navigation.
    private String activePrivacySection;
    private void showAppList() { showAppList(null); }

    private void showAppList(String privacySection) {
        activePrivacySection = privacySection;
        pendingPrivacySection = privacySection;
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        pauseAndDetachWebView();
        hookUiVisible = true;
        settingsUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        selectedPackage = null; selectedBottomTab = activePrivacySection == null ? 4 : 2; base("选择应用");
        Button home = new Button(this); home.setText("授权状态与系统设置"); home.setOnClickListener(v -> showHookHub()); content.addView(home);
        search = new EditText(this); search.setSingleLine(true); search.setHint("搜索应用名称或包名");
        search.setPadding(dp(16), dp(10), dp(16), dp(10));
        content.addView(search, new LinearLayout.LayoutParams(-1, -2));
        TextView hint = new TextView(this); hint.setText("点击应用进入独立 Hook 配置"); hint.setTextColor(0xff66727e);
        hint.setPadding(dp(18), dp(8), dp(18), dp(8)); content.addView(hint);
        TextView loading = new TextView(this);
        loading.setText("正在后台读取已安装应用…");
        loading.setPadding(dp(18), dp(20), dp(18), dp(20));
        content.addView(loading);
        appsLoaded = false;
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s,int st,int c,int a) {}
            public void onTextChanged(CharSequence s,int st,int before,int count) {
                if (appsLoaded) renderApps(s.toString());
            }
            public void afterTextChanged(Editable e) {}
        });
        loadAppsAsync();
    }
    private void loadAppsAsync() {
        Thread previous = appLoaderThread;
        if (previous != null) previous.interrupt();
        final int generation = ++appLoadGeneration;
        Thread loader = new Thread(() -> {
            List<ApplicationInfo> loadedApps = new ArrayList<>();
            Map<String, String> loadedLabels = new HashMap<>();
            String failure = null;
            try {
                PackageManager pm = getPackageManager();
                for (ApplicationInfo ai : pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                    if (Thread.currentThread().isInterrupted()) return;
                    if ((ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                            && ai.packageName.startsWith("com.android.")) continue;
                    if (ai.packageName.equals(getPackageName()) || ai.packageName.equals("android")) continue;
                    loadedApps.add(ai);
                    try {
                        CharSequence label = pm.getApplicationLabel(ai);
                        loadedLabels.put(ai.packageName, label == null ? ai.packageName : label.toString());
                    } catch (RuntimeException unavailable) {
                        // A package may disappear while the PackageManager snapshot is being read.
                        loadedLabels.put(ai.packageName, ai.packageName);
                    }
                }
                Collections.sort(loadedApps, new Comparator<ApplicationInfo>() {
                    public int compare(ApplicationInfo a, ApplicationInfo b) {
                        return loadedLabels.get(a.packageName)
                                .compareToIgnoreCase(loadedLabels.get(b.packageName));
                    }
                });
            } catch (RuntimeException error) {
                failure = error.getClass().getSimpleName() + ": " + error.getMessage();
            }
            final String loadFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != appLoadGeneration
                        || !hookUiVisible || hookHubVisible || hookTargetVisible) return;
                appLoaderThread = null;
                apps.clear();
                apps.addAll(loadedApps);
                appLabels.clear();
                appLabels.putAll(loadedLabels);
                appIcons.clear();
                appsLoaded = loadFailure == null;
                while (content.getChildCount() > 5) content.removeViewAt(5);
                if (loadFailure != null) {
                    TextView error = new TextView(this);
                    error.setText("读取应用列表失败：" + loadFailure + "\n请检查应用列表权限后重试。");
                    error.setPadding(dp(18), dp(20), dp(18), dp(20));
                    content.addView(error);
                    Button retry = new Button(this);
                    retry.setText("重新读取应用列表");
                    retry.setOnClickListener(v -> loadAppsAsync());
                    content.addView(retry);
                } else {
                    renderApps(search == null ? "" : search.getText().toString());
                    if (pendingRestorePackage != null) {
                        String restorePackage = pendingRestorePackage;
                        pendingRestorePackage = null;
                        ApplicationInfo target = findApp(restorePackage);
                        if (target != null) showTarget(target);
                        else Toast.makeText(MainActivity.this,
                                "上次配置的应用已卸载，已返回应用列表。", Toast.LENGTH_LONG).show();
                    }
                }
            });
        }, "fx-app-index");
        appLoaderThread = loader;
        loader.start();
    }
    private void renderApps(String query) {
        if (!appsLoaded) return;
        cancelAppIconLoad();
        // Keep the fixed header, search field, and hint (children 0..4).
        // Replace only the loading indicator and previously rendered result rows.
        while (content.getChildCount() > 5) content.removeViewAt(5);
        filtered.clear();
        String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
        for (ApplicationInfo ai : apps) {
            String label = appLabels.get(ai.packageName);
            if (label == null) label = ai.packageName;
            if (label.toLowerCase(Locale.ROOT).contains(q)
                    || ai.packageName.toLowerCase(Locale.ROOT).contains(q)) filtered.add(ai);
        }
        if (filtered.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("没有匹配的应用");
            empty.setPadding(dp(18), dp(20), dp(18), dp(20));
            content.addView(empty);
            return;
        }
        appendAppRows(0, Math.min(MAX_APP_ROWS_PER_PAGE, filtered.size()));
    }

    private void appendAppRows(int start, int end) {
        for (int i = start; i < end; i++) {
            ApplicationInfo ai = filtered.get(i);
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(16), dp(10), dp(16), dp(10));
            row.setBackgroundColor(0xffffffff);
            ImageView icon = new ImageView(this);
            Drawable drawable = appIcons.get(ai.packageName);
            if (drawable != null) {
                icon.setImageDrawable(drawable);
                icon.setTag(Boolean.TRUE);
            } else {
                icon.setImageResource(android.R.drawable.sym_def_app_icon);
                icon.setTag(Boolean.FALSE);
            }
            appIconViews.put(ai.packageName, icon);
            row.addView(icon, new LinearLayout.LayoutParams(dp(42), dp(42)));
            LinearLayout labels = new LinearLayout(this);
            labels.setOrientation(LinearLayout.VERTICAL);
            labels.setPadding(dp(12), 0, 0, 0);
            TextView name = new TextView(this);
            name.setText(appLabels.containsKey(ai.packageName)
                    ? appLabels.get(ai.packageName) : ai.packageName);
            name.setTextSize(16);
            name.setTextColor(0xff17212b);
            TextView pkg = new TextView(this);
            pkg.setText(ai.packageName);
            pkg.setTextSize(11);
            pkg.setTextColor(0xff75808a);
            labels.addView(name);
            labels.addView(pkg);
            row.addView(labels, new LinearLayout.LayoutParams(0, -2, 1));
            TextView arrow = new TextView(this);
            arrow.setText("›");
            arrow.setTextSize(28);
            arrow.setTextColor(0xff637080);
            row.addView(arrow);
            row.setOnClickListener(v -> showTarget(ai));
            content.addView(row, new LinearLayout.LayoutParams(-1, -2));
            View divider = new View(this);
            divider.setBackgroundColor(0xffe8ebee);
            content.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
        }
        if (end < filtered.size()) {
            Button more = new Button(this);
            more.setText("加载更多应用（" + (filtered.size() - end) + "）");
            more.setOnClickListener(v -> {
                int nextEnd = Math.min(end + MAX_APP_ROWS_PER_PAGE, filtered.size());
                int oldCount = content.getChildCount();
                // Remove the previous pagination control before appending the next page.
                if (oldCount > 4 && content.getChildAt(oldCount - 1) == more) {
                    content.removeViewAt(oldCount - 1);
                }
                appendAppRows(end, nextEnd);
            });
            content.addView(more, new LinearLayout.LayoutParams(-1, -2));
        }
        loadMissingAppIconsAsync();
    }

    private void loadMissingAppIconsAsync() {
        List<ApplicationInfo> missing = new ArrayList<>();
        for (ApplicationInfo ai : apps) {
            ImageView view = appIconViews.get(ai.packageName);
            if (view != null && !Boolean.TRUE.equals(view.getTag())
                    && !appIcons.containsKey(ai.packageName)) missing.add(ai);
        }
        if (missing.isEmpty()) return;
        Thread previous = appIconLoaderThread;
        if (previous != null) previous.interrupt();
        final int generation = ++appIconLoadGeneration;
        Thread worker = new Thread(() -> {
            Map<String, Drawable> loaded = new LinkedHashMap<>();
            PackageManager pm = getPackageManager();
            for (ApplicationInfo ai : missing) {
                if (Thread.currentThread().isInterrupted()) return;
                try {
                    Drawable drawable = pm.getApplicationIcon(ai);
                    if (drawable != null) loaded.put(ai.packageName, drawable);
                } catch (RuntimeException unavailable) {
                    // The package may be removed while icons are being decoded.
                }
            }
            if (Thread.currentThread().isInterrupted()) return;
            if (appIconLoaderThread == Thread.currentThread()) appIconLoaderThread = null;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != appIconLoadGeneration
                        || !hookUiVisible || hookTargetVisible || hookHubVisible) return;
                for (Map.Entry<String, Drawable> entry : loaded.entrySet()) {
                    appIcons.put(entry.getKey(), entry.getValue());
                    ImageView target = appIconViews.get(entry.getKey());
                    if (target != null && target.getParent() != null) {
                        target.setImageDrawable(entry.getValue());
                        target.setTag(Boolean.TRUE);
                    }
                }
            });
        }, "fx-app-icons");
        worker.setDaemon(true);
        appIconLoaderThread = worker;
        worker.start();
    }

    private void cancelAppIconLoad() {
        appIconLoadGeneration++;
        Thread worker = appIconLoaderThread;
        appIconLoaderThread = null;
        if (worker != null) worker.interrupt();
        appIconViews.clear();
    }

    private String key(String feature) { return selectedPackage + ":" + feature; }
    private boolean get(String feature) { return getPreferences(0).getBoolean(key(feature), false); }
    private void showTarget(ApplicationInfo ai) {
        cancelAppIconLoad();
        try {
            // The package may have been uninstalled after the background app index was built.
            ai = getPackageManager().getApplicationInfo(ai.packageName, 0);
        } catch (PackageManager.NameNotFoundException removed) {
            Toast.makeText(this, "该应用已卸载，正在刷新应用列表。", Toast.LENGTH_LONG).show();
            showAppList(activePrivacySection);
            return;
        }
        hookUiVisible = true;
        settingsUiVisible = false;
        hookTargetVisible = true;
        hookHubVisible = false;
        selectedPackage = ai.packageName;
        try {
            CharSequence label = getPackageManager().getApplicationLabel(ai);
            selectedLabel = label == null ? ai.packageName : label.toString();
        } catch (RuntimeException unavailable) {
            selectedLabel = ai.packageName;
        }
        base(selectedLabel);
        TextView pkg=new TextView(this); pkg.setText(selectedPackage); pkg.setTextColor(0xff687582);
        pkg.setPadding(dp(18),0,dp(18),dp(12)); content.addView(pkg);
        boolean targetDebuggable = (ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        TextView scopeNotice = new TextView(this);
        scopeNotice.setText("LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置。本页只发布 FX Hook 规则，不会自动授予或修改 LSPosed 作用域。");
        scopeNotice.setTextColor(0xff697681);
        scopeNotice.setPadding(dp(18), dp(4), dp(18), dp(12));
        content.addView(scopeNotice);
        TextView targetBuildState = new TextView(this);
        targetBuildState.setText(targetDebuggable
                ? "目标应用：可调试版本（自定义只读 Hook 可执行）"
                : "目标应用：非调试版本（自定义只读 Hook 暂不执行）");
        targetBuildState.setTextColor(0xff697681);
        targetBuildState.setPadding(dp(18),0,dp(18),dp(12));
        content.addView(targetBuildState);
        section("广告识别");
        TextView adNote=new TextView(this);
        adNote.setText("广告类型由内置识别引擎自动判断，无需按应用配置启动页、信息流或弹窗开关。");
        adNote.setTextColor(0xff697681); adNote.setPadding(dp(18),dp(2),dp(18),dp(14)); content.addView(adNote);
        section("隐私 Hook");
        toggle("隐私保护总开关", "privacy", false);
        section("标识与追踪");
        toggle("统一广告标识（应用内）", "ad_id_unify", false);
        section("剪贴板保护");
        toggle("阻止剪贴板读取", "clipboard_read_block", false);
        toggle("隔离剪贴板", "clipboard_isolate", false);
        section("Wi-Fi 网络隐私");
        toggle("限制 Wi-Fi 扫描", "wifi_scan_block", false);
        section("Wi-Fi 环境模拟");
        TextView wifiSimulationNote = new TextView(this);
        wifiSimulationNote.setText("仅在本地 debuggable 目标应用的 LSPosed 进程中覆盖 WifiInfo.getSSID()/getBSSID() 返回值；不更改系统真实 Wi-Fi 连接或扫描结果。");
        wifiSimulationNote.setTextColor(0xff697681);
        wifiSimulationNote.setPadding(dp(18), dp(2), dp(18), dp(8));
        content.addView(wifiSimulationNote);
        EditText simulatedSsid = new EditText(this);
        simulatedSsid.setSingleLine(true);
        simulatedSsid.setHint("测试 SSID（最多 32 字节）");
        simulatedSsid.setText(getPreferences(0).getString(selectedPackage + ":wifi_sim_ssid", ""));
        EditText simulatedBssid = new EditText(this);
        simulatedBssid.setSingleLine(true);
        simulatedBssid.setHint("测试 BSSID（AA:BB:CC:DD:EE:FF）");
        simulatedBssid.setText(getPreferences(0).getString(selectedPackage + ":wifi_sim_bssid", ""));
        Switch simulateWifi = new Switch(this);
        simulateWifi.setText("启用此应用的 Wi-Fi 标识模拟");
        simulateWifi.setChecked(getPreferences(0).getBoolean(selectedPackage + ":wifi_simulate", false));
        simulateWifi.setEnabled(targetDebuggable);
        simulatedSsid.setEnabled(targetDebuggable);
        simulatedBssid.setEnabled(targetDebuggable);
        Button saveWifiSimulation = new Button(this);
        saveWifiSimulation.setAllCaps(false);
        saveWifiSimulation.setText("保存并发布 Wi-Fi 测试配置");
        saveWifiSimulation.setEnabled(targetDebuggable);
        saveWifiSimulation.setOnClickListener(v -> {
            String ssid = simulatedSsid.getText().toString();
            String bssid = simulatedBssid.getText().toString().trim();
            boolean enabled = simulateWifi.isChecked();
            if (enabled && ssid.isEmpty() && bssid.isEmpty()) {
                Toast.makeText(this, "至少填写 SSID 或 BSSID。", Toast.LENGTH_LONG).show(); return;
            }
            if (ssid.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 32
                    || ssid.contains(",") || ssid.contains("|")
                    || ssid.indexOf('\n') >= 0 || ssid.indexOf('\r') >= 0) {
                Toast.makeText(this, "SSID 不能超过 32 字节或包含逗号、换行。", Toast.LENGTH_LONG).show(); return;
            }
            if (!bssid.isEmpty() && !bssid.matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}")) {
                Toast.makeText(this, "BSSID 格式应为 AA:BB:CC:DD:EE:FF。", Toast.LENGTH_LONG).show(); return;
            }
            getPreferences(0).edit()
                    .putBoolean(selectedPackage + ":wifi_simulate", enabled)
                    .putString(selectedPackage + ":wifi_sim_ssid", ssid)
                    .putString(selectedPackage + ":wifi_sim_bssid", bssid)
                    .apply();
            publishConfig();
        });
        content.addView(simulatedSsid);
        content.addView(simulatedBssid);
        content.addView(simulateWifi);
        content.addView(saveWifiSimulation);
        section("网络类型模拟");
        TextView networkSimulationNote = new TextView(this);
        networkSimulationNote.setText("仅在 debuggable 目标进程中覆盖 NetworkInfo 类型和 NetworkCapabilities.hasTransport() 判断；不改变系统实际连接、路由或 VPN。");
        networkSimulationNote.setTextColor(0xff697681);
        networkSimulationNote.setPadding(dp(18), dp(2), dp(18), dp(8));
        content.addView(networkSimulationNote);
        String[] networkModes = {"wifi", "cellular"};
        String[] networkModeLabels = {"Wi-Fi", "移动数据"};
        String savedNetworkMode = getPreferences(0).getString(selectedPackage + ":network_type", "wifi");
        final String[] chosenNetworkMode = { "cellular".equals(savedNetworkMode) ? "cellular" : "wifi" };
        TextView chosenNetworkModeText = new TextView(this);
        chosenNetworkModeText.setText("当前模拟类型：" + ("cellular".equals(chosenNetworkMode[0]) ? "移动数据" : "Wi-Fi"));
        chosenNetworkModeText.setTextColor(0xff526170);
        chosenNetworkModeText.setPadding(dp(18), dp(4), dp(18), dp(4));
        Button chooseNetworkMode = new Button(this);
        chooseNetworkMode.setAllCaps(false);
        chooseNetworkMode.setText("选择模拟网络类型");
        chooseNetworkMode.setOnClickListener(v -> {
            int selectedMode = "cellular".equals(chosenNetworkMode[0]) ? 1 : 0;
            new AlertDialog.Builder(this).setTitle("网络类型")
                    .setSingleChoiceItems(networkModeLabels, selectedMode,
                            (dialog, which) -> chosenNetworkMode[0] = networkModes[which])
                    .setPositiveButton("确定", (dialog, which) -> chosenNetworkModeText.setText(
                            "当前模拟类型：" + ("cellular".equals(chosenNetworkMode[0]) ? "移动数据" : "Wi-Fi")))
                    .setNegativeButton("取消", null).show();
        });
        Switch simulateNetworkType = new Switch(this);
        simulateNetworkType.setText("启用此应用的网络类型模拟");
        simulateNetworkType.setChecked(getPreferences(0).getBoolean(selectedPackage + ":network_type_sim", false));
        simulateNetworkType.setEnabled(targetDebuggable);
        chooseNetworkMode.setEnabled(targetDebuggable);
        Button saveNetworkType = new Button(this);
        saveNetworkType.setAllCaps(false);
        saveNetworkType.setText("保存并发布网络类型配置");
        saveNetworkType.setEnabled(targetDebuggable);
        saveNetworkType.setOnClickListener(v -> {
            getPreferences(0).edit()
                    .putBoolean(selectedPackage + ":network_type_sim", simulateNetworkType.isChecked())
                    .putString(selectedPackage + ":network_type", chosenNetworkMode[0])
                    .apply();
            publishConfig();
        });
        content.addView(chosenNetworkModeText);
        content.addView(chooseNetworkMode);
        content.addView(simulateNetworkType);
        content.addView(saveNetworkType);
        section("设备标识模拟");
        TextView androidIdNote = new TextView(this);
        androidIdNote.setText("只覆盖此 debuggable 目标进程读取 Settings.Secure.ANDROID_ID 的结果；不会更改系统 Android ID 或其他应用。");
        androidIdNote.setTextColor(0xff697681);
        androidIdNote.setPadding(dp(18), dp(2), dp(18), dp(8));
        content.addView(androidIdNote);
        EditText simulatedAndroidId = new EditText(this);
        simulatedAndroidId.setSingleLine(true);
        simulatedAndroidId.setHint("16 位十六进制 Android ID");
        simulatedAndroidId.setText(getPreferences(0).getString(selectedPackage + ":android_id", ""));
        Switch simulateAndroidId = new Switch(this);
        simulateAndroidId.setText("启用此应用的 Android ID 测试值");
        simulateAndroidId.setChecked(getPreferences(0).getBoolean(selectedPackage + ":android_id_simulate", false));
        simulateAndroidId.setEnabled(targetDebuggable);
        simulatedAndroidId.setEnabled(targetDebuggable);
        Button saveAndroidId = new Button(this);
        saveAndroidId.setAllCaps(false);
        saveAndroidId.setText("保存并发布 Android ID 测试值");
        saveAndroidId.setEnabled(targetDebuggable);
        saveAndroidId.setOnClickListener(v -> {
            String value = simulatedAndroidId.getText().toString().trim().toLowerCase(java.util.Locale.ROOT);
            boolean enabled = simulateAndroidId.isChecked();
            if (enabled && !value.matches("[0-9a-f]{16}")) {
                Toast.makeText(this, "Android ID 必须为 16 位十六进制字符串。", Toast.LENGTH_LONG).show();
                return;
            }
            getPreferences(0).edit()
                    .putBoolean(selectedPackage + ":android_id_simulate", enabled)
                    .putString(selectedPackage + ":android_id", value).apply();
            publishConfig();
        });
        content.addView(simulatedAndroidId);
        content.addView(simulateAndroidId);
        content.addView(saveAndroidId);
        section("时间与时区模拟");
        TextView timeZoneNote = new TextView(this);
        timeZoneNote.setText("只覆盖此 debuggable 目标进程调用 TimeZone.getDefault() 的结果；不修改系统时间、系统时区或其他应用。");
        timeZoneNote.setTextColor(0xff697681);
        timeZoneNote.setPadding(dp(18), dp(2), dp(18), dp(8));
        content.addView(timeZoneNote);
        EditText simulatedTimeZone = new EditText(this);
        simulatedTimeZone.setSingleLine(true);
        simulatedTimeZone.setHint("IANA 时区，例如 Asia/Tokyo");
        simulatedTimeZone.setText(getPreferences(0).getString(selectedPackage + ":time_zone", "Asia/Tokyo"));
        Switch simulateTimeZone = new Switch(this);
        simulateTimeZone.setText("启用此应用的时区测试值");
        simulateTimeZone.setChecked(getPreferences(0).getBoolean(selectedPackage + ":time_zone_simulate", false));
        simulateTimeZone.setEnabled(targetDebuggable);
        simulatedTimeZone.setEnabled(targetDebuggable);
        Button saveTimeZone = new Button(this);
        saveTimeZone.setAllCaps(false);
        saveTimeZone.setText("保存并发布时区测试值");
        saveTimeZone.setEnabled(targetDebuggable);
        saveTimeZone.setOnClickListener(v -> {
            String value = simulatedTimeZone.getText().toString().trim();
            boolean enabled = simulateTimeZone.isChecked();
            boolean known = false;
            for (String id : java.util.TimeZone.getAvailableIDs()) if (id.equals(value)) { known = true; break; }
            if (enabled && !known) {
                Toast.makeText(this, "请输入系统支持的 IANA 时区，例如 Asia/Tokyo。", Toast.LENGTH_LONG).show();
                return;
            }
            getPreferences(0).edit()
                    .putBoolean(selectedPackage + ":time_zone_simulate", enabled)
                    .putString(selectedPackage + ":time_zone", value).apply();
            publishConfig();
        });
        content.addView(simulatedTimeZone);
        content.addView(simulateTimeZone);
        content.addView(saveTimeZone);
        section("位置隐私");
        TextView gpsNote = new TextView(this);
        gpsNote.setText("GPS 测试模拟仅对所选 debuggable 应用生效：覆盖 LocationManager.getLastKnownLocation()，并统一模拟该进程读取 Location.getLatitude()/getLongitude()/getAccuracy() 的结果（含返回 Location 对象的 Fused 回调）。不改变系统 GPS/GNSS provider、真实定位硬件或其他应用。");
        gpsNote.setTextColor(0xff697681);
        gpsNote.setPadding(dp(18), dp(2), dp(18), dp(8));
        content.addView(gpsNote);
        EditText gpsLatitude = new EditText(this);
        gpsLatitude.setSingleLine(true);
        gpsLatitude.setInputType(android.text.InputType.TYPE_CLASS_NUMBER
                | android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                | android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL);
        gpsLatitude.setHint("纬度 -90 至 90");
        gpsLatitude.setText(getPreferences(0).getString(selectedPackage + ":location_lat", ""));
        EditText gpsLongitude = new EditText(this);
        gpsLongitude.setSingleLine(true);
        gpsLongitude.setInputType(android.text.InputType.TYPE_CLASS_NUMBER
                | android.text.InputType.TYPE_NUMBER_FLAG_SIGNED
                | android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL);
        gpsLongitude.setHint("经度 -180 至 180");
        gpsLongitude.setText(getPreferences(0).getString(selectedPackage + ":location_lon", ""));
        EditText gpsAccuracy = new EditText(this);
        gpsAccuracy.setSingleLine(true);
        gpsAccuracy.setInputType(android.text.InputType.TYPE_CLASS_NUMBER
                | android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL);
        gpsAccuracy.setHint("精度（米，0 至 1000）");
        gpsAccuracy.setText(getPreferences(0).getString(selectedPackage + ":location_accuracy", "5"));
        Switch simulateLocation = new Switch(this);
        simulateLocation.setText("启用此应用的 GPS 测试位置");
        simulateLocation.setChecked(getPreferences(0).getBoolean(selectedPackage + ":location_simulate", false));
        simulateLocation.setEnabled(targetDebuggable);
        gpsLatitude.setEnabled(targetDebuggable);
        gpsLongitude.setEnabled(targetDebuggable);
        gpsAccuracy.setEnabled(targetDebuggable);
        Button saveLocation = new Button(this);
        saveLocation.setAllCaps(false);
        saveLocation.setText("保存并发布 GPS 测试位置");
        saveLocation.setEnabled(targetDebuggable);
        saveLocation.setOnClickListener(v -> {
            boolean enabled = simulateLocation.isChecked();
            String latitudeText = gpsLatitude.getText().toString().trim();
            String longitudeText = gpsLongitude.getText().toString().trim();
            String accuracyText = gpsAccuracy.getText().toString().trim();
            try {
                if (!enabled) {
                    getPreferences(0).edit().putBoolean(selectedPackage + ":location_simulate", false).apply();
                    publishConfig();
                    return;
                }
                double lat = Double.parseDouble(latitudeText);
                double lon = Double.parseDouble(longitudeText);
                float accuracy = Float.parseFloat(accuracyText.isEmpty() ? "5" : accuracyText);
                if (Double.isNaN(lat) || Double.isInfinite(lat) || lat < -90d || lat > 90d
                        || Double.isNaN(lon) || Double.isInfinite(lon) || lon < -180d || lon > 180d
                        || Float.isNaN(accuracy) || Float.isInfinite(accuracy) || accuracy < 0f || accuracy > 1000f) {
                    throw new IllegalArgumentException("坐标或精度超出范围。");
                }
                getPreferences(0).edit()
                        .putBoolean(selectedPackage + ":location_simulate", true)
                        .putString(selectedPackage + ":location_lat", Double.toString(lat))
                        .putString(selectedPackage + ":location_lon", Double.toString(lon))
                        .putString(selectedPackage + ":location_accuracy", Float.toString(accuracy))
                        .apply();
                publishConfig();
            } catch (Exception invalid) {
                new AlertDialog.Builder(this).setTitle("GPS 参数无效")
                        .setMessage(invalid.getMessage() == null ? "请输入有效经纬度和精度。" : invalid.getMessage())
                        .setPositiveButton("知道了", null).show();
            }
        });
        content.addView(gpsLatitude);
        content.addView(gpsLongitude);
        content.addView(gpsAccuracy);
        content.addView(simulateLocation);
        content.addView(saveLocation);
        toggle("限制位置访问", "location_access_block", false);
        section("设备访问");
        toggle("限制摄像头访问", "camera_access_block", false);
        section("媒体隐私");
        toggle("清理媒体查询元数据", "media_store_query_block", false);
        toggle("清理图片/视频元数据", "exif_strip", false);
        section("麦克风保护");
        toggle("阻止录音启动（会影响录音功能）", "mic_access_block", false);
        toggle("录音静音（保留录音流程）", "mic_silence", false);
        section("通知保护");
        toggle("阻止通知监听注册", "notification_listen_block", false);
        toggle("隐藏通知权限提示", "notification_permission_hide", false);
        section("传感器保护");
        toggle("限制加速度计", "sensor_accel", false);
        toggle("限制陀螺仪", "sensor_gyro", false);
        toggle("限制光线传感器", "sensor_light", false);
        toggle("限制磁场传感器", "sensor_magnet", false);
        toggle("限制气压传感器", "sensor_pressure", false);
        toggle("限制距离传感器", "sensor_prox", false);
        toggle("限制传感器采样频率", "sensor_rate_limit", false);
        section("会员诊断");
        toggle("只读会员状态诊断", "member_diag", false);
        TextView note=new TextView(this);
        note.setText("会员诊断仅记录应用内可观察状态，不修改购买结果、会员资格、令牌或服务端授权。");
        note.setTextColor(0xff697681); note.setPadding(dp(18),dp(2),dp(18),dp(14)); content.addView(note);
        section("自定义 Hook");
        TextView custom=new TextView(this);
        custom.setText("仅对可调试版本目标应用生效。OBSERVE 只记录方法调用元数据；RETURN_TRUE/FALSE 仅允许零参数 boolean 测试方法，用于你自己的调试构建。不会修改正式应用、账号、会员或服务端授权。");
        custom.setTextColor(0xff697681); custom.setPadding(dp(18),dp(4),dp(18),dp(8)); content.addView(custom);
        Button addRule=new Button(this); addRule.setText("添加自定义 Hook 规则");
        addRule.setOnClickListener(v->showCustomRuleDialog()); content.addView(addRule);
        Button ruleGroups = new Button(this); ruleGroups.setText("管理规则分组");
        ruleGroups.setOnClickListener(v -> showCustomRuleGroupsDialog());
        content.addView(ruleGroups);
        LinearLayout ruleTools = new LinearLayout(this);
        ruleTools.setOrientation(LinearLayout.HORIZONTAL);
        Button importRules = new Button(this); importRules.setText("批量导入 JSON");
        importRules.setOnClickListener(v -> showCustomRuleImportDialog());
        Button exportRules = new Button(this); exportRules.setText("导出 JSON");
        exportRules.setOnClickListener(v -> showCustomRuleExportDialog());
        ruleTools.addView(importRules, new LinearLayout.LayoutParams(0, -2, 1));
        ruleTools.addView(exportRules, new LinearLayout.LayoutParams(0, -2, 1));
        content.addView(ruleTools);
        renderCustomRules();
        Button save=new Button(this); save.setText("保存并发布 Hook 配置");
        save.setOnClickListener(v -> {
            getPreferences(0).edit().putBoolean(key("draft_saved"),true).apply();
            publishConfig();
        });
        content.addView(save,new LinearLayout.LayoutParams(-1,-2));
        Button back=new Button(this);
        back.setText(activePrivacySection == null ? "返回应用列表" : "返回隐私应用列表");
        back.setOnClickListener(v -> showAppList(activePrivacySection));
        content.addView(back,new LinearLayout.LayoutParams(-1,-2));
        focusPendingPrivacySection();
    }
 

    private void focusPendingPrivacySection() {
        final String requested = activePrivacySection;
        if (requested == null || nativeScroll == null) return;
        pendingPrivacySection = null;
        nativeScroll.post(() -> {
            if (isFinishing() || isDestroyed() || !hookTargetVisible) return;
            for (int i = 0; i < content.getChildCount(); i++) {
                View child = content.getChildAt(i);
                Object tag = child.getTag();
                if (tag instanceof String && ("fx-section:" + requested).equals(tag)) {
                    nativeScroll.smoothScrollTo(0, Math.max(0, child.getTop() - dp(12)));
                    return;
                }
            }
        });
    }

    private boolean validCustomRuleGroupName(String value) {
        if (value == null) return false;
        String name = value.trim();
        return !name.isEmpty() && name.length() <= 24
                && name.matches("[\\\\p{L}\\\\p{N}_ -]+")
                && !name.contains("|");
    }

    private java.util.LinkedHashSet<String> getCustomRuleGroups() {
        java.util.LinkedHashSet<String> groups = new java.util.LinkedHashSet<>();
        groups.add("默认");
        java.util.Set<String> saved = getPreferences(0).getStringSet(
                selectedPackage + ":dev_rule_groups", null);
        if (saved != null) {
            for (String group : saved) {
                if (validCustomRuleGroupName(group)) groups.add(group.trim());
            }
        }
        for (int i = 1; i <= 64; i++) {
            String group = getPreferences(0).getString(
                    selectedPackage + ":dev_rule_group_" + i, "默认");
            if (validCustomRuleGroupName(group)) groups.add(group.trim());
        }
        return groups;
    }

    private void ensureCustomRuleGroup(String groupName) {
        if (!validCustomRuleGroupName(groupName)) return;
        java.util.LinkedHashSet<String> groups = getCustomRuleGroups();
        groups.add(groupName.trim());
        getPreferences(0).edit().putStringSet(
                selectedPackage + ":dev_rule_groups",
                new java.util.HashSet<>(groups)).apply();
    }

    private void showAddCustomRuleGroupDialog() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("例如：网络监控、会员状态、设备模拟");
        new AlertDialog.Builder(this).setTitle("新增规则分组")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("新增", (dialog, which) -> {
                    String value = input.getText().toString().trim();
                    if (!validCustomRuleGroupName(value)) {
                        new AlertDialog.Builder(this).setMessage("分组名称无效，最长 24 个字符。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    ensureCustomRuleGroup(value);
                    new AlertDialog.Builder(this).setMessage("已创建分组：" + value)
                            .setPositiveButton("继续管理", (d, w) -> showCustomRuleGroupsDialog())
                            .setNegativeButton("关闭", null).show();
                }).show();
    }

    private void showCustomRuleGroupsDialog() {
        java.util.LinkedHashSet<String> groups = getCustomRuleGroups();
        String[] names = groups.toArray(new String[0]);
        new AlertDialog.Builder(this).setTitle("规则分组 · " + names.length + " 个")
                .setItems(names, (dialog, which) -> {
                    String chosen = names[which];
                    if ("默认".equals(chosen)) {
                        new AlertDialog.Builder(this).setMessage("“默认”分组始终保留。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    new AlertDialog.Builder(this).setTitle("删除分组")
                            .setMessage("删除分组“" + chosen + "”？其中的规则会移动到“默认”，不会删除 Hook 规则。")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除分组", (d, w) -> {
                                for (int slot = 1; slot <= 64; slot++) {
                                    String key = selectedPackage + ":dev_rule_group_" + slot;
                                    if (chosen.equals(getPreferences(0).getString(key, "默认")))
                                        getPreferences(0).edit().putString(key, "默认").apply();
                                }
                                java.util.LinkedHashSet<String> latest = getCustomRuleGroups();
                                latest.remove(chosen);
                                getPreferences(0).edit().putStringSet(
                                        selectedPackage + ":dev_rule_groups",
                                        new java.util.HashSet<>(latest)).apply();
                                ApplicationInfo target = findApp(selectedPackage);
                                if (target != null) showTarget(target);
                            }).show();
                })
                .setNeutralButton("新增分组", (dialog, which) -> showAddCustomRuleGroupDialog())
                .setNegativeButton("关闭", null).show();
    }

    private void showCustomRuleGroupPicker(int slot) {
        java.util.LinkedHashSet<String> groups = getCustomRuleGroups();
        String[] names = groups.toArray(new String[0]);
        String key = selectedPackage + ":dev_rule_group_" + slot;
        String current = getPreferences(0).getString(key, "默认");
        int selected = 0;
        for (int i = 0; i < names.length; i++) if (names[i].equals(current)) selected = i;
        final int[] chosen = { selected };
        new AlertDialog.Builder(this).setTitle("将规则移动到分组")
                .setSingleChoiceItems(names, selected, (dialog, which) -> chosen[0] = which)
                .setNeutralButton("新增分组", (dialog, which) -> showAddCustomRuleGroupDialog())
                .setNegativeButton("取消", null)
                .setPositiveButton("移动", (dialog, which) -> {
                    String group = names[chosen[0]];
                    getPreferences(0).edit().putString(key, group).apply();
                    ApplicationInfo target = findApp(selectedPackage);
                    if (target != null) showTarget(target);
                }).show();
    }

    private void showCustomRuleDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(8), dp(20), 0);

        EditText id = new EditText(this);
        id.setSingleLine(true);
        id.setHint("规则 ID，例如 observe1");
        EditText descriptor = new EditText(this);
        descriptor.setSingleLine(false);
        descriptor.setMinLines(2);
        descriptor.setHint("Java：com.example.Foo#run(java.lang.String,int[])java.lang.Object\n"
                + "Smali：Lcom/example/Foo;->run(Ljava/lang/String;[I)Ljava/lang/Object;\n"
                + "旧式：com.example.Foo#isReady()Z");
        EditText action = new EditText(this);
        action.setSingleLine(true);
        action.setText("OBSERVE");
        action.setHint("OBSERVE / RETURN_TRUE / RETURN_FALSE / RETURN_NULL / RETURN_ZERO / RETURN_EMPTY_STRING");
        EditText group = new EditText(this);
        group.setSingleLine(true);
        group.setText("默认");
        group.setHint("规则分组，例如 网络监控");
        EditText priority = new EditText(this);
        priority.setSingleLine(true);
        priority.setInputType(android.text.InputType.TYPE_CLASS_NUMBER
                | android.text.InputType.TYPE_NUMBER_FLAG_SIGNED);
        priority.setText("0");
        priority.setHint("优先级（-1000 至 1000）");

        TextView help = new TextView(this);
        help.setText("支持 Java 精确签名、Smali/JVM 描述符和旧式零参数 boolean 签名。"
                + "RETURN_TRUE/FALSE 仅支持零参数 boolean；RETURN_NULL 仅支持对象/数组；"
                + "RETURN_ZERO 仅支持数值原语；RETURN_EMPTY_STRING 仅支持 String。"
                + "所有替换动作只对 debuggable 目标生效；观察日志不记录参数值、返回值、口令或令牌。");
        help.setTextSize(12);
        help.setTextColor(0xff687681);
        help.setPadding(0, dp(6), 0, dp(8));
        form.addView(id);
        form.addView(descriptor);
        form.addView(action);
        form.addView(group);
        form.addView(priority);
        form.addView(help);

        new AlertDialog.Builder(this).setTitle("新增自定义 Hook 规则").setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) -> {
                    String ruleId = id.getText().toString().trim();
                    String method = descriptor.getText().toString().trim();
                    String actionText = action.getText().toString().trim().toUpperCase(java.util.Locale.ROOT);
                    String groupName = group.getText().toString().trim();
                    String priorityText = priority.getText().toString().trim();
                    if (!validCustomRuleGroupName(groupName)) {
                        new AlertDialog.Builder(this).setMessage("分组名称最多 24 个字符，只允许字母、数字、空格、下划线和连字符。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    if (!"OBSERVE".equals(actionText) && !"RETURN_TRUE".equals(actionText)
                            && !"RETURN_FALSE".equals(actionText) && !"RETURN_NULL".equals(actionText)
                            && !"RETURN_ZERO".equals(actionText) && !"RETURN_EMPTY_STRING".equals(actionText)) {
                        new AlertDialog.Builder(this).setMessage("动作只允许 OBSERVE、RETURN_TRUE、RETURN_FALSE、RETURN_NULL、RETURN_ZERO 或 RETURN_EMPTY_STRING。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    ApplicationInfo target = findApp(selectedPackage);
                    boolean debuggable = target != null
                            && (target.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
                    if (!debuggable && !"OBSERVE".equals(actionText)) {
                        new AlertDialog.Builder(this).setMessage("行为替换仅对 debuggable 目标开放。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    DeveloperHookRule rule = DeveloperHookRule.parse(
                            ruleId + "|" + method + "|" + actionText + "|" + priorityText, selectedPackage);
                    if (rule == null) {
                        new AlertDialog.Builder(this)
                                .setMessage("规则无效：检查目标包名、方法签名、动作类型和优先级。替换动作只接受零参数 boolean 方法。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    for (int n = 1; n <= 64; n++) {
                        String existing = getPreferences(0).getString(selectedPackage + ":dev_rule_" + n, null);
                        if (existing != null && existing.startsWith(rule.id + "|")) {
                            new AlertDialog.Builder(this).setMessage("规则 ID 已存在，请换一个 ID。")
                                    .setPositiveButton("知道了", null).show();
                            return;
                        }
                    }
                    int slot = 1;
                    while (slot <= 64 && getPreferences(0).contains(selectedPackage + ":dev_rule_" + slot)) slot++;
                    if (slot > 64) {
                        new AlertDialog.Builder(this).setMessage("每个应用最多配置 64 条自定义规则。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    getPreferences(0).edit()
                            .putString(selectedPackage + ":dev_rule_" + slot,
                                    rule.id + "|" + rule.descriptor + "|" + rule.action.name() + "|" + rule.priority)
                            .putString(selectedPackage + ":dev_rule_base_" + slot, rule.action.name())
                            .putString(selectedPackage + ":dev_rule_group_" + slot, groupName)
                            .putBoolean(selectedPackage + ":dev_hook_enabled", true)
                            .apply();
                    ensureCustomRuleGroup(groupName);
                    ApplicationInfo currentTarget = findApp(selectedPackage);
                    if (currentTarget == null) {
                        new AlertDialog.Builder(this).setMessage("目标应用已卸载或不再可用，请返回应用列表刷新。")
                                .setPositiveButton("知道了", null).show();
                        return;
                    }
                    showTarget(currentTarget);
                }).show();
    }

    private void showCustomRuleExportDialog() {
        try {
            org.json.JSONArray exported = new org.json.JSONArray();
            for (int n = 1; n <= 64; n++) {
                String value = getPreferences(0).getString(selectedPackage + ":dev_rule_" + n, null);
                if (value == null) continue;
                String[] parts = value.split("\\|", -1);
                if (parts.length != 4) continue;
                org.json.JSONObject item = new org.json.JSONObject();
                item.put("id", parts[0]);
                item.put("descriptor", parts[1]);
                String baseAction = getPreferences(0).getString(
                        selectedPackage + ":dev_rule_base_" + n,
                        "OFF".equals(parts[2]) ? "OBSERVE" : parts[2]);
                item.put("action", baseAction);
                item.put("enabled", !"OFF".equals(parts[2]));
                item.put("priority", Integer.parseInt(parts[3]));
                item.put("group", getPreferences(0).getString(
                        selectedPackage + ":dev_rule_group_" + n, "默认"));
                exported.put(item);
            }
            EditText output = new EditText(this);
            output.setText(exported.toString(2));
            output.setGravity(android.view.Gravity.TOP | android.view.Gravity.START);
            output.setMinLines(8);
            output.setSelectAllOnFocus(true);
            new AlertDialog.Builder(this).setTitle("导出自定义 Hook 规则")
                    .setView(output)
                    .setNegativeButton("关闭", null)
                    .setPositiveButton("复制", (dialog, which) -> {
                        android.content.ClipboardManager clipboard =
                                (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                        if (clipboard != null) {
                            clipboard.setPrimaryClip(android.content.ClipData.newPlainText(
                                    "FX Hook rules", output.getText().toString()));
                            Toast.makeText(this, "规则 JSON 已复制。", Toast.LENGTH_SHORT).show();
                        }
                    }).show();
        } catch (Exception error) {
            new AlertDialog.Builder(this).setMessage("导出失败：" + error.getMessage())
                    .setPositiveButton("知道了", null).show();
        }
    }

    private void showCustomRuleImportDialog() {
        EditText input = new EditText(this);
        input.setGravity(android.view.Gravity.TOP | android.view.Gravity.START);
        input.setMinLines(8);
        input.setHint("[{\\"id\\":\\"observe1\\",\\"descriptor\\":\\"com.example.Foo#run()Z\\",\\"action\\":\\"OBSERVE\\",\\"priority\\":0}]");
        new AlertDialog.Builder(this).setTitle("批量导入自定义 Hook 规则")
                .setMessage("接受 OBSERVE、RETURN_TRUE、RETURN_FALSE、RETURN_NULL、RETURN_ZERO、RETURN_EMPTY_STRING；所有 RETURN_* 仅对 debuggable 目标开放，且按签名限制返回类型。JSON 可用 enabled:false 暂停规则。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("验证并导入", (dialog, which) -> {
                    try {
                        org.json.JSONArray array = new org.json.JSONArray(input.getText().toString());
                        if (array.length() > 64) throw new IllegalArgumentException("单次导入最多 64 条规则。");
                        java.util.Set<String> ids = new java.util.HashSet<>();
                        java.util.List<String> candidates = new java.util.ArrayList<>();
                        java.util.List<String> baseActions = new java.util.ArrayList<>();
                        java.util.List<String> baseGroups = new java.util.ArrayList<>();
                        for (int n = 1; n <= 64; n++) {
                            String existing = getPreferences(0).getString(selectedPackage + ":dev_rule_" + n, null);
                            if (existing != null) {
                                String[] parts = existing.split("\\|", -1);
                                if (parts.length == 4) {
                                    ids.add(parts[0]);
                                    baseActions.add(getPreferences(0).getString(
                                            selectedPackage + ":dev_rule_base_" + n,
                                            "OFF".equals(parts[2]) ? "OBSERVE" : parts[2]));
                                    baseGroups.add(getPreferences(0).getString(
                                            selectedPackage + ":dev_rule_group_" + n, "默认"));
                                }
                                candidates.add(existing);
                            }
                        }
                        for (int i = 0; i < array.length(); i++) {
                            org.json.JSONObject item = array.optJSONObject(i);
                            if (item == null) throw new IllegalArgumentException("第 " + (i + 1) + " 条规则不是对象。");
                            String id = item.optString("id", "");
                            String descriptor = item.optString("descriptor", "");
                            String action = item.optString("action", "OBSERVE").toUpperCase(java.util.Locale.ROOT);
                            int priority = item.optInt("priority", 0);
                            String groupName = item.optString("group", "默认").trim();
                            boolean enabled = item.optBoolean("enabled", true);
                            if (!validCustomRuleGroupName(groupName))
                                throw new IllegalArgumentException("第 " + (i + 1) + " 条规则分组名称无效。");
                            if (!"OBSERVE".equals(action) && !"RETURN_TRUE".equals(action)
                                    && !"RETURN_FALSE".equals(action) && !"RETURN_NULL".equals(action)
                                    && !"RETURN_ZERO".equals(action) && !"RETURN_EMPTY_STRING".equals(action))
                                throw new IllegalArgumentException("不支持该规则动作。");
                            ApplicationInfo currentTarget = findApp(selectedPackage);
                            boolean debugBuild = currentTarget != null
                                    && (currentTarget.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
                            if (!debugBuild && !"OBSERVE".equals(action))
                                throw new IllegalArgumentException("RETURN_* 规则仅能导入 debuggable 目标。");
                            DeveloperHookRule parsed = DeveloperHookRule.parse(
                                    id + "|" + descriptor + "|" + action + "|" + priority, selectedPackage);
                            if (parsed == null) throw new IllegalArgumentException("第 " + (i + 1) + " 条规则签名/动作无效或不属于当前目标包。");
                            if (!ids.add(parsed.id)) throw new IllegalArgumentException("规则 ID 重复：" + parsed.id);
                            String storedAction = enabled ? action : "OFF";
                            candidates.add(parsed.id + "|" + parsed.descriptor + "|" + storedAction + "|" + parsed.priority);
                            baseActions.add(action);
                            baseGroups.add(groupName);
                        }
                        if (candidates.size() > 64) throw new IllegalArgumentException("当前应用最多保存 64 条规则。");
                        android.content.SharedPreferences.Editor editor = getPreferences(0).edit();
                        for (int n = 1; n <= 64; n++) {
                            editor.remove(selectedPackage + ":dev_rule_" + n);
                            editor.remove(selectedPackage + ":dev_rule_base_" + n);
                            editor.remove(selectedPackage + ":dev_rule_group_" + n);
                        }
                        for (int i = 0; i < candidates.size(); i++) {
                            editor.putString(selectedPackage + ":dev_rule_" + (i + 1), candidates.get(i));
                            editor.putString(selectedPackage + ":dev_rule_base_" + (i + 1), baseActions.get(i));
                            editor.putString(selectedPackage + ":dev_rule_group_" + (i + 1), baseGroups.get(i));
                        }
                        editor.putBoolean(selectedPackage + ":dev_hook_enabled", !candidates.isEmpty()).apply();
                        java.util.Set<String> allGroups = new java.util.LinkedHashSet<>();
                        allGroups.add("默认");
                        allGroups.addAll(baseGroups);
                        editor.putStringSet(selectedPackage + ":dev_rule_groups", allGroups);
                        ApplicationInfo currentTarget = findApp(selectedPackage);
                        if (currentTarget != null) showTarget(currentTarget);
                        Toast.makeText(this, "已导入 " + array.length() + " 条规则。", Toast.LENGTH_SHORT).show();
                    } catch (Exception invalid) {
                        new AlertDialog.Builder(this).setTitle("导入失败")
                                .setMessage(invalid.getMessage() == null ? "JSON 格式或规则数据无效。" : invalid.getMessage())
                                .setPositiveButton("知道了", null).show();
                    }
                }).show();
    }

    private ApplicationInfo findApp(String pkg) {
        for(ApplicationInfo ai:apps) if(ai.packageName.equals(pkg)) return ai;
        return null;
    }

    private void renderCustomRules() {
        for (String groupName : getCustomRuleGroups()) {
            LinearLayout groupRows = new LinearLayout(this);
            groupRows.setOrientation(LinearLayout.VERTICAL);
            int groupCount = 0;
            for (int i = 1; i <= 64; i++) {
                String key = selectedPackage + ":dev_rule_" + i;
                String value = getPreferences(0).getString(key, null);
                if (value == null) continue;
                String ruleGroup = getPreferences(0).getString(
                        selectedPackage + ":dev_rule_group_" + i, "默认");
                if (!groupName.equals(ruleGroup)) continue;
                String[] parts = value.split("\\\\|", -1);
                if (parts.length != 4) continue;

                final int slot = i;
                String baseAction = getPreferences(0).getString(
                        selectedPackage + ":dev_rule_base_" + slot,
                        "OFF".equals(parts[2]) ? "OBSERVE" : parts[2]);
                boolean active = !"OFF".equalsIgnoreCase(parts[2]);
                LinearLayout row = new LinearLayout(this);
                row.setOrientation(LinearLayout.VERTICAL);
                row.setPadding(dp(12), dp(6), dp(12), dp(6));
                row.setBackground(uiPanelDrawable());
                TextView item = new TextView(this);
                item.setText(parts[0] + " · " + parts[1] + "\\\\n动作：" + baseAction
                        + " · 优先级：" + parts[3] + (active ? "" : " · 已暂停"));
                item.setTextSize(12);
                item.setTextColor(0xff596775);
                row.addView(item);

                Switch enabled = new Switch(this);
                enabled.setText("启用规则");
                enabled.setChecked(active);
                enabled.setOnCheckedChangeListener((button, checked) -> {
                    String[] current = getPreferences(0).getString(key, "").split("\\\\|", -1);
                    if (current.length != 4) return;
                    String currentBase = getPreferences(0).getString(
                            selectedPackage + ":dev_rule_base_" + slot,
                            "OFF".equals(current[2]) ? "OBSERVE" : current[2]);
                    current[2] = checked ? currentBase : "OFF";
                    getPreferences(0).edit()
                            .putString(key, current[0] + "|" + current[1] + "|" + current[2] + "|" + current[3])
                            .putString(selectedPackage + ":dev_rule_base_" + slot, currentBase)
                            .apply();
                });
                row.addView(enabled);

                Button moveGroup = new Button(this);
                moveGroup.setText("移动到分组");
                moveGroup.setOnClickListener(v -> showCustomRuleGroupPicker(slot));
                row.addView(moveGroup);

                Button remove = new Button(this);
                remove.setText("删除 " + parts[0]);
                remove.setOnClickListener(v -> {
                    getPreferences(0).edit().remove(key)
                            .remove(selectedPackage + ":dev_rule_base_" + slot)
                            .remove(selectedPackage + ":dev_rule_group_" + slot).apply();
                    ApplicationInfo ai = findApp(selectedPackage);
                    if (ai != null) showTarget(ai);
                });
                row.addView(remove);
                groupRows.addView(row, new LinearLayout.LayoutParams(-1, -2));
                groupCount++;
            }
            if (groupCount > 0) {
                TextView heading = title(groupName + " · " + groupCount + " 条规则", 14);
                heading.setPadding(dp(18), dp(8), dp(18), dp(4));
                content.addView(heading);
                content.addView(groupRows, new LinearLayout.LayoutParams(-1, -2));
            }
        }
    }

    private boolean enabled(String pkg, String feature) {
        return getPreferences(0).getBoolean(pkg + ":" + feature, false);
    }

    private void publishConfig() {
        try {
            StringBuilder cfg = new StringBuilder();
            boolean anyPrivacy=false, anyWifi=false, anyNotif=false, anyNotifPerm=false, anyClipboardIso=false;
            List<String> rows = new ArrayList<>();
            List<String> legacyManagedRows = new ArrayList<>();
            final String[][] legacyDuplicateKeys = {
                {"exif_strip","exif_strip"},
                {"clipboard_read_block","clipboard"}, {"clipboard_isolate","clipboard_isolate"},
                {"sensor_accel","sensor_accel"}, {"sensor_gyro","sensor_gyro"},
                {"sensor_light","sensor_light"}, {"sensor_magnet","sensor_magnet"},
                {"sensor_pressure","sensor_pressure"}, {"sensor_prox","sensor_prox"},
                {"sensor_rate_limit","sensor_rate_limit"}, {"wifi_scan_block","block_wifi_scan"},
                {"notification_listen_block","block_notif_listen"},
                {"notification_permission_hide","hide_notif_perm"},
                {"ad_id_unify","ad_id_unify"},
                {"mic_access_block","mic_block"},
                {"mic_silence","mic_block"}, {"mic_silence","audio_fp_block"},
                {"camera_access_block","cam_null"},
                {"location_access_block","disable_passive_loc"},
                {"media_store_query_block","block_mediastore"}
            };
            for (ApplicationInfo ai : apps) {
                String p=ai.packageName;
                String[] keys={"member_diag","privacy","exif_strip",
                    "clipboard_read_block","clipboard_isolate","wifi_scan_block","notification_listen_block",
                    "notification_permission_hide","ad_id_unify","mic_silence","camera_access_block","location_access_block",
                    "location_simulate","android_id_simulate","time_zone_simulate",
                    "mic_access_block","media_store_query_block","sensor_accel","sensor_gyro","sensor_light",
                    "sensor_magnet","sensor_pressure","sensor_prox","sensor_rate_limit"};
                StringBuilder row=new StringBuilder(p);
                boolean has=false;
                for(String k:keys) {
                    boolean on=enabled(p,k);
                    if(on) {
                        row.append(',').append(k).append('=').append('1'); has=true;
                        if(k.equals("privacy")||k.equals("exif_strip")||k.equals("clipboard_read_block")||
                           k.equals("clipboard_isolate")||k.equals("mic_silence")||k.equals("camera_access_block")||
                           k.equals("location_access_block")||k.equals("mic_access_block")||
                           k.equals("media_store_query_block")||k.equals("ad_id_unify")||k.startsWith("sensor_")) anyPrivacy=true;
                        if(k.equals("wifi_scan_block")) anyWifi=true;
                        if(k.equals("notification_listen_block")) anyNotif=true;
                        if(k.equals("notification_permission_hide")) anyNotifPerm=true;
                        if(k.equals("clipboard_isolate")) anyClipboardIso=true;
                    }
                }
                if (enabled(p, "location_simulate")) {
                    String lat = getPreferences(0).getString(p + ":location_lat", "");
                    String lon = getPreferences(0).getString(p + ":location_lon", "");
                    String accuracy = getPreferences(0).getString(p + ":location_accuracy", "5");
                    if (lat.isEmpty() || lon.isEmpty())
                        throw new IllegalStateException("GPS 模拟必须同时填写纬度和经度：" + p);
                    row.append(",location_lat=").append(lat)
                            .append(",location_lon=").append(lon)
                            .append(",location_accuracy=").append(accuracy);
                    has = true;
                }
                if (enabled(p, "android_id_simulate")) {
                    String value = getPreferences(0).getString(p + ":android_id", "");
                    if (!value.matches("(?i)[0-9a-f]{16}"))
                        throw new IllegalStateException("Android ID 测试值必须为 16 位十六进制字符串：" + p);
                    row.append(",android_id=").append(value.toLowerCase(java.util.Locale.ROOT));
                    has = true;
                }
                if (enabled(p, "time_zone_simulate")) {
                    String value = getPreferences(0).getString(p + ":time_zone", "");
                    boolean known = false;
                    for (String id : java.util.TimeZone.getAvailableIDs()) if (id.equals(value)) { known = true; break; }
                    if (!known) throw new IllegalStateException("不支持的测试时区：" + p);
                    row.append(",time_zone=").append(value);
                    has = true;
                }
                StringBuilder legacyManaged = new StringBuilder(p);
                for (String[] mapping : legacyDuplicateKeys) {
                    if (enabled(p, mapping[0])) legacyManaged.append(',').append(mapping[1]);
                }
                if (legacyManaged.length() > p.length()) legacyManagedRows.add(legacyManaged.toString());
                boolean wifiSim = getPreferences(0).getBoolean(p + ":wifi_simulate", false);
                if (wifiSim && (ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                    String fakeSsid = getPreferences(0).getString(p + ":wifi_sim_ssid", "");
                    String fakeBssid = getPreferences(0).getString(p + ":wifi_sim_bssid", "");
                    if (!fakeSsid.isEmpty() || !fakeBssid.isEmpty()) {
                        row.append(",wifi_simulate=1");
                        if (!fakeSsid.isEmpty()) row.append(",wifi_ssid=").append(fakeSsid);
                        if (!fakeBssid.isEmpty()) row.append(",wifi_bssid=").append(fakeBssid);
                        has = true;
                    }
                }
                boolean networkTypeSim = getPreferences(0).getBoolean(p + ":network_type_sim", false);
                String networkType = getPreferences(0).getString(p + ":network_type", "wifi");
                if (networkTypeSim && (ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0
                        && ("wifi".equals(networkType) || "cellular".equals(networkType))) {
                    row.append(",network_type_simulate=1,network_type=").append(networkType);
                    has = true;
                }
                boolean customEnabled=false;
                for(int n=1;n<=64;n++) {
                    String rule=getPreferences(0).getString(p+":dev_rule_"+n,null);
                    if(rule!=null) {
                        if(!customEnabled) { row.append(",dev_hook_enabled=1"); customEnabled=true; }
                        row.append(",dev_rule_").append(n).append('=').append(rule);
                        has=true;
                    }
                }
                if(has) rows.add(row.toString());
            }
            cfg.append("schema_version=1\n")
               .append("ads_enabled=1\n")
               .append("privacy_enabled=").append(anyPrivacy?'1':'0').append('\n')
               .append("wifi_scan_enabled=").append(anyWifi?'1':'0').append('\n')
               .append("notification_listen_enabled=").append(anyNotif?'1':'0').append('\n')
               .append("notification_permission_hide_enabled=").append(anyNotifPerm?'1':'0').append('\n')
               .append("clipboard_isolate_enabled=").append(anyClipboardIso?'1':'0').append('\n')
               .append("[list:targets]\n");
            for(String row:rows) cfg.append(row).append('\n');
            if(rows.size()>990) throw new IllegalStateException("目标应用配置超过 990 条上限，请缩小 Hook 作用范围。");
            byte[] configBytes=cfg.toString().getBytes("UTF-8");
            if(configBytes.length>65536) throw new IllegalStateException("Hook 配置超过 64 KiB 上限，请减少目标或自定义规则数量。");
            String expectedHash=sha256Hex(configBytes);
            String encoded=android.util.Base64.encodeToString(configBytes,android.util.Base64.NO_WRAP);
            StringBuilder managedConfig=new StringBuilder();
            for(String row:legacyManagedRows) managedConfig.append(row).append('\n');
            byte[] managedBytes=managedConfig.toString().getBytes("UTF-8");
            if(managedBytes.length>65536) throw new IllegalStateException("Hook 兼容映射超过 64 KiB 上限。");
            String managedHash=sha256Hex(managedBytes);
            String managedEncoded=android.util.Base64.encodeToString(managedBytes,android.util.Base64.NO_WRAP);
            int androidUser=android.os.Process.myUid()/100000;
            String moduleDir="/data/adb/lspd/modules/"+androidUser+"/de.privacyguard.adhook/files";
            String remote=moduleDir+"/fx-hook-targets.conf";
            String temp=remote+".tmp";
            String legacyDir="/data/local/tmp/privacyguard";
            String managedFile=legacyDir+"/fx-api101-managed.conf";
            String managedTemp=managedFile+".tmp";
            String pgDir="/data/adb/privacyguard";
            String nativeOverlay=pgDir+"/fx-native-hook-targets-"+androidUser+".conf";
            String nativeOverlayTemp=nativeOverlay+".tmp";
            String command="set -e; umask 077; mkdir -p '"+moduleDir+"' '"+legacyDir+"' '"+pgDir+"'; "
                    +"printf '%s' '"+encoded+"' | base64 -d > '"+temp+"'; "
                    +"printf '%s' '"+encoded+"' | base64 -d > '"+nativeOverlayTemp+"'; "
                    +"printf '%s' '"+managedEncoded+"' | base64 -d > '"+managedTemp+"'; "
                    +"test -s '"+temp+"' && test -s '"+nativeOverlayTemp+"'; "
                    +"actual_tmp=$(sha256sum '"+temp+"' | cut -d ' ' -f1); "
                    +"actual_native_tmp=$(sha256sum '"+nativeOverlayTemp+"' | cut -d ' ' -f1); "
                    +"actual_managed_tmp=$(sha256sum '"+managedTemp+"' | cut -d ' ' -f1); "
                    +"test \"$actual_tmp\" = '"+expectedHash+"' && test \"$actual_native_tmp\" = '"+expectedHash+"' && test \"$actual_managed_tmp\" = '"+managedHash+"'; "
                    +"chmod 0755 '"+legacyDir+"'; chmod 0644 '"+temp+"' '"+managedTemp+"'; chmod 0600 '"+nativeOverlayTemp+"'; "
                    +"chown 0:0 '"+temp+"' '"+managedTemp+"' '"+nativeOverlayTemp+"'; "
                    +"chmod 0755 '"+moduleDir+"'; chcon u:object_r:magisk_file:s0 '"+moduleDir+"' '"+temp+"' '"+pgDir+"' '"+nativeOverlayTemp+"'; "
                    +"chcon u:object_r:shell_data_file:s0 '"+legacyDir+"' '"+managedTemp+"'; sync; "
                    +"if [ -e '"+remote+"' ]; then cp -p '"+remote+"' '"+remote+".bak'; else rm -f '"+remote+".bak'; fi; "
                    +"if [ -e '"+managedFile+"' ]; then cp -p '"+managedFile+"' '"+managedFile+".bak'; else rm -f '"+managedFile+".bak'; fi; "
                    +"if [ -e '"+nativeOverlay+"' ]; then cp -p '"+nativeOverlay+"' '"+nativeOverlay+".bak'; else rm -f '"+nativeOverlay+".bak'; fi; "
                    +"mv -f '"+managedTemp+"' '"+managedFile+"'; "
                    +"if ! mv -f '"+nativeOverlayTemp+"' '"+nativeOverlay+"'; then "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"if ! mv -f '"+temp+"' '"+remote+"'; then "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"if ! chmod 0644 '"+remote+"' '"+managedFile+"' || ! chmod 0600 '"+nativeOverlay+"' || "
                    +"! chown 0:0 '"+remote+"' '"+managedFile+"' '"+nativeOverlay+"' || "
                    +"! chmod 0755 '"+moduleDir+"' || ! chmod 0755 '"+legacyDir+"' || ! chcon u:object_r:magisk_file:s0 '"+moduleDir+"' '"+remote+"' '"+pgDir+"' '"+nativeOverlay+"' || "
                    +"! chcon u:object_r:shell_data_file:s0 '"+legacyDir+"' '"+managedFile+"'; then "
                    +"if [ -e '"+remote+".bak' ]; then mv -f '"+remote+".bak' '"+remote+"'; else rm -f '"+remote+"'; fi; "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; sync; "
                    +"actual=$(sha256sum '"+remote+"' | cut -d ' ' -f1); "
                    +"actual_native=$(sha256sum '"+nativeOverlay+"' | cut -d ' ' -f1); "
                    +"actual_managed=$(sha256sum '"+managedFile+"' | cut -d ' ' -f1); "
                    +"if [ \"$actual\" != '"+expectedHash+"' ] || [ \"$actual_native\" != '"+expectedHash+"' ] || [ \"$actual_managed\" != '"+managedHash+"' ]; then "
                    +"if [ -e '"+remote+".bak' ]; then mv -f '"+remote+".bak' '"+remote+"'; else rm -f '"+remote+"'; fi; "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"printf 'SHA256=%s\\nAPI101_OVERLAY_SHA256=%s\\nAPI101_OWNERSHIP_SHA256=%s\\n' \"$actual\" \"$actual_native\" \"$actual_managed\"";
            if(command.length()>131072) throw new IllegalStateException("Root 发布命令超过 128 KiB 上限，请减少目标或自定义规则数量。");
            if (hookPublisherThread != null && hookPublisherThread.isAlive()) {
                Toast.makeText(this, "Hook 配置正在发布，请等待当前操作完成。", Toast.LENGTH_LONG).show();
                return;
            }
            Thread publisher = new Thread(() -> {
                RootAccess.Result result = RootAccess.execute(command, 60000L, 1024 * 1024);
                if (hookPublisherThread == Thread.currentThread()) hookPublisherThread = null;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    if(result.exitCode==0) {
                        getSharedPreferences("fx_hook_publish", MODE_PRIVATE).edit()
                                .putString("sha256", expectedHash)
                                .putString("remote_path", remote)
                                .putLong("published_at", System.currentTimeMillis())
                                .apply();
                        new AlertDialog.Builder(this).setMessage("配置已原子写入 LSPosed Remote Files，并已输出 SHA-256 校验值：\\n"+result.output+"\\n请确认 LSPosed Manager 已启用 FX 并将目标应用加入作用域，然后强制停止并重新打开目标应用。")
                            .setPositiveButton("知道了",null).show();
                    } else {
                        new AlertDialog.Builder(this).setMessage("Root 发布失败（退出码 "+result.exitCode+"）。"+result.output+"请确认 KernelSU 已授予 FX Hook Root 权限。配置仍保存在本机草稿。")
                            .setPositiveButton("知道了",null).show();
                    }
                });
            }, "fx-config-publisher");
            hookPublisherThread = publisher;
            publisher.start();
        } catch(Exception e) {
            new AlertDialog.Builder(this).setMessage("配置同步失败："+e.getClass().getSimpleName()+"。本机草稿仍已保存。")
                .setPositiveButton("知道了",null).show();
        }
    }

    private static String sha256Hex(byte[] data) throws Exception {
        byte[] digest=java.security.MessageDigest.getInstance("SHA-256").digest(data);
        char[] hex="0123456789abcdef".toCharArray();
        char[] out=new char[digest.length*2];
        for(int i=0;i<digest.length;i++) {
            int value=digest[i]&0xff;
            out[i*2]=hex[value>>>4];
            out[i*2+1]=hex[value&0x0f];
        }
        return new String(out);
    }

    private void section(String s) {
        TextView t=title(s,16);
        t.setBackground(roundedDrawable("miuix".equals(uiMode) ? 0xffe5ecf8 : "glass".equals(uiMode) ? 0xccefffff : 0xffe9eef3,
                "glass".equals(uiMode) ? 0x66ffffff : 0));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12), dp(10), dp(12), dp(4));
        t.setTag("fx-section:" + s);
        content.addView(t,lp);
    }
    private void toggle(String label,String feature,boolean def) {
        Switch sw=new Switch(this); sw.setText(label); sw.setTextSize(15); sw.setPadding(dp(18),dp(12),dp(18),dp(12));
        sw.setBackground(uiPanelDrawable()); sw.setChecked(getPreferences(0).getBoolean(key(feature),def));
        sw.setOnCheckedChangeListener((b,on)->getPreferences(0).edit().putBoolean(key(feature),on).apply());
        content.addView(sw,new LinearLayout.LayoutParams(-1,-2));
    }
}